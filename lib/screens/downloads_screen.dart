import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/downloaded_episode.dart';
import '../models/novel.dart';
import '../providers/download_provider.dart';
import '../services/offline_storage_service.dart';
import '../widgets/anime_poster_image.dart';
import 'manga_reader_screen.dart';
import 'novel_reader_screen.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _downloadedMangas = [];
  List<Map<String, dynamic>> _downloadedNovels = [];
  bool _loadingManga = false;
  bool _loadingNovel = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1 && _downloadedMangas.isEmpty && !_loadingManga) {
        _loadManga();
      } else if (_tabController.index == 2 && _downloadedNovels.isEmpty && !_loadingNovel) {
        _loadNovels();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DownloadProvider>().loadLibrary();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadManga() async {
    setState(() => _loadingManga = true);
    try {
      final mangas = await OfflineStorageService.getDownloadedMangas();
      if (mounted) setState(() => _downloadedMangas = mangas);
    } finally {
      if (mounted) setState(() => _loadingManga = false);
    }
  }

  Future<void> _loadNovels() async {
    setState(() => _loadingNovel = true);
    try {
      final novels = await OfflineStorageService.getDownloadedNovels();
      if (mounted) setState(() => _downloadedNovels = novels);
    } finally {
      if (mounted) setState(() => _loadingNovel = false);
    }
  }

  Map<String, List<DownloadedEpisode>> _groupByAnime(List<DownloadedEpisode> items) {
    final map = <String, List<DownloadedEpisode>>{};
    for (final item in items) {
      map.putIfAbsent(item.animeUrl, () => []).add(item);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis descargas'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.primaryColor,
          labelColor: context.primaryColor,
          unselectedLabelColor: context.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.play_circle_outline), text: 'Anime'),
            Tab(icon: Icon(Icons.menu_book_outlined), text: 'Manga'),
            Tab(icon: Icon(Icons.auto_stories_outlined), text: 'Novelas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AnimeTab(),
          _MangaTab(
            mangas: _downloadedMangas,
            loading: _loadingManga,
            onRefresh: _loadManga,
            onDeleted: () => setState(() => _downloadedMangas = []),
          ),
          _NovelTab(
            novels: _downloadedNovels,
            loading: _loadingNovel,
            onRefresh: _loadNovels,
            onDeleted: () => setState(() => _downloadedNovels = []),
          ),
        ],
      ),
    );
  }
}

// ─── Anime Tab ─────────────────────────────────────────────────────────────

