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
    loadPopularAnime(); // Recargar populares al cambiar de proveedor
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
