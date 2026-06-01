import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../widgets/anime_poster_image.dart';
import 'detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  final bool embedded;

  const CatalogScreen({super.key, this.embedded = false});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  Timer? _filterDebounce;
  final _searchController = TextEditingController();

  static const _defaultGenres = [
    'Acción', 'Aventura', 'Fantasía', 'Drama', 'Romance', 'Comedia',
    'Suspenso', 'Ciencia Ficción', 'Isekai', 'Psicológico',
  ];
  static const _defaultTypes = ['TV Anime', 'Película', 'OVA', 'Especial'];
  static const _defaultStatuses = ['En emisión', 'Finalizado', 'Próximamente'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimeProvider>().loadCatalog();
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _reloadFromApi() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      context.read<AnimeProvider>().loadCatalog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AnimeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Catálogo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.loadCatalog(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(context, provider),
          Expanded(child: _buildBody(provider)),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, AnimeProvider provider) {
    final genres = provider.facetGenres.isNotEmpty ? provider.facetGenres : _defaultGenres;
    final years = provider.facetYears.isNotEmpty
        ? provider.facetYears
        : List.generate(30, (i) => (DateTime.now().year - i).toString());
    final types = provider.facetTypes.isNotEmpty ? provider.facetTypes : _defaultTypes;
    final statuses = provider.facetStatuses.isNotEmpty ? provider.facetStatuses : _defaultStatuses;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: AppTheme.cardColor.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) {
              provider.setCatalogQuery(v);
              _reloadFromApi();
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Filtrar por título...',
              prefixIcon: const Icon(Icons.filter_alt, color: AppTheme.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        provider.setCatalogQuery('');
                        _reloadFromApi();
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'Género',
                  value: provider.catalogGenre,
                  items: ['', ...genres],
                  onChanged: (v) {
                    provider.setCatalogGenre(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Año',
                  value: provider.catalogYear,
                  items: ['', ...years.take(15)],
                  onChanged: (v) {
                    provider.setCatalogYear(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Tipo',
                  value: provider.catalogType,
                  items: ['', ...types],
                  onChanged: (v) {
                    provider.setCatalogType(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Estado',
                  value: provider.catalogStatus,
                  items: ['', ...statuses],
                  onChanged: (v) {
                    provider.setCatalogStatus(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    _searchController.clear();
                    provider.clearCatalogFilters();
                    provider.loadCatalog();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value.isNotEmpty ? AppTheme.primaryColor : Colors.transparent,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? '' : value,
          hint: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          dropdownColor: AppTheme.cardColor,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(item.isEmpty ? 'Todos' : item, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBody(AnimeProvider provider) {
    if (provider.isLoadingCatalog) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
      );
    }

    if (provider.catalogError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
              const SizedBox(height: 12),
              Text(provider.catalogError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => provider.loadCatalog(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final results = provider.catalogResults;
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No hay resultados con estos filtros.\nPrueba limpiar o cambiar de proveedor.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: widget.embedded ? 88 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${results.length} animes',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              itemCount: results.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final anime = results[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailScreen(
                        animeUrl: anime.url,
                        animeTitle: anime.title,
                        animeImage: anime.image,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AnimePosterImage(
                            imageUrl: anime.image,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
