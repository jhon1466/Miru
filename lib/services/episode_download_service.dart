import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/anime.dart';
import '../models/downloaded_episode.dart';

class EpisodeDownloadService {
  static const _indexFileName = 'index.json';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Future<Directory> _downloadsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/miru_downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String episodeId(String episodeUrl, bool isSub) =>
      '${episodeUrl.trim()}|${isSub ? 'sub' : 'dub'}';

  static bool isLikelyDirectFile(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('master.m3u')) return false;
    if (lower.contains('/embed') || lower.contains('blogger.com')) return false;
    if (RegExp(r'\.(mp4|mkv|webm|avi|mov)(\?|$)', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    return false;
  }

  static EpisodeLink? pickOfflineLink(EpisodeLinksResponse links, {required bool preferSub}) {
    final ordered = preferSub
        ? [
            links.subDownload,
            links.dubDownload,
            links.subStream,
            links.dubStream,
          ]
        : [
            links.dubDownload,
            links.subDownload,
            links.dubStream,
            links.subStream,
          ];

    for (final list in ordered) {
      for (final link in list) {
        if (link.url.isEmpty) continue;
        if (isLikelyDirectFile(link.url)) return link;
      }
    }

    for (final list in ordered) {
      if (list.isNotEmpty && list.first.url.isNotEmpty) {
        return list.first;
      }
    }
    return null;
  }

  static Future<List<DownloadedEpisode>> loadLibrary() async {
    final root = await _downloadsRoot();
    final indexFile = File('${root.path}/$_indexFileName');
    if (!await indexFile.exists()) return [];

    try {
      final raw = json.decode(await indexFile.readAsString()) as List<dynamic>;
      final items = raw
          .map((e) => DownloadedEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
      final valid = <DownloadedEpisode>[];
      for (final item in items) {
        if (await File(item.filePath).exists()) {
          valid.add(item);
        }
      }
      if (valid.length != items.length) {
        await _saveLibrary(valid);
      }
      return valid;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveLibrary(List<DownloadedEpisode> items) async {
    final root = await _downloadsRoot();
    final indexFile = File('${root.path}/$_indexFileName');
    await indexFile.writeAsString(
      json.encode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<DownloadedEpisode?> findDownloaded(String episodeUrl, bool isSub) async {
    final id = episodeId(episodeUrl, isSub);
    final library = await loadLibrary();
    for (final item in library) {
      if (item.id == id) return item;
    }
    return null;
  }

  static String _extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final ext in ['.mp4', '.mkv', '.webm', '.avi', '.mov']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.mp4';
  }

  static Future<DownloadedEpisode> downloadEpisode({
    required String sourceUrl,
    required String serverName,
    required String animeTitle,
    required String animeUrl,
    required String animeImage,
    required double episodeNumber,
    required String episodeUrl,
    required String episodeTitle,
    required bool isSub,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final id = episodeId(episodeUrl, isSub);
    final root = await _downloadsRoot();
    final ext = _extensionFromUrl(sourceUrl);
    final filePath = '${root.path}/$id$ext';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(sourceUrl));
      request.headers['User-Agent'] = _userAgent;
      request.headers['Accept'] = '*/*';
      request.headers['Referer'] = animeUrl;

      final response = await client.send(request).timeout(const Duration(minutes: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('El servidor respondió ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        if (isCancelled?.call() == true) {
          await sink.close();
          if (await file.exists()) await file.delete();
          throw DownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        } else {
          onProgress?.call(-1);
        }
      }

      await sink.close();
      final size = await file.length();
      if (size < 1024 * 50) {
        await file.delete();
        throw Exception('Archivo demasiado pequeño; prueba otro servidor');
      }

      final entry = DownloadedEpisode(
        id: id,
        animeTitle: animeTitle,
        animeUrl: animeUrl,
        animeImage: animeImage,
        episodeNumber: episodeNumber,
        episodeUrl: episodeUrl,
        episodeTitle: episodeTitle,
        isSub: isSub,
        serverName: serverName,
        filePath: filePath,
        fileSizeBytes: size,
        downloadedAt: DateTime.now(),
      );

      final library = await loadLibrary();
      library.removeWhere((e) => e.id == id);
      library.add(entry);
      await _saveLibrary(library);
      return entry;
    } finally {
      client.close();
    }
  }

  static Future<void> deleteDownload(DownloadedEpisode item) async {
    final file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    final library = await loadLibrary();
    library.removeWhere((e) => e.id == item.id);
    await _saveLibrary(library);
  }

  static Future<int> totalStorageBytes() async {
    final library = await loadLibrary();
    var total = 0;
    for (final item in library) {
      final file = File(item.filePath);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }
}

class DownloadCancelledException implements Exception {
  @override
  String toString() => 'Descarga cancelada';
}
