import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../models/anime.dart';
import '../models/downloaded_episode.dart';
import '../services/episode_download_service.dart';
import '../services/download_notification_service.dart';

class DownloadProvider extends ChangeNotifier {
  static const _channel = MethodChannel('com.anime1v.app/foreground_service');

  final Map<String, ActiveDownloadTask> _active = {};
  final List<ActiveDownloadTask> _failed = [];
  List<DownloadedEpisode> _library = [];
  bool _loaded = false;
  final Set<String> _cancelled = {};
  final Set<String> _paused = {};

  Future<void> _updateForegroundService() async {
    if (Platform.isAndroid) {
      try {
        final hasActive = _active.values.any((t) =>
            t.status == DownloadTaskStatus.downloading ||
            t.status == DownloadTaskStatus.queued);
        if (hasActive) {
          await _channel.invokeMethod('startService');
        } else {
          await _channel.invokeMethod('stopService');
        }
      } catch (e) {
        debugPrint('Error updating foreground service: $e');
      }
    }
  }

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
    return _active.containsKey(id) && _active[id]!.status != DownloadTaskStatus.paused;
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
    
    ActiveDownloadTask task;
    if (_active.containsKey(id)) {
      task = _active[id]!;
      if (task.status == DownloadTaskStatus.paused) {
        task.status = DownloadTaskStatus.queued;
        task.statusMessage = 'Reanudando…';
        _paused.remove(id);
        _cancelled.remove(id);
      } else {
        return false;
      }
    } else {
      final existing = getDownloaded(episodeUrl, preferSub);
      if (existing != null) return true;

      _failed.removeWhere((t) => t.id == id);
      _cancelled.remove(id);
      _paused.remove(id);

      task = ActiveDownloadTask(
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
    }
    notifyListeners();
    _updateForegroundService();

    final notificationId = id.hashCode & 0x7FFFFFFF;
    final prefs = await SharedPreferences.getInstance();
    final bgDownloadsEnabled = prefs.getBool('settings_background_downloads_enabled') ?? true;

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
      _updateForegroundService();

      Object? lastError;
      for (var i = 0; i < candidates.length; i++) {
        if (_cancelled.contains(id)) throw DownloadCancelledException();
        if (_paused.contains(id)) throw DownloadPausedException();
        final link = candidates[i];
        task.statusMessage = candidates.length > 1
            ? 'Descargando (${link.server})…'
            : 'Descargando…';
        notifyListeners();

        int lastNotifiedPct = -1;
        try {
          if (bgDownloadsEnabled) {
            unawaited(DownloadNotificationService.showProgress(
              notificationId,
              animeTitle,
              task.episodeTitle,
              0.0,
            ));
          }
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
            onProgress: (p, received, total, speed) {
              task.receivedBytes = received;
              task.totalBytes = total;
              task.speed = speed;

              if (speed > 0 && total != null) {
                final remaining = total - received;
                if (remaining > 0) {
                  final seconds = remaining / (speed * 1024 * 1024);
                  if (seconds < 60) {
                    task.eta = '${seconds.toStringAsFixed(0)}s';
                  } else {
                    final minutes = seconds / 60;
                    task.eta = '${minutes.toStringAsFixed(1)} min';
                  }
                } else {
                  task.eta = '0s';
                }
              } else {
                task.eta = '--';
              }

              if (p >= 0) {
                task.progress = p.clamp(0.0, 1.0);
                task.statusMessage = 'Descargando ${(task.progress * 100).toStringAsFixed(0)}%';
              } else {
                final mb = received / (1024 * 1024);
                task.statusMessage = 'Descargando ${mb.toStringAsFixed(1)} MB…';
              }
              notifyListeners();

              if (bgDownloadsEnabled) {
                final pct = p >= 0 ? (p * 100).round() : -1;
                if (pct != lastNotifiedPct) {
                  lastNotifiedPct = pct;
                  unawaited(DownloadNotificationService.showProgress(
                    notificationId,
                    animeTitle,
                    task.episodeTitle,
                    p,
                    speed: speed > 0 ? '${speed.toStringAsFixed(1)} MB/s' : null,
                  ));
                }
              }
            },
            isCancelled: () => _cancelled.contains(id),
            isPaused: () => _paused.contains(id),
          );

          task.status = DownloadTaskStatus.completed;
          task.progress = 1;
          task.statusMessage = 'Completado';
          task.speed = 0.0;
          task.eta = '';
          _active.remove(id);
          await loadLibrary();
          notifyListeners();
          _updateForegroundService();
          
          if (bgDownloadsEnabled) {
            unawaited(DownloadNotificationService.showComplete(
              notificationId,
              animeTitle,
              task.episodeTitle,
            ));
          }
          return true;
        } catch (e) {
          if (e is DownloadCancelledException || e is DownloadPausedException) rethrow;
          lastError = e;
        }
      }

