import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../services/favorite_service.dart';
import '../widgets/anime_poster_image.dart';
import '../widgets/comments_section.dart';
import '../widgets/episode_download_button.dart';
import '../models/anime.dart';
import '../utils/image_utils.dart';
import '../services/follow_service.dart';
import '../widgets/media_rating_section.dart';
import '../services/completed_service.dart';
import '../providers/supporter_provider.dart';
import '../providers/download_provider.dart';
import 'player_screen.dart';
import 'downloads_screen.dart';

class DetailScreen extends StatefulWidget {
  final String animeUrl;
  final String animeTitle;
  final String? animeImage;
  final String? focusCommentId;
  final double? initialEpisodeNumber;

  const DetailScreen({
    super.key,
    required this.animeUrl,
    required this.animeTitle,
    this.animeImage,
    this.focusCommentId,
    this.initialEpisodeNumber,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final GlobalKey _commentsKey = GlobalKey();
  bool _reverseEpisodeOrder = false;
  final TextEditingController _episodeSearchController = TextEditingController();
  String _episodeSearchQuery = '';
  // Posición vertical del banner: -1.0 = arriba, 0.0 = centro, 1.0 = abajo
  double _bannerAlignY = 0.0;
  bool _adjustingBanner = false;

  @override
  void dispose() {
    _episodeSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimeProvider>().loadAnimeDetails(widget.animeUrl);
      if (widget.focusCommentId != null) {
        _scrollToComments();
      }
    });
  }

