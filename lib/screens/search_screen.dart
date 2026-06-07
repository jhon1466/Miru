import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../widgets/anime_poster_image.dart';
import '../widgets/provider_chips_row.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final bool embedded;

  const SearchScreen({super.key, this.embedded = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  List<String> _history = [];
  static const _historyKey = 'search_history';
  static const _maxHistory = 15;

  final List<String> _quickSuggestions = [
    'One Piece',
    'Naruto',
    'Bleach',
    'Dragon Ball',
    'Jujutsu Kaisen',
    'Demon Slayer',
    'Solo Leveling',
    'Chainsaw Man',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = prefs.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _saveToHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(q);          // evita duplicados
    list.insert(0, q);       // más reciente primero
    if (list.length > _maxHistory) list.removeLast();
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _removeFromHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(query);
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      context.read<AnimeProvider>().clearSearch();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<AnimeProvider>().search(trimmed);
      _saveToHistory(trimmed);
    });
  }

  void _onSearchSubmit(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) return;
    context.read<AnimeProvider>().search(q);
    _saveToHistory(q);
  }

  void _applyQuery(String query) {
    setState(() => _searchController.text = query);
    _onSearchSubmit(query);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: _onSearchSubmit,
            onChanged: (val) {
              setState(() {});
              _onSearchChanged(val);
            },
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar anime...',
              prefixIcon: Icon(Icons.search, color: context.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: context.textSecondary),
                      onPressed: () {
                        _debounce?.cancel();
                        setState(() => _searchController.clear());
                        animeProvider.clearSearch();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProviderChipsRow(
            provider: animeProvider,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          if (_searchController.text.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: context.cardColor.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    animeProvider.selectedProviderDomain.isEmpty
                        ? 'Buscando en todos los proveedores'
                        : 'Buscando en ${animeProvider.providers.firstWhere((p) => p["domain"] == animeProvider.selectedProviderDomain, orElse: () => {"name": animeProvider.selectedProviderDomain})["name"]}',
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    'En vivo',
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildSearchBody(animeProvider)),
        ],
      ),
    );
  }

  Widget _buildSearchBody(AnimeProvider provider) {
    if (provider.isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 16),
            Text('Buscando animes...', style: TextStyle(color: context.textSecondary)),
          ],
        ),
      );
    }

    if (provider.searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.dangerColor),
              const SizedBox(height: 16),
              Text(provider.searchError!, textAlign: TextAlign.center, style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => _onSearchSubmit(_searchController.text), child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (provider.searchResults.isEmpty) {
      if (_searchController.text.trim().isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 48, color: context.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'No se encontraron resultados para tu búsqueda.\nIntenta con otro término o cambia de proveedor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary),
                ),
              ],
            ),
          ),
        );
      }

      return _buildEmptyState();
    }

    return _buildResultsGrid(provider);
  }

  Widget _buildEmptyState() {
    final EdgeInsets padding = EdgeInsets.only(
      left: 20.0,
      right: 20.0,
      top: 20.0,
      bottom: widget.embedded
          ? (MediaQuery.of(context).viewInsets.bottom > 0 ? 20.0 : MediaQuery.of(context).padding.bottom + 80.0)
          : 20.0,
    );

    return SingleChildScrollView(
      padding: padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Historial ────────────────────────────────────
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.history, size: 17, color: context.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Búsquedas recientes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Borrar todo', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: _history.asMap().entries.map((entry) {
                  final i = entry.key;
                  final q = entry.value;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => _applyQuery(q),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 16, color: context.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(q, style: TextStyle(fontSize: 14, color: context.textPrimary)),
                              ),
                              GestureDetector(
                                onTap: () => _removeFromHistory(q),
                                child: Icon(Icons.close, size: 16, color: context.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < _history.length - 1)
                        Divider(height: 1, indent: 44, color: context.textSecondary.withValues(alpha: 0.1)),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Sugerencias populares ─────────────────────────
          Text(
            'Búsquedas populares',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Escribe para ver resultados al instante, sin pulsar Enter.',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _quickSuggestions.map((suggestion) {
              return InkWell(
                onTap: () => _applyQuery(suggestion),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
                  ),
                  child: Text(suggestion, style: TextStyle(color: context.textPrimary, fontSize: 13)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsGrid(AnimeProvider provider) {
    return GridView.builder(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: widget.embedded
            ? (MediaQuery.of(context).viewInsets.bottom > 0 ? 16.0 : MediaQuery.of(context).padding.bottom + 80.0)
            : 16.0,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: provider.searchResults.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.60,
        crossAxisSpacing: 10,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final anime = provider.searchResults[index];
        return InkWell(
          onTap: () {
            FocusScope.of(context).unfocus();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(
                  animeUrl: anime.url,
                  animeTitle: anime.title,
                  animeImage: anime.image,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      AnimePosterImage(
                        imageUrl: anime.image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                      if (anime.score != null)
                        Positioned(
                          left: 6, top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 10),
                                const SizedBox(width: 2),
                                Text(anime.score.toString(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      if (anime.type != null)
                        Positioned(
                          right: 6, bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.9), borderRadius: BorderRadius.circular(6)),
                            child: Text(anime.type!, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: context.textPrimary),
              ),
              if (anime.year != null || anime.status != null)
                Text(
                  '${anime.year ?? ''} • ${anime.status ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: context.textSecondary),
                ),
            ],
          ),
        );
      },
    );
  }
}
