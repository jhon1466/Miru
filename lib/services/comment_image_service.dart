import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

class CommentImageService {
  static final _storage = FirebaseStorage.instance;
  static final _picker = ImagePicker();

  static Future<XFile?> pickImage() async {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  /// Comprime la imagen (máx. 1024px, JPEG ~75%) y la sube a Storage (excepto si es GIF/WebP).
  static Future<String?> uploadCompressed({
    required String animeSlug,
    required XFile file,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final nameLower = file.name.toLowerCase();
    final pathLower = file.path.toLowerCase();
    final bool isGif = nameLower.endsWith('.gif') || pathLower.endsWith('.gif');
    final bool isWebp = nameLower.endsWith('.webp') || pathLower.endsWith('.webp');

    Uint8List dataToUpload;
    String contentType;
    String ext;

    if (isGif || isWebp) {
      dataToUpload = await file.readAsBytes();
      contentType = isGif ? 'image/gif' : 'image/webp';
      ext = isGif ? 'gif' : 'webp';
    } else {
      final bytes = await file.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return null;
      dataToUpload = compressed;
      contentType = 'image/jpeg';
      ext = 'jpg';
    }

    final path =
        'comment_images/$animeSlug/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = _storage.ref(path);
    await ref.putData(
      dataToUpload,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  static Future<void> deleteIfOwned(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } catch (e) {
      debugPrint('No se pudo borrar imagen de comentario: $e');
    }
  }

  static Future<void> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
