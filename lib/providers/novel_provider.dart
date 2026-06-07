import 'package:flutter/material.dart';
import '../models/novel.dart';
import '../services/offline_storage_service.dart';
import '../services/sky_novels_service.dart';

class NovelProvider extends ChangeNotifier {
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
      final newItems = await SkyNovelsService.fetchPopularNovels(page: _popularPage);

      if (loadMore) {
        _popularNovels.addAll(newItems);
      } else {
        _popularNovels = newItems;
      }

      _hasMorePopular = newItems.length >= 20;
    } catch (e) {
      _popularError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingPopular = false;
      notifyListeners();
    }
  }

  Future<void> searchNovels(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _searchError = null;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchResults = [];
    _searchError = null;
    notifyListeners();

    try {
      _searchResults = await SkyNovelsService.searchNovels(trimmed);
    } catch (e) {
      _searchError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> loadNovelDetails(Novel novel) async {
    _selectedNovel = novel;
    _selectedNovelSynopsis = null;
    _chapters = [];
    _isLoadingDetails = true;
    _detailsError = null;
    notifyListeners();

    try {
      final details = await SkyNovelsService.fetchNovelDetails(novel.id);
      if (details != null) {
        _selectedNovelSynopsis = details['synopsis']?.toString();
        _chapters = (details['chapters'] as List<NovelChapter>?) ?? [];

        final updatedNovel = details['novel'] as Novel?;
        if (updatedNovel != null) {
          _selectedNovel = updatedNovel;
        } else if (details['coverUrl'] != null && details['coverUrl'].toString().isNotEmpty) {
          _selectedNovel = Novel(
            id: novel.id,
            title: novel.title,
            url: novel.url,
            coverUrl: details['coverUrl'].toString(),
            status: novel.status,
            author: novel.author,
          );
        }
      } else {
        _detailsError = 'No se pudieron cargar los detalles de la novela.';
      }
    } catch (e) {
      _detailsError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  Future<void> loadChapterContent(String chapterUrl, {String? novelId, String? chapterId}) async {
    _chapterParagraphs = [];
    _isLoadingContent = true;
    _contentError = null;
    _isContentOffline = false;
    notifyListeners();

    try {
      if (novelId != null && chapterId != null) {
        final isDownloaded = await OfflineStorageService.isNovelChapterDownloaded(novelId, chapterId);
        if (isDownloaded) {
          final localParagraphs = await OfflineStorageService.getNovelChapterParagraphs(novelId, chapterId);
          if (localParagraphs.isNotEmpty) {
            // Re-aplica limpieza por si el caché tiene espacios sin limpiar
            _chapterParagraphs = localParagraphs
                .map(SkyNovelsService.cleanParagraph)
                .where((p) => p.isNotEmpty)
                .toList();
            _isContentOffline = true;
            return;
          }
        }
      }

      _chapterParagraphs = await SkyNovelsService.fetchChapterContent(chapterUrl);
      if (_chapterParagraphs.isEmpty) {
        _contentError = 'No se encontró contenido en este capítulo.';
      }
    } catch (e) {
      _contentError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingContent = false;
      notifyListeners();
    }
  }
}
