import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../services/user_service.dart';
import '../services/favorite_service.dart';
import '../services/follow_service.dart';
import '../widgets/anime_poster_image.dart';
import 'detail_screen.dart';
import '../services/manga_favorite_service.dart';
import '../services/manga_follow_service.dart';
import '../services/novel_favorite_service.dart';
import '../services/novel_follow_service.dart';
import '../providers/manga_history_provider.dart';
import '../providers/novel_history_provider.dart';
import '../models/manga_history_item.dart';
import '../models/novel_history_item.dart';
import '../models/novel.dart';
import 'manga_detail_screen.dart';
import 'novel_detail_screen.dart';
import '../services/completed_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String displayName;
  final String? photoUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.displayName,
    this.photoUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  int _tabIndex = 0; // 0: Favorites, 1: Following
  String _mediaType = 'anime'; // 'anime' | 'manga' | 'novel'

  String _getSectionTitle() {
    final typeName = _mediaType == 'anime'
        ? 'Anime'
        : _mediaType == 'manga'
            ? 'Manga'
            : 'Novela';
    final actionName = _tabIndex == 0
        ? 'Favoritos'
        : _tabIndex == 1
            ? 'Siguiendo'
            : 'Terminados';
    return '$typeName $actionName';
  }

  Widget _buildMediaChip(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? context.primaryColor : context.textSecondary.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: context.primaryColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : context.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isOwner = authProvider.userId == widget.userId;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: Text(profileTitle(isOwner)),
        backgroundColor: context.backgroundColor,
      ),
      body: StreamBuilder<UserProfile?>(
        stream: UserService.profileStream(widget.userId),
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
              ),
            );
          }

          final profile = profileSnap.data;
          // Perfil sin documento = público por compatibilidad; si existe, respetar isPublic
          final isPublic = profile?.isPublic ?? true;
          final isPrivate = !isPublic;
          final canViewFavorites = isOwner || isPublic;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    children: [
                      _buildAvatar(profile),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (profile?.isSupporter == true) ...[
                            const Text('👑', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            profile?.displayName ?? widget.displayName,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (profile?.isSupporter == true) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.supporterColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.supporterColor.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite_rounded, color: context.supporterColor, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'Supporter',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: context.supporterColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isPrivate) ...[
                        const SizedBox(height: 10),
                        PrivateProfileBadge(isOwner: isOwner),
                      ],
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isPrivate && !isOwner)
                        const _PrivateProfileWarning()
                      else if (isPrivate && isOwner)
                        const OwnerPrivateNotice(),

                      if (canViewFavorites) ...[
                        ProfileStatsSection(
                          userId: widget.userId,
                          isOwner: isOwner,
                          mediaType: _mediaType,
                        ),
                      ],

                      if (!canViewFavorites) ...[
                        const SizedBox(height: 8),
                        // Sin favoritos para visitantes de perfil privado
                      ] else ...[
                        if (isOwner || isPublic) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildMediaChip(
                                context,
                                title: 'Anime',
                                icon: Icons.movie_creation_rounded,
                                isActive: _mediaType == 'anime',
                                onTap: () => setState(() => _mediaType = 'anime'),
                              ),
                              const SizedBox(width: 8),
                              _buildMediaChip(
                                context,
                                title: 'Manga',
                                icon: Icons.book_rounded,
                                isActive: _mediaType == 'manga',
                                onTap: () => setState(() => _mediaType = 'manga'),
                              ),
                              const SizedBox(width: 8),
                              _buildMediaChip(
                                context,
                                title: 'Novelas',
                                icon: Icons.auto_stories_rounded,
                                isActive: _mediaType == 'novel',
                                onTap: () => setState(() => _mediaType = 'novel'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                           Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getSectionTitle(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildTabButton(
                                    context,
                                    title: 'Favoritos',
                                    isActive: _tabIndex == 0,
                                    onTap: () => setState(() => _tabIndex = 0),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTabButton(
                                    context,
                                    title: 'Siguiendo',
                                    isActive: _tabIndex == 1,
                                    onTap: () => setState(() => _tabIndex = 1),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTabButton(
                                    context,
                                    title: 'Vistos',
                                    isActive: _tabIndex == 2,
                                    onTap: () => setState(() => _tabIndex = 2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        FavoritesGrid(
                          userId: widget.userId,
                          tabIndex: _tabIndex,
                          mediaType: _mediaType,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
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

  String profileTitle(bool isOwner) => isOwner ? 'Mi Perfil' : 'Perfil de usuario';

  Widget _buildAvatar(UserProfile? profile) {
    final photoUrl = profile?.photoUrl ?? widget.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(photoUrl),
        backgroundColor: context.cardColor,
      );
    }
    final initial = (profile?.displayName ?? widget.displayName).isNotEmpty
        ? (profile?.displayName ?? widget.displayName)[0].toUpperCase()
        : 'U';
    return CircleAvatar(
      radius: 48,
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      child: Text(
        initial,
        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

/// Aviso para visitantes: perfil privado, sin acceso a favoritos.
class _PrivateProfileWarning extends StatelessWidget {
  const _PrivateProfileWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.dangerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 52, color: AppTheme.dangerColor),
          const SizedBox(height: 14),
          Text(
            'Perfil privado',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este usuario ha configurado su perfil como privado.\n'
            'Su lista de animes favoritos no está disponible.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso para el dueño cuando su perfil es privado.
class OwnerPrivateNotice extends StatelessWidget {
  const OwnerPrivateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_off, color: Colors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tu perfil es privado. Solo tú puedes ver tus favoritos aquí; '
              'otros usuarios verán este perfil como privado.',
              style: TextStyle(fontSize: 13, color: context.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivateProfileBadge extends StatelessWidget {
  final bool isOwner;

  const PrivateProfileBadge({super.key, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.dangerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 14, color: AppTheme.dangerColor),
          const SizedBox(width: 6),
          Text(
            isOwner ? 'Tu perfil es privado' : 'Perfil privado',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.dangerColor,
            ),
          ),
        ],
      ),
    );
  }
}

class UnifiedFavorite {
  final String id;
  final String title;
  final String? coverUrl;
  final VoidCallback onTap;

  UnifiedFavorite({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.onTap,
  });
}

class FavoritesGrid extends StatelessWidget {
  final String userId;
  final int tabIndex;
  final String mediaType;

  const FavoritesGrid({
    super.key,
    required this.userId,
    required this.tabIndex,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    if (tabIndex == 2) {
      return StreamBuilder<List<CompletedMedia>>(
        stream: CompletedService.getCompleted(userId, mediaType),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return _buildLoading(context);
          final items = snap.data ?? [];
          if (items.isEmpty) return _buildEmptyState(context);

          final unified = items.map((fav) => UnifiedFavorite(
            id: fav.mediaId,
            title: fav.title,
            coverUrl: fav.image,
            onTap: () {
              if (mediaType == 'anime') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(
                      animeUrl: fav.mediaId,
                      animeTitle: fav.title,
                      animeImage: fav.image,
                    ),
                  ),
                );
              } else if (mediaType == 'manga') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MangaDetailScreen(mangaId: fav.mediaId),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NovelDetailScreen(
                      novel: Novel(
                        id: fav.mediaId,
                        title: fav.title,
                        url: fav.mediaId,
                        coverUrl: fav.image,
                        status: fav.status,
                        author: fav.author,
                      ),
                    ),
                  ),
                );
              }
            },
          )).toList();

          return _buildGrid(context, unified);
        },
      );
    }

    final showFavorites = tabIndex == 0;
    if (mediaType == 'anime') {
      return StreamBuilder<List<FavoriteAnime>>(
        stream: showFavorites
            ? FavoriteService.getFavorites(userId)
            : FollowService.getFollowing(userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return _buildLoading(context);
          final items = snap.data ?? [];
          if (items.isEmpty) return _buildEmptyState(context);

          final unified = items.map((fav) => UnifiedFavorite(
            id: fav.animeUrl,
            title: fav.title,
            coverUrl: fav.image,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailScreen(
                  animeUrl: fav.animeUrl,
                  animeTitle: fav.title,
                  animeImage: fav.image,
                ),
              ),
            ),
          )).toList();

          return _buildGrid(context, unified);
        },
      );
    } else if (mediaType == 'manga') {
      return StreamBuilder<List<FavoriteManga>>(
        stream: showFavorites
            ? MangaFavoriteService.getFavorites(userId)
            : MangaFollowService.getFollowing(userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return _buildLoading(context);
          final items = snap.data ?? [];
          if (items.isEmpty) return _buildEmptyState(context);

          final unified = items.map((fav) => UnifiedFavorite(
            id: fav.mangaId,
            title: fav.title,
            coverUrl: fav.coverUrl,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MangaDetailScreen(mangaId: fav.mangaId),
              ),
            ),
          )).toList();

          return _buildGrid(context, unified);
        },
      );
    } else {
      return StreamBuilder<List<FavoriteNovel>>(
        stream: showFavorites
            ? NovelFavoriteService.getFavorites(userId)
            : NovelFollowService.getFollowing(userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return _buildLoading(context);
          final items = snap.data ?? [];
          if (items.isEmpty) return _buildEmptyState(context);

          final unified = items.map((fav) => UnifiedFavorite(
            id: fav.novelId,
            title: fav.title,
            coverUrl: fav.coverUrl,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NovelDetailScreen(
                  novel: Novel(
                    id: fav.novelId,
                    title: fav.title,
                    url: fav.novelId,
                    coverUrl: fav.coverUrl,
                    status: fav.status,
                    author: fav.author,
                  ),
                ),
              ),
            ),
          )).toList();

          return _buildGrid(context, unified);
        },
      );
    }
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    String message;
    IconData icon;
    if (tabIndex == 2) {
      message = 'Ninguno terminado aún';
      icon = Icons.check_circle_outline;
    } else if (mediaType == 'anime') {
      message = tabIndex == 0 ? 'Sin favoritos aún' : 'No sigue ningún anime aún';
      icon = tabIndex == 0 ? Icons.bookmark_outline : Icons.notifications_none_outlined;
    } else if (mediaType == 'manga') {
      message = tabIndex == 0 ? 'Sin favoritos aún' : 'No sigue ningún manga aún';
      icon = tabIndex == 0 ? Icons.bookmark_outline : Icons.notifications_none_outlined;
    } else {
      message = tabIndex == 0 ? 'Sin favoritos aún' : 'No sigue ninguna novela aún';
      icon = tabIndex == 0 ? Icons.bookmark_outline : Icons.notifications_none_outlined;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: context.textSecondary,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<UnifiedFavorite> items) {
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
        final item = items[index];
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AnimePosterImage(
                    imageUrl: item.coverUrl,
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
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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

class ProfileStatsSection extends StatelessWidget {
  final String userId;
  final bool isOwner;
  final String mediaType;

  const ProfileStatsSection({
    super.key,
    required this.userId,
    required this.isOwner,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaType == 'anime') {
      final historyProvider = Provider.of<HistoryProvider>(context);
      return StreamBuilder<List<FavoriteAnime>>(
        stream: FavoriteService.getFavorites(userId),
        builder: (context, favSnap) {
          return StreamBuilder<List<FavoriteAnime>>(
            stream: FollowService.getFollowing(userId),
            builder: (context, followSnap) {
              final favs = favSnap.data ?? [];
              final following = followSnap.data ?? [];

              final favsCount = favs.length;
              final followingCount = following.length;
              final episodesCount = isOwner ? historyProvider.recentEpisodes.length : 0;
              final timeSpentMin = episodesCount * 23;
              final timeSpentStr = timeSpentMin >= 60
                  ? '${(timeSpentMin / 60).floor()}h ${timeSpentMin % 60}m'
                  : '${timeSpentMin}m';

              final genreCounts = <String, int>{};
              for (final fav in favs) {
                for (final genre in fav.genres) {
                  genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
                }
              }
              final sortedGenres = genreCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final topGenres = sortedGenres.take(4).toList();
              final maxCount = sortedGenres.isNotEmpty ? sortedGenres.first.value : 1;

              return _buildStatsLayout(
                context,
                favsCount: favsCount,
                followingCount: followingCount,
                thirdLabel: 'Vistos',
                thirdValue: '$episodesCount',
                thirdIcon: Icons.play_circle_fill,
                thirdColor: context.successColor,
                fourthLabel: 'Tiempo',
                fourthValue: timeSpentStr,
                fourthIcon: Icons.access_time_filled,
                fourthColor: Colors.amber,
                topGenres: topGenres,
                maxGenreCount: maxCount,
              );
            },
          );
        },
      );
    } else if (mediaType == 'manga') {
      final historyProvider = Provider.of<MangaHistoryProvider>(context);
      return StreamBuilder<List<FavoriteManga>>(
        stream: MangaFavoriteService.getFavorites(userId),
        builder: (context, favSnap) {
          return StreamBuilder<List<FavoriteManga>>(
            stream: MangaFollowService.getFollowing(userId),
            builder: (context, followSnap) {
              final favs = favSnap.data ?? [];
              final following = followSnap.data ?? [];

              final favsCount = favs.length;
              final followingCount = following.length;
              final chaptersCount = isOwner ? historyProvider.history.length : 0;

              return _buildStatsLayout(
                context,
                favsCount: favsCount,
                followingCount: followingCount,
                thirdLabel: 'Manga Leídos',
                thirdValue: '$chaptersCount',
                thirdIcon: Icons.menu_book,
                thirdColor: context.successColor,
                fourthLabel: 'Páginas/Dato',
                fourthValue: isOwner ? '${_getTotalMangaPages(historyProvider.history)} pág' : null,
                fourthIcon: Icons.find_in_page_outlined,
                fourthColor: Colors.amber,
                topGenres: [],
                maxGenreCount: 1,
              );
            },
          );
        },
      );
    } else {
      final historyProvider = Provider.of<NovelHistoryProvider>(context);
      return StreamBuilder<List<FavoriteNovel>>(
        stream: NovelFavoriteService.getFavorites(userId),
        builder: (context, favSnap) {
          return StreamBuilder<List<FavoriteNovel>>(
            stream: NovelFollowService.getFollowing(userId),
            builder: (context, followSnap) {
              final favs = favSnap.data ?? [];
              final following = followSnap.data ?? [];

              final favsCount = favs.length;
              final followingCount = following.length;
              final chaptersCount = isOwner ? historyProvider.history.length : 0;

              return _buildStatsLayout(
                context,
                favsCount: favsCount,
                followingCount: followingCount,
                thirdLabel: 'Novelas Leídas',
                thirdValue: '$chaptersCount',
                thirdIcon: Icons.chrome_reader_mode,
                thirdColor: context.successColor,
                fourthLabel: 'Capítulos',
                fourthValue: isOwner ? '${_getTotalNovelChapters(historyProvider.history)} cap' : null,
                fourthIcon: Icons.bookmark_added_outlined,
                fourthColor: Colors.amber,
                topGenres: [],
                maxGenreCount: 1,
              );
            },
          );
        },
      );
    }
  }

  int _getTotalMangaPages(List<MangaHistoryItem> history) {
    int total = 0;
    for (final item in history) {
      total += item.page;
    }
    return total;
  }

  int _getTotalNovelChapters(List<NovelHistoryItem> history) {
    return history.length;
  }

  Widget _buildStatsLayout(
    BuildContext context, {
    required int favsCount,
    required int followingCount,
    String? thirdLabel,
    String? thirdValue,
    IconData? thirdIcon,
    Color? thirdColor,
    String? fourthLabel,
    String? fourthValue,
    IconData? fourthIcon,
    Color? fourthColor,
    required List<MapEntry<String, int>> topGenres,
    required int maxGenreCount,
  }) {
    final showThirdAndFourth = isOwner && thirdLabel != null && thirdValue != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showThirdAndFourth) ...[
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.7,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            children: [
              _buildStatCard(
                context,
                label: 'Favoritos',
                value: '$favsCount',
                icon: Icons.bookmark,
                color: context.primaryColor,
              ),
              _buildStatCard(
                context,
                label: 'Siguiendo',
                value: '$followingCount',
                icon: Icons.notifications,
                color: context.accentColor,
              ),
              _buildStatCard(
                context,
                label: thirdLabel,
                value: thirdValue,
                icon: thirdIcon!,
                color: thirdColor!,
              ),
              if (fourthLabel != null && fourthValue != null)
                _buildStatCard(
                  context,
                  label: fourthLabel,
                  value: fourthValue,
                  icon: fourthIcon!,
                  color: fourthColor!,
                ),
            ],
          ),
        ] else ...[
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.7,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            children: [
              _buildStatCard(
                context,
                label: 'Favoritos',
                value: '$favsCount',
                icon: Icons.bookmark,
                color: context.primaryColor,
              ),
              _buildStatCard(
                context,
                label: 'Siguiendo',
                value: '$followingCount',
                icon: Icons.notifications,
                color: context.accentColor,
              ),
            ],
          ),
        ],

        if (topGenres.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Géneros Preferidos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...topGenres.map((entry) {
            final ratio = entry.value / maxGenreCount;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        '${entry.value} ${entry.value == 1 ? 'anime' : 'animes'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: context.cardColor,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ratio > 0.7 ? context.primaryColor : context.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
