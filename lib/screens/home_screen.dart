import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../core/update_service.dart';
import '../widgets/update_dialog.dart';
import '../providers/anime_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/notification_provider.dart';
import '../services/favorite_service.dart';
import '../services/follow_service.dart';
import '../widgets/anime_poster_image.dart';
import '../models/anime.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'notifications_screen.dart';
import 'public_chat_screen.dart';
import '../providers/chat_provider.dart';
import 'profile_tab_screen.dart';
import 'downloads_screen.dart';
import '../providers/supporter_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _libraryTabIndex = 0; // 0: Favorites, 1: Following

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AnimeProvider>(context, listen: false);
      if (provider.popularAnime.isEmpty) {
        provider.loadPopularAnime();
      }
      if (provider.latestPublishedEpisodes.isEmpty) {
        provider.loadLatestPublishedEpisodes();
      }
      _checkUpdates();
    });
  }

  Future<void> _checkUpdates() async {
    final updateInfo = await UpdateService.checkForUpdates();
    if (updateInfo.hasUpdate && mounted) {
      showAppUpdateDialog(context, updateInfo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);
    final historyProvider = Provider.of<HistoryProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/miruapp.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'MIRU',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          _NotificationsBell(authProvider: authProvider),
          _ChatIconButton(authProvider: authProvider),
          // Botón de descargas
          IconButton(
            tooltip: 'Descargas',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DownloadsScreen()),
            ),
            icon: const Icon(Icons.download_rounded, size: 24),
          ),
          _ProfileIconButton(authProvider: authProvider),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeBanner(context, authProvider),

            // Animes Destacados / Populares
            _buildPopularSection(context, animeProvider),

            _buildLatestPublishedSection(context, animeProvider),

            // Continuar Viendo (Historial)
            if (historyProvider.history.isNotEmpty)
              _buildContinueWatchingSection(context, historyProvider),

            // Favoritos (nube si hay sesión, local si no)
            _buildFavoritesSection(context, historyProvider, authProvider),
            
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner(BuildContext context, app_auth.AuthProvider authProvider) {
    final greeting = authProvider.isLoggedIn
        ? '¡Hola, ${authProvider.displayName ?? 'Usuario'}!'
        : '¡Hola!';
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          Text(
            'Encuentra tus animes favoritos hoy.',
            style: TextStyle(fontSize: 14, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularSection(BuildContext context, AnimeProvider provider) {
    if (provider.isLoadingPopular) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 12.0),
            child: Text(
              'Destacados de la Semana',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
          ),
          SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
            ),
          ),
        ],
      );
    }

    if (provider.popularAnime.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 12.0),
          child: Text(
            'Destacados de la Semana',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: provider.popularAnime.length,
            itemBuilder: (context, index) {
              final anime = provider.popularAnime[index];
              return Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 6.0),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(
                          animeUrl: anime.url,
                          animeTitle: anime.title,
                          animeImage: anime.image ?? '',
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: anime.image ?? '',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (context, url) => Container(color: context.cardColor),
                                errorWidget: (context, url, error) => Container(
                                  color: context.cardColor,
                                  child: Icon(Icons.movie, color: context.textSecondary),
                                ),
                              ),
                              if (anime.score != null)
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.75),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withOpacity(0.3), width: 0.5),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          anime.score.toString(),
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 38,
                        child: Text(
                          anime.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary),
                        ),
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

  Widget _buildLatestPublishedSection(BuildContext context, AnimeProvider provider) {
    if (provider.isLoadingLatestEpisodes && provider.latestPublishedEpisodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
        ),
      );
    }

    if (provider.latestEpisodesError != null && provider.latestPublishedEpisodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          provider.latestEpisodesError!,
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
      );
    }

    final episodes = provider.latestPublishedEpisodes;
    if (episodes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 4.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Capítulos más recientes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 20, color: context.textSecondary),
                onPressed: () => provider.loadLatestPublishedEpisodes(forceNetwork: true),
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 12.0),
          child: Text(
            'Recién publicados en el sitio',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final item = episodes[index];
              return Container(
                width: 180,
                margin: const EdgeInsets.symmetric(horizontal: 6.0),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlayerScreen(
                          episodeUrl: item.episodeUrl,
                          episodeNumber: item.episodeNumber,
                          animeTitle: item.animeTitle,
                          animeUrl: item.animeUrl,
                          animeImage: item.image ?? '',
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimePosterImage(
                                imageUrl: item.image,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Ep. ${item.episodeNumber.toString().replaceAll('.0', '')}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 34,
                        child: Text(
                          item.animeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: context.textPrimary,
                          ),
                        ),
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

  Widget _buildContinueWatchingSection(BuildContext context, HistoryProvider historyProvider) {
    final history = historyProvider.history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 12.0),
          child: Text(
            'Continuar viendo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            scrollDirection: Axis.horizontal,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(
                        episodeUrl: item.episodeUrl,
                        episodeNumber: item.episodeNumber,
                        animeTitle: item.animeTitle,
                        animeUrl: item.animeUrl,
                        animeImage: item.animeImage,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 260,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: item.animeImage,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (context, url) => Container(color: context.cardColor),
                                errorWidget: (context, url, error) => Container(
                                  color: context.cardColor,
                                  child: Icon(Icons.movie, color: context.textSecondary, size: 40),
                                ),
                              ),
                              Positioned.fill(
                                child: Container(
                                  color: context.cardColor.withOpacity(0.4),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.animeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.episodeTitle,
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hace ${_timeAgo(item.timestamp)}',
                              style: TextStyle(fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert, color: context.textSecondary),
                        onPressed: () => _showHistoryOptions(context, item),
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

  void _showHistoryOptions(BuildContext context, HistoryItem item) {
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
                  builder: (context) => DetailScreen(
                    animeUrl: item.animeUrl,
                    animeTitle: item.animeTitle,
                    animeImage: item.animeImage,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppTheme.dangerColor),
            title: Text('Eliminar del historial', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              final provider = Provider.of<HistoryProvider>(context, listen: false);
              final uid = Provider.of<app_auth.AuthProvider>(context, listen: false).userId;
              provider.removeFromHistory(item.animeUrl, userId: uid);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTabButton(
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? context.primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? context.primaryColor : context.textSecondary.withOpacity(0.3),
            width: 1,
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

  Widget _buildFavoritesSection(
    BuildContext context,
    HistoryProvider historyProvider,
    app_auth.AuthProvider authProvider,
  ) {
    if (authProvider.isLoggedIn && authProvider.userId != null) {
      if (_libraryTabIndex == 0) {
        return StreamBuilder<List<FavoriteAnime>>(
          stream: FavoriteService.getFavorites(authProvider.userId!),
          builder: (context, snapshot) {
            final cloudFavs = snapshot.data ?? [];
            final items = cloudFavs.isNotEmpty
                ? cloudFavs
                    .map((f) => AnimeSearchResult(
                          title: f.title,
                          url: f.animeUrl,
                          image: f.image,
                          type: f.type,
                          score: f.score,
                          status: f.status,
                        ))
                    .toList()
                : historyProvider.favorites;
            return _buildLibraryContent(
              context,
              authProvider,
              items,
              isFavorites: true,
              isLoading: snapshot.connectionState == ConnectionState.waiting,
            );
          },
        );
      } else {
        return StreamBuilder<List<FavoriteAnime>>(
          stream: FollowService.getFollowing(authProvider.userId!),
          builder: (context, snapshot) {
            final following = snapshot.data ?? [];
            final items = following
                .map((f) => AnimeSearchResult(
                      title: f.title,
                      url: f.animeUrl,
                      image: f.image,
                      type: f.type,
                      score: f.score,
                      status: f.status,
                    ))
                .toList();
            return _buildLibraryContent(
              context,
              authProvider,
              items,
              isFavorites: false,
              isLoading: snapshot.connectionState == ConnectionState.waiting,
            );
          },
        );
      }
    }
    return _buildLibraryContent(context, authProvider, historyProvider.favorites, isFavorites: true);
  }

  Widget _buildLibraryContent(
    BuildContext context,
    app_auth.AuthProvider authProvider,
    List<AnimeSearchResult> items, {
    required bool isFavorites,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Row(
              children: [
                Text(
                  'Mi Biblioteca',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                if (authProvider.isLoggedIn && authProvider.userId != null) ...[
                  const Spacer(),
                  _buildLibraryTabButton(
                    context,
                    title: 'Favoritos',
                    isActive: _libraryTabIndex == 0,
                    onTap: () => setState(() => _libraryTabIndex = 0),
                  ),
                  const SizedBox(width: 8),
                  _buildLibraryTabButton(
                    context,
                    title: 'Siguiendo',
                    isActive: _libraryTabIndex == 1,
                    onTap: () => setState(() => _libraryTabIndex = 1),
                  ),
                ],
              ],
            ),
          ),
          if (isLoading && items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                ),
              ),
            )
          else if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    isFavorites ? Icons.bookmark_outline : Icons.notifications_none_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isFavorites ? 'Aún no tienes favoritos' : 'No sigues ningún anime',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFavorites
                        ? 'Busca animes y agrégalos a tu biblioteca para acceder rápido a ellos.'
                        : 'Sigue tus animes en emisión favoritos para enterarte de nuevos capítulos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
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
                final anime = items[index];
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(
                          animeUrl: anime.url,
                          animeTitle: anime.title,
                          animeImage: anime.image ?? '',
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
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 34,
                        child: Text(
                          anime.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: context.textPrimary),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _NotificationsBell extends StatelessWidget {
  final app_auth.AuthProvider authProvider;

  const _NotificationsBell({required this.authProvider});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unreadCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, size: 26),
          tooltip: 'Notificaciones',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ).then((_) {
              if (authProvider.isLoggedIn) {
                context.read<NotificationProvider>().refreshUnread();
              }
            });
          },
        ),
        if (authProvider.isLoggedIn && unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatIconButton extends StatelessWidget {
  final app_auth.AuthProvider authProvider;

  const _ChatIconButton({required this.authProvider});

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.watch<ChatProvider>().hasUnread;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, size: 26),
          tooltip: 'Chat Público',
          onPressed: () {
            if (authProvider.isLoggedIn) {
              // Marcar como leído al abrir
              context.read<ChatProvider>().markSeen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PublicChatScreen()),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Debes iniciar sesión para acceder al chat público'),
                  backgroundColor: context.dangerColor,
                ),
              );
            }
          },
        ),
        if (hasUnread)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfileIconButton extends StatelessWidget {
  final app_auth.AuthProvider authProvider;

  const _ProfileIconButton({required this.authProvider});

  @override
  Widget build(BuildContext context) {
    final photoUrl = authProvider.photoUrl;
    final isSupporter = context.watch<SupporterProvider>().isSupporter;

    void goToProfile() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileTabScreen()),
        );

    if (authProvider.isLoggedIn && photoUrl != null) {
      return Tooltip(
        message: 'Mi Perfil',
        child: GestureDetector(
          onTap: goToProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _AvatarWithFrame(photoUrl: photoUrl, isSupporter: isSupporter),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Iniciar sesión',
      onPressed: goToProfile,
      icon: const Icon(Icons.person_outline_rounded, size: 26),
    );
  }
}

class _AvatarWithFrame extends StatelessWidget {
  final String photoUrl;
  final bool isSupporter;

  const _AvatarWithFrame({required this.photoUrl, required this.isSupporter});

  @override
  Widget build(BuildContext context) {
    const double size     = 34.0;   // diámetro total del avatar
    const double ring     = 2.5;    // grosor del anillo
    const double gap      = 2.0;    // gap entre anillo y foto
    const double badgeD   = 16.0;   // diámetro del badge de corona
    final bg = Theme.of(context).scaffoldBackgroundColor;

    final photo = ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        width: size - (ring + gap) * 2,
        height: size - (ring + gap) * 2,
        fit: BoxFit.cover,
      ),
    );

    if (!isSupporter) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size + badgeD * 0.5, // espacio extra arriba para la corona
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Posiciona el círculo en la parte inferior ─────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Anillo degradado
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFEC80),
                          Color(0xFFFFD93D),
                          Color(0xFFFF9A3C),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD93D).withValues(alpha: 0.4),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                  // Gap entre anillo y foto
                  Container(
                    width: size - ring * 2,
                    height: size - ring * 2,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
                  ),
                  // Foto
                  photo,
                ],
              ),
            ),
          ),
          // ── Badge corona centrado arriba ──────────────────
          Positioned(
            top: 0,
            left: size / 2 - badgeD / 2,
            child: Container(
              width: badgeD,
              height: badgeD,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD93D),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD93D).withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: const Center(
                child: Text('👑', style: TextStyle(fontSize: 9, height: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
