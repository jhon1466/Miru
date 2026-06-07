import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../widgets/anime_poster_image.dart';
import '../widgets/catalog_hentai_chip.dart';
import '../widgets/provider_chips_row.dart';
import 'detail_screen.dart';

bool _isTVScreen(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.navigationMode == NavigationMode.directional ||
      mq.size.shortestSide > 480;
}

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
    'Acción',
    'Artes Marciales',
    'Aventura',
    'Carreras',
    'Ciencia Ficción',
    'Comedia',
    'Cyberpunk',
    'Demencia',
    'Demonios',
    'Deportes',
    'Drama',
    'Ecchi',
    'Escolar',
    'Espacial',
    'Fantasía',
    'Fantasía oscura',
    'Gore',
    'Harem',
    'Histórico',
    'Isekai',
    'Josei',
    'Juegos',
    'Magia',
    'Mecha',
    'Militar',
    'Misterio',
    'Música',
    'Parodia',
    'Policial',
    'Post-Apocalíptico',
    'Psicológico',
    'Recuentos de la vida',
    'Romance',
    'Samuráis',
    'Seinen',
    'Shoujo',
    'Shounen',
    'Sobrenatural',
    'Superpoderes',
    'Suspenso',
    'Terror',
    'Vampiros',
    'Yaoi',
    'Yuri',
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
    final isTV = _isTVScreen(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Catálogo'),
        actions: [
          if (isTV) ...[
            // En TV: botón de búsqueda que abre diálogo (no roba foco automáticamente)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar',
              onPressed: () => _showTVSearchDialog(context, provider),
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Filtros',
              onPressed: () => _showTVFiltersDialog(context, provider),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar catálogo',
            onPressed: () => provider.loadCatalog(forceNetwork: true),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isTV) _buildFilters(context, provider),
          Expanded(child: _buildBody(provider, isTV: isTV)),
        ],
      ),
    );
  }

  /// Diálogo de búsqueda para TV — el teclado solo aparece cuando el usuario lo pide
  void _showTVSearchDialog(BuildContext context, AnimeProvider provider) {
    final ctrl = TextEditingController(text: provider.catalogQuery);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buscar anime'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Título del anime...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) {
            provider.setCatalogQuery(v);
            _reloadFromApi();
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.clear();
              provider.setCatalogQuery('');
              _reloadFromApi();
              Navigator.pop(ctx);
            },
            child: const Text('Limpiar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  /// Diálogo de filtros para TV — género, año, tipo, estado
  void _showTVFiltersDialog(BuildContext context, AnimeProvider provider) {
    final genres = {
      ..._defaultGenres,
      ...provider.facetGenres,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final types = {
      ..._defaultTypes,
      ...provider.facetTypes,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final statuses = {
      ..._defaultStatuses,
      ...provider.facetStatuses,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Filtros'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogDropdown(ctx, setD, 'Género', provider.catalogGenre,
                    ['', ...genres], (v) {
                  provider.setCatalogGenre(v ?? '');
                  _reloadFromApi();
                }),
                const SizedBox(height: 12),
                _dialogDropdown(ctx, setD, 'Año', provider.catalogYear,
                    ['', ..._yearOptions], (v) {
                  provider.setCatalogYear(v ?? '');
                  _reloadFromApi();
                }),
                const SizedBox(height: 12),
                _dialogDropdown(ctx, setD, 'Tipo', provider.catalogType,
                    ['', ...types], (v) {
                  provider.setCatalogType(v ?? '');
                  _reloadFromApi();
                }),
                const SizedBox(height: 12),
                _dialogDropdown(ctx, setD, 'Estado', provider.catalogStatus,
                    ['', ...statuses], (v) {
                  provider.setCatalogStatus(v ?? '');
                  _reloadFromApi();
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                provider.clearCatalogFilters();
                provider.loadCatalog();
                Navigator.pop(ctx);
              },
              child: const Text('Limpiar todo'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogDropdown(
    BuildContext ctx,
    StateSetter setD,
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: ctx.primaryColor)),
        ),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value.isEmpty ? '' : value,
              dropdownColor: ctx.cardColor,
              style: TextStyle(fontSize: 13, color: ctx.textPrimary),
              items: items.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item.isEmpty ? 'Todos' : item,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ctx.textPrimary)),
                  )).toList(),
              onChanged: (v) {
                setD(() {});
                onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, AnimeProvider provider) {
    final genres = {
      ..._defaultGenres,
      ...provider.facetGenres,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final types = {
      ..._defaultTypes,
      ...provider.facetTypes,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final statuses = {
      ..._defaultStatuses,
      ...provider.facetStatuses,
    }.where((s) => s.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: context.cardColor.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chips de proveedor
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 38,
              child: ProviderChipsRow(
                provider: provider,
                padding: const EdgeInsets.only(right: 8),
              ),
            ),
          ),
          CatalogHentaiChip(provider: provider),
          TextField(
            controller: _searchController,
            onChanged: (v) {
              provider.setCatalogQuery(v);
              _reloadFromApi();
            },
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'Filtrar por título...',
              prefixIcon: Icon(Icons.search, color: context.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: context.textSecondary),
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.primaryColor,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(minWidth: 100, maxWidth: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value.isNotEmpty ? context.primaryColor : context.textSecondary.withValues(alpha: 0.25),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value.isEmpty ? '' : value,
              dropdownColor: context.cardColor,
              style: TextStyle(fontSize: 12, color: context.textPrimary),
              icon: Icon(Icons.arrow_drop_down, color: context.textSecondary, size: 20),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.isEmpty ? 'Todos' : item,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textPrimary),
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
                      style: TextStyle(fontSize: 12, color: context.textPrimary),
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

  Widget _buildBody(AnimeProvider provider, {bool isTV = false}) {
    if (provider.isLoadingCatalog && provider.catalogResults.isEmpty) {
      final slowFilter = provider.catalogYear.isNotEmpty ||
          provider.catalogStatus.isNotEmpty ||
          provider.catalogType.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.primaryColor)),
            if (slowFilter) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Aplicando filtros al catálogo…\nPuede tardar un momento la primera vez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (provider.catalogError != null && provider.catalogResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: context.dangerColor, size: 48),
              const SizedBox(height: 12),
              Text(provider.catalogError!, textAlign: TextAlign.center, style: TextStyle(color: context.textPrimary)),
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
      return Center(
        child: Text(
          'No hay resultados con estos filtros.\nPrueba limpiar o cambiar de proveedor.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary),
        ),
      );
    }

    final itemCount = results.length + (provider.isLoadingMoreCatalog ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _countLabel(provider),
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                bottom: widget.embedded
                    ? (MediaQuery.of(context).viewInsets.bottom > 0
                        ? 16.0
                        : MediaQuery.of(context).padding.bottom + 80.0)
                    : 16.0,
              ),
              itemCount: itemCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isTV ? 5 : 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: isTV ? 14 : 10,
                mainAxisSpacing: isTV ? 16 : 12,
              ),
              itemBuilder: (context, index) {
                if (index >= results.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(context.primaryColor),
                      ),
                    ),
                  );
                }

                final anime = results[index];
                if (isTV) {
                  return _TVAnimeCard(anime: anime);
                }
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: context.textPrimary,
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

// ── Tarjeta de anime con foco D-pad para TV ────────────────────────────────

class _TVAnimeCard extends StatefulWidget {
  final dynamic anime; // AnimeResult
  const _TVAnimeCard({required this.anime});

  @override
  State<_TVAnimeCard> createState() => _TVAnimeCardState();
}

class _TVAnimeCardState extends State<_TVAnimeCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              animeUrl: widget.anime.url,
              animeTitle: widget.anime.title,
              animeImage: widget.anime.image,
            ),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? primary : Colors.transparent,
              width: 3,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: primary.withValues(alpha: 0.5), blurRadius: 12)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AnimePosterImage(
                    imageUrl: widget.anime.image,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: _focused ? primary : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
