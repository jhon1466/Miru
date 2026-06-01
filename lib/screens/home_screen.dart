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
import '../widgets/anime_poster_image.dart';
import '../models/anime.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
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
          const SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
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
                                fit: BoxFit.contain,
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
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary),
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
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
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
                onPressed: () => provider.loadLatestPublishedEpisodes(),
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
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final item = episodes[index];
              return Container(
                width: 130,
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
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimePosterImage(
                                imageUrl: item.image,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
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
                      Text(
                        item.animeTitle,
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

  Widget _buildFavoritesSection(
    BuildContext context,
    HistoryProvider historyProvider,
    app_auth.AuthProvider authProvider,
  ) {
    if (authProvider.isLoggedIn && authProvider.userId != null) {
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
          return _buildFavoritesContent(context, items, isLoading: snapshot.connectionState == ConnectionState.waiting);
        },
      );
    }
    return _buildFavoritesContent(context, historyProvider.favorites);
  }

  Widget _buildFavoritesContent(
    BuildContext context,
    List<AnimeSearchResult> favorites, {
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Text(
              'Mi Biblioteca',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
          ),
          if (isLoading && favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                ),
              ),
            )
          else if (favorites.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.bookmark_outline, size: 40, color: AppTheme.primaryColor),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no tienes favoritos',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Busca animes y agrégalos a tu biblioteca para acceder rápido a ellos.',
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
              itemCount: favorites.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.62,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final anime = favorites[index];
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
                                fit: BoxFit.contain,
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
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: context.textPrimary),
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
              decoration: const BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.all(Radius.circular(10)),
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
