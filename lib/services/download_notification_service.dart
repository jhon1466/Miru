import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  static const String _channelId = 'miru_downloads_channel';
  static const String _channelName = 'Descargas de Episodios';
  
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: 'Notificaciones sobre el progreso de descargas de capítulos',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  static Future<void> initialize() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  static Future<void> showProgress(
    int notificationId,
    String animeTitle,
    String episodeTitle,
    double progress, {
    String? speed,
  }) async {
    final int pct = progress >= 0 ? (progress * 100).round().clamp(0, 100) : 0;
    final String progressText = progress >= 0 ? '$pct%' : 'Descargando...';
    final String body = speed != null ? '$progressText - $speed' : progressText;

    await _plugin.show(
      notificationId,
      '$animeTitle - $episodeTitle',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channel.description,
          importance: Importance.low,
          priority: Priority.low,
          showProgress: progress >= 0,
          maxProgress: 100,
          progress: pct,
          ongoing: true,
          onlyAlertOnce: true,
          icon: '@mipmap/ic_launcher',
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  static Future<void> showComplete(
    int notificationId,
    String animeTitle,
    String episodeTitle,
  ) async {
    await _plugin.show(
      notificationId,
      'Descarga completada',
      '$animeTitle - $episodeTitle',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> showFailed(
    int notificationId,
    String animeTitle,
    String episodeTitle,
    String errorMsg,
  ) async {
    await _plugin.show(
      notificationId,
      'Descarga fallida',
      '$animeTitle - $episodeTitle: $errorMsg',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> cancel(int notificationId) async {
    await _plugin.cancel(notificationId);
  }
}
