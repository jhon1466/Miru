import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

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
    // Esperar un momento y enfocar el campo de búsqueda
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    context.read<AnimeProvider>().search(query);
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: _onSearchSubmit,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar anime...',
              prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                        });
                        animeProvider.clearSearch();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (val) {
              setState(() {}); // Actualiza para mostrar/ocultar botón de borrar
            },
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-cabecera con información del proveedor activo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppTheme.cardColor.withOpacity(0.5),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  animeProvider.selectedProviderDomain.isEmpty 
                      ? 'Buscando en: Todos los proveedores' 
                      : 'Buscando en: ${animeProvider.providers.firstWhere((p) => p['domain'] == animeProvider.selectedProviderDomain)['name']}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _buildSearchBody(animeProvider),
          ),
        ],
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
            Text('Escaneando proveedores de streaming...', style: TextStyle(color: AppTheme.textSecondary)),
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
                const SizedBox(height: 16),
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

      // Sugerencias rápidas cuando el buscador está vacío
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Búsquedas Populares',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

    // Grid de resultados de búsqueda
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
            // Guardar el teclado
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
                      CachedNetworkImage(
                        imageUrl: anime.image ?? '',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => Container(color: AppTheme.cardColor),
                        errorWidget: (context, url, error) => Container(
                          color: AppTheme.cardColor,
                          child: const Icon(Icons.movie, color: AppTheme.textSecondary),
                        ),
                      ),
                      // Puntuación
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
                      // Tipo (Serie, Película, OVA)
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
