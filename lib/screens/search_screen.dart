import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      context.read<AnimeProvider>().clearSearch();
      return;
    }

    // Búsqueda en vivo: espera 400ms tras dejar de escribir
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<AnimeProvider>().search(trimmed);
    });
  }

  void _onSearchSubmit(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) return;
    context.read<AnimeProvider>().search(query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);

    return Scaffold(
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
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar anime...',
              prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                      onPressed: () {
                        _debounce?.cancel();
                        setState(() {
                          _searchController.clear();
                        });
                        animeProvider.clearSearch();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: widget.embedded ? 88 : 0),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProviderChipsRow(
            provider: animeProvider,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppTheme.cardColor.withOpacity(0.5),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    animeProvider.selectedProviderDomain.isEmpty
                        ? 'Buscando en: Todos los proveedores'
                        : 'Buscando en: ${animeProvider.providers.firstWhere((p) => p['domain'] == animeProvider.selectedProviderDomain)['name']}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                if (_searchController.text.trim().isNotEmpty)
                  const Text(
                    'En vivo',
                    style: TextStyle(fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildSearchBody(animeProvider),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildSearchBody(AnimeProvider provider) {
    if (provider.isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
            SizedBox(height: 16),
            Text('Buscando animes...', style: TextStyle(color: AppTheme.textSecondary)),
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
              const Icon(Icons.error_outline, size: 48, color: AppTheme.dangerColor),
              const SizedBox(height: 16),
              Text(
                provider.searchError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _onSearchSubmit(_searchController.text),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.searchResults.isEmpty) {
      if (_searchController.text.trim().isNotEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 48, color: AppTheme.textSecondary),
                SizedBox(height: 16),
                Text(
                  'No se encontraron resultados para tu búsqueda.\nIntenta con otro término o cambia de proveedor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Búsquedas Populares',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Escribe para ver resultados al instante, sin pulsar Enter.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: _quickSuggestions.map((suggestion) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _searchController.text = suggestion;
                    });
                    _onSearchSubmit(suggestion);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
                    ),
                    child: Text(
                      suggestion,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
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
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 10),
                                const SizedBox(width: 2),
                                Text(
                                  anime.score.toString(),
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (anime.type != null)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              anime.type!,
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              if (anime.year != null || anime.status != null)
                Text(
                  '${anime.year ?? ''} • ${anime.status ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
            ],
          ),
        );
      },
    );
  }
}
