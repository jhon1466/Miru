import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/novel.dart';
import '../providers/novel_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/novel_history_provider.dart';
import '../widgets/anime_poster_image.dart';
import '../services/novel_favorite_service.dart';
import '../services/novel_follow_service.dart';
import '../services/offline_storage_service.dart';
import '../utils/auth_ui.dart';
import '../widgets/media_rating_section.dart';
import '../services/completed_service.dart';
import 'novel_reader_screen.dart';
import '../widgets/comments_section.dart';

class NovelDetailScreen extends StatefulWidget {
  final Novel novel;

  const NovelDetailScreen({super.key, required this.novel});

  @override
  State<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends State<NovelDetailScreen> {
  bool _reverseChapterOrder = false;
  String _chapterSearchQuery = '';
  String? _downloadingChapterId;
  double _downloadProgress = 0.0;
  final Set<String> _downloadedChapterIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<NovelProvider>();
      await provider.loadNovelDetails(widget.novel);
      _loadOfflineStatus();
    });
  }

  // ── acción favorito ─────────────────────────────────────────
  Future<void> _toggleFavorite(String userId, Novel novel) async {
    await NovelFavoriteService.toggleFavorite(userId, novel);
  }

  // ── acción seguir ──────────────────────────────────────────
  Future<void> _toggleFollow(String userId, Novel novel) async {
    await NovelFollowService.toggleFollow(userId, novel);
  }

  Future<void> _loadOfflineStatus() async {
    final provider = context.read<NovelProvider>();
    final chapters = provider.chapters;
    final Set<String> downloaded = {};
    for (final ch in chapters) {
      final isDl = await OfflineStorageService.isNovelChapterDownloaded(widget.novel.id, ch.id);
      if (isDl) downloaded.add(ch.id);
    }
    if (mounted) {
      setState(() {
        _downloadedChapterIds.addAll(downloaded);
      });
    }
  }

  Future<void> _downloadChapter(Novel details, NovelChapter chapter) async {
    setState(() {
      _downloadingChapterId = chapter.id;
      _downloadProgress = 0.0;
    });
    try {
      final paragraphs = await OfflineStorageService.fetchNovelParagraphs(chapter.url);
      if (paragraphs.isEmpty) {
        throw Exception('No se encontró contenido en el capítulo.');
      }
      await OfflineStorageService.saveNovelChapter(
        novelId: details.id,
        novelTitle: details.title,
        coverUrl: details.coverUrl ?? '',
        novelUrl: details.url,
        chapterId: chapter.id,
        chapterNumber: chapter.number,
        chapterTitle: chapter.title,
        chapterUrl: chapter.url,
        paragraphs: paragraphs,
      );
      if (mounted) {
        setState(() => _downloadedChapterIds.add(chapter.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capítulo "${chapter.title}" descargado'),
            backgroundColor: context.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: $e'),
            backgroundColor: context.dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingChapterId = null);
    }
  }

  Future<void> _deleteNovelChapter(NovelChapter chapter) async {
    await OfflineStorageService.deleteNovelChapter(widget.novel.id, chapter.id);
    if (mounted) {
      setState(() => _downloadedChapterIds.remove(chapter.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capítulo eliminado'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // ── navegar al reader guardando historial ────────────────────────
  void _openChapter(
    BuildContext ctx,
    Novel details,
    NovelChapter chapter,
    List<NovelChapter> allChapters,
    app_auth.AuthProvider auth,
  ) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => NovelReaderScreen(
          novelId: details.id,
          novelTitle: details.title,
          novelUrl: details.url,
          novelCover: details.coverUrl ?? '',
          chapter: chapter,
          allChapters: allChapters,
        ),
      ),
    ).then((_) {
      // Actualizar progreso en historial local si se leyó algo
      if (mounted) setState(() {});
    });

    // Guardar en historial al abrir
    ctx.read<NovelHistoryProvider>().addToHistory(
          novelId: details.id,
          novelTitle: details.title,
          coverUrl: details.coverUrl ?? '',
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          chapterNumber: chapter.number,
          userId: auth.userId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final details = novelProvider.selectedNovel;
    final isLoading = novelProvider.isLoadingDetails;
    final error = novelProvider.detailsError;
    final userId = authProvider.userId;
    final isLoggedIn = authProvider.isLoggedIn;

    if (isLoading) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          title: Text(widget.novel.title),
        ),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.primaryColor),
          ),
        ),
      );
    }

    if (error != null || details == null) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          title: Text(widget.novel.title),
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
                  error ?? 'Error al cargar detalles de la novela',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => novelProvider.loadNovelDetails(widget.novel),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    var displayedChapters = List<NovelChapter>.from(novelProvider.chapters);
    if (_chapterSearchQuery.trim().isNotEmpty) {
      final query = _chapterSearchQuery.trim().toLowerCase();
      displayedChapters = displayedChapters.where((ch) {
        return ch.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_reverseChapterOrder) {
      displayedChapters.sort((a, b) => b.number.compareTo(a.number));
    } else {
      displayedChapters.sort((a, b) => a.number.compareTo(b.number));
    }

    final coverCandidates =
        details.coverUrl != null ? [details.coverUrl!] : <String>[];

    // Último capítulo leído de esta novela
    final historyProvider = context.watch<NovelHistoryProvider>();
    final lastRead = historyProvider.history
        .where((h) => h.novelId == details.id)
        .toList();
    final lastChapterId =
        lastRead.isNotEmpty ? lastRead.first.chapterId : null;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Banner / AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: context.backgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverCandidates.isNotEmpty)
                    AnimePosterImage(
                      urlCandidates: coverCandidates,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(color: context.backgroundColor),
                  DecoratedBox(
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
                ],
              ),
            ),
            // ── Botones Favorito y Seguir en AppBar ──────────────
            actions: isLoggedIn && userId != null
                ? [
                    _FavButton(userId: userId, novel: details, onTap: _toggleFavorite),
                    _FollowButton(userId: userId, novel: details, onTap: _toggleFollow),
                    const SizedBox(width: 8),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.login),
                      tooltip: 'Iniciar sesión para guardar',
                      onPressed: () => signInWithGoogleAndWelcome(
                        context,
                        context.read<app_auth.AuthProvider>(),
                      ),
                    ),
                  ],
          ),

          // ── Info ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 110,
                          height: 160,
                          child: AnimePosterImage(
                            urlCandidates: coverCandidates,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              details.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            if (details.author != null && details.author!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                details.author!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.primaryColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Novela Ligera',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${novelProvider.chapters.length} capítulos',
                              style: TextStyle(fontSize: 13, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── Botones de acción ─────────────────────────────
                  const SizedBox(height: 20),
                  if (isLoggedIn && userId != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _FavButtonLarge(
                            userId: userId,
                            novel: details,
                            onTap: _toggleFavorite,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FollowButtonLarge(
                            userId: userId,
                            novel: details,
                            onTap: _toggleFollow,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<bool>(
                      stream: CompletedService.isCompletedStream(userId, details.id),
                      builder: (context, snapshot) {
                        final isCompleted = snapshot.data ?? false;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              await CompletedService.toggleCompleted(
                                userId: userId,
                                mediaId: details.id,
                                mediaType: 'novel',
                                title: details.title,
                                image: details.coverUrl,
                                status: details.status,
                                author: details.author,
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
                                    isCompleted ? 'Terminada / Leída' : 'Marcar como Terminada',
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
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => signInWithGoogleAndWelcome(
                          context,
                          context.read<app_auth.AuthProvider>(),
                        ),
                        icon: const Icon(Icons.login),
                        label: const Text('Inicia sesión para guardar y seguir'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.textSecondary.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Inicia sesión para marcar como terminada'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: Icon(Icons.check_circle_outline, color: context.textSecondary),
                      label: Text('Marcar como Terminada', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                    ),
                  ],

                  // ── Continuar lectura ──────────────────────────────
                  if (lastChapterId != null && displayedChapters.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ContinueReadingBanner(
                      lastChapterId: lastChapterId,
                      chapters: displayedChapters,
                      onTap: (chapter) => _openChapter(
                        context,
                        details,
                        chapter,
                        novelProvider.chapters,
                        authProvider,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Text(
                    'Sinopsis',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    novelProvider.selectedNovelSynopsis ?? 'Sin sinopsis disponible.',
                    style: TextStyle(
                        fontSize: 14, color: context.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  MediaRatingSection(
                    mediaId: details.id,
                    mediaType: 'novel',
                    title: details.title,
                    image: details.coverUrl,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Capítulos (${displayedChapters.length})',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary),
                      ),
                      IconButton(
                        icon: Icon(
                          _reverseChapterOrder
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: context.primaryColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _reverseChapterOrder = !_reverseChapterOrder;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (val) {
                      setState(() {
                        _chapterSearchQuery = val;
                      });
                    },
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Buscar capítulo (ej. 1, 24...)',
                      hintStyle: TextStyle(color: context.textSecondary),
                      prefixIcon: Icon(Icons.search, color: context.textSecondary),
                      fillColor: context.cardColor,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(color: context.cardColor, height: 20),
                ],
              ),
            ),
          ),

          // ── Lista de capítulos ────────────────────────────────────
          displayedChapters.isEmpty
              ? const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text('No hay capítulos disponibles.'),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chapter = displayedChapters[index];
                        final isLastRead = chapter.id == lastChapterId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isLastRead
                                ? context.primaryColor.withValues(alpha: 0.15)
                                : context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: isLastRead
                                ? Border.all(
                                    color: context.primaryColor.withValues(alpha: 0.5),
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            onTap: () => _openChapter(
                              context,
                              details,
                              chapter,
                              novelProvider.chapters,
                              authProvider,
                            ),
                            leading: isLastRead
                                ? Icon(Icons.bookmark_rounded,
                                    color: context.primaryColor, size: 20)
                                : null,
                            title: Text(
                              chapter.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isLastRead
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 14,
                                color: isLastRead
                                    ? context.primaryColor
                                    : context.textPrimary,
                              ),
                            ),
                            subtitle: _downloadingChapterId == chapter.id
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: LinearProgressIndicator(
                                      color: context.primaryColor,
                                      backgroundColor: context.primaryColor.withValues(alpha: 0.2),
                                      minHeight: 4,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  )
                                : _downloadedChapterIds.contains(chapter.id)
                                    ? Text(
                                        'Disponible sin conexión',
                                        style: TextStyle(fontSize: 11, color: Colors.green),
                                      )
                                    : isLastRead
                                        ? Text(
                                            'Último leído',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.primaryColor,
                                            ),
                                          )
                                        : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_downloadingChapterId == chapter.id)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.primaryColor,
                                    ),
                                  )
                                else if (_downloadedChapterIds.contains(chapter.id))
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Eliminar descarga',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteNovelChapter(chapter),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(Icons.download_outlined, color: context.primaryColor, size: 20),
                                    tooltip: 'Descargar capítulo',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: _downloadingChapterId != null
                                        ? null
                                        : () => _downloadChapter(details, chapter),
                                  ),
                                Icon(Icons.chevron_right, color: context.textSecondary),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: displayedChapters.length,
                    ),
                  ),
                ),

          // Sección de Comentarios de la Novela
          SliverToBoxAdapter(
            child: CommentsSection(
              animeSlug: details.id,
              animeTitle: details.title,
              animeUrl: details.url,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ── Widget: Botón Favorito en AppBar ─────────────────────────────────────────
class _FavButton extends StatelessWidget {
  final String userId;
  final Novel novel;
  final Future<void> Function(String, Novel) onTap;

  const _FavButton({
    required this.userId,
    required this.novel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NovelFavoriteService.isFavoriteStream(userId, novel.id),
      builder: (context, snap) {
        final isFav = snap.data ?? false;
        return IconButton(
          icon: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFav ? Colors.redAccent : null,
          ),
          tooltip: isFav ? 'Quitar de favoritos' : 'Agregar a favoritos',
          onPressed: () => onTap(userId, novel),
        );
      },
    );
  }
}

// ── Widget: Botón Seguir en AppBar ───────────────────────────────────────────
class _FollowButton extends StatelessWidget {
  final String userId;
  final Novel novel;
  final Future<void> Function(String, Novel) onTap;

  const _FollowButton({
    required this.userId,
    required this.novel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NovelFollowService.isFollowingStream(userId, novel.id),
      builder: (context, snap) {
        final isFollowing = snap.data ?? false;
        return IconButton(
          icon: Icon(
            isFollowing
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            color: isFollowing ? Colors.amber : null,
          ),
          tooltip: isFollowing ? 'Dejar de seguir' : 'Seguir (notificaciones)',
          onPressed: () => onTap(userId, novel),
        );
      },
    );
  }
}

// ── Widget: Botón Favorito grande ────────────────────────────────────────────
class _FavButtonLarge extends StatelessWidget {
  final String userId;
  final Novel novel;
  final Future<void> Function(String, Novel) onTap;

  const _FavButtonLarge({
    required this.userId,
    required this.novel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NovelFavoriteService.isFavoriteStream(userId, novel.id),
      builder: (context, snap) {
        final isFav = snap.data ?? false;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isFav
                  ? Colors.redAccent
                  : context.cardColor,
              foregroundColor: isFav ? Colors.white : context.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => onTap(userId, novel),
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 18,
            ),
            label: Text(isFav ? 'Favorito' : 'Favoritos'),
          ),
        );
      },
    );
  }
}

// ── Widget: Botón Seguir grande ──────────────────────────────────────────────
class _FollowButtonLarge extends StatelessWidget {
  final String userId;
  final Novel novel;
  final Future<void> Function(String, Novel) onTap;

  const _FollowButtonLarge({
    required this.userId,
    required this.novel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NovelFollowService.isFollowingStream(userId, novel.id),
      builder: (context, snap) {
        final isFollowing = snap.data ?? false;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isFollowing
                  ? Colors.amber.shade700
                  : context.cardColor,
              foregroundColor:
                  isFollowing ? Colors.white : context.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => onTap(userId, novel),
            icon: Icon(
              isFollowing
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 18,
            ),
            label: Text(isFollowing ? 'Siguiendo' : 'Seguir'),
          ),
        );
      },
    );
  }
}