  void _showSupporterRequired(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Text('👑', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga en lote exclusivo para supporters de Patreon',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showBatchDownloadDialog(BuildContext context, AnimeDetails details) {
    final episodes = details.episodes;
    if (episodes.isEmpty) return;

    final preferSub = true;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              const Text('👑 ', style: TextStyle(fontSize: 20)),
              Expanded(
                child: Text(
                  'Descarga en lote',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Se intentará descargar los ${episodes.length} episodios de "${details.title}".\n\n'
            'Las descargas se añadirán a la cola una a una. ¿Continuar?',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: Text('Descargar ${episodes.length} eps'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _startBatchDownload(context, details, preferSub);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _startBatchDownload(
    BuildContext context,
    AnimeDetails details,
    bool preferSub,
  ) async {
    final downloads = context.read<DownloadProvider>();
    final total = details.episodes.length;

    // Feedback inmediato al usuario
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Añadiendo $total episodios a la cola…',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
        ),
      );
    }

    int queued = 0;
    for (final ep in details.episodes) {
      if (!context.mounted) break;
      await downloads.startEpisodeDownload(
        episodeUrl: ep.url,
        episodeNumber: ep.number,
        animeTitle: details.title,
        animeUrl: widget.animeUrl,
        animeImage: widget.animeImage ?? '',
        preferSub: preferSub,
      );
      queued++;
    }

    if (context.mounted && queued > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$queued/${total} episodios en descarga',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _scrollToComments() {
    Future.delayed(const Duration(milliseconds: 600), () {
      final keyContext = _commentsKey.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);
    final historyProvider = Provider.of<HistoryProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    final details = animeProvider.selectedAnime;

    if (animeProvider.isLoadingDetails) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.animeTitle),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.primaryColor)),
              const SizedBox(height: 16),
              Text('Obteniendo detalles del anime...', style: TextStyle(color: context.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (animeProvider.detailsError != null || details == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.animeTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: context.dangerColor),
                const SizedBox(height: 16),
                Text(
                  animeProvider.detailsError ?? 'Error desconocido al cargar detalles',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => animeProvider.loadAnimeDetails(widget.animeUrl),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Listado de episodios ordenados y filtrados
    final List<Episode> displayedEpisodes;
    if (_episodeSearchQuery.trim().isNotEmpty) {
      final query = _episodeSearchQuery.toLowerCase().trim();
      displayedEpisodes = details.episodes.where((ep) {
        final numberStr = ep.number.toString().replaceAll('.0', '');
        return ep.title.toLowerCase().contains(query) ||
            numberStr.contains(query);
      }).toList();
    } else {
      displayedEpisodes = List<Episode>.from(details.episodes);
    }

    if (_reverseEpisodeOrder) {
      displayedEpisodes.sort((a, b) => a.number.compareTo(b.number));
    } else {
      displayedEpisodes.sort((a, b) => b.number.compareTo(a.number));
    }

    final posterImage = details.image ?? widget.animeImage ?? '';
    final posterCandidates = posterImage.isNotEmpty ? [posterImage] : <String>[];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Banner de Fondo con Efecto Blur y Botón de Retroceso
          SliverAppBar(
            expandedHeight: 220,
            pinned: false,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Imagen de fondo con posición ajustable (drag solo en modo ajuste)
                  if (posterImage.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: _adjustingBanner ? (d) {
                        setState(() {
                          _bannerAlignY = (_bannerAlignY + d.delta.dy / 110).clamp(-1.0, 1.0);
                        });
                      } : null,
                      child: AnimePosterImage(
                        urlCandidates: posterCandidates,
                        fit: BoxFit.cover,
                        alignment: Alignment(0, _bannerAlignY),
                      ),
                    )
                  else
                    Container(color: context.backgroundColor),
                  // Gradiente oscuro sobre la portada
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              context.backgroundColor.withValues(alpha: 0.85),
                              context.backgroundColor,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Borde de selección al ajustar
                  if (_adjustingBanner)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Hint de arrastre centrado
                  if (_adjustingBanner)
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_vert_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text('Arrastra para reposicionar', style: TextStyle(color: Colors.white, fontSize: 12)),
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
            backgroundColor: context.backgroundColor,
            actions: [
              // Botón ajustar posición del banner
              if (posterImage.isNotEmpty)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  decoration: BoxDecoration(
                    color: _adjustingBanner
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _adjustingBanner = !_adjustingBanner),
                    icon: Icon(
                      _adjustingBanner ? Icons.check_rounded : Icons.crop_free_rounded,
                      size: 16,
                      color: _adjustingBanner
                          ? Theme.of(context).colorScheme.primary
                          : context.textSecondary,
                    ),
                    label: Text(
                      _adjustingBanner ? 'Listo' : 'Ajustar',
                      style: TextStyle(
                        fontSize: 12,
                        color: _adjustingBanner
                            ? Theme.of(context).colorScheme.primary
                            : context.textSecondary,
                      ),
                    ),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.share, color: context.textPrimary, size: 26),
                tooltip: 'Compartir',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Mira ${widget.animeTitle} en la app: ${widget.animeUrl}',
                    ),
                  );
                },
              ),
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
                            color: isFavCloud ? context.dangerColor : context.textPrimary,
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
                                backgroundColor: isFavCloud ? context.dangerColor : context.successColor,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : IconButton(
                      icon: Icon(Icons.favorite_border, color: context.textSecondary, size: 28),
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
              style: TextStyle(color: context.textPrimary),
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
                                style: TextStyle(fontSize: 13, color: context.textSecondary, fontStyle: FontStyle.italic),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.primaryColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    details.type ?? 'Serie',
                                    style: TextStyle(fontSize: 11, color: context.primaryColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (details.year != null)
                                  Text(
                                    details.year!,
                                    style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
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
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary),
                                  ),
                                  if (details.votes != null)
                                    Text(
                                      ' (${details.votes!.toInt()} votos)',
                                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Estado: ${details.status ?? 'Desconocido'}',
                              style: TextStyle(fontSize: 13, color: context.textSecondary),
                            ),
                            Text(
                              'Episodios: ${details.episodes.length}',
                              style: TextStyle(fontSize: 13, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (details.status?.toLowerCase().contains('emisi') == true) ...[
                    const SizedBox(height: 16),
                    authProvider.isLoggedIn
                        ? StreamBuilder<bool>(
                            stream: FollowService.isFollowingStream(
                              authProvider.userId!,
                              widget.animeUrl,
                            ),
                            builder: (context, snapshot) {
                              final isFollowing = snapshot.data ?? false;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        await FollowService.toggleFollow(
                                          authProvider.userId!,
                                          details,
                                          widget.animeUrl,
                                          fallbackImage: widget.animeImage,
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).clearSnackBars();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(isFollowing ? 'Dejaste de seguir este anime' : 'Ahora sigues este anime'),
                                            backgroundColor: isFollowing ? context.dangerColor : context.successColor,
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      child: Ink(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                        decoration: BoxDecoration(
                                          color: isFollowing 
                                              ? context.cardColor 
                                              : context.primaryColor,
                                          borderRadius: BorderRadius.circular(12),
                                          border: isFollowing 
                                              ? Border.all(color: context.primaryColor.withValues(alpha: 0.5)) 
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              isFollowing ? Icons.notifications_active : Icons.notifications_none,
                                              color: isFollowing ? context.primaryColor : Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              isFollowing ? 'Siguiendo' : 'Seguir Anime',
                                              style: TextStyle(
                                                color: isFollowing ? context.primaryColor : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline, size: 14, color: context.textSecondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Al seguir este anime, recibirás una notificación al estrenarse un nuevo capítulo en la aplicación.',
                                          style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.primaryColor.withValues(alpha: 0.5),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Inicia sesión con Google para seguir este anime y recibir notificaciones'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 20),
                                label: const Text('Seguir Anime', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: context.textSecondary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Al seguir este anime, recibirás una notificación al estrenarse un nuevo capítulo en la aplicación.',
                                      style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 12),
                  authProvider.isLoggedIn
                      ? StreamBuilder<bool>(
                          stream: CompletedService.isCompletedStream(
                            authProvider.userId!,
                            widget.animeUrl,
                          ),
                          builder: (context, snapshot) {
                            final isCompleted = snapshot.data ?? false;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await CompletedService.toggleCompleted(
                                    userId: authProvider.userId!,
                                    mediaId: widget.animeUrl,
                                    mediaType: 'anime',
                                    title: details.title,
                                    image: details.image ?? widget.animeImage,
                                    type: details.type,
                                    status: details.status,
                                    genres: details.genres.map((g) => g.name).toList(),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(isCompleted ? 'Eliminado de terminados' : 'Marcado como terminado'),
                                      backgroundColor: isCompleted ? context.dangerColor : context.successColor,
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isCompleted ? context.successColor : context.cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isCompleted
                                        ? null
                                        : Border.all(color: context.textSecondary.withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isCompleted ? Icons.check_circle : Icons.check_circle_outline,
                                        color: isCompleted ? Colors.white : context.textSecondary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isCompleted ? 'Terminado / Visto' : 'Marcar como Terminado',
                                        style: TextStyle(
                                          color: isCompleted ? Colors.white : context.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.textSecondary.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Inicia sesión con Google para marcar como terminado'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: Icon(Icons.check_circle_outline, color: context.textSecondary),
                          label: Text('Marcar como Terminado', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                        ),
                  const SizedBox(height: 16),

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
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.textSecondary.withOpacity(0.15)),
                          ),
                          child: Text(
                            genre.name,
                            style: TextStyle(fontSize: 12, color: context.textPrimary),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Sinopsis
                  Text(
                    'Sinopsis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.description ?? 'Sin sinopsis disponible.',
                    style: TextStyle(fontSize: 14, color: context.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  MediaRatingSection(
                    mediaId: widget.animeUrl,
                    mediaType: 'anime',
                    title: details.title,
                    image: details.image ?? widget.animeImage,
                  ),

                  if (details.relations.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Animes Relacionados',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 175,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: details.relations.length,
                        itemBuilder: (context, index) {
                          final relation = details.relations[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DetailScreen(
                                    animeUrl: relation.url,
                                    animeTitle: relation.title,
                                    animeImage: relation.image,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 105,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        AnimePosterImage(
                                          imageUrl: relation.image,
                                          urlCandidates: collectRelationPosterCandidates(
                                            apiImage: relation.image,
                                            animeUrl: relation.url,
                                          ),
                                          fit: BoxFit.cover,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        if (relation.relation != null && relation.relation!.isNotEmpty)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: context.primaryColor.withOpacity(0.9),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                relation.relation!,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
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
                                    relation.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
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

                  const SizedBox(height: 32),

                  // Lista de Episodios Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Episodios (${details.episodes.length})',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      Row(
                        children: [
                          // Botón descarga en lote (supporter)
                          Consumer<SupporterProvider>(
                            builder: (context, supporter, _) {
                              return IconButton(
                                icon: Icon(
                                  Icons.download_for_offline_rounded,
                                  color: supporter.isSupporter
                                      ? context.primaryColor
                                      : context.textSecondary.withOpacity(0.5),
                                ),
                                tooltip: supporter.isSupporter
                                    ? 'Descargar todos los episodios (Supporter)'
                                    : 'Descarga en lote (exclusivo Supporter)',
                                onPressed: supporter.isSupporter
                                    ? () => _showBatchDownloadDialog(context, details)
                                    : () => _showSupporterRequired(context),
                              );
                            },
                          ),
                          // Botón para invertir orden
                          IconButton(
                            icon: Icon(
                              _reverseEpisodeOrder ? Icons.arrow_downward : Icons.arrow_upward,
                              color: context.primaryColor,
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
                    ],
                  ),
                  Divider(color: context.cardColor, height: 20),
                  if (details.episodes.length > 100) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        controller: _episodeSearchController,
                        onChanged: (val) {
                          setState(() {
                            _episodeSearchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar episodio (ej: 12, Luffy...)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _episodeSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _episodeSearchController.clear();
                                    setState(() {
                                      _episodeSearchQuery = '';
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Lista de Episodios (SliverList para rendimiento)
          animeProvider.isLoadingEpisodes
              ? SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(context.primaryColor),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Cargando episodios...',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : displayedEpisodes.isEmpty
                  ? SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Text(
                            _episodeSearchQuery.trim().isNotEmpty
                                ? 'No se encontraron episodios para "$_episodeSearchQuery"'
                                : 'No hay episodios disponibles.',
                            style: TextStyle(color: context.textSecondary),
                          ),
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
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isWatched 
                                  ? context.primaryColor.withOpacity(0.15) 
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                    episodes: details.episodes,
                                  ),
                                ),
                              );
                            },
                            leading: _EpisodeThumbnail(
                              episode: episode,
                              animeId: details.id,
                              animeUrl: widget.animeUrl,
                              fallbackPosterUrl: posterImage.isNotEmpty ? posterImage : null,
                              isWatched: isWatched,
                            ),
                            title: Text(
                              episode.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isWatched ? context.textSecondary : context.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Número: ${episode.number.toString().replaceAll('.0', '')}',
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                EpisodeDownloadButton(
                                  episodeUrl: episode.url,
                                  episodeNumber: episode.number,
                                  animeTitle: details.title,
                                  animeUrl: widget.animeUrl,
                                  animeImage: posterImage,
                                ),
                                Icon(Icons.chevron_right, color: context.textSecondary),
                              ],
                            ),
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
              sectionKey: _commentsKey,
              animeSlug: Uri.parse(widget.animeUrl).pathSegments.lastWhere(
                (s) => s.isNotEmpty,
                orElse: () => widget.animeUrl.hashCode.toString(),
              ),
              animeTitle: widget.animeTitle,
              animeUrl: widget.animeUrl,
              focusCommentId: widget.focusCommentId,
            ),
          ),

          // Espaciador final
          const SliverToBoxAdapter(
            child: SizedBox(height: 50),
          ),
        ],
      ),
    );
  }
}

class _EpisodeThumbnail extends StatelessWidget {
  final Episode episode;
  final String? animeId;
  final String animeUrl;
  final String? fallbackPosterUrl;
  final bool isWatched;

  const _EpisodeThumbnail({
    required this.episode,
    required this.animeId,
    required this.animeUrl,
    this.fallbackPosterUrl,
    required this.isWatched,
  });

  @override
  Widget build(BuildContext context) {
    final thumbUrls = collectEpisodeThumbnailCandidates(
      apiImage: episode.image,
      animeId: animeId,
      episodeNumber: episode.number,
      animeUrl: animeUrl,
      fallbackPosterUrl: fallbackPosterUrl,
    );

    return SizedBox(
      width: 112,
      height: 63,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumbUrls.isEmpty
                ? ColoredBox(
                    color: context.backgroundColor,
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: context.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : AnimePosterImage(
                    urlCandidates: thumbUrls,
                    fit: BoxFit.cover,
                  ),
          ),
          Deco(context),
          Center(
            child: Icon(
              isWatched ? Icons.check_circle : Icons.play_circle_fill,
              color: isWatched ? context.primaryColor : Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget Deco(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black.withValues(alpha: 0.35),
      ),
    );
  }
}
