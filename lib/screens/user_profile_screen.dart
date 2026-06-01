import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/user_service.dart';
import '../services/favorite_service.dart';
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
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isOwner = authProvider.userId == widget.userId;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(profileTitle(isOwner)),
        backgroundColor: AppTheme.darkBackground,
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
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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

                      if (!canViewFavorites) ...[
                        const SizedBox(height: 8),
                        // Sin favoritos para visitantes de perfil privado
                      ] else ...[
                        if (isOwner || isPublic) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Anime Favoritos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _FavoritesGrid(userId: widget.userId),
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

  String profileTitle(bool isOwner) => isOwner ? 'Mi Perfil' : 'Perfil de usuario';

  Widget _buildAvatar(UserProfile? profile) {
    final photoUrl = profile?.photoUrl ?? widget.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(photoUrl),
        backgroundColor: AppTheme.cardColor,
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
      child: const Column(
        children: [
          Icon(Icons.lock_outline, size: 52, color: AppTheme.dangerColor),
          SizedBox(height: 14),
          Text(
            'Perfil privado',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Este usuario ha configurado su perfil como privado.\n'
            'Su lista de animes favoritos no está disponible.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_off, color: Colors.amber, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tu perfil es privado. Solo tú puedes ver tus favoritos aquí; '
              'otros usuarios verán este perfil como privado.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
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
          const Icon(Icons.lock, size: 14, color: AppTheme.dangerColor),
          const SizedBox(width: 6),
          Text(
            isOwner ? 'Tu perfil es privado' : 'Perfil privado',
            style: const TextStyle(
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

  const _FavoritesGrid({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FavoriteAnime>>(
      stream: FavoriteService.getFavorites(userId),
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
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(Icons.bookmark_outline, size: 40, color: AppTheme.textSecondary),
                SizedBox(height: 10),
                Text('Sin favoritos aún', style: TextStyle(color: AppTheme.textSecondary)),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white,
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
