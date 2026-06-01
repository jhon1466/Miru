import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../core/api_client.dart';

class AnimeProvider extends ChangeNotifier {
  // Búsqueda
  List<AnimeSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  List<AnimeSearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  // Detalle de Anime
  AnimeDetails? _selectedAnime;
  bool _isLoadingDetails = false;
  String? _detailsError;

  AnimeDetails? get selectedAnime => _selectedAnime;
  bool get isLoadingDetails => _isLoadingDetails;
  String? get detailsError => _detailsError;

  // Enlaces de Episodio
  EpisodeLinksResponse? _episodeLinks;
  bool _isLoadingEpisode = false;
  String? _episodeError;

  EpisodeLinksResponse? get episodeLinks => _episodeLinks;
  bool get isLoadingEpisode => _isLoadingEpisode;
  String? get episodeError => _episodeError;

  // Animes Populares
  List<AnimeSearchResult> _popularAnime = [];
  bool _isLoadingPopular = false;
  String? _popularError;

  List<AnimeSearchResult> get popularAnime => _popularAnime;
  bool get isLoadingPopular => _isLoadingPopular;
  String? get popularError => _popularError;

  // Episodios recién publicados
  List<LatestPublishedEpisode> _latestPublishedEpisodes = [];
  bool _isLoadingLatestEpisodes = false;
  String? _latestEpisodesError;

  List<LatestPublishedEpisode> get latestPublishedEpisodes => _latestPublishedEpisodes;
  bool get isLoadingLatestEpisodes => _isLoadingLatestEpisodes;
  String? get latestEpisodesError => _latestEpisodesError;

  // Proveedores
  String _selectedProviderDomain = ''; // '' = Todos
  final List<Map<String, String>> _providers = [
    {'name': 'Todos', 'domain': ''},
    {'name': 'AnimeAV1', 'domain': 'animeav1.com'},
    {'name': 'AnimeFLV', 'domain': 'animeflv.net'},
    {'name': 'TioAnime', 'domain': 'tioanime.com'},
    {'name': 'MonosChinos', 'domain': 'monoschinos2.com'},
    {'name': 'HentaiLA', 'domain': 'hentaila.com'},
  ];

  String get selectedProviderDomain => _selectedProviderDomain;
  List<Map<String, String>> get providers => _providers;

  void selectProvider(String domain) {
    _selectedProviderDomain = domain;
    notifyListeners();
    loadPopularAnime();
    loadLatestPublishedEpisodes();
    if (_catalogAll.isNotEmpty) {
      loadCatalog();
    }
  }

