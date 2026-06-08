import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';
import '../providers/manga_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/supporter_provider.dart';
import '../widgets/anime_poster_image.dart';
import '../models/manga.dart';
import '../services/manga_favorite_service.dart';
import '../services/manga_follow_service.dart';
import '../services/offline_storage_service.dart';
import '../widgets/media_rating_section.dart';
import '../services/completed_service.dart';
import 'manga_reader_screen.dart';
import 'downloads_screen.dart';
import '../widgets/comments_section.dart';

class MangaDetailScreen extends StatefulWidget {
  final String mangaId;
  final String slug;

  const MangaDetailScreen({super.key, required this.mangaId, this.slug = ''});

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  bool _reverseChapterOrder = false;
  Map<String, String>? _readingProgress;
  String _chapterSearchQuery = '';
  String? _downloadingChapterId;
  double _downloadProgress = 0.0;
  final Set<String> _downloadedChapterIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<MangaProvider>();
      if (widget.slug.isNotEmpty) {
        await provider.loadMangaDetailsBySlug(widget.mangaId, widget.slug);
      } else {
        await provider.loadMangaDetails(widget.mangaId);
      }
      if (mounted) {
        provider.loadChapters(widget.mangaId, slug: widget.slug);
      }
      _loadProgress();
      _loadOfflineStatus();
    });
  }

  Future<void> _loadProgress() async {
    if (!mounted) return;
    final provider = context.read<MangaProvider>();
    final progress = await provider.getReadingProgress(widget.mangaId);
    if (mounted) {
      setState(() {
        _readingProgress = progress;
      });
    }
  }

  Future<void> _loadOfflineStatus() async {
    if (!mounted) return;
    final provider = context.read<MangaProvider>();
    final chapters = provider.chapters;
    final Set<String> downloaded = {};
    for (final ch in chapters) {
      final isDl = await OfflineStorageService.isMangaChapterDownloaded(widget.mangaId, ch.id);
      if (isDl) downloaded.add(ch.id);
    }
    if (mounted) {
      setState(() {
        _downloadedChapterIds.addAll(downloaded);
      });
    }
  }

  Future<void> _downloadChapter(MangaChapter chapter, String mangaTitle, String coverUrl) async {
    setState(() {
      _downloadingChapterId = chapter.id;
      _downloadProgress = 0.0;
    });
    try {
      // Fetch page URLs first
      final pageUrls = await OfflineStorageService.fetchMangaPages(widget.mangaId, chapter.id);
      if (pageUrls.isEmpty) throw Exception('No se encontraron páginas');
      await OfflineStorageService.saveMangaChapter(
        mangaId: widget.mangaId,
        mangaTitle: mangaTitle,
        coverUrl: coverUrl,
        chapterId: chapter.id,
        chapterNumber: chapter.chapterNumber,
        pageUrls: pageUrls,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (mounted) {
        setState(() => _downloadedChapterIds.add(chapter.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capítulo ${chapter.chapterNumber} descargado'),
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

  Future<void> _deleteChapter(MangaChapter chapter) async {
    await OfflineStorageService.deleteMangaChapter(widget.mangaId, chapter.id);
    if (mounted) {
      setState(() => _downloadedChapterIds.remove(chapter.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capítulo ${chapter.chapterNumber} eliminado'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ── Descarga en lote (Supporter) ──────────────────────────────────────────
  bool _isBatchDownloading = false;
  int _batchTotal = 0;
  int _batchDone = 0;

  void _showSupporterRequired(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          Icon(Icons.download_for_offline_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('Descarga en lote exclusivo para Supporters de Patreon')),
        ]),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showBatchDownloadDialog(
    BuildContext context,
    List<MangaChapter> chapters,
    String mangaTitle,
    String coverUrl,
  ) {
    final notDownloaded = chapters
        .where((c) => !_downloadedChapterIds.contains(c.id))
        .toList();
    if (notDownloaded.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos los capítulos ya están descargados')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Text('👑 ', style: TextStyle(fontSize: 20)),
          Text('Descarga en lote', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          'Se descargarán ${notDownloaded.length} capítulos de "$mangaTitle" '
          'que aún no tienes offline.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text('Descargar ${notDownloaded.length} caps'),
            onPressed: () {
              Navigator.pop(ctx);
              _startBatchDownload(context, notDownloaded, mangaTitle, coverUrl);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startBatchDownload(
    BuildContext context,
    List<MangaChapter> chapters,
    String mangaTitle,
    String coverUrl,
  ) async {
    setState(() {
      _isBatchDownloading = true;
      _batchTotal = chapters.length;
      _batchDone = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.download_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text('Descargando ${chapters.length} capítulos…')),
        ]),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ),
    );

    for (final chapter in chapters) {
      if (!mounted) break;
      try {
        final pageUrls = await OfflineStorageService.fetchMangaPages(widget.mangaId, chapter.id);
        if (pageUrls.isEmpty) throw Exception('Sin páginas');
        await OfflineStorageService.saveMangaChapter(
          mangaId: widget.mangaId,
          mangaTitle: mangaTitle,
          coverUrl: coverUrl,
          chapterId: chapter.id,
          chapterNumber: chapter.chapterNumber,
          pageUrls: pageUrls,
        );
        if (mounted) setState(() {
          _downloadedChapterIds.add(chapter.id);
          _batchDone++;
        });
      } catch (_) {
        if (mounted) setState(() => _batchDone++);
      }
    }

    if (mounted) {
      setState(() => _isBatchDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lote completado: $_batchDone/${_batchTotal} capítulos'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mangaProvider = Provider.of<MangaProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final supporter = Provider.of<SupporterProvider>(context, listen: false);
    final details = mangaProvider.selectedManga;
    final isLoading = mangaProvider.isLoadingDetails || mangaProvider.isLoadingChapters;
    final error = mangaProvider.detailsError ?? mangaProvider.chaptersError;

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manga')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.primaryColor)),
              const SizedBox(height: 16),
              Text('Obteniendo detalles del manga...', style: TextStyle(color: context.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (error != null || details == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: context.dangerColor),
                const SizedBox(height: 16),
                Text(
                  error ?? 'Error desconocido',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    mangaProvider.loadMangaDetails(widget.mangaId);
                    mangaProvider.loadChapters(widget.mangaId, slug: widget.slug);
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final coverCandidates = details.coverUrl != null ? [details.coverUrl!] : <String>[];

    // Preparar capítulos ordenados
    var displayedChapters = List<MangaChapter>.from(mangaProvider.chapters);
    if (_chapterSearchQuery.trim().isNotEmpty) {
      final query = _chapterSearchQuery.trim().toLowerCase();
      displayedChapters = displayedChapters.where((ch) {
        return ch.chapterNumber.toLowerCase().contains(query) ||
               ch.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_reverseChapterOrder) {
      displayedChapters.sort((a, b) {
        final aNum = double.tryParse(a.chapterNumber) ?? 0.0;
        final bNum = double.tryParse(b.chapterNumber) ?? 0.0;
        return aNum.compareTo(bNum);
      });
    } else {
      displayedChapters.sort((a, b) {
        final aNum = double.tryParse(a.chapterNumber) ?? 0.0;
        final bNum = double.tryParse(b.chapterNumber) ?? 0.0;
        return bNum.compareTo(aNum);
      });
    }

    // Comprobar si hay historial para reanudar lectura
    final resumeChapterId = _readingProgress?['chapterId'];
    final resumeChapterNum = _readingProgress?['chapterNumber'];
    final resumePage = int.tryParse(_readingProgress?['page'] ?? '1') ?? 1;

    final mangaSlug = widget.slug.isNotEmpty ? widget.slug : details.title.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    final mangaShareUrl = 'https://zonatmo.org/library/manga/${widget.mangaId}/$mangaSlug';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header Banner
          SliverAppBar(
            expandedHeight: 220,
            pinned: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (details.coverUrl != null)
                    AnimePosterImage(
                      urlCandidates: coverCandidates,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(color: context.backgroundColor),
                  // Gradiente difuminado sobre la portada
                  Positioned.fill(
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
                ],
              ),
            ),
          ),

          // Pinned AppBar with actions
          SliverAppBar(
            pinned: true,
            backgroundColor: context.backgroundColor,
            title: Text(
              details.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textPrimary),
            ),
            actions: [
              // Compartir
              IconButton(
                icon: Icon(Icons.share, color: context.textPrimary, size: 24),
                tooltip: 'Compartir',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: '¡Lee ${details.title} en ZonaTMO! $mangaShareUrl',
                    ),
                  );
                },
              ),
              // Favorito
              authProvider.isLoggedIn
                  ? StreamBuilder<bool>(
                      stream: MangaFavoriteService.isFavoriteStream(
                        authProvider.userId!,
                        widget.mangaId,
                      ),
                      builder: (context, snapshot) {
                        final isFav = snapshot.data ?? false;
                        return IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav ? context.dangerColor : context.textPrimary,
                            size: 26,
                          ),
                          onPressed: () async {
                            await MangaFavoriteService.toggleFavorite(
                              authProvider.userId!,
                              details,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isFav ? 'Eliminado de biblioteca' : 'Añadido a biblioteca'),
                                backgroundColor: isFav ? context.dangerColor : context.successColor,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : IconButton(
                      icon: Icon(Icons.favorite_border, color: context.textSecondary, size: 26),
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
          ),

          // Metadata e Información de Manga
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover
                      AnimePosterImage(
                        urlCandidates: coverCandidates,
                        width: 110,
                        height: 160,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(width: 16),
                      // Meta info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.primaryColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    details.status?.toUpperCase() ?? 'DESCONOCIDO',
                                    style: TextStyle(fontSize: 10, color: context.primaryColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (details.year != null)
                                  Text(
                                    details.year.toString(),
                                    style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (details.author != null) ...[
                              Text(
                                'Autor: ${details.author}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: context.textSecondary),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              'Capítulos: ${mangaProvider.chapters.length}',
                              style: TextStyle(fontSize: 13, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Botón Seguir (debajo de la fila de cover+meta)
                  const SizedBox(height: 16),
                  authProvider.isLoggedIn
                      ? StreamBuilder<bool>(
                          stream: MangaFollowService.isFollowingStream(
                            authProvider.userId!,
                            widget.mangaId,
                          ),
                          builder: (context, snapshot) {
                            final isFollowing = snapshot.data ?? false;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await MangaFollowService.toggleFollow(
                                    authProvider.userId!,
                                    details,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(isFollowing ? 'Dejaste de seguir este manga' : 'Ahora sigues este manga'),
                                      backgroundColor: isFollowing ? context.dangerColor : context.successColor,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isFollowing ? context.cardColor : context.primaryColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isFollowing
                                        ? Border.all(color: context.primaryColor.withValues(alpha: 0.5))
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isFollowing ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                        color: isFollowing ? context.primaryColor : Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isFollowing ? 'Siguiendo' : 'Seguir Manga',
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
                            );
                          },
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.primaryColor.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Inicia sesión con Google para seguir este manga'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: Icon(Icons.bookmark_border_rounded, color: context.primaryColor),
                          label: Text('Seguir Manga', style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold)),
                        ),
                  const SizedBox(height: 12),
                  authProvider.isLoggedIn
                      ? StreamBuilder<bool>(
                          stream: CompletedService.isCompletedStream(
                            authProvider.userId!,
                            widget.mangaId,
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
                                    mediaId: widget.mangaId,
                                    mediaType: 'manga',
                                    title: details.title,
                                    image: details.coverUrl,
                                    type: null,
                                    status: details.status,
                                    genres: details.genres,
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
                                        isCompleted ? 'Terminado / Leído' : 'Marcar como Terminado',
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

                  // Botón de reanudación de lectura
                  if (resumeChapterId != null && resumeChapterId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: context.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MangaReaderScreen(
                                mangaId: widget.mangaId,
                                mangaTitle: details.title,
                                coverUrl: details.coverUrl ?? '',
                                chapterId: resumeChapterId,
                                chapterNumber: resumeChapterNum ?? '?',
                                startPage: resumePage,
                              ),
                            ),
                          ).then((_) => _loadProgress());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                'Continuar leyendo Cap. $resumeChapterNum (Pág. $resumePage)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

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
                            border: Border.all(color: context.textSecondary.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(fontSize: 11, color: context.textPrimary),
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
                    details.description.isNotEmpty ? details.description : 'Sin sinopsis disponible.',
                    style: TextStyle(fontSize: 14, color: context.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  MediaRatingSection(
                    mediaId: widget.mangaId,
                    mediaType: 'manga',
                    title: details.title,
                    image: details.coverUrl,
                  ),

                  const SizedBox(height: 28),
                  // Chapters Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Capítulos (${displayedChapters.length})',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                          ),
                          // Descarga en lote (Supporter)
                          if (mangaProvider.chapters.isNotEmpty)
                            _isBatchDownloading
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        value: _batchTotal > 0 ? _batchDone / _batchTotal : null,
                                        valueColor: AlwaysStoppedAnimation(context.primaryColor),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      Icons.download_for_offline_rounded,
                                      color: supporter.isSupporter
                                          ? context.primaryColor
                                          : context.textSecondary.withValues(alpha: 0.5),
                                    ),
                                    tooltip: supporter.isSupporter
                                        ? 'Descargar todos los capítulos (Supporter)'
                                        : 'Descarga en lote (exclusivo Supporter)',
                                    onPressed: supporter.isSupporter
                                        ? () => _showBatchDownloadDialog(
                                              context,
                                              mangaProvider.chapters,
                                              details.title,
                                              details.coverUrl ?? '',
                                            )
                                        : () => _showSupporterRequired(context),
                                  ),
                          IconButton(
                            icon: Icon(
                              _reverseChapterOrder ? Icons.arrow_downward : Icons.arrow_upward,
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
                    ],
                  ),
                  Divider(color: context.cardColor, height: 30),
                ],
              ),
            ),
          ),

          // Chapters list view
          displayedChapters.isEmpty
              ? const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text(
                        'No hay capítulos disponibles.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, height: 1.5),
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chapter = displayedChapters[index];
                        final isChapterProgress = _readingProgress?['chapterId'] == chapter.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isChapterProgress
                                  ? context.primaryColor.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MangaReaderScreen(
                                    mangaId: widget.mangaId,
                                    mangaTitle: details.title,
                                    coverUrl: details.coverUrl ?? '',
                                    chapterId: chapter.id,
                                    chapterNumber: chapter.chapterNumber,
                                  ),
                                ),
                              ).then((_) => _loadProgress());
                            },
                            title: Text(
                              'Capítulo ${chapter.chapterNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            subtitle: _downloadingChapterId == chapter.id
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress,
                                      color: context.primaryColor,
                                      backgroundColor: context.primaryColor.withValues(alpha: 0.2),
                                      minHeight: 4,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  )
                                : Text(
                                    _downloadedChapterIds.contains(chapter.id)
                                        ? 'Disponible sin conexión'
                                        : 'Leer capítulo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _downloadedChapterIds.contains(chapter.id)
                                          ? Colors.green
                                          : context.textSecondary,
                                    ),
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isChapterProgress) ...[
                                  Icon(Icons.bookmark_rounded, color: context.primaryColor, size: 18),
                                  const SizedBox(width: 4),
                                ],
                                if (_downloadingChapterId == chapter.id)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: _downloadProgress,
                                      color: context.primaryColor,
                                    ),
                                  )
                                else if (_downloadedChapterIds.contains(chapter.id))
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Eliminar descarga',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteChapter(chapter),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(Icons.download_outlined, color: context.primaryColor, size: 20),
                                    tooltip: 'Descargar capítulo',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: _downloadingChapterId != null
                                        ? null
                                        : () => _downloadChapter(
                                              chapter,
                                              details.title,
                                              details.coverUrl ?? '',
                                            ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: displayedChapters.length,
                    ),
                  ),
                ),

          // Sección de Comentarios del Manga
          SliverToBoxAdapter(
            child: CommentsSection(
              animeSlug: widget.mangaId,
              animeTitle: details.title,
              animeUrl: mangaShareUrl,
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 60),
          ),
        ],
      ),
    );
  }
}