class _AnimeTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final active = downloads.activeTasks;
    final failed = downloads.failedTasks;
    final grouped = <String, List<DownloadedEpisode>>{};
    for (final item in downloads.library) {
      grouped.putIfAbsent(item.animeUrl, () => []).add(item);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }
    final animeUrls = grouped.keys.toList()
      ..sort((a, b) {
        final ta = grouped[a]!.first.animeTitle.toLowerCase();
        final tb = grouped[b]!.first.animeTitle.toLowerCase();
        return ta.compareTo(tb);
      });

    return RefreshIndicator(
      onRefresh: downloads.loadLibrary,
      color: Theme.of(context).colorScheme.primary,
      child: active.isEmpty && failed.isEmpty && animeUrls.isEmpty
          ? _EmptyState(
              icon: Icons.download_for_offline_outlined,
              message:
                  'Descarga episodios desde el reproductor o la lista de capítulos. Verás el progreso aquí.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                if (active.isNotEmpty) ...[
                  const Text('En progreso',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...active.map((t) => _ActiveDownloadCard(task: t, isFailed: false)),
                  const SizedBox(height: 24),
                ],
                if (failed.isNotEmpty) ...[
                  const Text('Con error',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.dangerColor)),
                  const SizedBox(height: 8),
                  ...failed.map((t) => _ActiveDownloadCard(task: t, isFailed: true)),
                  const SizedBox(height: 24),
                ],
                if (animeUrls.isNotEmpty) ...[
                  const Text('Disponibles sin conexión',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...animeUrls.map((url) {
                    final eps = grouped[url]!;
                    return _AnimeDownloadGroup(
                      title: eps.first.animeTitle,
                      image: eps.first.animeImage,
                      episodes: eps,
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

// ─── Manga Tab ─────────────────────────────────────────────────────────────

class _MangaTab extends StatelessWidget {
  final List<Map<String, dynamic>> mangas;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onDeleted;

  const _MangaTab({
    required this.mangas,
    required this.loading,
    required this.onRefresh,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.primaryColor)));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: mangas.isEmpty
          ? _EmptyState(
              icon: Icons.menu_book_outlined,
              message:
                  'Toca el icono de descarga junto a un capítulo de manga para guardarlo y leerlo sin conexión.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: mangas.length,
              itemBuilder: (context, i) {
                final manga = mangas[i];
                final chapters =
                    (manga['chapters'] as List).cast<Map<String, dynamic>>();
                return _MangaDownloadGroup(
                  mangaId: manga['mangaId'] as String,
                  title: manga['mangaTitle'] as String,
                  coverUrl: manga['coverUrl'] as String,
                  chapters: chapters,
                  onRefresh: onRefresh,
                );
              },
            ),
    );
  }
}

class _MangaDownloadGroup extends StatelessWidget {
  final String mangaId;
  final String title;
  final String coverUrl;
  final List<Map<String, dynamic>> chapters;
  final Future<void> Function() onRefresh;

  const _MangaDownloadGroup({
    required this.mangaId,
    required this.title,
    required this.coverUrl,
    required this.chapters,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimePosterImage(
            urlCandidates: coverUrl.isNotEmpty ? [coverUrl] : [],
            width: 48,
            height: 64,
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '${chapters.length} capítulo${chapters.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        children: chapters.map((ch) {
          final chapterId = ch['chapterId'] as String;
          final chapterNumber = ch['chapterNumber']?.toString() ?? '?';
          return ListTile(
            leading: Icon(Icons.chrome_reader_mode_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: Text('Capítulo $chapterNumber'),
            subtitle: const Text('Sin conexión',
                style: TextStyle(fontSize: 11, color: Colors.green)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar capítulo'),
                    content: Text('¿Quitar el capítulo $chapterNumber de este dispositivo?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('No')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar',
                            style: TextStyle(color: AppTheme.dangerColor)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await OfflineStorageService.deleteMangaChapter(mangaId, chapterId);
                  await onRefresh();
                }
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MangaReaderScreen(
                    mangaId: mangaId,
                    mangaTitle: title,
                    coverUrl: coverUrl,
                    chapterId: chapterId,
                    chapterNumber: chapterNumber,
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

// ─── Novel Tab ─────────────────────────────────────────────────────────────

class _NovelTab extends StatelessWidget {
  final List<Map<String, dynamic>> novels;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onDeleted;

  const _NovelTab({
    required this.novels,
    required this.loading,
    required this.onRefresh,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.primaryColor)));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: novels.isEmpty
          ? _EmptyState(
              icon: Icons.auto_stories_outlined,
              message:
                  'Toca el icono de descarga junto a un capítulo de novela para guardarlo y leerlo sin conexión.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: novels.length,
              itemBuilder: (context, i) {
                final novel = novels[i];
                final chapters =
                    (novel['chapters'] as List).cast<Map<String, dynamic>>();
                return _NovelDownloadGroup(
                  novelId: novel['novelId'] as String,
                  novelUrl: novel['novelUrl'] as String? ?? '',
                  title: novel['novelTitle'] as String,
                  coverUrl: novel['coverUrl'] as String,
                  chapters: chapters,
                  onRefresh: onRefresh,
                );
              },
            ),
    );
  }
}

class _NovelDownloadGroup extends StatelessWidget {
  final String novelId;
  final String novelUrl;
  final String title;
  final String coverUrl;
  final List<Map<String, dynamic>> chapters;
  final Future<void> Function() onRefresh;

  const _NovelDownloadGroup({
    required this.novelId,
    required this.novelUrl,
    required this.title,
    required this.coverUrl,
    required this.chapters,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimePosterImage(
            urlCandidates: coverUrl.isNotEmpty ? [coverUrl] : [],
            width: 48,
            height: 64,
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '${chapters.length} capítulo${chapters.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        children: chapters.map((ch) {
          final chapterId = ch['chapterId'] as String;
          final chapterTitle = ch['chapterTitle'] as String? ?? 'Capítulo';
          final chapterUrl = ch['chapterUrl'] as String? ?? '';
          final chapterNumberRaw = ch['chapterNumber'];
          final chapterNumber = chapterNumberRaw is num
              ? chapterNumberRaw.toDouble()
              : double.tryParse(chapterNumberRaw?.toString() ?? '') ?? 0.0;
          final paragraphs = (ch['paragraphs'] as List?)?.cast<String>() ?? [];

          return ListTile(
            leading:
                Icon(Icons.auto_stories_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(chapterTitle,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Sin conexión',
                style: TextStyle(fontSize: 11, color: Colors.green)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar capítulo'),
                    content:
                        Text('¿Quitar "$chapterTitle" de este dispositivo?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('No')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar',
                            style: TextStyle(color: AppTheme.dangerColor)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await OfflineStorageService.deleteNovelChapter(novelId, chapterId);
                  await onRefresh();
                }
              },
            ),
            onTap: () {
              final offlineChapter = NovelChapter(
                id: chapterId,
                title: chapterTitle,
                url: chapterUrl,
                number: chapterNumber,
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NovelReaderScreen(
                    novelId: novelId,
                    novelTitle: title,
                    novelUrl: novelUrl,
                    novelCover: coverUrl,
                    chapter: offlineChapter,
                    allChapters: chapters.map((c) {
                      final n = c['chapterNumber'];
                      return NovelChapter(
                        id: c['chapterId'] as String,
                        title: c['chapterTitle'] as String? ?? '',
                        url: c['chapterUrl'] as String? ?? '',
                        number: n is num
                            ? n.toDouble()
                            : double.tryParse(n?.toString() ?? '') ?? 0.0,
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

// ─── Shared Widgets ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 72, color: AppTheme.textSecondary),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  final ActiveDownloadTask task;
  final bool isFailed;

  const _ActiveDownloadCard({required this.task, required this.isFailed});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final isPaused = task.status == DownloadTaskStatus.paused;
    final isQueued = task.status == DownloadTaskStatus.queued;
    final isDownloading = task.status == DownloadTaskStatus.downloading;

    IconData getStatusIcon() {
      if (isFailed) return Icons.error_outline;
      if (isPaused) return Icons.pause_circle_outline;
      if (isQueued) return Icons.hourglass_empty;
      return Icons.downloading;
    }

    Color getStatusColor() {
      if (isFailed) return AppTheme.dangerColor;
      if (isPaused) return Theme.of(context).colorScheme.secondary;
      return Theme.of(context).colorScheme.primary;
    }

    String getStatusText() {
      if (isFailed) return 'Descarga fallida';
      if (isPaused) return 'Pausado';
      if (isQueued) return 'En cola…';
      return task.statusMessage.isNotEmpty ? task.statusMessage : 'Descargando';
    }

    final receivedMB = task.receivedBytes / (1024 * 1024);
    String progressDetails = '${receivedMB.toStringAsFixed(1)} MB';
    if (task.totalBytes != null && task.totalBytes! > 0) {
      final totalMB = task.totalBytes! / (1024 * 1024);
      progressDetails += ' / ${totalMB.toStringAsFixed(1)} MB';
    }

    if (isDownloading && task.speed > 0) {
      progressDetails += ' (${task.speed.toStringAsFixed(1)} MB/s)';
      if (task.eta.isNotEmpty && task.eta != '--') {
        progressDetails += ' · ETA: ${task.eta}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isFailed ? AppTheme.dangerColor.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(getStatusIcon(), color: getStatusColor(), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    getStatusText(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: getStatusColor(),
                    ),
                  ),
                ),
                if (!isFailed)
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: getStatusColor(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.animeTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${task.episodeTitle} · ${task.isSub ? 'SUB' : 'DUB'}',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (isFailed) ...[
              Text(
                task.error ?? 'No se pudo completar la descarga',
                style: const TextStyle(
                    color: AppTheme.dangerColor, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => downloads.dismissFailed(task.id),
                    child: const Text('Descartar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      downloads.dismissFailed(task.id);
                      downloads.startEpisodeDownload(
                        episodeUrl: task.episodeUrl,
                        episodeNumber: task.episodeNumber,
                        animeTitle: task.animeTitle,
                        animeUrl: task.animeUrl,
                        animeImage: task.animeImage,
                        preferSub: task.isSub,
                      );
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ] else ...[
              LinearProgressIndicator(
                value: isQueued ? null : task.progress,
                color: getStatusColor(),
                backgroundColor: getStatusColor().withValues(alpha: 0.15),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      progressDetails,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDownloading)
                        IconButton(
                          icon: const Icon(Icons.pause, size: 20),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () =>
                              downloads.pauseDownload(task.episodeUrl, task.isSub),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Pausar',
                        ),
                      if (isPaused)
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () => downloads.resumeDownload(
                            episodeUrl: task.episodeUrl,
                            episodeNumber: task.episodeNumber,
                            animeTitle: task.animeTitle,
                            animeUrl: task.animeUrl,
                            animeImage: task.animeImage,
                            preferSub: task.isSub,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Reanudar',
                        ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: AppTheme.dangerColor,
                        onPressed: () =>
                            downloads.cancelDownload(task.episodeUrl, task.isSub),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Cancelar',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimeDownloadGroup extends StatelessWidget {
  final String title;
  final String image;
  final List<DownloadedEpisode> episodes;

  const _AnimeDownloadGroup({
    required this.title,
    required this.image,
    required this.episodes,
  });

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimePosterImage(
            imageUrl: image.isNotEmpty ? image : null,
            width: 48,
            height: 64,
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '${episodes.length} episodio${episodes.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        children: episodes.map((ep) {
          return ListTile(
            leading: Icon(Icons.play_circle_outline,
                color: Theme.of(context).colorScheme.primary),
            title: Text(ep.episodeTitle),
            subtitle: Text('${ep.languageLabel} · ${ep.sizeLabel}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar descarga'),
                    content:
                        Text('¿Quitar ${ep.episodeLabel} de este dispositivo?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('No')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar',
                            style:
                                TextStyle(color: AppTheme.dangerColor)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await downloads.deleteDownload(ep);
                }
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => OfflinePlayerScreen(episode: ep)),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
