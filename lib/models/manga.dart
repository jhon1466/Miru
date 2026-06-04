class Manga {
  final String id;
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
    // Mantener compatibilidad por si se llama en algún punto con un mapa vacío o parcial
    return Manga(
      id: json['id']?.toString() ?? '',
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

  // Constructor de factoría para parsear InManga desde los listados HTML (búsqueda y populares)
  factory Manga.fromInMangaHtml(String html, {bool isPopular = false}) {
    // 1. Extraer href para obtener el UUID
    final hrefMatch = RegExp(r'href="([^"]*\/ver\/manga\/[^"]*)"').firstMatch(html);
    final href = hrefMatch?.group(1) ?? '';
    final parts = href.split('/');
    final id = parts.isNotEmpty ? parts.last : '';
    
    // 2. Extraer título
    String title = '';
    if (isPopular) {
      final titleMatch = RegExp(r'<strong class="media-box-heading[^"]*">([\s\S]*?)<\/strong>').firstMatch(html);
      title = titleMatch?.group(1) ?? '';
    } else {
      final titleMatch = RegExp(r'class="[^"]*ellipsed-text[^"]*">(?:<em[^>]*><\/em>)?\s*([^<]+)<\/h4>').firstMatch(html);
      title = titleMatch?.group(1) ?? '';
    }
    title = _decodeHtmlEntities(title.replaceAll(RegExp(r'<[^>]*>'), '')).trim();
    
    // 3. Extraer portada
    String? coverUrl;
    final coverMatch = RegExp(isPopular ? r'<img[^>]*src="([^"]+)"' : r'<img[^>]*data-src="([^"]+)"').firstMatch(html);
    if (coverMatch != null) {
      coverUrl = coverMatch.group(1);
      if (coverUrl != null && coverUrl.startsWith('..')) {
        coverUrl = 'https://inmanga.com${coverUrl.substring(2)}';
      }
    }
    
    // 4. Extraer estado (solo en búsqueda)
    String? status;
    final statusMatch = RegExp(r'label-(?:success|danger)[^"]*">([^<]+)<\/span>').firstMatch(html);
    if (statusMatch != null) {
      status = _decodeHtmlEntities(statusMatch.group(1) ?? '').trim();
    }
    
    return Manga(
      id: id,
      title: title,
      description: '',
      coverUrl: coverUrl,
      status: status,
      year: null,
      genres: [],
      author: null,
      availableLanguages: ['es'],
    );
  }

  // Constructor de factoría para parsear InManga desde la página de detalles HTML
  factory Manga.fromInMangaDetailHtml(String id, String html) {
    // 1. Extraer título
    final titleMatch = RegExp(r'<h1>([^<]+)</h1>').firstMatch(html) ?? 
                       RegExp(r'class="panel-heading visible-xs"[^>]*>([^<]+)</div>').firstMatch(html);
    final title = _decodeHtmlEntities(titleMatch?.group(1) ?? 'Manga').trim();
    
    // 2. Extraer portada
    String? coverUrl;
    final coverMatch = RegExp(r'src="([^"]*intomanga\.com\/i\/m\/[^"]+\/t\/o\/[^"]+\.jpg)"').firstMatch(html);
    if (coverMatch != null) {
      coverUrl = coverMatch.group(1);
    }
    
    // 3. Extraer sinopsis
    // Estructura real: <div class="panel widget"><div class="panel-heading"><h1>...</h1>...</div><div class="panel-body">SINOPSIS</div></div>
    // Buscamos el primer panel-body que siga a un h1 (el panel de descripción)
    String description = '';
    // Regex principal: panel widget que contiene h1 seguido de panel-body con texto
    final descMainMatch = RegExp(
      r'<div class="panel widget">\s*<div class="panel-heading">\s*<h1>[^<]+</h1>[\s\S]*?</div>\s*<div class="panel-body">([\s\S]*?)</div>',
    ).firstMatch(html);
    if (descMainMatch != null) {
      description = _decodeHtmlEntities(descMainMatch.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }
    // Fallback: primer panel-body no vacío
    if (description.isEmpty) {
      final allPanelBodies = RegExp(r'<div class="panel-body">([\s\S]*?)</div>').allMatches(html);
      for (final m in allPanelBodies) {
        final candidate = _decodeHtmlEntities(m.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (candidate.length > 20) {
          description = candidate;
          break;
        }
      }
    }
    
    // 4. Extraer estado
    String? status;
    final statusMatch = RegExp(r'label-[a-z\-]+\s+pull-right">\s*([^<]+)</span>\s*<em[^>]*></em>\s*Estado').firstMatch(html);
    if (statusMatch != null) {
      status = _decodeHtmlEntities(statusMatch.group(1) ?? '').trim();
    }
    
    // 5. Extraer año
    int? year;
    final dateMatch = RegExp(r'label-primary pull-right">\s*([^<]+)</span>\s*<em[^>]*></em>\s*Publicaci').firstMatch(html);
    if (dateMatch != null) {
      final dateStr = dateMatch.group(1)?.trim() ?? '';
      if (dateStr.length >= 4) {
        year = int.tryParse(dateStr.substring(dateStr.length - 4));
      }
    }
    
    // 6. Extraer autor
    String? author;
    final authorMatch = RegExp(r'label-warning pull-right">\s*([^<]+)</span>\s*<em[^>]*></em>\s*Autor').firstMatch(html);
    if (authorMatch != null) {
      author = _decodeHtmlEntities(authorMatch.group(1) ?? '').trim();
    }

    // 7. Extraer géneros
    final List<String> genres = [];
    final genreMatches = RegExp(r'<a[^>]*href="[^"]*filter\[genreIds\][^"]*"[^>]*>\s*([^<]+)\s*</a>').allMatches(html);
    for (final m in genreMatches) {
      final genre = _decodeHtmlEntities(m.group(1) ?? '').trim();
      if (genre.isNotEmpty) genres.add(genre);
    }
    
    return Manga(
      id: id,
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

// Función auxiliar para decodificar entidades HTML comunes en español
String _decodeHtmlEntities(String input) {
  var result = input;
  final entities = {
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
    '&nbsp;': ' ',
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&lt;': '<',
    '&gt;': '>',
  };
  entities.forEach((key, value) {
    result = result.replaceAll(key, value);
  });
  return result;
}

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

  // Constructor de factoría para parsear capítulos de InManga
  factory MangaChapter.fromInMangaJson(Map<String, dynamic> json) {
    final number = json['Number']?.toString() ?? '0';
    final id = json['Identification']?.toString() ?? '';
    return MangaChapter(
      id: id,
      chapterNumber: number,
      volume: null,
      title: 'Capítulo $number',
      pagesCount: 0,
      scanlationGroup: null,
      translatedLanguage: 'es',
      externalUrl: null,
    );
  }
}
