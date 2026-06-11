class Manga {
  final String id;
  final String slug;
  final String title;
  final String description;
  final String? coverUrl;
  final String? status;
  final int? year;
  final List<String> genres;
  final String? author;
  final List<String> availableLanguages;

  Manga({
    required this.id,
    this.slug = '',
    required this.title,
    required this.description,
    this.coverUrl,
    this.status,
    this.year,
    required this.genres,
    this.author,
    required this.availableLanguages,
  });

  factory Manga.fromJson(Map<String, dynamic> json) {
    return Manga(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      status: json['status']?.toString(),
      year: int.tryParse(json['year']?.toString() ?? ''),
      genres: List<String>.from(json['genres'] ?? []),
      author: json['author']?.toString(),
      availableLanguages: ['es'],
    );
  }

  // ── ZonaTMO: tarjeta de listado HTML ──────────────────────────────────────
  // Estructura de cada tarjeta en /library:
  // <div class="element">
  //   <div class="thumbnail-title">
  //     <a href="/library/manga/{slug}/{id}">
  //       <img src="..." onerror="...">
  //       <h4 class="text-truncate">{title}</h4>
  //     </a>
  //   </div>
  // </div>
  factory Manga.fromZonaTmoHtml(String block) {
    // 1. href → slug + id
    final hrefMatch = RegExp(r'href="/library/(?:manga|manhwa|manhua)/([^/]+)/(\d+)"').firstMatch(block);
    final slug = hrefMatch?.group(1) ?? '';
    final id   = hrefMatch?.group(2) ?? '';

    // 2. Título
    final titleMatch = RegExp(r'<h4[^>]*class="[^"]*text-truncate[^"]*"[^>]*>([\s\S]*?)</h4>').firstMatch(block);
    String title = _decodeHtmlEntities(
      (titleMatch?.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim(),
    );

    // 3. Portada
    String? coverUrl;
    final imgMatch = RegExp(r'<img[^>]+(?:src|data-src)="([^"]+)"').firstMatch(block);
    coverUrl = imgMatch?.group(1);
    if (coverUrl != null && coverUrl.startsWith('/')) {
      coverUrl = 'https://zonatmo.org$coverUrl';
    }

    // 4. Estado (badge opcional)
    String? status;
    final statusMatch = RegExp(r'<span[^>]*class="[^"]*badge[^"]*"[^>]*>([\s\S]*?)</span>').firstMatch(block);
    if (statusMatch != null) {
      status = _decodeHtmlEntities(statusMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
    }

    return Manga(
      id: id,
      slug: slug,
      title: title,
      description: '',
      coverUrl: coverUrl,
      status: status,
      genres: [],
      availableLanguages: ['es'],
    );
  }

  // ── ZonaTMO: página de detalles ───────────────────────────────────────────
  factory Manga.fromZonaTmoDetailHtml(String id, String slug, String html) {
    // 1. Título — ZonaTMO pone el nombre en og:title o en <title>
    String title = '';

    // Prioridad 1: <meta property="og:title" content="...">
    final ogTitle = RegExp(r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"').firstMatch(html)
        ?? RegExp(r'<meta[^>]+content="([^"]+)"[^>]+property="og:title"').firstMatch(html);
    if (ogTitle != null) {
      String t = _decodeHtmlEntities(ogTitle.group(1)!.trim());
      // ZonaTMO og:title = "Ver {nombre} Online Gratis" — quitar prefijo y sufijo
      t = t.replaceFirst(RegExp(r'^Ver\s+', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'\s+Online\b.*$', caseSensitive: false), '');
      title = t.trim();
    }

    // Prioridad 2: <h1 class="...element-title..."> o cualquier <h1>
    if (title.isEmpty) {
      final h1 = RegExp(r'<h1[^>]*>([\s\S]*?)</h1>').firstMatch(html);
      if (h1 != null) {
        title = _decodeHtmlEntities(h1.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
      }
    }

    // Prioridad 4: primer <h2> que no sea "Capítulos"
    if (title.isEmpty) {
      for (final m in RegExp(r'<h2[^>]*>([\s\S]*?)</h2>').allMatches(html)) {
        final t = _decodeHtmlEntities(m.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
        if (t.isNotEmpty && !t.startsWith('Cap')) { title = t; break; }
      }
    }

    if (title.isEmpty) title = slug.replaceAll('-', ' ');
    // ignore: avoid_print
    print('[DETAIL] title="$title" slug="$slug"');

    // 2. Portada — ZonaTMO: <img class="book-thumbnail"> o data-bg en el detail
    String? coverUrl;
    final coverMatch = RegExp(r'<img[^>]+class="[^"]*book-thumbnail[^"]*"[^>]+src="([^"]+)"').firstMatch(html)
        ?? RegExp(r'<img[^>]+src="(https://(?:storage\.)?zonatmo\.org/(?:storage/)?covers/[^"]+)"').firstMatch(html)
        ?? RegExp(r'data-bg="(https?://[^"]+covers[^"]+)"').firstMatch(html);
    coverUrl = coverMatch?.group(1);
    if (coverUrl != null && coverUrl.startsWith('/')) {
      coverUrl = 'https://zonatmo.org$coverUrl';
    }

    // 3. Sinopsis — ZonaTMO: <p class="element-description"> o <div class="col-12">
    String description = '';
    final descMatch = RegExp(r'<p[^>]+class="[^"]*element-description[^"]*"[^>]*>([\s\S]*?)</p>').firstMatch(html)
        ?? RegExp(r'<meta[^>]+name="description"[^>]+content="([^"]+)"').firstMatch(html)
        ?? RegExp(r'<meta[^>]+content="([^"]+)"[^>]+name="description"').firstMatch(html);
    if (descMatch != null) {
      description = _decodeHtmlEntities(
        descMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      );
    }

    // 4. Estado — ZonaTMO lo renderiza con un span ancla seguido del texto:
    //   <span class="status-dot publishing"></span>Publicándose
    // La clase (publishing/ended/cancelled/on_hold) está en inglés y el texto
    // visible en español. Tomamos el texto del PRIMER status-dot (el del manga
    // principal; las tarjetas relacionadas y el contador "N Abandonado" van
    // después y no usan este patrón para el estado principal).
    String? status;
    final statusMatch2 = RegExp(
      r'<span[^>]*class="[^"]*status-dot[^"]*"[^>]*>\s*</span>\s*([^<\n]+)',
    ).firstMatch(html);
    if (statusMatch2 != null) {
      status = _decodeHtmlEntities(statusMatch2.group(1)!.trim());
    } else {
      // Respaldo: buscar el texto dentro de la sección etiquetada "Estado".
      const stateTexts = [
        'Publicándose', 'Publicandose', 'En emisión', 'En Emisión',
        'Finalizado', 'Cancelado', 'Abandonado', 'Pausado',
      ];
      final estadoLabel = RegExp(r'>\s*Estado:?\s*<').firstMatch(html);
      String searchRegion = html;
      if (estadoLabel != null) {
        final start = estadoLabel.end;
        final end = (start + 400).clamp(0, html.length);
        searchRegion = html.substring(start, end);
      }
      int bestIdx = -1;
      for (final s in stateTexts) {
        final i = searchRegion.indexOf(s);
        if (i >= 0 && (bestIdx == -1 || i < bestIdx)) {
          bestIdx = i;
          if (s == 'Publicandose' || s == 'Publicándose') {
            status = 'Publicándose';
          } else if (s == 'En Emisión' || s == 'En emisión') {
            status = 'En emisión';
          } else {
            status = s;
          }
        }
      }
    }

    // 5. Autor — ZonaTMO: <a href="/library?...demography..."> o label "Autor"
    String? author;
    final authorMatch = RegExp(
      r'(?:Autor|Author)[^<]*<[^>]+>[^<]*<a[^>]*>([^<]+)</a>',
      caseSensitive: false,
    ).firstMatch(html) ?? RegExp(r'<a[^>]+href="/library\?[^"]*author[^"]*"[^>]*>([^<]+)</a>').firstMatch(html);
    if (authorMatch != null) {
      author = _decodeHtmlEntities(authorMatch.group(1)!.trim());
    }

    // 6. Géneros — ZonaTMO: <a href="/biblioteca?genders[]=..."> o /library?genders
    final List<String> genres = [];
    final genreMatches = RegExp(
      r'<a[^>]+href="[^"]*(?:genders|genres|generos)[^"]*"[^>]*>([^<]+)</a>',
    ).allMatches(html);
    for (final m in genreMatches) {
      final g = _decodeHtmlEntities(m.group(1)!.trim());
      if (g.isNotEmpty && g.length < 40) genres.add(g);
    }

    // 7. Año
    int? year;
    final yearMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(html.substring(0, html.length > 3000 ? 3000 : html.length));
    if (yearMatch != null) year = int.tryParse(yearMatch.group(0)!);

    return Manga(
      id: id,
      slug: slug,
      title: title,
      description: description,
      coverUrl: coverUrl,
      status: status,
      year: year,
      genres: genres,
      author: author,
      availableLanguages: ['es'],
    );
  }
}

// ── Entidades HTML ────────────────────────────────────────────────────────────
String _decodeHtmlEntities(String input) {
  var result = input;
  const entities = {
    '&#225;': 'á', '&aacute;': 'á',
    '&#233;': 'é', '&eacute;': 'é',
    '&#237;': 'í', '&iacute;': 'í',
    '&#243;': 'ó', '&oacute;': 'ó',
    '&#250;': 'ú', '&uacute;': 'ú',
    '&#241;': 'ñ', '&ntilde;': 'ñ',
    '&#209;': 'Ñ', '&Ntilde;': 'Ñ',
    '&#193;': 'Á', '&Aacute;': 'Á',
    '&#201;': 'É', '&Eacute;': 'É',
    '&#205;': 'Í', '&Iacute;': 'Í',
    '&#211;': 'Ó', '&Oacute;': 'Ó',
    '&#218;': 'Ú', '&Uacute;': 'Ú',
    '&#220;': 'Ü', '&Uuml;': 'Ü',
    '&#252;': 'ü', '&uuml;': 'ü',
    '&nbsp;': ' ', '&amp;': '&',
    '&quot;': '"', '&#39;': "'",
    '&lt;': '<', '&gt;': '>',
  };
  entities.forEach((key, value) {
    result = result.replaceAll(key, value);
  });
  return result;
}

// ── Capítulo ──────────────────────────────────────────────────────────────────
class MangaChapter {
  final String id;
  final String chapterNumber;
  final String? volume;
  final String title;
  final int pagesCount;
  final String? scanlationGroup;
  final String translatedLanguage;
  final String? externalUrl;

  MangaChapter({
    required this.id,
    required this.chapterNumber,
    this.volume,
    required this.title,
    required this.pagesCount,
    this.scanlationGroup,
    required this.translatedLanguage,
    this.externalUrl,
  });

  factory MangaChapter.fromJson(Map<String, dynamic> json) {
    return MangaChapter(
      id: json['id']?.toString() ?? '',
      chapterNumber: json['chapterNumber']?.toString() ?? '0',
      volume: json['volume']?.toString(),
      title: json['title']?.toString() ?? 'Capítulo',
      pagesCount: int.tryParse(json['pagesCount']?.toString() ?? '0') ?? 0,
      scanlationGroup: json['scanlationGroup']?.toString(),
      translatedLanguage: json['translatedLanguage']?.toString() ?? 'es',
      externalUrl: json['externalUrl']?.toString(),
    );
  }

  // ── ZonaTMO: fila de capítulo en la página de detalles HTML ──────────────
  // <li class="chapter-item">
  //   <a href="/viewer/{id}/cascade">Cap. {number}</a>
  //   <span class="text-truncate">{scanlation}</span>
  // </li>
  factory MangaChapter.fromZonaTmoHtml(String block) {
    // ID del capítulo desde href /viewer/{id}/cascade o /viewer/{id}/paginated
    final hrefMatch = RegExp(r'/viewer/(\d+)/').firstMatch(block);
    final id = hrefMatch?.group(1) ?? '';

    // Número de capítulo
    final numMatch = RegExp(r'Cap(?:ítulo|\.)\s*([\d.]+)', caseSensitive: false).firstMatch(block);
    final number = numMatch?.group(1) ?? '0';

    // Scanlation (grupo)
    String? scanlation;
    final scanMatch = RegExp(r'<span[^>]*class="[^"]*text-truncate[^"]*"[^>]*>([\s\S]*?)</span>').firstMatch(block);
    if (scanMatch != null) {
      scanlation = _decodeHtmlEntities(scanMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
    }

    return MangaChapter(
      id: id,
      chapterNumber: number,
      title: 'Capítulo $number',
      pagesCount: 0,
      scanlationGroup: scanlation,
      translatedLanguage: 'es',
    );
  }
}
