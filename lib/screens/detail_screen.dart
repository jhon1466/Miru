import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../services/favorite_service.dart';
import '../utils/image_utils.dart';
import '../widgets/anime_poster_image.dart';
import '../widgets/comments_section.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final String animeUrl;
  final String animeTitle;
  final String? animeImage;

  const DetailScreen({
    super.key,
    required this.animeUrl,
    required this.animeTitle,
    this.animeImage,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _reverseEpisodeOrder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimeProvider>().loadAnimeDetails(widget.animeUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);
    final historyProvider = Provider.of<HistoryProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isFav = historyProvider.isFavorite(widget.animeUrl);

    return Scaffold(
      body: _buildBody(animeProvider, historyProvider, authProvider, isFav),
    );
  }

  Widget _buildBody(AnimeProvider provider, HistoryProvider historyProvider, app_auth.AuthProvider authProvider, bool isFav) {
    if (provider.isLoadingDetails) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
            SizedBox(height: 16),
            Text('Obteniendo detalles del anime...', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (provider.detailsError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.animeTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppTheme.dangerColor),
                const SizedBox(height: 16),
                Text(
                  provider.detailsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadAnimeDetails(widget.animeUrl),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final details = provider.selectedAnime;
    if (details == null) {
      return const SizedBox.shrink();
    }

    final displayedEpisodes = _reverseEpisodeOrder 
        ? details.episodes.reversed.toList() 
        : details.episodes;

    final posterCandidates = collectPosterUrlCandidates(
      apiImage: details.image,
      apiBackdrop: details.backdrop,
      passedImage: widget.animeImage,
      animeUrl: widget.animeUrl,
      animeId: details.id,
    );
    final posterImage = posterCandidates.isNotEmpty ? posterCandidates.first : '';

    final bannerCandidates = collectBannerUrlCandidates(
      apiImage: details.image,
      apiBackdrop: details.backdrop,
      passedImage: widget.animeImage,
      animeUrl: widget.animeUrl,
      animeId: details.id,
      knownWorkingPosterUrl: posterImage.isNotEmpty ? posterImage : null,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimePosterImage(
                  urlCandidates: bannerCandidates,
                  fit: BoxFit.cover,
                ),
                // Degradado solo en la parte inferior para no tapar el banner
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 140,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.darkBackground.withValues(alpha: 0.85),
                          AppTheme.darkBackground,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverAppBar(
          pinned: true,
          backgroundColor: AppTheme.darkBackground,
          automaticallyImplyLeading: true,
          actions: [
            // Botón de favorito con Firestore
            authProvider.isLoggedIn
                ? StreamBuilder<bool>(
                    stream: FavoriteService.isFavoriteStream(
                      authProvider.userId!,
                      widget.animeUrl,
                    ),
                    builder: (context, snapshot) {
                      final isFavCloud = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isFavCloud ? Icons.favorite : Icons.favorite_border,
                          color: isFavCloud ? AppTheme.dangerColor : Colors.white,
                          size: 28,
                        ),
                        onPressed: () async {
                          final wasFav = isFavCloud;
                          await FavoriteService.toggleFavorite(
                            authProvider.userId!,
                            details,
                            widget.animeUrl,
                            fallbackImage: widget.animeImage,
                          );
                          if (wasFav == historyProvider.isFavorite(widget.animeUrl)) {
                            await historyProvider.toggleFavoriteWithUrl(details, widget.animeUrl);
                          }
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isFavCloud ? 'Eliminado de biblioteca' : 'Añadido a biblioteca'),
                              backgroundColor: isFavCloud ? AppTheme.dangerColor : AppTheme.successColor,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.favorite_border, color: AppTheme.textSecondary, size: 28),
                    tooltip: 'Inicia sesión para guardar favoritos',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Inicia sesión con Google para guardar favoritos'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
          ],
          title: Text(
            details.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Contenido del Anime
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila con Info Rápida (Poster + Metadatos)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster
                    AnimePosterImage(
                      urlCandidates: posterCandidates,
                      width: 110,
                      height: 160,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 16),
                    // Metadatos
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (details.titleJapanese != null) ...[
                            Text(
                              details.titleJapanese!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  details.type ?? 'Serie',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (details.year != null)
                                Text(
                                  details.year!,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (details.score != null)
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  details.score.toString(),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                if (details.votes != null)
                                  Text(
                                    ' (${details.votes!.toInt()} votos)',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Estado: ${details.status ?? 'Desconocido'}',
                            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          Text(
                            'Episodios: ${details.episodes.length}',
                            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          Text(
                            'Fuente: ${details.source ?? 'Desconocido'}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                // Géneros
                if (details.genres.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: details.genres.map((genre) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.textSecondary.withOpacity(0.15)),
                        ),
                        child: Text(
                          genre.name,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Sinopsis
                const Text(
                  'Sinopsis',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  details.description ?? 'Sin sinopsis disponible.',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                ),

                const SizedBox(height: 32),

                // Lista de Episodios Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Episodios (${details.episodes.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    // Botón para invertir orden
                    IconButton(
                      icon: Icon(
                        _reverseEpisodeOrder ? Icons.arrow_downward : Icons.arrow_upward,
                        color: AppTheme.primaryColor,
                      ),
                      tooltip: _reverseEpisodeOrder ? 'Mostrar del primero al último' : 'Mostrar del último al primero',
                      onPressed: () {
                        setState(() {
                          _reverseEpisodeOrder = !_reverseEpisodeOrder;
                        });
                      },
                    ),
                  ],
                ),
                const Divider(color: AppTheme.cardColor, height: 20),
              ],
            ),
          ),
        ),

        // Lista de Episodios (SliverList para rendimiento)
        displayedEpisodes.isEmpty
            ? const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Text('No hay episodios disponibles.', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                ),
              )
            : SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final episode = displayedEpisodes[index];
                      // Verificar si ya fue visto
                      final lastWatchedNum = historyProvider.getLastWatchedEpisode(widget.animeUrl);
                      final isWatched = lastWatchedNum != null && lastWatchedNum >= episode.number;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isWatched 
                                ? AppTheme.primaryColor.withOpacity(0.15) 
                                : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PlayerScreen(
                                  episodeUrl: episode.url,
                                  episodeNumber: episode.number,
                                  animeTitle: details.title,
                                  animeUrl: widget.animeUrl,
                                  animeImage: posterImage,
                                ),
                              ),
                            );
                          },
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isWatched 
                                  ? AppTheme.primaryColor.withOpacity(0.1) 
                                  : AppTheme.darkBackground,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isWatched ? Icons.check : Icons.play_arrow_rounded,
                              color: isWatched ? AppTheme.primaryColor : Colors.white,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            episode.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isWatched ? AppTheme.textSecondary : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            'Número: ${episode.number.toString().replaceAll('.0', '')}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                        ),
                      );
                    },
                    childCount: displayedEpisodes.length,
                  ),
                ),
              ),

        // Sección de Comentarios del Anime
        SliverToBoxAdapter(
          child: CommentsSection(
            animeSlug: Uri.parse(widget.animeUrl).pathSegments.lastWhere(
              (s) => s.isNotEmpty,
              orElse: () => widget.animeUrl.hashCode.toString(),
            ),
            animeTitle: widget.animeTitle,
          ),
        ),

        // Espaciador final
        const SliverToBoxAdapter(
          child: SizedBox(height: 50),
        ),
      ],
    );
  }
}
