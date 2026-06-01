/// Normaliza URLs de imágenes de anime para [CachedNetworkImage].
String? normalizeAnimeImageUrl(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == 'null') return null;

  if (trimmed.startsWith('//')) {
    return 'https:${trimmed.substring(2)}';
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return null;
}

/// Elige la primera URL de imagen válida entre varios campos del JSON de la API.
String? pickAnimeImageUrl(Map<String, dynamic> json) {
  final candidates = [
    json['image'],
    json['poster'],
    json['cover'],
    json['backdrop'],
    json['banner'],
    json['thumbnail'],
  ];
  for (final candidate in candidates) {
    final url = normalizeAnimeImageUrl(candidate?.toString());
    if (url != null) return url;
  }
  return null;
}

/// Resuelve la mejor URL de portada disponible.
String resolvePosterUrl({
  String? apiImage,
  String? apiBackdrop,
  String? passedImage,
}) {
  return normalizeAnimeImageUrl(apiImage) ??
      normalizeAnimeImageUrl(apiBackdrop) ??
      normalizeAnimeImageUrl(passedImage) ??
      '';
}