// ── Widget: Banner "Continuar leyendo" ───────────────────────────────────────
class _ContinueReadingBanner extends StatelessWidget {
  final String lastChapterId;
  final List<NovelChapter> chapters;
  final void Function(NovelChapter) onTap;

  const _ContinueReadingBanner({
    required this.lastChapterId,
    required this.chapters,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Buscar el capítulo siguiente al último leído
    final lastIndex =
        chapters.indexWhere((c) => c.id == lastChapterId);
    final targetChapter = lastIndex >= 0 && lastIndex + 1 < chapters.length
        ? chapters[lastIndex + 1]
        : lastIndex >= 0
            ? chapters[lastIndex]
            : null;

    if (targetChapter == null) return const SizedBox.shrink();

    final isNext =
        lastIndex >= 0 && lastIndex + 1 < chapters.length;

    return GestureDetector(
      onTap: () => onTap(targetChapter),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.primaryColor.withValues(alpha: 0.25),
              context.primaryColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: context.primaryColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              isNext
                  ? Icons.play_circle_filled_rounded
                  : Icons.replay_rounded,
              color: context.primaryColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNext ? 'Continuar leyendo' : 'Releer último capítulo',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                  Text(
                    targetChapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.primaryColor),
          ],
        ),
      ),
    );
  }
}
