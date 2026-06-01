import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../core/update_service.dart';
import '../widgets/update_dialog.dart';
import '../providers/anime_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../services/favorite_service.dart';
import '../widgets/anime_poster_image.dart';
import '../models/anime.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

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
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, size: 26),
                tooltip: 'Notificaciones',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Las notificaciones estarán disponibles pronto'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeBanner(context, authProvider),

            // Selector de Proveedores
            _buildProviderSelector(context, animeProvider),

            // Animes Destacados / Populares
            _buildPopularSection(context, animeProvider),

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
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Text(
            'Encuentra tus animes favoritos hoy.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(BuildContext context, AnimeProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Text(
            'Proveedor Activo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: provider.providers.length,
            itemBuilder: (context, index) {
              final prov = provider.providers[index];
              final isSelected = provider.selectedProviderDomain == prov['domain'];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text(prov['name'] ?? ''),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                  disabledColor: Colors.transparent,
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : AppTheme.cardColor,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: AppTheme.cardColor,
                  onSelected: (selected) {
                    if (selected) {
                      provider.selectProvider(prov['domain'] ?? '');
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPopularSection(BuildContext context, AnimeProvider provider) {
    if (provider.isLoadingPopular) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 12.0),
            child: Text(
              'Destacados de la Semana',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          SizedBox(
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
        const Padding(
          padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 12.0),
          child: Text(
            'Destacados de la Semana',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                                placeholder: (context, url) => Container(color: AppTheme.cardColor),
                                errorWidget: (context, url, error) => Container(
                                  color: AppTheme.cardColor,
                                  child: const Icon(Icons.movie, color: AppTheme.textSecondary),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
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
        const Padding(
          padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 24.0, bottom: 4.0),
          child: Text(
            'Continuar Viendo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 20.0, right: 20.0, bottom: 12.0),
          child: Text(
            'Mantén pulsado un anime para quitarlo de la lista',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return Container(
                width: 280,
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
                          animeImage: item.animeImage,
                        ),
                      ),
                    );
                  },
                  onLongPress: () => _confirmRemoveHistory(context, historyProvider, item),
                  borderRadius: BorderRadius.circular(16),
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Imagen de Fondo (Poster difuminado u opaco)
                        Positioned.fill(
                          child: item.animeImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: item.animeImage,
                                  fit: BoxFit.cover,
                                  color: Colors.black.withOpacity(0.6),
                                  colorBlendMode: BlendMode.srcOver,
                                  placeholder: (context, url) => Container(color: AppTheme.cardColor),
                                  errorWidget: (context, url, error) => Container(
                                    color: AppTheme.cardColor,
                                    child: const Center(
                                      child: Icon(Icons.movie, color: AppTheme.textSecondary, size: 40),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: AppTheme.cardColor,
                                  child: const Center(
                                    child: Icon(Icons.movie, color: AppTheme.textSecondary, size: 40),
                                  ),
                                ),
                        ),
                        // Detalles del episodio
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.animeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Episodio ${item.episodeNumber.toString().replaceAll('.0', '')} - ${item.episodeTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        // Botón flotante Play en el centro-derecha
                        const Positioned(
                          right: 16,
                          top: 16,
                          child: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor,
                            radius: 18,
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
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

  void _confirmRemoveHistory(BuildContext context, HistoryProvider provider, HistoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Quitar del historial', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar "${item.animeTitle}" de Continuar viendo?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.removeFromHistory(item.animeUrl);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"${item.animeTitle}" eliminado del historial'),
                  backgroundColor: AppTheme.successColor,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.dangerColor)),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text(
              'Mi Biblioteca',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.bookmark_outline, size: 40, color: AppTheme.primaryColor),
                  SizedBox(height: 12),
                  Text(
                    'Aún no tienes favoritos',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Busca animes y agrégalos a tu biblioteca para acceder rápido a ellos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
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
}
