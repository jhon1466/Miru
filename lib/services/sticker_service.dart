import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sticker.dart';

class StickerService {
  static const _indexFile = 'packs.json';
  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;

  static Future<Directory> _root() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/miru_stickers');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<StickerPack>> loadPacks() async {
    final root = await _root();
    final file = File('${root.path}/$_indexFile');
    if (!await file.exists()) {
      await _ensureDefaultPack();
    }
    try {
      final raw = json.decode(await file.readAsString()) as List<dynamic>;
      final packs = raw.map((e) => StickerPack.fromJson(e as Map<String, dynamic>)).toList();
      for (final pack in packs) {
        for (final s in pack.stickers) {
          if (!await File(s.filePath).exists()) continue;
        }
      }
      return packs.where((p) => p.stickers.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePacks(List<StickerPack> packs) async {
    final root = await _root();
    await File('${root.path}/$_indexFile').writeAsString(
      json.encode(packs.map((p) => p.toJson()).toList()),
    );
  }

  static Future<void> _ensureDefaultPack() async {
    final packs = [
      StickerPack(id: 'default', name: 'Favoritos', stickers: []),
    ];
    await _savePacks(packs);
  }

  static Future<XFile?> pickImageForSticker() {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  static CollectionReference _stickersRef(String userId) {
    return FirebaseFirestore.instance.collection('users').doc(userId).collection('stickers');
  }

  /// Guarda sticker en el pack del usuario.
  static Future<StickerItem?> saveToPack({
    required String packId,
    required File sourceFile,
    String? label,
  }) async {
    final root = await _root();
    final packDir = Directory('${root.path}/$packId');
    if (!await packDir.exists()) await packDir.create(recursive: true);

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final pathLower = sourceFile.path.toLowerCase();
    final isGif = pathLower.endsWith('.gif');
    final isWebp = pathLower.endsWith('.webp');
    final ext = isGif ? 'gif' : (isWebp ? 'webp' : 'png');
    final outPath = '${packDir.path}/$id.$ext';

    if (isGif || isWebp) {
      await sourceFile.copy(outPath);
    } else {
      final bytes = await sourceFile.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 512,
        minHeight: 512,
        quality: 90,
        format: CompressFormat.png,
      );
      if (compressed.isEmpty) return null;
      await File(outPath).writeAsBytes(compressed);
    }

    final packs = await loadPacks();
    var pack = packs.where((p) => p.id == packId).firstOrNull;
    if (pack == null) {
      pack = StickerPack(id: packId, name: 'Mis stickers', stickers: []);
      packs.add(pack);
    }
    pack.stickers.add(StickerItem(id: id, filePath: outPath, label: label));
    await _savePacks(packs);

    // Subir a la nube inmediatamente si tiene sesión activa
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && packId == userPackId(user.uid)) {
      try {
        final storagePath = 'users/${user.uid}/sticker_$id.$ext';
        final ref = _storage.ref(storagePath);
        final file = File(outPath);
        final bytes = await file.readAsBytes();
        final mimeType = ext == 'gif' ? 'image/gif' : (ext == 'webp' ? 'image/webp' : 'image/png');
        await ref.putData(bytes, SettableMetadata(contentType: mimeType));
        final downloadUrl = await ref.getDownloadURL();

        await _stickersRef(user.uid).doc(id).set({
          'url': downloadUrl,
          'label': label,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error uploading newly created sticker to cloud: $e');
      }
    }

    return pack.stickers.last;
  }

  static Future<void> deleteSticker(String packId, String stickerId) async {
    final packs = await loadPacks();
    for (final pack in packs) {
      if (pack.id != packId) continue;
      final item = pack.stickers.where((s) => s.id == stickerId).firstOrNull;
      if (item != null) {
        if (!item.filePath.startsWith('http')) {
          final file = File(item.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        pack.stickers.removeWhere((s) => s.id == stickerId);

        // Eliminar de la nube si tiene sesión activa
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && packId == userPackId(user.uid)) {
          try {
            await _stickersRef(user.uid).doc(stickerId).delete();
            final ext = item.filePath.startsWith('http') 
                ? (item.filePath.contains('.gif') ? 'gif' : (item.filePath.contains('.webp') ? 'webp' : 'png'))
                : item.filePath.split('.').last;
            final storagePath = 'users/${user.uid}/sticker_$stickerId.$ext';
            await _storage.ref(storagePath).delete();
          } catch (e) {
            debugPrint('Error deleting sticker from cloud: $e');
          }
        }
      }
    }
    await _savePacks(packs);
  }

  static Future<void> syncStickersWithCloud(String uid) async {
    try {
      final packs = await loadPacks();
      final userPackIdVal = userPackId(uid);
      var userPack = packs.where((p) => p.id == userPackIdVal).firstOrNull;
      if (userPack == null) {
        userPack = StickerPack(id: userPackIdVal, name: 'Mis stickers', stickers: []);
        packs.add(userPack);
      }

      // 1. Obtener stickers de la nube (Firestore)
      final snap = await _stickersRef(uid).get();
      final cloudStickers = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return StickerItem(
          id: doc.id,
          filePath: data['url'] ?? '',
          label: data['label'],
        );
      }).toList();

      bool hasChanges = false;

      // 2. Sincronizar de la nube al local: agregar los que no están en local
      for (final cloudItem in cloudStickers) {
        final localItem = userPack.stickers.where((s) => s.id == cloudItem.id).firstOrNull;
        if (localItem == null) {
          userPack.stickers.add(cloudItem);
          hasChanges = true;
        }
      }

      // 3. Sincronizar de local a la nube: subir los que están localmente pero no en la nube
      for (final localItem in List<StickerItem>.from(userPack.stickers)) {
        final inCloud = cloudStickers.any((s) => s.id == localItem.id);
        if (!inCloud && !localItem.filePath.startsWith('http')) {
          final file = File(localItem.filePath);
          if (await file.exists()) {
            final ext = localItem.filePath.split('.').last;
            final storagePath = 'users/$uid/sticker_${localItem.id}.$ext';
            final ref = _storage.ref(storagePath);
            
            final bytes = await file.readAsBytes();
            final mimeType = ext == 'gif' ? 'image/gif' : (ext == 'webp' ? 'image/webp' : 'image/png');
            await ref.putData(bytes, SettableMetadata(contentType: mimeType));
            final downloadUrl = await ref.getDownloadURL();

            await _stickersRef(uid).doc(localItem.id).set({
              'url': downloadUrl,
              'label': localItem.label,
              'createdAt': FieldValue.serverTimestamp(),
            });
            hasChanges = true;
          }
        }
      }

      if (hasChanges) {
        await _savePacks(packs);
      }
    } catch (e) {
      debugPrint('Error syncing stickers with cloud: $e');
    }
  }

  static Future<String?> uploadForComment({
    required String animeSlug,
    required File file,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final pathLower = file.path.toLowerCase();
    final isGif = pathLower.endsWith('.gif');
    final isWebp = pathLower.endsWith('.webp');
    final ext = isGif ? 'gif' : (isWebp ? 'webp' : 'png');
    final mimeType = isGif ? 'image/gif' : (isWebp ? 'image/webp' : 'image/png');

    final path = 'comment_stickers/$animeSlug/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = _storage.ref(path);

    if (isGif || isWebp) {
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: mimeType));
    } else {
      final bytes = await file.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 512,
        minHeight: 512,
        quality: 88,
        format: CompressFormat.png,
      );
      if (compressed.isEmpty) return null;
      await ref.putData(compressed, SettableMetadata(contentType: 'image/png'));
    }
    return ref.getDownloadURL();
  }

  static String userPackId(String uid) => 'user_$uid';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
