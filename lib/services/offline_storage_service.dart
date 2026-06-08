import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'sky_novels_service.dart';

class OfflineStorageService {
  static Future<Directory> _getMangaOfflineDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/manga_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _getNovelOfflineDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/novel_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // --- MANGA ---

  static Future<List<String>> fetchMangaPages(String mangaId, String chapterId) async {
    // ZonaTMO: /view_uploads/{uploadId}
    final uri = Uri.parse('https://zonatmo.org/view_uploads/$chapterId');
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
      'Referer': 'https://zonatmo.org/',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'es-ES,es;q=0.9',
      'Upgrade-Insecure-Requests': '1',
    });
    if (response.statusCode == 200) {
      return _parseZonaTmoPages(response.body);
    }
    return [];
  }

  static List<String> _parseZonaTmoPages(String html) {
    // 1. data-src (ZonaTMO carga imágenes lazy: data-src="https://storage.zonatmo.org/chapters/...")
    final dataSrc = RegExp(r'data-src="(https?://[^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((u) => u.contains('storage.zonatmo') || u.contains('/chapters/'))
        .toList();
    if (dataSrc.isNotEmpty) return dataSrc;

    // 2. src en img del lector
    final imgSrc = RegExp(r'<img[^>]+src="(https?://[^"]*(?:storage\.zonatmo|/chapters/)[^"]*)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();
    if (imgSrc.isNotEmpty) return imgSrc;

    // 3. Cualquier data-src con URL absoluta
    final anyDataSrc = RegExp(r'data-src="(https?://[^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((u) => u.startsWith('http'))
        .toList();
    return anyDataSrc;
  }

  static Future<void> saveMangaChapter({
    required String mangaId,
    required String mangaTitle,
    required String coverUrl,
    required String chapterId,
    required String chapterNumber,
    required List<String> pageUrls,
    Function(double progress)? onProgress,
  }) async {
    final root = await _getMangaOfflineDir();
    final chapterDir = Directory('${root.path}/$mangaId/$chapterId');
    if (!await chapterDir.exists()) {
      await chapterDir.create(recursive: true);
    }

    final client = http.Client();
    try {
      for (int i = 0; i < pageUrls.length; i++) {
        final url = pageUrls[i];
        final file = File('${chapterDir.path}/page_$i.jpg');
        final res = await client.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
          'Referer': 'https://zonatmo.org/',
          'Origin': 'https://zonatmo.org',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        });
        if (res.statusCode == 200) {
          await file.writeAsBytes(res.bodyBytes);
        }
        if (onProgress != null) {
          onProgress((i + 1) / pageUrls.length);
        }
      }

      // Save metadata
      final metadata = {
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterId': chapterId,
        'chapterNumber': chapterNumber,
        'pageCount': pageUrls.length,
        'downloadedAt': DateTime.now().toIso8601String(),
      };
      final metaFile = File('${chapterDir.path}/metadata.json');
      await metaFile.writeAsString(json.encode(metadata));
    } catch (e) {
      if (await chapterDir.exists()) {
        await chapterDir.delete(recursive: true);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<bool> isMangaChapterDownloaded(String mangaId, String chapterId) async {
    final root = await _getMangaOfflineDir();
    final metaFile = File('${root.path}/$mangaId/$chapterId/metadata.json');
    return metaFile.exists();
  }

  static Future<List<String>> getMangaChapterPages(String mangaId, String chapterId) async {
    final root = await _getMangaOfflineDir();
    final chapterDir = Directory('${root.path}/$mangaId/$chapterId');
    if (!await chapterDir.exists()) return [];

    final metaFile = File('${chapterDir.path}/metadata.json');
    if (!await metaFile.exists()) return [];

    final Map<String, dynamic> metadata = json.decode(await metaFile.readAsString());
    final count = metadata['pageCount'] as int? ?? 0;

    final List<String> paths = [];
    for (int i = 0; i < count; i++) {
      paths.add('${chapterDir.path}/page_$i.jpg');
    }
    return paths;
  }

  static Future<void> deleteMangaChapter(String mangaId, String chapterId) async {
    final root = await _getMangaOfflineDir();
    final chapterDir = Directory('${root.path}/$mangaId/$chapterId');
    if (await chapterDir.exists()) {
      await chapterDir.delete(recursive: true);
    }
    // If the manga folder is empty, delete it too
    final mangaDir = Directory('${root.path}/$mangaId');
    if (await mangaDir.exists()) {
      final children = await mangaDir.list().toList();
      if (children.isEmpty) {
        await mangaDir.delete(recursive: true);
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getDownloadedMangas() async {
    final root = await _getMangaOfflineDir();
    if (!await root.exists()) return [];

    final List<Map<String, dynamic>> results = [];
    final mangaDirs = await root.list().toList();
    
    for (final mangaEntity in mangaDirs) {
      if (mangaEntity is! Directory) continue;
      
      final mangaId = mangaEntity.path.split(Platform.pathSeparator).last;
      final chapterDirs = await mangaEntity.list().toList();
      
      final List<Map<String, dynamic>> chapters = [];
      String mangaTitle = 'Manga';
      String coverUrl = '';

      for (final chapterEntity in chapterDirs) {
        if (chapterEntity is! Directory) continue;
        final metaFile = File('${chapterEntity.path}/metadata.json');
        if (await metaFile.exists()) {
          try {
            final Map<String, dynamic> metadata = json.decode(await metaFile.readAsString());
            mangaTitle = metadata['mangaTitle'] ?? mangaTitle;
            coverUrl = metadata['coverUrl'] ?? coverUrl;
            chapters.add(metadata);
          } catch (_) {}
        }
      }

      if (chapters.isNotEmpty) {
        chapters.sort((a, b) {
          final aNum = double.tryParse(a['chapterNumber']?.toString() ?? '') ?? 0.0;
          final bNum = double.tryParse(b['chapterNumber']?.toString() ?? '') ?? 0.0;
          return aNum.compareTo(bNum);
        });

        results.add({
          'mangaId': mangaId,
          'mangaTitle': mangaTitle,
          'coverUrl': coverUrl,
          'chapters': chapters,
        });
      }
    }

    results.sort((a, b) => (a['mangaTitle'] as String).compareTo(b['mangaTitle'] as String));
    return results;
  }

  // --- NOVEL ---

  static Future<List<String>> fetchNovelParagraphs(String chapterUrl) async {
    return await SkyNovelsService.fetchChapterContent(chapterUrl);
  }

  static Future<void> saveNovelChapter({
    required String novelId,
    required String novelTitle,
    required String coverUrl,
    required String novelUrl,
    required String chapterId,
    required double chapterNumber,
    required String chapterTitle,
    required String chapterUrl,
    required List<String> paragraphs,
  }) async {
    final root = await _getNovelOfflineDir();
    final chapterDir = Directory('${root.path}/$novelId');
    if (!await chapterDir.exists()) {
      await chapterDir.create(recursive: true);
    }

    final metadata = {
      'novelId': novelId,
      'novelTitle': novelTitle,
      'coverUrl': coverUrl,
      'novelUrl': novelUrl,
      'chapterId': chapterId,
      'chapterNumber': chapterNumber,
      'chapterTitle': chapterTitle,
      'chapterUrl': chapterUrl,
      'paragraphs': paragraphs,
      'downloadedAt': DateTime.now().toIso8601String(),
    };
    final file = File('${chapterDir.path}/$chapterId.json');
    await file.writeAsString(json.encode(metadata));
  }

  static Future<bool> isNovelChapterDownloaded(String novelId, String chapterId) async {
    final root = await _getNovelOfflineDir();
    final file = File('${root.path}/$novelId/$chapterId.json');
    return file.exists();
  }

  static Future<List<String>> getNovelChapterParagraphs(String novelId, String chapterId) async {
    final root = await _getNovelOfflineDir();
    final file = File('${root.path}/$novelId/$chapterId.json');
    if (!await file.exists()) return [];

    final Map<String, dynamic> metadata = json.decode(await file.readAsString());
    final List<dynamic> list = metadata['paragraphs'] ?? [];
    return list.map((e) => e.toString()).toList();
  }

  static Future<void> deleteNovelChapter(String novelId, String chapterId) async {
    final root = await _getNovelOfflineDir();
    final file = File('${root.path}/$novelId/$chapterId.json');
    if (await file.exists()) {
      await file.delete();
    }
    // If the novel folder is empty, delete it too
    final novelDir = Directory('${root.path}/$novelId');
    if (await novelDir.exists()) {
      final children = await novelDir.list().toList();
      if (children.isEmpty) {
        await novelDir.delete(recursive: true);
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getDownloadedNovels() async {
    final root = await _getNovelOfflineDir();
    if (!await root.exists()) return [];

    final List<Map<String, dynamic>> results = [];
    final novelDirs = await root.list().toList();

    for (final novelEntity in novelDirs) {
      if (novelEntity is! Directory) continue;

      final novelId = novelEntity.path.split(Platform.pathSeparator).last;
      final chapterFiles = await novelEntity.list().toList();

      final List<Map<String, dynamic>> chapters = [];
      String novelTitle = 'Novela';
      String coverUrl = '';
      String novelUrl = '';

      for (final fileEntity in chapterFiles) {
        if (fileEntity is! File || !fileEntity.path.endsWith('.json')) continue;
        try {
          final Map<String, dynamic> metadata = json.decode(await fileEntity.readAsString());
          novelTitle = metadata['novelTitle'] ?? novelTitle;
          coverUrl = metadata['coverUrl'] ?? coverUrl;
          novelUrl = metadata['novelUrl'] ?? novelUrl;
          chapters.add(metadata);
        } catch (_) {}
      }

      if (chapters.isNotEmpty) {
        chapters.sort((a, b) {
          final aNum = double.tryParse(a['chapterNumber']?.toString() ?? '') ?? 0.0;
          final bNum = double.tryParse(b['chapterNumber']?.toString() ?? '') ?? 0.0;
          return aNum.compareTo(bNum);
        });

        results.add({
          'novelId': novelId,
          'novelTitle': novelTitle,
          'coverUrl': coverUrl,
          'novelUrl': novelUrl,
          'chapters': chapters,
        });
      }
    }

    results.sort((a, b) => (a['novelTitle'] as String).compareTo(b['novelTitle'] as String));
    return results;
  }
}
