import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga.dart';
import '../services/offline_storage_service.dart';

class MangaProvider extends ChangeNotifier {
  static const String _baseUrl = 'https://inmanga.com';
  static const String _historyKeyPrefix = 'manga_progress_';

  // Popular Manga
  List<Manga> _popularManga = [];
  bool _isLoadingPopular = false;
  bool _isLoadingMorePopular = false;
  String? _popularError;
  int _popularOffset = 0;
  bool _hasMorePopular = true;
  static const int _pageSize = 30;

  List<Manga> get popularManga => _popularManga;
  bool get isLoadingPopular => _isLoadingPopular;
  bool get isLoadingMorePopular => _isLoadingMorePopular;
  String? get popularError => _popularError;
  bool get hasMorePopular => _hasMorePopular;

  // Search Results
  List<Manga> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingMoreSearch = false;
  String? _searchError;
  int _searchOffset = 0;
  bool _hasMoreSearch = true;
  String _lastSearchQuery = '';

  List<Manga> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get isLoadingMoreSearch => _isLoadingMoreSearch;
  String? get searchError => _searchError;
  bool get hasMoreSearch => _hasMoreSearch;

  // Manga details
  Manga? _selectedManga;
  bool _isLoadingDetails = false;
  String? _detailsError;

  Manga? get selectedManga => _selectedManga;
  bool get isLoadingDetails => _isLoadingDetails;
  String? get detailsError => _detailsError;

  // Chapters list
  List<MangaChapter> _chapters = [];
  bool _isLoadingChapters = false;
  bool _isLoadingMoreChapters = false;
  String? _chaptersError;
  int _chaptersOffset = 0;
  bool _hasMoreChapters = false; // InManga returns all chapters in a single API call

  List<MangaChapter> get chapters => _chapters;
  bool get isLoadingChapters => _isLoadingChapters;
  bool get isLoadingMoreChapters => _isLoadingMoreChapters;
  String? get chaptersError => _chaptersError;
  bool get hasMoreChapters => _hasMoreChapters;

  // Chapter Pages
  List<String> _chapterPages = [];
  bool _isLoadingPages = false;
  String? _pagesError;
  bool _isPagesOffline = false;

  List<String> get chapterPages => _chapterPages;
  bool get isLoadingPages => _isLoadingPages;
  String? get pagesError => _pagesError;
  bool get isPagesOffline => _isPagesOffline;

  // Popular Manga — paginado con sortby=2 (más vistos)
  Future<void> loadPopularManga({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMorePopular || _isLoadingMorePopular) return;
      _isLoadingMorePopular = true;
    } else {
      _isLoadingPopular = true;
      _popularOffset = 0;
      _hasMorePopular = true;
      _popularManga = [];
      _popularError = null;
    }
    notifyListeners();

    try {
      final uri = Uri.parse('$_baseUrl/manga/getMangasConsultResult');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: {
          'filter[queryString]': '',
          'filter[skip]': _popularOffset.toString(),
          'filter[take]': _pageSize.toString(),
          'filter[sortby]': '2',
          'filter[broadcastStatus]': '0',
          'filter[onlyFavorites]': 'false',
        },
      );

