import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga.dart';
import '../services/offline_storage_service.dart';

class MangaProvider extends ChangeNotifier {
  static const String _baseUrl = 'https://zonatmo.org';
  static const String _keyAdult = 'settings_adult_content_enabled';

  // Lee la preferencia +18 directo de SharedPreferences
  Future<bool> _isAdultEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAdult) ?? false;
  }

  // Géneros a excluir siempre (yaoi, BL, shounen-ai y equivalentes)
  static const List<String> _excludedGenres = [
    'yaoi', 'boys love', 'boys-love', 'bl', 'shounen ai', 'shounen-ai',
    'bara', 'gay', 'yuri', 'girls love', 'girls-love', 'shoujo ai', 'shoujo-ai',
  ];
  // Géneros +18 (excluidos salvo que adultContentEnabled = true)
  static const List<String> _adultGenres = [
    'adulto', 'adult', 'smut', 'hentai', 'erotico', 'erótico',
  ];

  // Filtra un Manga según género/slug/título
  bool _isExcluded(Manga m, {bool adultEnabled = false}) {
    final check = '${m.title} ${m.slug} ${m.genres.join(' ')}'.toLowerCase();
    if (_excludedGenres.any((g) => check.contains(g))) return true;
    if (!adultEnabled && _adultGenres.any((g) => check.contains(g))) return true;
    return false;
  }

  // Headers que simulan un navegador Android Chrome real
  static Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Referer': '$_baseUrl/',
    'Upgrade-Insecure-Requests': '1',
  };

  static const String _historyKeyPrefix = 'manga_progress_';
  static const int _pageSize = 24;

  // ── Popular ──────────────────────────────────────────────────────────────
  List<Manga> _popularManga = [];
  bool _isLoadingPopular = false;
  bool _isLoadingMorePopular = false;
  String? _popularError;
  int _popularPage = 1;
  bool _hasMorePopular = true;

  List<Manga> get popularManga => _popularManga;
  bool get isLoadingPopular => _isLoadingPopular;
  bool get isLoadingMorePopular => _isLoadingMorePopular;
  String? get popularError => _popularError;
  bool get hasMorePopular => _hasMorePopular;

  // ── Búsqueda ──────────────────────────────────────────────────────────────
  List<Manga> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingMoreSearch = false;
  String? _searchError;
  int _searchPage = 1;
  bool _hasMoreSearch = true;
  String _lastSearchQuery = '';

  List<Manga> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get isLoadingMoreSearch => _isLoadingMoreSearch;
  String? get searchError => _searchError;
  bool get hasMoreSearch => _hasMoreSearch;

  // ── Detalles ──────────────────────────────────────────────────────────────
  Manga? _selectedManga;
  bool _isLoadingDetails = false;
  String? _detailsError;

  Manga? get selectedManga => _selectedManga;
  bool get isLoadingDetails => _isLoadingDetails;
  String? get detailsError => _detailsError;

  // ── Capítulos ─────────────────────────────────────────────────────────────
  List<MangaChapter> _chapters = [];
  bool _isLoadingChapters = false;
  bool _isLoadingMoreChapters = false;
  String? _chaptersError;
  bool _hasMoreChapters = false;

  List<MangaChapter> get chapters => _chapters;
  bool get isLoadingChapters => _isLoadingChapters;
  bool get isLoadingMoreChapters => _isLoadingMoreChapters;
  String? get chaptersError => _chaptersError;
  bool get hasMoreChapters => _hasMoreChapters;

  // ── Páginas ───────────────────────────────────────────────────────────────
  List<String> _chapterPages = [];
  bool _isLoadingPages = false;
  String? _pagesError;
  bool _isPagesOffline = false;

  List<String> get chapterPages => _chapterPages;
  bool get isLoadingPages => _isLoadingPages;
  String? get pagesError => _pagesError;
  bool get isPagesOffline => _isPagesOffline;

  // ── Popular — paginado ────────────────────────────────────────────────────
  // GET /library?order_item=likes_count&order_dir=desc&_={ts}&page={n}
  // Fallback: GET / (homepage con manga destacados)
  Future<void> loadPopularManga({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMorePopular || _isLoadingMorePopular) return;
      _isLoadingMorePopular = true;
    } else {
      _isLoadingPopular = true;
      _popularPage = 1;
      _hasMorePopular = true;
      _popularManga = [];
      _popularError = null;
    }
    notifyListeners();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;

      http.Response response;

      final bool isHomepage = (_popularPage == 1);
      final bool adultEnabled = await _isAdultEnabled();
      if (isHomepage) {
        // Homepage: tiene las 3 pestañas separadas (Populares / Boys / Girls)
        // Parseamos SOLO la pestaña general
        response = await http.get(Uri.parse(_baseUrl), headers: _headers);
      } else {
        // Paginación: /biblioteca — excluir BL/yaoi y opcionalmente adulto
        final excludeIds = ['30', '31', '33', if (!adultEnabled) '32'];
        final excludeQs = excludeIds.map((id) => 'exclude_genders%5B%5D=$id').join('&');
        final qs = 'order_item=likes_count&order_dir=desc&filter_by=title'
            '&_=$ts&page=$_popularPage&$excludeQs';
        final uri = Uri.parse('$_baseUrl/biblioteca?$qs');
        response = await http.get(uri, headers: _headers);
      }

      if (response.statusCode == 200) {
        int rawCount = 0; // items antes del filtro de géneros
        List<Manga> items;
        if (isHomepage) {
          items = _parseMangaList(response.body, adultEnabled: adultEnabled);
          rawCount = items.length; // homepage ya viene pre-filtrado por pills
        } else {
          final result = _parseMangaListFull(response.body, adultEnabled: adultEnabled);
          rawCount = result.rawCount;
          items    = result.items;
        }
        debugPrint('[POP] page=$_popularPage raw=$rawCount filtered=${items.length} loadMore=$loadMore');
        if (loadMore) {
          _popularManga.addAll(items);
        } else {
          _popularManga = items;
        }
        // Hay más páginas si el servidor devolvió items (aunque el filtro los elimine)
        if (!loadMore && _popularPage == 1) {
          _hasMorePopular = true;
          _popularPage = 2;
        } else {
          _hasMorePopular = rawCount > 0; // continuar mientras el servidor dé contenido
          if (_hasMorePopular) _popularPage++;
        }
        if (items.isEmpty && !loadMore && rawCount == 0) {
          _popularError = 'No se encontraron mangas.';
        }
      } else {
        _popularError = 'Error ${response.statusCode} al cargar populares';
      }
    } catch (e) {
      _popularError = e.toString();
    } finally {
      _isLoadingPopular = false;
      _isLoadingMorePopular = false;
      notifyListeners();
    }
  }

  // ── Búsqueda ──────────────────────────────────────────────────────────────
  // GET /library?title={query}&page={n}
  Future<void> searchManga(String query, {bool loadMore = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _isLoadingMoreSearch = false;
      _searchPage = 1;
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
      _searchPage = 1;
      _hasMoreSearch = true;
      _searchResults = [];
      _lastSearchQuery = trimmed;
    }
    _searchError = null;
    notifyListeners();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final adultEnabled = await _isAdultEnabled();
      final excludeIds = ['30', '31', '33', if (!adultEnabled) '32'];
      final excludeQs = excludeIds.map((id) => 'exclude_genders%5B%5D=$id').join('&');
      final encodedQuery = Uri.encodeQueryComponent(_lastSearchQuery);
      final qs = 'title=$encodedQuery&filter_by=title&_=$ts&page=$_searchPage&$excludeQs';
      final uri = Uri.parse('$_baseUrl/biblioteca?$qs');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final items = _parseMangaList(response.body, adultEnabled: adultEnabled);
        if (loadMore) {
          _searchResults.addAll(items);
        } else {
          _searchResults = items;
        }
        _hasMoreSearch = items.isNotEmpty;
        if (_hasMoreSearch) _searchPage++;
      } else {
        _searchError = 'Error ${response.statusCode} en búsqueda';
      }
    } catch (e) {
      _searchError = e.toString();
    } finally {
      _isSearching = false;
      _isLoadingMoreSearch = false;
      notifyListeners();
    }
  }

  // ── Detalles ──────────────────────────────────────────────────────────────
  // GET /library/manga/{slug}/{id}   (o manhwa/manhua)
  Future<void> loadMangaDetails(String mangaId) async {
    _isLoadingDetails = true;
    _detailsError = null;
    _selectedManga = null;
    notifyListeners();

    try {
      // ZonaTMO: /library/manga/{id}/{slug}
      final slug = _selectedManga?.slug ?? 'a';
      final uri = Uri.parse('$_baseUrl/library/manga/$mangaId/$slug');

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        _selectedManga = Manga.fromZonaTmoDetailHtml(mangaId, slug, response.body);
      } else {
        _detailsError = 'Error ${response.statusCode} al cargar detalles';
      }
    } catch (e) {
      _detailsError = e.toString();
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  // Versión que acepta slug directamente (llamada desde el UI)
  Future<void> loadMangaDetailsBySlug(String id, String slug) async {
    _isLoadingDetails = true;
    _detailsError = null;
    _selectedManga = null;
    notifyListeners();

    try {
      // ZonaTMO: /library/manga/{id}/{slug}
      final uri = Uri.parse('$_baseUrl/library/manga/$id/$slug');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        _selectedManga = Manga.fromZonaTmoDetailHtml(id, slug, response.body);
      } else {
        _detailsError = 'Error ${response.statusCode} al cargar detalles';
      }
    } catch (e) {
      _detailsError = e.toString();
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  // ── Capítulos ─────────────────────────────────────────────────────────────
  // GET /library/manga/{id}/chapters?lang=es&_={timestamp}
  Future<void> loadChapters(String mangaId,
      {bool loadMore = false, List<String>? languages, String? slug}) async {
    if (loadMore) return; // ZonaTMO devuelve todos los capítulos de una vez

    _isLoadingChapters = true;
    _hasMoreChapters = false;
    _chapters = [];
    _chaptersError = null;
    notifyListeners();

    try {
      // ZonaTMO: los capítulos están en la página de detalle del manga
      final resolvedSlug = (_selectedManga?.slug.isNotEmpty == true)
          ? _selectedManga!.slug
          : (slug?.isNotEmpty == true ? slug! : 'a');
      final uri = Uri.parse('$_baseUrl/library/manga/$mangaId/$resolvedSlug');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final body = response.body;
        // ¿Dónde están los capítulos?
        final capIdx = body.indexOf('Capítulo');
        final capIdx2 = body.indexOf('Cap.');
        final viewerIdx = body.indexOf('/viewer/');
        debugPrint('[CHAP] indexOf Capítulo=$capIdx Cap.=$capIdx2 /viewer/=$viewerIdx bodyLen=${body.length}');
        _chapters = _parseChapters(body);
      } else {
        _chaptersError = 'Error ${response.statusCode} al cargar capítulos';
      }
    } catch (e) {
      _chaptersError = e.toString();
    } finally {
      _isLoadingChapters = false;
      notifyListeners();
    }
  }

  // ── Páginas de capítulo ───────────────────────────────────────────────────
  // GET /viewer/{chapterId}/cascade  → imágenes en JSON embebido o <img>
  Future<void> loadChapterPages(String chapterId, String mangaId) async {
    _isLoadingPages = true;
    _pagesError = null;
    _chapterPages = [];
    _isPagesOffline = false;
    notifyListeners();

    try {
      // 1. Caché offline
      final isDownloaded =
          await OfflineStorageService.isMangaChapterDownloaded(mangaId, chapterId);
      if (isDownloaded) {
        final localPages =
            await OfflineStorageService.getMangaChapterPages(mangaId, chapterId);
        if (localPages.isNotEmpty) {
          _chapterPages = localPages;
          _isPagesOffline = true;
          return;
        }
      }

      // 2. Red — ZonaTMO usa /view_uploads/{uploadId}
      final uri = Uri.parse('$_baseUrl/view_uploads/$chapterId');
      debugPrint('[PAGES] GET $uri');
      final response = await http.get(uri, headers: _headers);
      debugPrint('[PAGES] status=${response.statusCode} len=${response.body.length}');
      debugPrint('[PAGES] html_start=${response.body.substring(0, response.body.length.clamp(0, 500))}');

      if (response.statusCode == 200) {
        // Log fragmento del medio del HTML para ver estructura real
        final body = response.body;
        final mid = body.length ~/ 2;
        debugPrint('[PAGES] mid=${body.substring(mid, (mid + 600).clamp(0, body.length))}');
        // Buscar data-src
        final dataSrc = RegExp(r'data-src="([^"]+)"').allMatches(body).take(5);
        for (final d in dataSrc) {
          debugPrint('[PAGES] data-src: ${d.group(1)}');
        }
        // Buscar cualquier URL con /storage/ o /uploads/
        final storageUrls = RegExp(r'"((?:https?:)?//[^"]+/(?:storage|uploads?)/[^"]+)"').allMatches(body).take(5);
        for (final s in storageUrls) {
          debugPrint('[PAGES] storage: ${s.group(1)}');
        }
        _chapterPages = _parseChapterPages(response.body);
        debugPrint('[PAGES] parsed=${_chapterPages.length}');
        if (_chapterPages.isEmpty) {
          _pagesError = 'No se encontraron páginas para este capítulo.';
        }
      } else {
        _pagesError = 'Error ${response.statusCode} al obtener páginas';
      }
    } catch (e) {
      _pagesError = e.toString();
    } finally {
      _isLoadingPages = false;
      notifyListeners();
    }
  }

  // ── Parsers internos ──────────────────────────────────────────────────────

  List<Manga> _parseMangaList(String html, {bool adultEnabled = false}) {
    // Extraer solo la pestaña "Populares" — ignorar Boys (BL) y Girls (yuri)
    String parseTarget = _extractGeneralPopularSection(html);

    final Map<String, String> covers = {};
    final Map<String, List<String>> allTitles = {}; // todos los títulos por ID
    final Map<String, String> slugs = {};

    final anchorRegex = RegExp(
      r'<a\b([^>]*href="(?:https://zonatmo\.org)?/library/(?:manga|manhwa|manhua|doujinshi)/(\d+)/([^/"?#\s]+)"[^>]*)>([\s\S]*?)</a>',
    );

    for (final m in anchorRegex.allMatches(parseTarget)) {
      final attrs = m.group(1)!;
      final id    = m.group(2)!;
      final slug  = m.group(3)!;
      final inner = m.group(4)!;

      slugs[id] = slug;
      allTitles.putIfAbsent(id, () => []);

      // ── Portada: data-bg (ZonaTMO usa lazy-load CSS) ─────────────────────
      if (!covers.containsKey(id)) {
        final dataBg = RegExp(r'data-bg="(https?://[^"\s]+)"').firstMatch(inner);
        if (dataBg != null) {
          covers[id] = dataBg.group(1)!;
        } else {
          final img = RegExp(r'<img[^>]+(?:data-src|src)="(https?://[^"\s]+)"').firstMatch(inner);
          if (img != null) covers[id] = img.group(1)!;
        }
      }

      // ── Recolectar todos los candidatos de título ─────────────────────────
      // 1. title="" del <h4> (el más confiable en ZonaTMO)
      final h4title = RegExp(r'<h[2-5][^>]*\btitle="([^"]+)"').firstMatch(inner);
      if (h4title != null) allTitles[id]!.add(_decodeEntities(h4title.group(1)!.trim()));

      // 2. title="" del propio <a>
      final aTitle = RegExp(r'\btitle="([^"]+)"').firstMatch(attrs);
      if (aTitle != null) allTitles[id]!.add(_decodeEntities(aTitle.group(1)!.trim()));

      // 3. alt="" de la imagen
      final alt = RegExp(r'<img[^>]+\balt="([^"]+)"').firstMatch(inner);
      if (alt != null) allTitles[id]!.add(_decodeEntities(alt.group(1)!.trim()));

      // 4. texto dentro de <h4>
      final h4text = RegExp(r'<h[2-5][^>]*>([\s\S]*?)</h[2-5]>').firstMatch(inner);
      if (h4text != null) {
        final t = _decodeEntities(h4text.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
        if (t.isNotEmpty) allTitles[id]!.add(t);
      }
    }

    // ── Elegir el mejor título: preferir el que NO sea capítulo ─────────────
    final List<Manga> items = [];
    for (final id in allTitles.keys) {
      final candidates = allTitles[id]!.where((t) => t.isNotEmpty).toList();
      if (candidates.isEmpty) continue;

      final title = candidates.firstWhere(
        (t) => !_isChapter(t),
        orElse: () => '',
      );
      if (title.isEmpty) continue;

      final manga = Manga(
        id: id,
        slug: slugs[id] ?? '',
        title: title,
        description: '',
        genres: [],
        availableLanguages: ['es'],
        coverUrl: covers[id],
      );

      if (!_isExcluded(manga, adultEnabled: adultEnabled)) items.add(manga);
    }
    return items;
  }

  /// Parsea el catálogo completo de /biblioteca (sin filtrado por pestañas pills).
  /// Retorna rawCount (antes del filtro de géneros excluidos) + items filtrados.
  ({List<Manga> items, int rawCount}) _parseMangaListFull(String html, {bool adultEnabled = false}) {
    final Map<String, String> covers = {};
    final Map<String, List<String>> allTitles = {};
    final Map<String, String> slugs = {};

    final anchorRegex = RegExp(
      r'<a\b([^>]*href="(?:https://zonatmo\.org)?/library/(?:manga|manhwa|manhua|doujinshi)/(\d+)/([^/"?#\s]+)"[^>]*)>([\s\S]*?)</a>',
    );

    for (final m in anchorRegex.allMatches(html)) {
      final attrs = m.group(1)!;
      final id    = m.group(2)!;
      final slug  = m.group(3)!;
      final inner = m.group(4)!;

      slugs[id] = slug;
      allTitles.putIfAbsent(id, () => []);

      if (!covers.containsKey(id)) {
        final dataBg = RegExp(r'data-bg="(https?://[^"\s]+)"').firstMatch(inner);
        if (dataBg != null) {
          covers[id] = dataBg.group(1)!;
        } else {
          final img = RegExp(r'<img[^>]+(?:data-src|src)="(https?://[^"\s]+)"').firstMatch(inner);
          if (img != null) covers[id] = img.group(1)!;
        }
      }

      final h4title = RegExp(r'<h[2-5][^>]*\btitle="([^"]+)"').firstMatch(inner);
      if (h4title != null) allTitles[id]!.add(_decodeEntities(h4title.group(1)!.trim()));

      final aTitle = RegExp(r'\btitle="([^"]+)"').firstMatch(attrs);
      if (aTitle != null) allTitles[id]!.add(_decodeEntities(aTitle.group(1)!.trim()));

      final alt = RegExp(r'<img[^>]+\balt="([^"]+)"').firstMatch(inner);
      if (alt != null) allTitles[id]!.add(_decodeEntities(alt.group(1)!.trim()));

      final h4text = RegExp(r'<h[2-5][^>]*>([\s\S]*?)</h[2-5]>').firstMatch(inner);
      if (h4text != null) {
        final t = _decodeEntities(h4text.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
        if (t.isNotEmpty) allTitles[id]!.add(t);
      }
    }

    final List<Manga> all = [];
    for (final id in allTitles.keys) {
      final candidates = allTitles[id]!.where((t) => t.isNotEmpty).toList();
      if (candidates.isEmpty) continue;
      final title = candidates.firstWhere((t) => !_isChapter(t), orElse: () => '');
      if (title.isEmpty) continue;
      all.add(Manga(
        id: id,
        slug: slugs[id] ?? '',
        title: title,
        description: '',
        genres: [],
        availableLanguages: ['es'],
        coverUrl: covers[id],
      ));
    }
    final filtered = all.where((m) => !_isExcluded(m, adultEnabled: adultEnabled)).toList();
    debugPrint('[POP_FULL] raw=${all.length} filtered=${filtered.length}');
    return (items: filtered, rawCount: all.length);
  }

  /// Extrae solo el HTML de la pestaña "Populares" general.
  /// Descarta "pills-populars-boys" (BL/yaoi) y "pills-populars-girls" (yuri).
  String _extractGeneralPopularSection(String html) {
    // Buscar el inicio de la sección general (id="pills-populars")
    // pero NO id="pills-populars-boys" ni id="pills-populars-girls"
    const startMarker = 'id="pills-populars"';
    const boysMarker  = 'id="pills-populars-boys"';
    const girlsMarker = 'id="pills-populars-girls"';

    final startIdx = html.indexOf(startMarker);
    if (startIdx == -1) return html; // no tiene pestañas, devolver todo

    // El inicio real es después del marcador
    final contentStart = startIdx + startMarker.length;

    // Buscar dónde termina esta sección (al llegar a boys o girls)
    int endIdx = html.length;
    final boysIdx  = html.indexOf(boysMarker,  contentStart);
    final girlsIdx = html.indexOf(girlsMarker, contentStart);

    if (boysIdx  != -1 && boysIdx  < endIdx) endIdx = boysIdx;
    if (girlsIdx != -1 && girlsIdx < endIdx) endIdx = girlsIdx;

    final section = html.substring(contentStart, endIdx);
    debugPrint('[MANGA] section: start=$startIdx boys=$boysIdx girls=$girlsIdx len=${section.length}');
    return section;
  }

  bool _isChapter(String text) {
    final t = text.trim();
    return RegExp(
      r'^(?:cap[íi]?tulo?\.?\s*\d|tomo\s*\d|\d+[\s.,]*$|vol\.|one[- ]?shot|ep\.?\s*\d)',
      caseSensitive: false,
    ).hasMatch(t);
  }

  String _decodeEntities(String s) {
    return s
      .replaceAll('&amp;', '&').replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'").replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>').replaceAll('&nbsp;', ' ')
      .replaceAll('&aacute;', 'á').replaceAll('&eacute;', 'é')
      .replaceAll('&iacute;', 'í').replaceAll('&oacute;', 'ó')
      .replaceAll('&uacute;', 'ú').replaceAll('&ntilde;', 'ñ')
      .replaceAll('&Ntilde;', 'Ñ').replaceAll('&Aacute;', 'Á')
      .replaceAll('&Eacute;', 'É').replaceAll('&Iacute;', 'Í')
      .replaceAll('&Oacute;', 'Ó').replaceAll('&Uacute;', 'Ú');
  }

  List<MangaChapter> _parseChapters(String body) {
    final List<MangaChapter> list = [];
    final seen = <String>{};

    // Estructura real de ZonaTMO:
    // <li data-chapter-number="167.2">
    //   ...
    //   <a href="https://zonatmo.org/view_uploads/969020" class="btn btn-sm btn-primary">Leer online</a>
    // </li>
    //
    // Extraemos: uploadId desde /view_uploads/{id}, número desde data-chapter-number

    // ZonaTMO: cada <li data-chapter-number="X"> puede tener <ul>/<li> anidados
    // Usamos indexOf para extraer el bloque completo entre apertura y cierre real
    final liMatches = <Map<String,String>>[];
    int searchFrom = 0;
    while (true) {
      // Buscar próximo <li data-chapter-number="...">
      final liOpen = RegExp(r'<li[^>]+data-chapter-number="([^"]+)"[^>]*>');
      final openMatch = liOpen.firstMatch(body.substring(searchFrom));
      if (openMatch == null) break;
      final absStart = searchFrom + openMatch.start;
      final absInner = searchFrom + openMatch.end;
      final chNum    = openMatch.group(1)!;

      // Encontrar el </li> de cierre contando apertura/cierre de <li>
      int depth  = 1;
      int cursor = absInner;
      while (cursor < body.length && depth > 0) {
        final nextOpen  = body.indexOf('<li',  cursor);
        final nextClose = body.indexOf('</li>', cursor);
        if (nextClose < 0) break;
        if (nextOpen >= 0 && nextOpen < nextClose) {
          depth++;
          cursor = nextOpen + 3;
        } else {
          depth--;
          if (depth == 0) {
            liMatches.add({'num': chNum, 'inner': body.substring(absInner, nextClose)});
            cursor = nextClose + 5;
          } else {
            cursor = nextClose + 5;
          }
        }
      }
      searchFrom = absStart + 1;
      if (searchFrom >= body.length) break;
    }
    debugPrint('[CHAP] liMatches found=${liMatches.length}');

    for (final entry in liMatches) {
      final chapterNumber = entry['num']!;
      final inner         = entry['inner']!;

      // URL: https://zonatmo.org/view_uploads/{uploadId}
      final uploadMatch = RegExp(
        r'href="(?:https?://zonatmo\.org)?/view_uploads/(\d+)"',
      ).firstMatch(inner);

      if (uploadMatch == null) {
        // Log the first few misses to debug
        if (list.length < 3) debugPrint('[CHAP] no uploadId in inner: ${inner.substring(0, inner.length.clamp(0, 200))}');
        continue;
      }
      final uploadId = uploadMatch.group(1)!;
      if (seen.contains(uploadId)) continue;
      seen.add(uploadId);

      list.add(MangaChapter(
        id: uploadId,
        chapterNumber: chapterNumber,
        title: 'Capítulo $chapterNumber',
        pagesCount: 0,
        translatedLanguage: 'es',
      ));
    }

    // Ordenar descendente
    list.sort((a, b) {
      final an = double.tryParse(a.chapterNumber.replaceAll(',', '.')) ?? 0.0;
      final bn = double.tryParse(b.chapterNumber.replaceAll(',', '.')) ?? 0.0;
      return bn.compareTo(an);
    });

    return list;
  }

  List<String> _parseChapterPages(String html) {
    // ZonaTMO: imágenes lazy con data-src="https://storage.zonatmo.org/chapters/{id}/{n}.webp"
    // 1. data-src (método principal)
    final dataSrcRegex = RegExp(r'data-src="(https?://[^"]+)"');
    final dataSrcUrls = dataSrcRegex.allMatches(html)
        .map((m) => m.group(1)!)
        .where((u) => u.contains('storage.zonatmo') || u.contains('/chapters/'))
        .toList();
    if (dataSrcUrls.isNotEmpty) return dataSrcUrls;

    // 2. src en img dentro del lector
    final imgSrcRegex = RegExp(r'<img[^>]+src="(https?://[^"]*(?:storage\.zonatmo|/chapters/)[^"]*)"');
    final imgSrcUrls = imgSrcRegex.allMatches(html)
        .map((m) => m.group(1)!)
        .toList();
    if (imgSrcUrls.isNotEmpty) return imgSrcUrls;

    // 3. Cualquier data-src con URL absoluta
    final anyDataSrc = dataSrcRegex.allMatches(html)
        .map((m) => m.group(1)!)
        .where((u) => u.startsWith('http'))
        .toList();
    if (anyDataSrc.isNotEmpty) return anyDataSrc;

    return [];
  }

  // ── Progreso local ────────────────────────────────────────────────────────

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

  Future<void> saveReadingProgress(
      String mangaId, String chapterId, String chapterNumber, int page) async {
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
