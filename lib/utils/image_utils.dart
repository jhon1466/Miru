/// Normaliza URLs de imágenes de anime para [CachedNetworkImage].
String? normalizeAnimeImageUrl(String? raw, {String? baseAnimeUrl}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == 'null') return null;

  if (trimmed.startsWith('//')) {
    return 'https:${trimmed.substring(2)}';
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/') && baseAnimeUrl != null) {
    final uri = Uri.tryParse(baseAnimeUrl);
    if (uri != null && uri.host.isNotEmpty) {
      return '${uri.scheme}://${uri.host}$trimmed';
    }
  }
  return null;
}

/// Elige la primera URL de imagen válida entre varios campos del JSON de la API.
String? pickAnimeImageUrl(Map<String, dynamic> json, {String? baseAnimeUrl}) {
  final candidates = [
    json['image'],
    json['poster'],
    json['cover'],
    json['backdrop'],
    json['banner'],
    json['thumbnail'],
  ];
  for (final candidate in candidates) {
    final url = normalizeAnimeImageUrl(candidate?.toString(), baseAnimeUrl: baseAnimeUrl);
    if (url != null) return url;
  }
  return null;
}

/// Intenta inferir URLs a partir de la URL del anime (covers antes que banners).
List<String> inferImageUrlsFromAnimeUrl(String animeUrl, {bool bannersFirst = false}) {
  final uri = Uri.tryParse(animeUrl);
  if (uri == null) return [];

  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return [];

  String? slug;
  String? id;

  if (segments.contains('media')) {
    final idx = segments.indexOf('media');
    if (idx + 1 < segments.length) slug = segments[idx + 1];
  } else {
    slug = segments.last;
  }

  final numeric = RegExp(r'^\d+$');
  if (slug != null && numeric.hasMatch(slug)) {
    id = slug;
    slug = null;
  }

  final coverUrls = <String>[];
  final bannerUrls = <String>[];

  if (host.contains('animeav1')) {
    if (id != null) {
      coverUrls.add('https://cdn.animeav1.com/covers/$id.jpg');
      bannerUrls.add('https://cdn.animeav1.com/banners/$id.jpg');
    }
    if (slug != null) {
      coverUrls.add('https://cdn.animeav1.com/covers/$slug.jpg');
      bannerUrls.add('https://cdn.animeav1.com/banners/$slug.jpg');
    }
  } else if (host.contains('animeflv')) {
    if (slug != null) {
      coverUrls.add('https://${uri.host}/uploads/animes/covers/$slug.jpg');
    }
  }

  if (bannersFirst) {
    return [...bannerUrls, ...coverUrls];
  }
  return [...coverUrls, ...bannerUrls];
}

/// Cabeceras HTTP para CDNs que bloquean peticiones sin User-Agent/Referer.
Map<String, String> imageHttpHeadersForUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return _defaultImageHeaders;

  final host = uri.host.toLowerCase();
  final headers = Map<String, String>.from(_defaultImageHeaders);

  if (host.contains('animeav1')) {
    headers['Referer'] = 'https://animeav1.com/';
    headers['Origin'] = 'https://animeav1.com';
  } else if (host.contains('animeflv')) {
    headers['Referer'] = 'https://www3.animeflv.net/';
  } else if (host.contains('hentaila')) {
    headers['Referer'] = 'https://hentaila.com/';
  }

  return headers;
}

const Map<String, String> _defaultImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

void _addUrl(List<String> list, Set<String> seen, String? raw, {String? baseAnimeUrl}) {
  final url = normalizeAnimeImageUrl(raw, baseAnimeUrl: baseAnimeUrl);
  if (url != null && seen.add(url)) {
    list.add(url);
  }
}

/// Lista ordenada de candidatos para portada (prioriza image/poster).
List<String> collectPosterUrlCandidates({
  String? apiImage,
  String? apiBackdrop,
  String? passedImage,
  String? animeUrl,
  String? animeId,
}) {
  final seen = <String>{};
  final list = <String>[];

  _addUrl(list, seen, apiImage, baseAnimeUrl: animeUrl);
  _addUrl(list, seen, passedImage, baseAnimeUrl: animeUrl);
  _addUrl(list, seen, apiBackdrop, baseAnimeUrl: animeUrl);

  if (animeId != null) {
    _addUrl(list, seen, 'https://cdn.animeav1.com/covers/$animeId.jpg');
    _addUrl(list, seen, 'https://cdn.animeav1.com/banners/$animeId.jpg');
  }

  if (animeUrl != null) {
    for (final u in inferImageUrlsFromAnimeUrl(animeUrl)) {
      _addUrl(list, seen, u);
    }
  }

  return list;
}

/// Lista para banner: portada que ya funciona primero, luego backdrops amplios.
List<String> collectBannerUrlCandidates({
  String? apiImage,
  String? apiBackdrop,
  String? passedImage,
  String? animeUrl,
  String? animeId,
  String? knownWorkingPosterUrl,
}) {
  final seen = <String>{};
  final list = <String>[];

  // La portada visible casi siempre carga: usarla como primer intento del banner
  _addUrl(list, seen, knownWorkingPosterUrl, baseAnimeUrl: animeUrl);
  _addUrl(list, seen, apiImage, baseAnimeUrl: animeUrl);
  _addUrl(list, seen, passedImage, baseAnimeUrl: animeUrl);
  _addUrl(list, seen, apiBackdrop, baseAnimeUrl: animeUrl);

  if (animeId != null) {
    _addUrl(list, seen, 'https://cdn.animeav1.com/banners/$animeId.jpg');
    _addUrl(list, seen, 'https://cdn.animeav1.com/covers/$animeId.jpg');
  }

  if (animeUrl != null) {
    for (final u in inferImageUrlsFromAnimeUrl(animeUrl, bannersFirst: true)) {
      _addUrl(list, seen, u);
    }
  }

  return list;
}

/// Resuelve la mejor URL de portada disponible.
String resolvePosterUrl({
  String? apiImage,
  String? apiBackdrop,
  String? passedImage,
  String? animeUrl,
  String? animeId,
}) {
  final list = collectPosterUrlCandidates(
    apiImage: apiImage,
    apiBackdrop: apiBackdrop,
    passedImage: passedImage,
    animeUrl: animeUrl,
    animeId: animeId,
  );
  return list.isNotEmpty ? list.first : '';
}

/// Resuelve URL del banner (misma lógica que lista de candidatos).
String resolveBannerUrl({
  String? apiBackdrop,
  String? apiImage,
  String? passedImage,
  String? animeUrl,
  String? animeId,
  String? knownWorkingPosterUrl,
}) {
  final list = collectBannerUrlCandidates(
    apiImage: apiImage,
    apiBackdrop: apiBackdrop,
    passedImage: passedImage,
    animeUrl: animeUrl,
    animeId: animeId,
    knownWorkingPosterUrl: knownWorkingPosterUrl,
  );
  return list.isNotEmpty ? list.first : '';
}
