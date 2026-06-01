import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/downloaded_episode.dart';
import '../providers/download_provider.dart';
import '../widgets/anime_poster_image.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DownloadProvider>().loadLibrary();
    });
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
    final downloads = context.watch<DownloadProvider>();
    final active = downloads.activeTasks;
    final failed = downloads.failedTasks;
    final grouped = _groupByAnime(downloads.library);
    final animeUrls = grouped.keys.toList()
      ..sort((a, b) {
        final ta = grouped[a]!.first.animeTitle.toLowerCase();
        final tb = grouped[b]!.first.animeTitle.toLowerCase();
        return ta.compareTo(tb);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis descargas'),
      ),
      body: RefreshIndicator(
        onRefresh: downloads.loadLibrary,
        color: AppTheme.primaryColor,
        child: active.isEmpty && failed.isEmpty && animeUrls.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.download_for_offline_outlined, size: 72, color: AppTheme.textSecondary),
                  SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Descarga episodios desde el reproductor o la lista de capítulos. Verás el progreso aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (active.isNotEmpty) ...[
                    const Text(
                      'En progreso',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...active.map((t) => _ActiveDownloadCard(task: t, isFailed: false)),
                    const SizedBox(height: 24),
                  ],
                  if (failed.isNotEmpty) ...[
                    const Text(
                      'Con error',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.dangerColor),
                    ),
                    const SizedBox(height: 8),
                    ...failed.map((t) => _ActiveDownloadCard(task: t, isFailed: true)),
                    const SizedBox(height: 24),
                  ],
                  if (animeUrls.isNotEmpty) ...[
                    const Text(
                      'Disponibles sin conexión',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...animeUrls.map((url) {
                      final eps = grouped[url]!;
                      final header = eps.first;
                      return _AnimeDownloadGroup(
                        title: header.animeTitle,
                        image: header.animeImage,
                        episodes: eps,
                      );
                    }),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  final ActiveDownloadTask task;
  final bool isFailed;

  const _ActiveDownloadCard({required this.task, required this.isFailed});

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadProvider>();
    final isActive = !isFailed && task.status != DownloadTaskStatus.failed;

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
                Icon(
                  isFailed
                      ? Icons.error_outline
                      : (task.status == DownloadTaskStatus.queued
                          ? Icons.hourglass_top
                          : Icons.downloading),
                  color: isFailed ? AppTheme.dangerColor : AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isFailed ? 'Descarga fallida' : (task.statusMessage.isNotEmpty ? task.statusMessage : 'Descargando'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isFailed ? AppTheme.dangerColor : AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.animeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${task.episodeTitle} · ${task.isSub ? 'SUB' : 'DUB'}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (isFailed) ...[
              Text(
                task.error ?? 'No se pudo completar la descarga',
                style: const TextStyle(color: AppTheme.dangerColor, fontSize: 12, height: 1.35),
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
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ] else ...[
              LinearProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                color: AppTheme.primaryColor,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 6),
              Text(
                task.progress > 0
                    ? '${(task.progress * 100).toStringAsFixed(0)}%'
                    : (task.statusMessage.isNotEmpty ? task.statusMessage : 'Preparando…'),
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              if (isActive) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => downloads.cancelDownload(task.episodeUrl, task.isSub),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimePosterImage(
            imageUrl: image.isNotEmpty ? image : null,
            width: 48,
            height: 64,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '${episodes.length} episodio${episodes.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        children: episodes.map((ep) {
          return ListTile(
            leading: const Icon(Icons.play_circle_outline, color: AppTheme.primaryColor),
            title: Text(ep.episodeTitle),
            subtitle: Text('${ep.languageLabel} · ${ep.sizeLabel}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar descarga'),
                    content: Text('¿Quitar ${ep.episodeLabel} de este dispositivo?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar', style: TextStyle(color: AppTheme.dangerColor)),
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
                MaterialPageRoute(builder: (_) => OfflinePlayerScreen(episode: ep)),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