  // Buscar Anime
  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      _searchResults = await ApiClient.searchAnime(
        query,
        domain: _selectedProviderDomain.isEmpty ? null : _selectedProviderDomain,
      );
    } catch (e) {
      _searchError = e.toString().replaceAll('Exception: ', '');
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // Cargar Detalle de Anime
  Future<void> loadAnimeDetails(String animeUrl) async {
    _isLoadingDetails = true;
    _detailsError = null;
    _selectedAnime = null;
    notifyListeners();

    try {
      _selectedAnime = await ApiClient.getAnimeInfo(animeUrl);
    } catch (e) {
      _detailsError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  // Cargar Enlaces de Episodio
  Future<void> loadEpisodeLinks(String episodeUrl) async {
    _isLoadingEpisode = true;
    _episodeError = null;
    _episodeLinks = null;
    notifyListeners();

    try {
      _episodeLinks = await ApiClient.getEpisodeLinks(episodeUrl);
    } catch (e) {
      _episodeError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingEpisode = false;
      notifyListeners();
    }
  }

  // Cargar Animes Populares
  Future<void> loadPopularAnime() async {
    _isLoadingPopular = true;
    _popularError = null;
    notifyListeners();

    try {
      _popularAnime = await ApiClient.getPopularAnime(
        domain: _selectedProviderDomain.isEmpty ? null : _selectedProviderDomain,
      );
    } catch (e) {
      _popularError = e.toString().replaceAll('Exception: ', '');
      _popularAnime = [];
    } finally {
      _isLoadingPopular = false;
      notifyListeners();
    }
  }

  Future<void> loadLatestPublishedEpisodes() async {
    _isLoadingLatestEpisodes = true;
    _latestEpisodesError = null;
    notifyListeners();

    try {
      _latestPublishedEpisodes = await ApiClient.getLatestPublishedEpisodes(
        domain: _selectedProviderDomain.isEmpty ? null : _selectedProviderDomain,
      );
    } catch (e) {
      _latestEpisodesError = e.toString().replaceAll('Exception: ', '');
      _latestPublishedEpisodes = [];
    } finally {
      _isLoadingLatestEpisodes = false;
      notifyListeners();
    }
  }

  // Catálogo
  List<AnimeSearchResult> _catalogResults = [];
  List<AnimeSearchResult> _catalogAll = [];
  bool _isLoadingCatalog = false;
  bool _isLoadingMoreCatalog = false;
  bool _catalogHasMore = true;
  int _catalogPage = 1;
  int? _catalogTotalRecords;
  int? _catalogTotalPages;
  String? _catalogError;
  String _catalogGenre = '';
  String _catalogYear = '';
  String _catalogType = '';
  String _catalogStatus = '';
  String _catalogQuery = '';
  List<String> _facetGenres = [];
  List<String> _facetYears = [];
  List<String> _facetTypes = [];
  List<String> _facetStatuses = [];

  List<AnimeSearchResult> get catalogResults => _catalogResults;
  bool get isLoadingCatalog => _isLoadingCatalog;
  bool get isLoadingMoreCatalog => _isLoadingMoreCatalog;
  bool get catalogHasMore => _catalogHasMore;
  int? get catalogTotalRecords => _catalogTotalRecords;
  int? get catalogTotalPages => _catalogTotalPages;
  String? get catalogError => _catalogError;
  String get catalogGenre => _catalogGenre;
  String get catalogYear => _catalogYear;
  String get catalogType => _catalogType;
  String get catalogStatus => _catalogStatus;
  String get catalogQuery => _catalogQuery;
  List<String> get facetGenres => _facetGenres;
  List<String> get facetYears => _facetYears;
  List<String> get facetTypes => _facetTypes;
  List<String> get facetStatuses => _facetStatuses;

  void setCatalogGenre(String v) {
    _catalogGenre = v;
    notifyListeners();
  }

  void setCatalogYear(String v) {
    _catalogYear = v;
    notifyListeners();
  }

  void setCatalogType(String v) {
    _catalogType = v;
    notifyListeners();
  }

  void setCatalogStatus(String v) {
    _catalogStatus = v;
    notifyListeners();
  }

  void setCatalogQuery(String v) {
    _catalogQuery = v;
    notifyListeners();
  }

  void clearCatalogFilters() {
    _catalogGenre = '';
    _catalogYear = '';
    _catalogType = '';
    _catalogStatus = '';
    _catalogQuery = '';
    notifyListeners();
  }

  void _parseFacets(Map<String, dynamic>? facets) {
    if (facets == null) return;
    _facetGenres = _stringListFrom(facets['genres']);
    _facetYears = _stringListFrom(facets['years']);
    _facetTypes = _stringListFrom(facets['types']);
    _facetStatuses = _stringListFrom(facets['statuses']);
  }

  List<String> _stringListFrom(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  /// Filtro local solo para búsqueda por título mientras el usuario escribe.
  /// Año, género, tipo y estado los aplica el backend.
  List<AnimeSearchResult> _filterCatalogPage(List<AnimeSearchResult> items) {
    if (_catalogQuery.isEmpty) return items;
    final q = _catalogQuery.toLowerCase();
    return items
        .where((anime) =>
            anime.title.toLowerCase().contains(q) ||
            (anime.slug ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> loadCatalog({bool refresh = true}) async {
    if (refresh) {
      if (_isLoadingCatalog) return;
      _catalogPage = 1;
      _catalogHasMore = true;
      _catalogAll = [];
      _catalogResults = [];
      _isLoadingCatalog = true;
      _catalogError = null;
      notifyListeners();
    } else {
      if (_isLoadingCatalog || _isLoadingMoreCatalog || !_catalogHasMore) return;
      _isLoadingMoreCatalog = true;
      notifyListeners();
    }

    try {
      final data = await ApiClient.browseCatalog(
        domain: _selectedProviderDomain.isEmpty ? null : _selectedProviderDomain,
        genre: _catalogQuery.isEmpty && _catalogGenre.isNotEmpty ? _catalogGenre : null,
        year: _catalogYear.isEmpty ? null : _catalogYear,
        type: _catalogType.isEmpty ? null : _catalogType,
        status: _catalogStatus.isEmpty ? null : _catalogStatus,
        query: _catalogQuery.isNotEmpty ? _catalogQuery : null,
        page: _catalogPage,
      );

      final resultsList = data['results'] as List?;
      var pageItems = resultsList != null
          ? resultsList.map((item) => AnimeSearchResult.fromJson(item)).toList()
          : <AnimeSearchResult>[];
      pageItems = _filterCatalogPage(pageItems);

      if (refresh) {
        _catalogAll = pageItems;
      } else {
        final seen = _catalogAll.map((e) => e.url).toSet();
        _catalogAll.addAll(pageItems.where((e) => !seen.contains(e.url)));
      }

      _catalogResults = List.from(_catalogAll);
      _parseFacets(data['facets'] as Map<String, dynamic>?);

      _catalogTotalRecords = data['totalRecords'] is int
          ? data['totalRecords'] as int
          : int.tryParse(data['totalRecords']?.toString() ?? '');
      _catalogTotalPages = data['totalPages'] is int
          ? data['totalPages'] as int
          : int.tryParse(data['totalPages']?.toString() ?? '');
      _catalogHasMore = data['hasMore'] == true;

      if (pageItems.isNotEmpty) {
        _catalogPage += 1;
      } else {
        _catalogHasMore = false;
      }
    } catch (e) {
      if (refresh) {
        _catalogError = e.toString().replaceAll('Exception: ', '');
        _catalogAll = [];
        _catalogResults = [];
      }
    } finally {
      _isLoadingCatalog = false;
      _isLoadingMoreCatalog = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreCatalog() => loadCatalog(refresh: false);

  // Limpiar estados
  void clearSearch() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }

  void clearEpisodeLinks() {
    _episodeLinks = null;
    _episodeError = null;
    notifyListeners();
  }
}
