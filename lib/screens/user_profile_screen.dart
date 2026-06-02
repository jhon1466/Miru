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
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
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
                      Text(
                        profile?.displayName ?? widget.displayName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      if (isPrivate) ...[
                        const SizedBox(height: 10),
                        _PrivateProfileBadge(isOwner: isOwner),
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
                        const _OwnerPrivateNotice(),

                      if (canViewFavorites) ...[
                        _ProfileStatsSection(
                          userId: widget.userId,
                          isOwner: isOwner,
                        ),
                      ],

                      if (!canViewFavorites) ...[
                        const SizedBox(height: 8),
                        // Sin favoritos para visitantes de perfil privado
                      ] else ...[
                        if (isOwner || isPublic) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                _tabIndex == 0 ? 'Anime Favoritos' : 'Anime Siguiendo',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                              ),
                              const Spacer(),
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
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        _FavoritesGrid(
                          userId: widget.userId,
                          showFavorites: _tabIndex == 0,
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
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
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
class _OwnerPrivateNotice extends StatelessWidget {
  const _OwnerPrivateNotice();

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

class _PrivateProfileBadge extends StatelessWidget {
  final bool isOwner;

  const _PrivateProfileBadge({required this.isOwner});

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

class _FavoritesGrid extends StatelessWidget {
  final String userId;
  final bool showFavorites;

  const _FavoritesGrid({
    required this.userId,
    required this.showFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FavoriteAnime>>(
      stream: showFavorites
          ? FavoriteService.getFavorites(userId)
          : FollowService.getFollowing(userId),
      builder: (context, favsSnap) {
        if (favsSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
            ),
          );
        }

        final favs = favsSnap.data ?? [];
        if (favs.isEmpty) {
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
                  showFavorites ? Icons.bookmark_outline : Icons.notifications_none_outlined,
                  size: 40,
                  color: context.textSecondary,
                ),
                const SizedBox(height: 10),
                Text(
                  showFavorites ? 'Sin favoritos aún' : 'No sigue ningún anime aún',
                  style: TextStyle(color: context.textSecondary),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: favs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.62,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final fav = favs[index];
            return InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DetailScreen(
                    animeUrl: fav.animeUrl,
                    animeTitle: fav.title,
                    animeImage: fav.image,
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
                        imageUrl: fav.image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fav.title,
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
      },
    );
  }
}

class _ProfileStatsSection extends StatelessWidget {
  final String userId;
  final bool isOwner;

  const _ProfileStatsSection({
    required this.userId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
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

            // Calcular géneros
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cards Grid
                if (isOwner) ...[
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
                        label: 'Vistos',
                        value: '$episodesCount',
                        icon: Icons.play_circle_fill,
                        color: context.successColor,
                      ),
                      _buildStatCard(
                        context,
                        label: 'Tiempo',
                        value: timeSpentStr,
                        icon: Icons.access_time_filled,
                        color: Colors.amber,
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

                // Géneros más vistos
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
                    final ratio = entry.value / maxCount;
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
          },
        );
      },
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
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
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
