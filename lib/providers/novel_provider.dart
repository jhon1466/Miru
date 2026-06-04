import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/novel.dart';
import '../services/offline_storage_service.dart';

class NovelProvider extends ChangeNotifier {
  static const String _baseUrl = 'https://api.skynovels.net/api';

  // Popular Novels
  List<Novel> _popularNovels = [];
  bool _isLoadingPopular = false;
  String? _popularError;
  int _popularPage = 1;
  bool _hasMorePopular = true;

  List<Novel> get popularNovels => _popularNovels;
  bool get isLoadingPopular => _isLoadingPopular;
  String? get popularError => _popularError;
  bool get hasMorePopular => _hasMorePopular;

  // Search Results
  List<Novel> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  String _lastSearchQuery = '';

  List<Novel> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  // Novel Details
  Novel? _selectedNovel;
  String? _selectedNovelSynopsis;
  List<NovelChapter> _chapters = [];
  bool _isLoadingDetails = false;
  String? _detailsError;

  Novel? get selectedNovel => _selectedNovel;
  String? get selectedNovelSynopsis => _selectedNovelSynopsis;
  List<NovelChapter> get chapters => _chapters;
  bool get isLoadingDetails => _isLoadingDetails;
  String? get detailsError => _detailsError;

  // Chapter Content
  List<String> _chapterParagraphs = [];
  bool _isLoadingContent = false;
  String? _contentError;
  bool _isContentOffline = false;

  List<String> get chapterParagraphs => _chapterParagraphs;
  bool get isLoadingContent => _isLoadingContent;
  String? get contentError => _contentError;
  bool get isContentOffline => _isContentOffline;

  // Load Popular Novels
  Future<void> loadPopularNovels({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMorePopular || _isLoadingPopular) return;
      _popularPage++;
    } else {
      _popularPage = 1;
      _popularNovels = [];
      _hasMorePopular = true;
      _isLoadingPopular = true;
    }
    _popularError = null;
    notifyListeners();

