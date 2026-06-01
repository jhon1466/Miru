import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/anime.dart';
import '../models/downloaded_episode.dart';
import '../services/episode_download_service.dart';

class DownloadProvider extends ChangeNotifier {
  final Map<String, ActiveDownloadTask> _active = {};
  final List<ActiveDownloadTask> _failed = [];
  List<DownloadedEpisode> _library = [];
  bool _loaded = false;
  final Set<String> _cancelled = {};

  List<ActiveDownloadTask> get activeTasks => _active.values.toList();
  List<ActiveDownloadTask> get failedTasks => List.unmodifiable(_failed);
  List<DownloadedEpisode> get library => List.unmodifiable(_library);
  bool get isLoaded => _loaded;

  Future<void> loadLibrary() async {
    _library = await EpisodeDownloadService.loadLibrary();
    _loaded = true;
    notifyListeners();
  }

  bool isDownloading(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    return _active.containsKey(id);
  }

  DownloadedEpisode? getDownloaded(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    for (final item in _library) {
      if (item.id == id) return item;
    }
    return null;
  }

  ActiveDownloadTask? taskFor(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    return _active[id] ?? _failed.where((t) => t.id == id).firstOrNull;
  }

  void dismissFailed(String id) {
    _failed.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<bool> startEpisodeDownload({
    required String episodeUrl,
    required double episodeNumber,
    required String animeTitle,
    required String animeUrl,
    required String animeImage,
    required bool preferSub,
    EpisodeLinksResponse? links,
  }) async {
    final id = EpisodeDownloadService.episodeId(episodeUrl, preferSub);
    if (_active.containsKey(id)) return false;

    final existing = getDownloaded(episodeUrl, preferSub);
    if (existing != null) return true;

    _failed.removeWhere((t) => t.id == id);
    _cancelled.remove(id);

    final task = ActiveDownloadTask(
      id: id,
      animeTitle: animeTitle,
      animeUrl: animeUrl,
      animeImage: animeImage,
      episodeNumber: episodeNumber,
      episodeUrl: episodeUrl,
      episodeTitle: 'Episodio ${episodeNumber.toString().replaceAll('.0', '')}',
      isSub: preferSub,
      status: DownloadTaskStatus.queued,
      statusMessage: 'En cola…',
    );
    _active[id] = task;
    notifyListeners();

    try {
      task.statusMessage = 'Buscando servidor de descarga…';
      notifyListeners();

      final episodeLinks = links ?? await ApiClient.getEpisodeLinks(episodeUrl);
      final candidates = EpisodeDownloadService.listOfflineCandidates(
        episodeLinks,
        preferSub: preferSub,
      );

      if (candidates.isEmpty) {
        throw Exception(
          'No hay servidor de descarga directa. Abre el reproductor y elige un servidor marcado como descarga.',
        );
      }

      task.status = DownloadTaskStatus.downloading;
      task.statusMessage = 'Descargando…';
      notifyListeners();

      Object? lastError;
      for (var i = 0; i < candidates.length; i++) {
        if (_cancelled.contains(id)) throw DownloadCancelledException();
        final link = candidates[i];
        task.statusMessage = candidates.length > 1
            ? 'Descargando (${link.server})…'
            : 'Descargando…';
        task.progress = 0;
        notifyListeners();

        try {
          await EpisodeDownloadService.downloadEpisode(
            sourceUrl: link.url,
            serverName: link.server,
            animeTitle: animeTitle,
            animeUrl: animeUrl,
            animeImage: animeImage,
            episodeNumber: episodeNumber,
            episodeUrl: episodeUrl,
            episodeTitle: task.episodeTitle,
            isSub: preferSub,
            onProgress: (p, received, total) {
              task.receivedBytes = received;
              task.totalBytes = total;
              if (p >= 0) {
                task.progress = p.clamp(0.0, 1.0);
                task.statusMessage = 'Descargando ${(task.progress * 100).toStringAsFixed(0)}%';
              } else {
                final mb = received / (1024 * 1024);
                task.statusMessage = 'Descargando ${mb.toStringAsFixed(1)} MB…';
              }
              notifyListeners();
            },
            isCancelled: () => _cancelled.contains(id),
          );

          task.status = DownloadTaskStatus.completed;
          task.progress = 1;
          task.statusMessage = 'Completado';
          _active.remove(id);
          await loadLibrary();
          notifyListeners();
          return true;
        } catch (e) {
          if (e is DownloadCancelledException) rethrow;
          lastError = e;
        }
      }

      throw lastError ?? Exception('No se pudo descargar con ningún servidor');
    } on DownloadCancelledException {
      _active.remove(id);
      notifyListeners();
      return false;
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.error = e.toString().replaceFirst('Exception: ', '');
      task.statusMessage = 'Error';
      _active.remove(id);
      _failed.removeWhere((t) => t.id == id);
      _failed.insert(0, task);
      notifyListeners();
      return false;
    }
  }

  void cancelDownload(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    _cancelled.add(id);
    final task = _active[id];
    if (task != null) {
      task.statusMessage = 'Cancelando…';
      notifyListeners();
    }
  }

  Future<void> deleteDownload(DownloadedEpisode item) async {
    await EpisodeDownloadService.deleteDownload(item);
    await loadLibrary();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
