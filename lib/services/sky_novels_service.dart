import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/novel.dart';

class SkyNovelsService {
  static const String baseUrl = 'https://api.skynovels.net/api';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static Future<List<Novel>> fetchPopularNovels({int page = 1, int limit = 20}) async {
    final url = '$baseUrl/novels?order=views&page=$page&limit=$limit';
    final response = await http.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar populares: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final novelsJson = data['novels'] as List<dynamic>? ?? [];
    return novelsJson
        .map((n) => Novel.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Novel>> searchNovels(String query) async {
    final url = '$baseUrl/novels?q=${Uri.encodeComponent(query)}';
    final response = await http.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Error de búsqueda: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final novelsJson = data['novels'] as List<dynamic>? ?? [];
    return novelsJson
        .map((n) => Novel.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, dynamic>?> fetchNovelDetails(String novelId) async {
    final baseResponse = await http.get(
      Uri.parse('$baseUrl/novels/$novelId/base'),
      headers: _headers,
    );
    final chaptersResponse = await http.get(
      Uri.parse('$baseUrl/novel-chapters/$novelId'),
      headers: _headers,
    );

    if (baseResponse.statusCode != 200 || chaptersResponse.statusCode != 200) {
      debugPrint(
        'SkyNovels details error: ${baseResponse.statusCode} / ${chaptersResponse.statusCode}',
      );
      return null;
    }

    final baseData = jsonDecode(baseResponse.body) as Map<String, dynamic>;
    final chaptersData = jsonDecode(chaptersResponse.body) as Map<String, dynamic>;

    String synopsis = '';
    String? coverUrl;
    Novel? novel;

    final novelBase = baseData['novel'];
    if (novelBase is Map<String, dynamic>) {
      synopsis = novelBase['nvl_content']?.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      novel = Novel.fromJson(novelBase);
      coverUrl = novel.coverUrl;
    }

    final chapters = <NovelChapter>[];
    final novelObj = chaptersData['novel'];
    List<dynamic>? chaptersList;

    if (novelObj is List && novelObj.isNotEmpty) {
      final firstVolume = novelObj[0];
      if (firstVolume is Map && firstVolume['chapters'] != null) {
        chaptersList = firstVolume['chapters'] as List<dynamic>;
      }
    } else if (novelObj is Map) {
      final volumeData = novelObj['0'];
      if (volumeData is Map && volumeData['chapters'] != null) {
        chaptersList = volumeData['chapters'] as List<dynamic>;
      }
    }

    if (chaptersList != null && chaptersList.isNotEmpty) {
      chapters.addAll(
        chaptersList.map((c) => NovelChapter.fromJson(c as Map<String, dynamic>)),
      );
      chapters.sort((a, b) => a.number.compareTo(b.number));
    }

    return {
      'synopsis': synopsis,
      'coverUrl': coverUrl ?? '',
      'novel': novel,
      'chapters': chapters,
    };
  }

  static Future<List<String>> fetchChapterContent(String chapterId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chapters/$chapterId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al cargar contenido: ${response.statusCode}');
    }

    final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
    final chapterData = bodyJson['chapter'];
    if (chapterData is! Map<String, dynamic>) return [];

    final content = chapterData['chp_content']?.toString() ?? '';
    return _parseChapterContent(content);
  }

  static List<String> _parseChapterContent(String content) {
    final pRegex = RegExp(r'<p[^>]*>([\s\S]*?)<\/p>');
    final matches = pRegex.allMatches(content);
    final paragraphs = <String>[];

    if (matches.isNotEmpty) {
      for (final m in matches) {
        final text = _decodeHtmlText(m.group(1) ?? '');
        if (text.isNotEmpty && !_isSpamParagraph(text)) {
          paragraphs.add(text);
        }
      }
    } else {
      for (final line in content.split('\n')) {
        final text = _decodeHtmlText(line);
        if (text.isNotEmpty && !_isSpamParagraph(text)) {
          paragraphs.add(text);
        }
      }
    }

    return paragraphs;
  }

  /// Limpieza pública — usada también para re-limpiar párrafos del caché.
  static String cleanParagraph(String raw) => _decodeHtmlText(raw);

  static String _decodeHtmlText(String raw) {
    // 1. Elimina <img> sin dejar espacio
    var s = raw.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '');
    // 2. <br> → espacio simple
    s = s.replaceAll(RegExp(r'<br[^>]*>', caseSensitive: false), ' ');
    // 3. Resto de tags HTML
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    // 4. Entidades HTML
    s = s
        .replaceAll('&emsp;',  ' ')
        .replaceAll('&ensp;',  ' ')
        .replaceAll('&nbsp;',  ' ')
        .replaceAll('&amp;',   '&')
        .replaceAll('&lt;',    '<')
        .replaceAll('&gt;',    '>')
        .replaceAll('&quot;',  '"')
        .replaceAll("&apos;",  "'")
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8212;', '—')
        .replaceAll('&#8216;', '‘')
        .replaceAll('&#8217;', '’')
        .replaceAll('&#8220;', '“')
        .replaceAll('&#8221;', '”')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rsquo;', '’');
    // 5. Caracteres unicode de espacio especial → espacio normal o vacío
    s = s
        .replaceAll(' ', ' ')  // non-breaking space
        .replaceAll('​', '')   // zero-width space
        .replaceAll('‌', '')   // zero-width non-joiner
        .replaceAll('‍', '')   // zero-width joiner
        .replaceAll('﻿', '')   // BOM
        .replaceAll(' ', ' ')  // em space
        .replaceAll(' ', ' ')  // en space
        .replaceAll(' ', ' ')  // thin space
        .replaceAll('­', '');  // soft hyphen
    // 6. Colapsa múltiples espacios/tabs en uno solo
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    return s.trim();
  }

  static bool _isSpamParagraph(String text) {
    final lower = text.toLowerCase();
    return lower.contains('all rights reserved') || lower.contains('derechos reservados');
  }
}