    try {
      final url = '$_baseUrl/novels?order=views&page=$_popularPage&limit=20';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> novelsJson = data['novels'] ?? [];
        final List<Novel> newItems = novelsJson.map((n) => Novel.fromJson(n)).toList();

        if (loadMore) {
          _popularNovels.addAll(newItems);
        } else {
          _popularNovels = newItems;
        }

        _hasMorePopular = newItems.length >= 20;
      } else {
        _popularError = 'Error al cargar populares: ${response.statusCode}';
      }
    } catch (e) {
      _popularError = e.toString();
    } finally {
      _isLoadingPopular = false;
      notifyListeners();
    }
  }

  // Search Novels
  Future<void> searchNovels(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _searchError = null;
      _lastSearchQuery = '';
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchResults = [];
    _searchError = null;
    _lastSearchQuery = trimmed;
    notifyListeners();

    try {
      final url = '$_baseUrl/novels?q=${Uri.encodeComponent(trimmed)}';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> novelsJson = data['novels'] ?? [];
        _searchResults = novelsJson.map((n) => Novel.fromJson(n)).toList();
      } else {
        _searchError = 'Error de búsqueda: ${response.statusCode}';
      }
    } catch (e) {
      _searchError = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // Load Novel Details and Chapters
  Future<void> loadNovelDetails(Novel novel) async {
    _selectedNovel = novel;
    _selectedNovelSynopsis = null;
    _chapters = [];
    _isLoadingDetails = true;
    _detailsError = null;
    notifyListeners();

    try {
      final baseResponse = await http.get(
        Uri.parse('$_baseUrl/novels/${novel.id}/base'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );

      final chaptersResponse = await http.get(
        Uri.parse('$_baseUrl/novel-chapters/${novel.id}'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );

      if (baseResponse.statusCode == 200 && chaptersResponse.statusCode == 200) {
        final baseData = jsonDecode(baseResponse.body);
        final chaptersData = jsonDecode(chaptersResponse.body);

        final novelBase = baseData['novel'];
        if (novelBase != null) {
          _selectedNovelSynopsis = novelBase['nvl_content']?.toString()
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          _selectedNovel = Novel.fromJson(novelBase);
        }

        final novelObj = chaptersData['novel'];
        if (novelObj != null) {
          List<dynamic>? chaptersList;

          if (novelObj is List && novelObj.isNotEmpty) {
            // API returned novel as a JSON array: [{ chapters: [...] }]
            final firstVolume = novelObj[0];
            if (firstVolume is Map && firstVolume['chapters'] != null) {
              chaptersList = firstVolume['chapters'] as List<dynamic>;
            }
          } else if (novelObj is Map) {
            // API returned novel as a JSON object: { "0": { chapters: [...] } }
            final volumeData = novelObj['0'];
            if (volumeData != null && volumeData['chapters'] != null) {
              chaptersList = volumeData['chapters'] as List<dynamic>;
            }
          }

          if (chaptersList != null && chaptersList.isNotEmpty) {
            final List<NovelChapter> list = chaptersList
                .map((c) => NovelChapter.fromJson(c as Map<String, dynamic>))
                .toList();
            list.sort((a, b) => a.number.compareTo(b.number));
            _chapters = list;
          }
        }
      } else {
        _detailsError = 'Error al cargar detalles (Status: ${baseResponse.statusCode} / ${chaptersResponse.statusCode})';
      }
    } catch (e) {
      _detailsError = e.toString();
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  // Load Chapter Paragraphs
  Future<void> loadChapterContent(String chapterUrl, {String? novelId, String? chapterId}) async {
    _chapterParagraphs = [];
    _isLoadingContent = true;
    _contentError = null;
    _isContentOffline = false;
    notifyListeners();

    try {
      // 1. Check offline cache first
      if (novelId != null && chapterId != null) {
        final isDownloaded = await OfflineStorageService.isNovelChapterDownloaded(novelId, chapterId);
        if (isDownloaded) {
          final localParagraphs = await OfflineStorageService.getNovelChapterParagraphs(novelId, chapterId);
          if (localParagraphs.isNotEmpty) {
            _chapterParagraphs = localParagraphs;
            _isContentOffline = true;
            return;
          }
        }
      }
      final response = await http.get(
        Uri.parse('$_baseUrl/chapters/$chapterUrl'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final bodyJson = jsonDecode(response.body);
        final chapterData = bodyJson['chapter'];
        if (chapterData != null) {
          final content = chapterData['chp_content']?.toString() ?? '';

          final pRegex = RegExp(r'<p[^>]*>([\s\S]*?)<\/p>');
          final matches = pRegex.allMatches(content);

          final List<String> paragraphs = [];
          if (matches.isNotEmpty) {
            for (final m in matches) {
              final text = m.group(1)!
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&emsp;', ' ')
                  .replaceAll('&nbsp;', ' ')
                  .replaceAll('&amp;', '&')
                  .replaceAll('&#8211;', '—')
                  .replaceAll('&#8217;', "'")
                  .replaceAll('&#8220;', '"')
                  .replaceAll('&#8221;', '"')
                  .trim();
              if (text.isNotEmpty && !text.contains('All rights reserved') && !text.contains('derechos reservados')) {
                paragraphs.add(text);
              }
            }
          } else {
            final lines = content.split('\n');
            for (var line in lines) {
              final text = line
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&emsp;', ' ')
                  .replaceAll('&nbsp;', ' ')
                  .replaceAll('&amp;', '&')
                  .replaceAll('&#8211;', '—')
                  .replaceAll('&#8217;', "'")
                  .replaceAll('&#8220;', '"')
                  .replaceAll('&#8221;', '"')
                  .trim();
              if (text.isNotEmpty && !text.contains('All rights reserved') && !text.contains('derechos reservados')) {
                paragraphs.add(text);
              }
            }
          }

          _chapterParagraphs = paragraphs;
        } else {
          _contentError = 'Error: No se encontró contenido del capítulo.';
        }
      } else {
        _contentError = 'Error al cargar contenido: ${response.statusCode}';
      }
    } catch (e) {
      _contentError = e.toString();
    } finally {
      _isLoadingContent = false;
      notifyListeners();
    }
  }
}

