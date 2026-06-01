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
      body: StreamBuilder<UserProfile?>(
        stream: UserService.profileStream(widget.userId),
        builder: (context, profileSnap) {
          final profile = profileSnap.data;
          final isPublic = profile?.isPublic ?? true;
          final canViewFavorites = isPublic || isOwner;

          return CustomScrollView(
            slivers: [
              // App Bar con avatar
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppTheme.darkBackground,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Fondo degradado
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.primaryColor.withOpacity(0.3),
                              AppTheme.darkBackground,
                            ],
                          ),
                        ),
                      ),
                      // Avatar centrado
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            _buildAvatar(profile),
                            const SizedBox(height: 12),
                            Text(
                              profile?.displayName ?? widget.displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (!isPublic) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lock, size: 12, color: AppTheme.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      isOwner ? 'Tu perfil es privado' : 'Perfil Privado',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Contenido
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!canViewFavorites) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.lock_outline, size: 48, color: AppTheme.textSecondary),
                              SizedBox(height: 12),
                              Text(
                                'Este perfil es privado',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Este usuario ha configurado su perfil como privado. Sus favoritos no son visibles.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Favoritos del usuario
                        const Text(
                          'Anime Favoritos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<FavoriteAnime>>(
                          stream: FavoriteService.getFavorites(widget.userId),
                          builder: (context, favsSnap) {
                            if (favsSnap.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32.0),
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
                                    Text(
                                      'Sin favoritos aún',
                                      style: TextStyle(color: AppTheme.textSecondary),
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

  Widget _buildAvatar(UserProfile? profile) {
    final photoUrl = profile?.photoUrl ?? widget.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundImage: NetworkImage(photoUrl),
        backgroundColor: AppTheme.cardColor,
      );
    }
    final initial = (profile?.displayName ?? widget.displayName).isNotEmpty
        ? (profile?.displayName ?? widget.displayName)[0].toUpperCase()
        : 'U';
    return CircleAvatar(
      radius: 40,
      backgroundColor: AppTheme.primaryColor.withOpacity(0.3),
      child: Text(
        initial,
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}
