import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/anime.dart';
import '../models/downloaded_episode.dart';
import '../services/episode_download_service.dart';

class DownloadProvider extends ChangeNotifier {
  final Map<String, ActiveDownloadTask> _active = {};
  List<DownloadedEpisode> _library = [];
  bool _loaded = false;
  final Set<String> _cancelled = {};

  List<ActiveDownloadTask> get activeTasks => _active.values.toList();
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
    return _active[EpisodeDownloadService.episodeId(episodeUrl, isSub)];
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
    );
    _active[id] = task;
    notifyListeners();

    try {
      final episodeLinks = links ?? await ApiClient.getEpisodeLinks(episodeUrl);

      final link = EpisodeDownloadService.pickOfflineLink(episodeLinks, preferSub: preferSub);
      if (link == null || link.url.isEmpty) {
        throw Exception('No hay enlace descargable para este episodio');
      }

      if (!EpisodeDownloadService.isLikelyDirectFile(link.url)) {
        throw Exception(
          'Este servidor solo permite streaming. Elige un servidor de descarga directa.',
        );
      }

      task.status = DownloadTaskStatus.downloading;
      notifyListeners();

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
        onProgress: (p) {
          if (p >= 0) task.progress = p.clamp(0.0, 1.0);
          notifyListeners();
        },
        isCancelled: () => _cancelled.contains(id),
      );

      task.status = DownloadTaskStatus.completed;
      task.progress = 1;
      _active.remove(id);
      await loadLibrary();
      return true;
    } on DownloadCancelledException {
      task.status = DownloadTaskStatus.cancelled;
      _active.remove(id);
      notifyListeners();
      return false;
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 4));
      _active.remove(id);
      notifyListeners();
      return false;
    }
  }

  void cancelDownload(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    _cancelled.add(id);
    notifyListeners();
  }

  Future<void> deleteDownload(DownloadedEpisode item) async {
    await EpisodeDownloadService.deleteDownload(item);
    await loadLibrary();
  }
}