      if (response.statusCode == 200) {
        final html = response.body;
        final mangaRegex = RegExp(r'<a href="([^"]*/ver/manga/[^"]*)"[^>]*>([\s\S]*?)</a>');
        final matches = mangaRegex.allMatches(html);

        final List<Manga> newItems = [];
        for (final m in matches) {
          final block = m.group(0) ?? '';
          final manga = Manga.fromInMangaHtml(block, isPopular: false);
          if (manga.id.isNotEmpty && manga.title.isNotEmpty) {
            newItems.add(manga);
          }
        }

        _popularOffset += newItems.length;
        _hasMorePopular = newItems.length == _pageSize;

        if (loadMore) {
          _popularManga.addAll(newItems);
        } else {
          _popularManga = newItems;
        }
      } else {
        _popularError = 'Error al cargar populares: ${response.statusCode}';
      }
    } catch (e) {
      _popularError = e.toString();
    } finally {
      _isLoadingPopular = false;
      _isLoadingMorePopular = false;
      notifyListeners();
    }
  }

  // Search Manga
  Future<void> searchManga(String query, {bool loadMore = false}) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _isLoadingMoreSearch = false;
      _searchOffset = 0;
      _hasMoreSearch = true;
      _lastSearchQuery = '';
      notifyListeners();
      return;
    }

    if (loadMore) {
      if (!_hasMoreSearch || _isLoadingMoreSearch) return;
      _isLoadingMoreSearch = true;
    } else {
      _isSearching = true;
      _searchOffset = 0;
      _hasMoreSearch = true;
      _searchResults = [];
      _lastSearchQuery = trimmedQuery;
    }
    _searchError = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$_baseUrl/manga/getMangasConsultResult');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: {
          'filter[queryString]': _lastSearchQuery,
          'filter[skip]': _searchOffset.toString(),
          'filter[take]': _pageSize.toString(),
          'filter[sortby]': '1',
          'filter[broadcastStatus]': '0',
          'filter[onlyFavorites]': 'false',
        },
      );

      if (response.statusCode == 200) {
        final html = response.body;
        final mangaRegex = RegExp(r'<a href="([^"]*\/ver\/manga\/[^"]*)"[^>]*>([\s\S]*?)<\/a>');
        final matches = mangaRegex.allMatches(html);
        
        final List<Manga> newItems = [];
        for (final m in matches) {
          final block = m.group(0) ?? '';
          final manga = Manga.fromInMangaHtml(block, isPopular: false);
          if (manga.id.isNotEmpty && manga.title.isNotEmpty) {
            newItems.add(manga);
          }
        }

        _searchOffset += newItems.length;
        _hasMoreSearch = newItems.length == _pageSize;

        if (loadMore) {
          _searchResults.addAll(newItems);
        } else {
          _searchResults = newItems;
        }
      } else {
        _searchError = 'Error de búsqueda: ${response.statusCode}';
      }
    } catch (e) {
      _searchError = e.toString();
    } finally {
      _isSearching = false;
      _isLoadingMoreSearch = false;
      notifyListeners();
    }
  }

  // Load Manga Details
  Future<void> loadMangaDetails(String mangaId) async {
    _isLoadingDetails = true;
    _detailsError = null;
    _selectedManga = null;
    notifyListeners();

    try {
      // InManga ignores the slug part, so we can use a dummy slug 'a'
      final uri = Uri.parse('$_baseUrl/ver/manga/a/$mangaId');
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        _selectedManga = Manga.fromInMangaDetailHtml(mangaId, response.body);
      } else {
        _detailsError = 'Error al cargar detalles: ${response.statusCode}';
      }
    } catch (e) {
      _detailsError = e.toString();
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  // Load Chapters
  Future<void> loadChapters(String mangaId, {bool loadMore = false, List<String>? languages}) async {
    if (loadMore) return; // InManga returns all chapters in a single API call

    _isLoadingChapters = true;
    _chaptersOffset = 0;
    _hasMoreChapters = false;
    _chapters = [];
    _chaptersError = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$_baseUrl/chapter/getall').replace(queryParameters: {
        'mangaIdentification': mangaId,
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final Map<String, dynamic> outerJson = json.decode(data['data'] as String);
        final List<dynamic> list = outerJson['result'] as List? ?? [];
        
        final newItems = list.map((item) => MangaChapter.fromInMangaJson(item)).toList();

        // Ordenar capítulos de forma descendente por número
        newItems.sort((a, b) {
          final aNum = double.tryParse(a.chapterNumber) ?? 0.0;
          final bNum = double.tryParse(b.chapterNumber) ?? 0.0;
          return bNum.compareTo(aNum);
        });

        _chapters = newItems;
        _hasMoreChapters = false;
      } else {
        _chaptersError = 'Error al cargar capítulos: ${response.statusCode}';
      }
    } catch (e) {
      _chaptersError = e.toString();
    } finally {
      _isLoadingChapters = false;
      notifyListeners();
    }
  }

  // Load Chapter Pages
  Future<void> loadChapterPages(String chapterId, String mangaId) async {
    _isLoadingPages = true;
    _pagesError = null;
    _chapterPages = [];
    _isPagesOffline = false;
    notifyListeners();

    try {
      // 1. Check offline cache first
      final isDownloaded = await OfflineStorageService.isMangaChapterDownloaded(mangaId, chapterId);
      if (isDownloaded) {
        final localPages = await OfflineStorageService.getMangaChapterPages(mangaId, chapterId);
        if (localPages.isNotEmpty) {
          _chapterPages = localPages;
          _isPagesOffline = true;
          return;
        }
      }

      // 2. Fetch from network
      final uri = Uri.parse('$_baseUrl/chapter/chapterIndexControls').replace(queryParameters: {
        'identification': chapterId,
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        final html = response.body;
        
        // Extract PageList select inner content
        final selectMatch = RegExp(r'<select[^>]*id="PageList"[^>]*>([\s\S]*?)<\/select>').firstMatch(html);
        if (selectMatch != null) {
          final selectInnerHtml = selectMatch.group(1) ?? '';
          final pageOptionRegex = RegExp(r'<option[^>]*value="([^"]*)"[^>]*>\s*([\s\S]*?)\s*<\/option>');
          final matches = pageOptionRegex.allMatches(selectInnerHtml);
          
          final chapterIdLower = chapterId.toLowerCase();
          _chapterPages = matches.map((m) {
            final pageId = m.group(1) ?? '';
            return 'https://cdn1.intomanga.com/i/m/$mangaId/c/$chapterIdLower/o/$pageId.jpg';
          }).toList();
        } else {
          _pagesError = 'Error al estructurar el listador de páginas.';
        }
      } else {
        _pagesError = 'Error al obtener páginas: ${response.statusCode}';
      }
    } catch (e) {
      _pagesError = e.toString();
    } finally {
      _isLoadingPages = false;
      notifyListeners();
    }
  }

  // Leer progreso local
  Future<Map<String, String>?> getReadingProgress(String mangaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('$_historyKeyPrefix$mangaId');
      if (val != null) {
        final decoded = json.decode(val) as Map<String, dynamic>;
        return {
          'chapterId': decoded['chapterId']?.toString() ?? '',
          'chapterNumber': decoded['chapterNumber']?.toString() ?? '',
          'page': decoded['page']?.toString() ?? '1',
        };
      }
    } catch (_) {}
    return null;
  }

  // Guardar progreso local
  Future<void> saveReadingProgress(String mangaId, String chapterId, String chapterNumber, int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'chapterId': chapterId,
        'chapterNumber': chapterNumber,
        'page': page,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString('$_historyKeyPrefix$mangaId', json.encode(data));
      notifyListeners();
    } catch (_) {}
  }
}
