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
    if (lower.contains('/embed') &&
        !lower.contains('mp4upload.com') &&
        !lower.contains('pixeldrain.com') &&
        !lower.contains('streamtape.com')) {
      return false;
    }
    if (lower.contains('blogger.com')) return false;
    if (RegExp(r'\.(mp4|mkv|webm|avi|mov)(\?|$)', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    if (lower.contains('pixeldrain.com') ||
        lower.contains('mp4upload.com') ||
        lower.contains('streamtape.com')) {
      return true;
    }
    return false;
  }

  static Future<ResolvedDownloadLink> resolveDirectUrl(
    String url, {
    String? serverName,
    required String animeUrl,
  }) async {
    final lower = url.toLowerCase();
    final defaultHeaders = {
      'User-Agent': _userAgent,
      'Accept': '*/*',
      'Referer': animeUrl,
    };
    
    // 1. Pixeldrain
    if (lower.contains('pixeldrain.com')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final segments = uri.pathSegments;
        String? fileId;
        final uIndex = segments.indexOf('u');
        if (uIndex != -1 && uIndex < segments.length - 1) {
          fileId = segments[uIndex + 1];
        } else {
          final fileIndex = segments.indexOf('file');
          if (fileIndex != -1 && fileIndex < segments.length - 1) {
            fileId = segments[fileIndex + 1];
          }
        }
        if (fileId == null && segments.isNotEmpty) {
          fileId = segments.last;
        }
        if (fileId != null) {
          fileId = fileId.split('?').first;
          final directUrl = 'https://pixeldrain.com/api/file/$fileId';
          return ResolvedDownloadLink(
            url: directUrl,
            headers: {
              'User-Agent': _userAgent,
              'Accept': '*/*',
              'Referer': 'https://pixeldrain.com/',
            },
          );
        }
      }
    }

    // 2. MP4Upload
    if (lower.contains('mp4upload.com')) {
      String embedUrl = url;
      final match = RegExp(r'mp4upload\.com/(?:embed-)?([a-zA-Z0-9]+)').firstMatch(url);
      if (match != null) {
        final id = match.group(1);
        embedUrl = 'https://www.mp4upload.com/embed-$id.html';
      }
      
      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(embedUrl));
        request.headers['User-Agent'] = _userAgent;
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final html = await response.stream.bytesToString();
          final srcMatch = RegExp(r"""player\.src\(\{\s*type:\s*["']video/mp4["']\s*,\s*src:\s*["'](https://[^"']+)["']""").firstMatch(html) ??
                           RegExp(r"""src:\s*["'](https://[^"']+\.mp4[^"']*)["']""").firstMatch(html);
          if (srcMatch != null) {
            final directUrl = srcMatch.group(1)!;
            final resolvedUri = Uri.tryParse(directUrl);
            return ResolvedDownloadLink(
              url: directUrl,
              headers: {
                'User-Agent': _userAgent,
                'Accept': '*/*',
                'Referer': 'https://www.mp4upload.com/',
                if (resolvedUri != null) 'Origin': '${resolvedUri.scheme}://${resolvedUri.host}',
              },
            );
          }
        }
      } catch (e) {
        // Fallback silently
      }
    }
    
    // 3. StreamTape
    if (lower.contains('streamtape.com')) {
      try {
        String embedUrl = url;
        if (url.contains('/v/')) {
          embedUrl = url.replaceAll('/v/', '/e/');
        }
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(embedUrl));
        request.headers['User-Agent'] = _userAgent;
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final html = await response.stream.bytesToString();
          
          final mainMatch = RegExp(r"innerHTML\s*=\s*'([^']+)'\s*\+\s*\('([^']+)'\)").firstMatch(html) ??
                            RegExp(r'innerHTML\s*=\s*"([^"]+)"\s*\+\s*\("([^"]+)"\)').firstMatch(html);
          if (mainMatch != null) {
            final prefix = mainMatch.group(1)!;
            var tokenPart = mainMatch.group(2)!;
            
            final idx = html.indexOf(mainMatch.group(0)!);
            final jsSnippet = html.substring(idx + mainMatch.group(0)!.length);
            final endOfStatement = jsSnippet.indexOf(';');
            if (endOfStatement != -1) {
              final stmt = jsSnippet.substring(0, endOfStatement);
              final subMatches = RegExp(r'\.substring\((\d+)\)').allMatches(stmt);
              for (final m in subMatches) {
                final val = int.tryParse(m.group(1) ?? '') ?? 0;
                if (val > 0 && val <= tokenPart.length) {
                  tokenPart = tokenPart.substring(val);
                }
              }
            }
            final directUrl = 'https:$prefix$tokenPart';
            return ResolvedDownloadLink(
              url: directUrl,
              headers: {
                'User-Agent': _userAgent,
                'Accept': '*/*',
                'Referer': 'https://streamtape.com/',
              },
            );
          }
        }
      } catch (e) {
        // Fallback silently
      }
    }

    return ResolvedDownloadLink(url: url, headers: defaultHeaders);
  }

  /// Solo enlaces de descarga directa (nunca streaming / m3u8).
  static List<EpisodeLink> listOfflineCandidates(
    EpisodeLinksResponse links, {
    required bool preferSub,
  }) {
    final ordered = preferSub
        ? [links.subDownload, links.dubDownload]
        : [links.dubDownload, links.subDownload];

    final seen = <String>{};
    final out = <EpisodeLink>[];
    for (final list in ordered) {
      for (final link in list) {
        if (link.url.isEmpty || seen.contains(link.url)) continue;
        if (!isLikelyDirectFile(link.url)) continue;
        seen.add(link.url);
        out.add(link);
      }
    }
    return out;
  }

  static EpisodeLink? pickOfflineLink(EpisodeLinksResponse links, {required bool preferSub}) {
    final candidates = listOfflineCandidates(links, preferSub: preferSub);
    return candidates.isEmpty ? null : candidates.first;
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

  static String _safeFilename(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
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
    void Function(double progress, int receivedBytes, int? totalBytes, double speed)? onProgress,
    bool Function()? isCancelled,
    bool Function()? isPaused,
  }) async {
    final id = episodeId(episodeUrl, isSub);
    final root = await _downloadsRoot();
    
    // Resolver la URL real del archivo si es un hosting de terceros
    final resolved = await resolveDirectUrl(sourceUrl, serverName: serverName, animeUrl: animeUrl);
    
    final ext = _extensionFromUrl(resolved.url);
    final filePath = '${root.path}/${_safeFilename(id)}$ext';
    final file = File(filePath);

    int startBytes = 0;
    if (await file.exists()) {
      startBytes = await file.length();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(resolved.url));
      request.headers.addAll(resolved.headers);

      if (startBytes > 0) {
        request.headers['Range'] = 'bytes=$startBytes-';
      }

      final response = await client.send(request).timeout(const Duration(minutes: 30));
      
      IOSink sink;
      int received;
      int? total;

      if (response.statusCode == 206) {
        sink = file.openWrite(mode: FileMode.append);
        received = startBytes;
        total = response.contentLength != null ? response.contentLength! + startBytes : null;
      } else if (response.statusCode == 200) {
        sink = file.openWrite(mode: FileMode.write);
        received = 0;
        total = response.contentLength;
      } else if (response.statusCode == 416) {
        throw Exception('El servidor no admite reanudación en este punto (416).');
      } else {
        throw Exception('El servidor respondió ${response.statusCode}');
      }

      final stopwatch = Stopwatch()..start();
      int lastCheckedBytes = received;
      int lastCheckedTimeMs = 0;
      double speed = 0.0;

      await for (final chunk in response.stream) {
        if (isCancelled?.call() == true) {
          await sink.close();
          if (await file.exists()) await file.delete();
          throw DownloadCancelledException();
        }
        if (isPaused?.call() == true) {
          await sink.close();
          throw DownloadPausedException();
        }
        sink.add(chunk);
        received += chunk.length;

        final nowMs = stopwatch.elapsedMilliseconds;
        final elapsedSinceLastCheck = nowMs - lastCheckedTimeMs;
        if (elapsedSinceLastCheck >= 1000) {
          final bytesSinceLastCheck = received - lastCheckedBytes;
          speed = (bytesSinceLastCheck / (1024.0 * 1024.0)) / (elapsedSinceLastCheck / 1000.0);
          lastCheckedBytes = received;
          lastCheckedTimeMs = nowMs;
        }

        onProgress?.call(
          total != null && total > 0 ? received / total : -1,
          received,
          total,
          speed,
        );
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

class DownloadPausedException implements Exception {
  @override
  String toString() => 'Descarga pausada';
}

class ResolvedDownloadLink {
  final String url;
  final Map<String, String> headers;
  
  ResolvedDownloadLink({required this.url, required this.headers});
}
