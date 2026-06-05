import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/novel.dart';
import '../providers/novel_provider.dart';
import '../providers/novel_history_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/anime_poster_image.dart';
import '../services/novel_favorite_service.dart';
import '../services/novel_follow_service.dart';
import 'novel_detail_screen.dart';

class NovelTabScreen extends StatefulWidget {
  const NovelTabScreen({super.key});

  @override
  State<NovelTabScreen> createState() => _NovelTabScreenState();
}

class _NovelTabScreenState extends State<NovelTabScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NovelProvider>();
      if (provider.popularNovels.isEmpty) {
        provider.loadPopularNovels();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<NovelProvider>();
      final isSearchingMode = _searchController.text.trim().isNotEmpty;
      if (!isSearchingMode &&
          !provider.isLoadingPopular &&
          provider.hasMorePopular) {
        provider.loadPopularNovels(loadMore: true);
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        context.read<NovelProvider>().searchNovels(query);
      }
    });
  }

  void _openNovel(BuildContext context, Novel novel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelDetailScreen(novel: novel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final historyProvider = Provider.of<NovelHistoryProvider>(context);
    final isSearchingMode = _searchController.text.trim().isNotEmpty;
    final isPageLoading =
        isSearchingMode ? novelProvider.isSearching : novelProvider.isLoadingPopular;
    final pageError =
        isSearchingMode ? novelProvider.searchError : novelProvider.popularError;
    final displayedNovels = isSearchingMode
        ? novelProvider.searchResults
        : novelProvider.popularNovels;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.auto_stories_rounded,
                      color: context.primaryColor, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Novelas Ligeras',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Tabs ───────────────────────────────────────────────
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Explorar'),
                Tab(text: 'Mis Novelas'),
                Tab(text: 'Historial'),
              ],
              labelColor: context.primaryColor,
              unselectedLabelColor: context.textSecondary,
              indicatorColor: context.primaryColor,
              dividerColor: Colors.transparent,
            ),

            // ── Tab content ────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ─────── TAB 1: Explorar ───────────────────────
                  _ExploreTab(
                    searchController: _searchController,
                    scrollController: _scrollController,
                    isSearchingMode: isSearchingMode,
                    isPageLoading: isPageLoading,
                    pageError: pageError,
                    displayedNovels: displayedNovels,
                    novelProvider: novelProvider,
                    onSearchChanged: _onSearchChanged,
                    onOpenNovel: _openNovel,
                  ),

                  // ─────── TAB 2: Mis Novelas ────────────────────
                  _MyNovelsTab(
                    userId: authProvider.userId,
                    isLoggedIn: authProvider.isLoggedIn,
                    onOpenNovel: _openNovel,
                  ),

                  // ─────── TAB 3: Historial ──────────────────────
                  _HistoryTab(
                    history: historyProvider.history,
                    userId: authProvider.userId,
                    onOpenNovel: (novelId, title, coverUrl) {
                      // Abre el detalle por ID
                      final novel = Novel(
                        id: novelId,
                        title: title,
                        url: novelId,
                        coverUrl: coverUrl,
                      );
                      _openNovel(context, novel);
                    },
                    onRemove: (novelId) {
                      historyProvider.removeFromHistory(
                        novelId,
                        userId: authProvider.userId,
                      );
                    },
                    onClearAll: () {
                      historyProvider.clearHistory(
                          userId: authProvider.userId);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TAB 1 – EXPLORAR
// ═══════════════════════════════════════════════════════════════════
class _ExploreTab extends StatelessWidget {
  final TextEditingController searchController;
  final ScrollController scrollController;
  final bool isSearchingMode;
  final bool isPageLoading;
  final String? pageError;
  final List<Novel> displayedNovels;
  final NovelProvider novelProvider;
  final void Function(String) onSearchChanged;
  final void Function(BuildContext, Novel) onOpenNovel;

  const _ExploreTab({
    required this.searchController,
    required this.scrollController,
    required this.isSearchingMode,
    required this.isPageLoading,
    required this.pageError,
    required this.displayedNovels,
    required this.novelProvider,
    required this.onSearchChanged,
    required this.onOpenNovel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Buscador
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: searchController,
            onChanged: (q) {
              onSearchChanged(q);
              // setState equivalente via StatefulWidget parent
            },
            decoration: InputDecoration(
              hintText: 'Buscar novela ligera en español...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        novelProvider.searchNovels('');
                      },
                    )
                  : null,
            ),
          ),
        ),

        Expanded(
          child: isPageLoading && displayedNovels.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(context.primaryColor),
                  ),
                )
              : pageError != null && displayedNovels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: context.dangerColor),
                            const SizedBox(height: 12),
                            Text(pageError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (isSearchingMode) {
                                  novelProvider.searchNovels(searchController.text);
                                } else {
                                  novelProvider.loadPopularNovels();
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
                          await novelProvider.searchNovels(searchController.text);
                        } else {
                          await novelProvider.loadPopularNovels();
                        }
                      },
                      child: CustomScrollView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (!isSearchingMode)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Text(
                                  'Novelas Populares',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            ),

                          if (displayedNovels.isEmpty && !isPageLoading)
                            SliverToBoxAdapter(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Text(
                                    isSearchingMode
                                        ? 'No se encontraron resultados para "${searchController.text}"'
                                        : 'No hay novelas disponibles.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: context.textSecondary),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.58,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final novel = displayedNovels[index];
                                    final candidates = novel.coverUrl != null
                                        ? [novel.coverUrl!]
                                        : <String>[];

                                    return GestureDetector(
                                      onTap: () => onOpenNovel(context, novel),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: AnimePosterImage(
                                                urlCandidates: candidates,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            novel.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  childCount: displayedNovels.length,
                                ),
                              ),
                            ),

                          if (!isSearchingMode && novelProvider.isLoadingPopular)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation(
                                        context.primaryColor),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TAB 2 – MIS NOVELAS (Favoritos + Siguiendo)
// ═══════════════════════════════════════════════════════════════════
class _MyNovelsTab extends StatelessWidget {
  final String? userId;
  final bool isLoggedIn;
  final void Function(BuildContext, Novel) onOpenNovel;

  const _MyNovelsTab({
    required this.userId,
    required this.isLoggedIn,
    required this.onOpenNovel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoggedIn || userId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 56, color: context.textSecondary),
              const SizedBox(height: 16),
              Text(
                'Inicia sesión para ver tus novelas favoritas y las que estás siguiendo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.favorite_rounded), text: 'Favoritos'),
              Tab(icon: Icon(Icons.notifications_active_rounded), text: 'Siguiendo'),
            ],
            labelColor: context.primaryColor,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: context.primaryColor,
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Favoritos
                StreamBuilder<List<FavoriteNovel>>(
                  stream: NovelFavoriteService.getFavorites(userId!),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  context.primaryColor)));
                    }
                    final favs = snap.data ?? [];
                    if (favs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite_border_rounded,
                                  size: 56, color: context.textSecondary),
                              const SizedBox(height: 12),
                              Text(
                                'Aún no tienes novelas favoritas.',
                                style: TextStyle(color: context.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return _NovelGridList(
                      items: favs
                          .map((f) => _NovelCardItem(
                                id: f.novelId,
                                title: f.title,
                                coverUrl: f.coverUrl,
                              ))
                          .toList(),
                      onOpenNovel: onOpenNovel,
                    );
                  },
                ),

                // Siguiendo
                StreamBuilder<List<FavoriteNovel>>(
                  stream: NovelFollowService.getFollowing(userId!),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  context.primaryColor)));
                    }
                    final following = snap.data ?? [];
                    if (following.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none_rounded,
                                  size: 56, color: context.textSecondary),
                              const SizedBox(height: 12),
                              Text(
                                'No estás siguiendo ninguna novela.',
                                style: TextStyle(color: context.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sigue una novela para recibir notificaciones\ncuando salgan nuevos capítulos.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return _NovelGridList(
                      items: following
                          .map((f) => _NovelCardItem(
                                id: f.novelId,
                                title: f.title,
                                coverUrl: f.coverUrl,
                              ))
                          .toList(),
                      onOpenNovel: onOpenNovel,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TAB 3 – HISTORIAL
// ═══════════════════════════════════════════════════════════════════
class _HistoryTab extends StatelessWidget {
  final List<dynamic> history;
  final String? userId;
  final void Function(String, String, String?) onOpenNovel;
  final void Function(String) onRemove;
  final VoidCallback onClearAll;

  const _HistoryTab({
    required this.history,
    required this.userId,
    required this.onOpenNovel,
    required this.onRemove,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 56, color: context.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No has leído ninguna novela aún.',
                style: TextStyle(color: context.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Botón limpiar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Limpiar historial'),
                    content:
                        const Text('¿Borrar todo el historial de novelas?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar')),
                      TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onClearAll();
                          },
                          child: const Text('Limpiar',
                              style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ),
                icon: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.redAccent),
                label: const Text('Limpiar',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              final coverUrl = item.coverUrl as String?;
              final candidates =
                  coverUrl != null && coverUrl.isNotEmpty ? [coverUrl] : <String>[];
              return Dismissible(
                key: Key(item.novelId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                ),
                onDismissed: (_) => onRemove(item.novelId),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    onTap: () =>
                        onOpenNovel(item.novelId, item.novelTitle, item.coverUrl),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 46,
                        height: 64,
                        child: AnimePosterImage(
                          urlCandidates: candidates,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    title: Text(
                      item.novelTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary),
                    ),
                    subtitle: Text(
                      'Capítulo ${item.chapterNumber.toStringAsFixed(0)}: ${item.chapterTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.more_vert, color: context.textSecondary),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: context.cardColor,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (ctx) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.info, color: Colors.blue),
                                title: Text('Ver detalles', style: TextStyle(color: context.textPrimary)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onOpenNovel(item.novelId, item.novelTitle, item.coverUrl);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.delete, color: AppTheme.dangerColor),
                                title: Text('Eliminar del historial', style: TextStyle(color: context.textPrimary)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onRemove(item.novelId);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════
class _NovelCardItem {
  final String id;
  final String title;
  final String? coverUrl;

  _NovelCardItem({required this.id, required this.title, this.coverUrl});
}

class _NovelGridList extends StatelessWidget {
  final List<_NovelCardItem> items;
  final void Function(BuildContext, Novel) onOpenNovel;

  const _NovelGridList({required this.items, required this.onOpenNovel});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final candidates =
            item.coverUrl != null ? [item.coverUrl!] : <String>[];
        final novel =
            Novel(id: item.id, title: item.title, url: item.id, coverUrl: item.coverUrl);

        return GestureDetector(
          onTap: () => onOpenNovel(context, novel),
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
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