      throw lastError ?? Exception('No se pudo descargar con ningún servidor');
    } on DownloadCancelledException {
      _active.remove(id);
      notifyListeners();
      _updateForegroundService();
      if (bgDownloadsEnabled) {
        unawaited(DownloadNotificationService.cancel(notificationId));
      }
      return false;
    } on DownloadPausedException {
      task.status = DownloadTaskStatus.paused;
      task.speed = 0.0;
      task.eta = '';
      task.statusMessage = 'Pausado';
      notifyListeners();
      _updateForegroundService();
      if (bgDownloadsEnabled) {
        unawaited(DownloadNotificationService.cancel(notificationId));
      }
      return false;
    } catch (e, stack) {
      debugPrint('ERROR EN DESCARGA DE EPISODIO: $e');
      debugPrint('STACK TRACE: $stack');
      try {
        getApplicationDocumentsDirectory().then((docDir) async {
          final logFile = File('${docDir.path}/last_error.txt');
          await logFile.writeAsString('ERROR: $e\nSTACK:\n$stack');
        });
        getExternalStorageDirectory().then((extDir) async {
          if (extDir != null) {
            final logFile = File('${extDir.path}/last_error.txt');
            await logFile.writeAsString('ERROR: $e\nSTACK:\n$stack');
          }
        });
      } catch (logErr) {
        debugPrint('Failed to write log file: $logErr');
      }

      task.status = DownloadTaskStatus.failed;
      task.error = e.toString().replaceFirst('Exception: ', '');
      task.statusMessage = 'Error';
      task.speed = 0.0;
      task.eta = '';
      _active.remove(id);
      _failed.removeWhere((t) => t.id == id);
      _failed.insert(0, task);
      notifyListeners();
      _updateForegroundService();
      if (bgDownloadsEnabled) {
        unawaited(DownloadNotificationService.showFailed(
          notificationId,
          animeTitle,
          task.episodeTitle,
          task.error ?? 'Error desconocido',
        ));
      }
      return false;
    }
  }

  void pauseDownload(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    _paused.add(id);
    final task = _active[id];
    if (task != null) {
      task.status = DownloadTaskStatus.paused;
      task.speed = 0.0;
      task.eta = '';
      task.statusMessage = 'Pausado';
      notifyListeners();
      _updateForegroundService();
    }

    final notificationId = id.hashCode & 0x7FFFFFFF;
    SharedPreferences.getInstance().then((prefs) {
      final bg = prefs.getBool('settings_background_downloads_enabled') ?? true;
      if (bg) {
        unawaited(DownloadNotificationService.cancel(notificationId));
      }
    });
  }

  void resumeDownload({
    required String episodeUrl,
    required double episodeNumber,
    required String animeTitle,
    required String animeUrl,
    required String animeImage,
    required bool preferSub,
    EpisodeLinksResponse? links,
  }) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, preferSub);
    _paused.remove(id);
    _cancelled.remove(id);
    final task = _active[id];
    if (task != null) {
      task.status = DownloadTaskStatus.queued;
      task.statusMessage = 'En cola…';
      notifyListeners();
    }
    startEpisodeDownload(
      episodeUrl: episodeUrl,
      episodeNumber: episodeNumber,
      animeTitle: animeTitle,
      animeUrl: animeUrl,
      animeImage: animeImage,
      preferSub: preferSub,
      links: links,
    );
  }

  void cancelDownload(String episodeUrl, bool isSub) {
    final id = EpisodeDownloadService.episodeId(episodeUrl, isSub);
    _cancelled.add(id);
    _paused.remove(id);
    final task = _active[id];
    if (task != null) {
      if (task.status == DownloadTaskStatus.paused) {
        _active.remove(id);
      } else {
        task.statusMessage = 'Cancelando…';
      }
      notifyListeners();
      _updateForegroundService();
    }

    final notificationId = id.hashCode & 0x7FFFFFFF;
    SharedPreferences.getInstance().then((prefs) {
      final bg = prefs.getBool('settings_background_downloads_enabled') ?? true;
      if (bg) {
        unawaited(DownloadNotificationService.cancel(notificationId));
      }
    });
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
