import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/manga_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/manga_favorite_service.dart';
import '../services/manga_follow_service.dart';
import '../widgets/anime_poster_image.dart';
import 'manga_detail_screen.dart';
import 'manga_reader_screen.dart';

class MangaTabScreen extends StatefulWidget {
  const MangaTabScreen({super.key});

  @override
  State<MangaTabScreen> createState() => _MangaTabScreenState();
}

class _MangaTabScreenState extends State<MangaTabScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _libraryTabIndex = 0; // 0: Favoritos, 1: Siguiendo

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MangaProvider>();
      if (provider.popularManga.isEmpty) {
        provider.loadPopularManga();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<MangaProvider>();
      final isSearchingMode = _searchController.text.trim().isNotEmpty;
      if (isSearchingMode) {
        if (!provider.isSearching && provider.hasMoreSearch && !provider.isLoadingMoreSearch) {
          provider.searchManga(_searchController.text, loadMore: true);
        }
      } else {
        if (!provider.isLoadingPopular && provider.hasMorePopular && !provider.isLoadingMorePopular) {
          provider.loadPopularManga(loadMore: true);
        }
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        context.read<MangaProvider>().searchManga(query);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mangaProvider = Provider.of<MangaProvider>(context);
    final mangaHistoryProvider = Provider.of<MangaHistoryProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isSearchingMode = _searchController.text.trim().isNotEmpty;
    final isPageLoading = isSearchingMode ? mangaProvider.isSearching : mangaProvider.isLoadingPopular;
    final pageError = isSearchingMode ? mangaProvider.searchError : mangaProvider.popularError;
    final displayedManga = isSearchingMode ? mangaProvider.searchResults : mangaProvider.popularManga;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header + Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.book_rounded, color: context.primaryColor, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'InManga',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (query) {
                      _onSearchChanged(query);
                      setState(() {}); // rebuild to show/hide search mode content
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar manga en español...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                context.read<MangaProvider>().searchManga('');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Contenido principal
            Expanded(
              child: isPageLoading && displayedManga.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(context.primaryColor),
                      ),
                    )
                  : pageError != null && displayedManga.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: context.dangerColor),
                                const SizedBox(height: 12),
                                Text(
                                  pageError,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: context.textSecondary),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    if (isSearchingMode) {
                                      mangaProvider.searchManga(_searchController.text);
                                    } else {
                                      mangaProvider.loadPopularManga();
                                    }
                                  },
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            if (isSearchingMode) {
                              await mangaProvider.searchManga(_searchController.text);
                            } else {
                              await mangaProvider.loadPopularManga();
                            }
                          },
                          child: CustomScrollView(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              // ─── Secciones personales (solo si no está buscando) ───────
                              if (!isSearchingMode) ...[
                                // Continuar leyendo
                                if (mangaHistoryProvider.history.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildContinueReadingSection(context, mangaHistoryProvider, authProvider),
                                  ),

                                // Mi Biblioteca Manga
                                SliverToBoxAdapter(
                                  child: _buildLibrarySection(context, authProvider),
                                ),

                                // Separador antes de populares
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                    child: Text(
                                      'Mangas Populares',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // ─── Grid de mangas (búsqueda o populares) ─────────────────
                              if (displayedManga.isEmpty && !isPageLoading)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Text(
                                        isSearchingMode
                                            ? 'No se encontraron resultados para "${_searchController.text}"'
                                            : 'No hay mangas populares disponibles.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: context.textSecondary),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.58,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final manga = displayedManga[index];
                                        final candidates = manga.coverUrl != null ? [manga.coverUrl!] : <String>[];

                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => MangaDetailScreen(mangaId: manga.id),
                                              ),
                                            );
                                          },
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    AnimePosterImage(
                                                      urlCandidates: candidates,
                                                      fit: BoxFit.cover,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    if (manga.status != null)
                                                      Positioned(
                                                        top: 6,
                                                        left: 6,
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: context.primaryColor.withValues(alpha: 0.9),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            manga.status!.toUpperCase(),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 8,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                manga.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.textPrimary,
                                                ),
                                              ),
                                              if (manga.author != null)
                                                Text(
                                                  manga.author!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: context.textSecondary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                      childCount: displayedManga.length,
                                    ),
                                  ),
                                ),

                              if (isSearchingMode ? mangaProvider.isLoadingMoreSearch : mangaProvider.isLoadingMorePopular)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation(context.primaryColor),
                                      ),
                                    ),
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 90),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueReadingSection(
    BuildContext context,
    MangaHistoryProvider historyProvider,
    app_auth.AuthProvider authProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            'Continuar leyendo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: historyProvider.history.length,
            itemBuilder: (context, index) {
              final item = historyProvider.history[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaReaderScreen(
                        mangaId: item.mangaId,
                        mangaTitle: item.mangaTitle,
                        coverUrl: item.coverUrl,
                        chapterId: item.chapterId,
                        chapterNumber: item.chapterNumber,
                        startPage: item.page,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 280,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                        child: SizedBox(
                          width: 68,
                          height: double.infinity,
                          child: item.coverUrl.isNotEmpty
                              ? AnimePosterImage(
                                  urlCandidates: [item.coverUrl],
                                  fit: BoxFit.cover,
                                )
                              : Container(color: context.primaryColor.withValues(alpha: 0.2)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.mangaTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cap. ${item.chapterNumber} · Pág. ${item.page}',
                              style: TextStyle(fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert, color: context.textSecondary, size: 20),
                        onPressed: () => _showHistoryOptions(context, item.mangaId, historyProvider, authProvider),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showHistoryOptions(
    BuildContext context,
    String mangaId,
    MangaHistoryProvider historyProvider,
    app_auth.AuthProvider authProvider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardColor,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.info, color: Colors.blue),
            title: Text('Ver detalles', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MangaDetailScreen(mangaId: mangaId),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppTheme.dangerColor),
            title: Text('Eliminar del historial', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              historyProvider.removeFromHistory(mangaId, userId: authProvider.userId);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLibrarySection(BuildContext context, app_auth.AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Mi Biblioteca Manga',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              if (authProvider.isLoggedIn && authProvider.userId != null) ...[
                const Spacer(),
                _buildTabButton(
                  context,
                  title: 'Favoritos',
                  isActive: _libraryTabIndex == 0,
                  onTap: () => setState(() => _libraryTabIndex = 0),
                ),
                const SizedBox(width: 8),
                _buildTabButton(
                  context,
                  title: 'Siguiendo',
                  isActive: _libraryTabIndex == 1,
                  onTap: () => setState(() => _libraryTabIndex = 1),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (!authProvider.isLoggedIn || authProvider.userId == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.bookmark_outline, size: 36, color: context.primaryColor),
                  const SizedBox(height: 8),
                  Text(
                    'Guarda tus mangas favoritos',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inicia sesión con Google para guardar mangas y sincronizarlos en todos tus dispositivos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ],
              ),
            )
          else
            _buildMangaLibraryGrid(context, authProvider.userId!),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? context.primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? context.primaryColor : context.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMangaLibraryGrid(BuildContext context, String userId) {
    return StreamBuilder<List<FavoriteManga>>(
      stream: _libraryTabIndex == 0
          ? MangaFavoriteService.getFavorites(userId)
          : MangaFollowService.getFollowing(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor))),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Icon(
                  _libraryTabIndex == 0 ? Icons.favorite_border : Icons.bookmark_border_rounded,
                  size: 36,
                  color: context.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  _libraryTabIndex == 0 ? 'Sin favoritos aún' : 'No sigues ningún manga aún',
                  style: TextStyle(color: context.textSecondary),
                ),
              ],
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.62,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final fav = items[index];
            final candidates = fav.coverUrl != null ? [fav.coverUrl!] : <String>[];
            return InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MangaDetailScreen(mangaId: fav.mangaId)),
              ),
              borderRadius: BorderRadius.circular(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AnimePosterImage(
                        urlCandidates: candidates,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fav.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
