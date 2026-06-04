import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';
import '../providers/manga_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/anime_poster_image.dart';
import '../models/manga.dart';
import '../services/manga_favorite_service.dart';
import '../services/manga_follow_service.dart';
import 'manga_reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final String mangaId;

  const MangaDetailScreen({super.key, required this.mangaId});

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  bool _reverseChapterOrder = false;
  Map<String, String>? _readingProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<MangaProvider>();
      await provider.loadMangaDetails(widget.mangaId);
      if (mounted) {
        provider.loadChapters(widget.mangaId);
      }
      _loadProgress();
    });
  }

  Future<void> _loadProgress() async {
    final progress = await context.read<MangaProvider>().getReadingProgress(widget.mangaId);
    if (mounted) {
      setState(() {
        _readingProgress = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mangaProvider = Provider.of<MangaProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
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
                    mangaProvider.loadChapters(widget.mangaId);
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
    final displayedChapters = List<MangaChapter>.from(mangaProvider.chapters);
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

    final mangaShareUrl = 'https://inmanga.com/ver/manga/${details.title.replaceAll(' ', '-').toLowerCase()}/${widget.mangaId}';

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
                      text: '¡Lee ${details.title} en InManga! $mangaShareUrl',
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

                  const SizedBox(height: 28),
                  // Chapters Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Capítulos (${mangaProvider.chapters.length})',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
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
                            subtitle: Text(
                              'Leer capítulo',
                              style: TextStyle(fontSize: 12, color: context.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isChapterProgress) ...[
                                  Icon(Icons.bookmark_rounded, color: context.primaryColor, size: 18),
                                  const SizedBox(width: 8),
                                ],
                                Icon(
                                  Icons.chrome_reader_mode_outlined,
                                  color: context.textSecondary,
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

          const SliverToBoxAdapter(
            child: SizedBox(height: 60),
          ),
        ],
      ),
    );
  }
}
