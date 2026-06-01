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
  final _scrollController = ScrollController();

  static const _defaultGenres = [
    'Acción', 'Aventura', 'Fantasía', 'Drama', 'Romance', 'Comedia',
    'Suspenso', 'Ciencia Ficción', 'Isekai', 'Psicológico',
  ];
  static const _defaultTypes = ['TV Anime', 'Película', 'OVA', 'Especial'];
  static const _defaultStatuses = ['En emisión', 'Finalizado', 'Próximamente'];

  static List<String> get _yearOptions {
    final current = DateTime.now().year;
    return List.generate(current - 1991 + 1, (i) => (current - i).toString());
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimeProvider>().loadCatalog();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    if (_scrollController.position.pixels >= max - 280) {
      context.read<AnimeProvider>().loadMoreCatalog();
    }
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
            tooltip: 'Recargar catálogo',
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
              prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _filterDropdown(
                  label: 'Género',
                  value: provider.catalogGenre,
                  items: ['', ...genres],
                  onChanged: (v) {
                    provider.setCatalogGenre(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterDropdown(
                  label: 'Año',
                  value: provider.catalogYear,
                  items: ['', ..._yearOptions],
                  onChanged: (v) {
                    provider.setCatalogYear(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterDropdown(
                  label: 'Tipo',
                  value: provider.catalogType,
                  items: ['', ...types],
                  onChanged: (v) {
                    provider.setCatalogType(v ?? '');
                    _reloadFromApi();
                  },
                ),
                const SizedBox(width: 8),
                _filterDropdown(
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

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = value.isEmpty ? 'Todos' : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(minWidth: 100, maxWidth: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value.isNotEmpty ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.25),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value.isEmpty ? '' : value,
              dropdownColor: AppTheme.cardColor,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary, size: 20),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.isEmpty ? 'Todos' : item,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              selectedItemBuilder: (context) {
                return items.map((_) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selected,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  );
                }).toList();
              },
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  String _countLabel(AnimeProvider provider) {
    final loaded = provider.catalogResults.length;
    final total = provider.catalogTotalRecords;
    if (total != null && total > 0) {
      return 'Mostrando $loaded de $total animes';
    }
    if (provider.catalogTotalPages != null && provider.catalogTotalPages! > 1) {
      return '$loaded animes cargados · desliza para ver más';
    }
    return '$loaded animes';
  }

  Widget _buildBody(AnimeProvider provider) {
    if (provider.isLoadingCatalog && provider.catalogResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
      );
    }

    if (provider.catalogError != null && provider.catalogResults.isEmpty) {
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

    final itemCount = results.length + (provider.isLoadingMoreCatalog ? 1 : 0);

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
            _countLabel(provider),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              itemCount: itemCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                if (index >= results.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                      ),
                    ),
                  );
                }

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
