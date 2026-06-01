import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
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
    return pack.stickers.last;
  }

  static Future<void> deleteSticker(String packId, String stickerId) async {
    final packs = await loadPacks();
    for (final pack in packs) {
      if (pack.id != packId) continue;
      final item = pack.stickers.where((s) => s.id == stickerId).firstOrNull;
      if (item != null) {
        await File(item.filePath).delete();
        pack.stickers.removeWhere((s) => s.id == stickerId);
      }
    }
    await _savePacks(packs);
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

  static List<StickerPack> getBuiltInPacks() {
    return [
      StickerPack(
        id: 'builtin_reactions',
        name: 'Reacciones',
        stickers: [
          StickerItem(id: 'r1', filePath: 'https://media.tenor.com/t54QA2bVp0kAAAAC/anime-spy-x-family.gif', label: 'Anya Smug'),
          StickerItem(id: 'r2', filePath: 'https://media.tenor.com/u9S4PdgqcCgAAAAd/chika-fujiwara-chika-dance.gif', label: 'Chika Dance'),
          StickerItem(id: 'r3', filePath: 'https://media.tenor.com/5u5C6g5m38gAAAAC/one-punch-man-saitama.gif', label: 'Saitama OK'),
          StickerItem(id: 'r4', filePath: 'https://media.tenor.com/eD93cr-4s70AAAAC/pokemon-pikachu.gif', label: 'Pikachu Shocked'),
          StickerItem(id: 'r5', filePath: 'https://media.tenor.com/P3a579kF-10AAAAC/goku-shrug.gif', label: 'Goku Shrug'),
          StickerItem(id: 'r6', filePath: 'https://media.tenor.com/kP1t37D4YV8AAAAC/kaguya-sama-love-is-war-shinomiya-kaguya.gif', label: 'Kaguya Love'),
          StickerItem(id: 'r7', filePath: 'https://media.tenor.com/yG1T6z_8mKwAAAAC/naruto-run.gif', label: 'Naruto Run'),
          StickerItem(id: 'r8', filePath: 'https://media.tenor.com/bC8w5Q8m2dAAAAAC/megumin-explosion.gif', label: 'Megumin Explosion'),
        ],
      ),
      StickerPack(
        id: 'builtin_memes',
        name: 'Memes',
        stickers: [
          StickerItem(id: 'm1', filePath: 'https://media.tenor.com/aC-2sKzJjF0AAAAC/kono-dio-da-dio-brando.gif', label: 'Kono Dio Da'),
          StickerItem(id: 'm2', filePath: 'https://media.tenor.com/h52mN0zS274AAAAC/luffy-one-piece.gif', label: 'Luffy Laugh'),
          StickerItem(id: 'm3', filePath: 'https://media.tenor.com/r_z79Z3GZ0sAAAAC/anime-blush.gif', label: 'Blush'),
          StickerItem(id: 'm4', filePath: 'https://media.tenor.com/y8e22i3G1d4AAAAC/umaru-umaru-chan.gif', label: 'Umaru Cry'),
          StickerItem(id: 'm5', filePath: 'https://media.tenor.com/W2-jD96oMHYAAAAC/levi-ackerman-clean.gif', label: 'Levi Clean'),
          StickerItem(id: 'm6', filePath: 'https://media.tenor.com/dI9g1J7gN5oAAAAC/zoro-lost.gif', label: 'Zoro Lost'),
          StickerItem(id: 'm7', filePath: 'https://media.tenor.com/f2L4Bv4N5t0AAAAC/nezuko-demon-slayer.gif', label: 'Nezuko Run'),
          StickerItem(id: 'm8', filePath: 'https://media.tenor.com/B942yq4hG8sAAAAC/deku-crying.gif', label: 'Deku Cry'),
        ],
      ),
    ];
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
