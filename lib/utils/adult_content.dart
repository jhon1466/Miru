import '../models/anime.dart';

/// Proveedores y URLs de contenido +18.
class AdultContent {
  static const String hentaiDomain = 'hentaila.com';

  static const List<String> adultDomains = [
    hentaiDomain,
    'www.hentaila.com',
  ];

  static bool isAdultDomain(String? domain) {
    if (domain == null || domain.isEmpty) return false;
    final d = domain.toLowerCase().replaceAll('www.', '');
    return adultDomains.any((ad) => d == ad.replaceAll('www.', '') || d.endsWith(ad.replaceAll('www.', '')));
  }

  static bool isAdultUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('hentaila.com');
  }

  static List<Map<String, String>> filterProviders(
    List<Map<String, String>> providers, {
    required bool adultEnabled,
  }) {
    if (adultEnabled) return providers;
    return providers
        .where((p) {
          final domain = p['domain'] ?? '';
          return domain.isEmpty || !isAdultDomain(domain);
        })
        .toList();
  }

  static List<AnimeSearchResult> filterAnimeList(
    List<AnimeSearchResult> items, {
    required bool adultEnabled,
  }) {
    if (adultEnabled) return items;
    return items.where((a) => !isAdultUrl(a.url)).toList();
  }
}
