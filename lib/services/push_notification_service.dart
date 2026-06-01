import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../providers/notification_provider.dart';
import 'user_service.dart';
import 'notification_navigation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background: ${message.notification?.title}');
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'miru_replies',
    'Respuestas a comentarios',
    description: 'Avisos cuando alguien responde tus comentarios',
    importance: Importance.high,
  );

  static NotificationProvider? _notificationProvider;
  static String? _currentToken;
  static bool _initialized = false;

  static void attachProvider(NotificationProvider provider) {
    _notificationProvider = provider;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          NotificationNavigation.handlePayload(payload);
        }
      },
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _scheduleOpenFromMessage(initial);
    }

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await registerTokenForUser(user.uid);
      } else if (_currentToken != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await UserService.removeFcmToken(uid, _currentToken!);
        }
        _currentToken = null;
      }
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await registerTokenForUser(user.uid);
    }

    _messaging.onTokenRefresh.listen((token) async {
      _currentToken = token;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await UserService.addFcmToken(uid, token);
      }
    });
  }

  static Future<void> registerTokenForUser(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await UserService.addFcmToken(uid, token);
    } catch (e) {
      debugPrint('FCM registerToken: $e');
    }
  }

  static Future<void> unregisterCurrentToken(String uid) async {
    if (_currentToken != null) {
      await UserService.removeFcmToken(uid, _currentToken!);
    }
    await _messaging.deleteToken();
    _currentToken = null;
  }

  static void _onForegroundMessage(RemoteMessage message) {
    _notificationProvider?.refreshUnread();

    final title = message.notification?.title ?? message.data['title'] ?? 'Miru';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final payload = _payloadFromMessage(message);

    _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    _scheduleOpenFromMessage(message);
  }

  static void _scheduleOpenFromMessage(RemoteMessage message) {
    final payload = _payloadFromMessage(message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationNavigation.handlePayload(payload);
    });
  }

  static String _payloadFromMessage(RemoteMessage message) {
    final d = message.data;
    return [
      d['animeSlug'] ?? '',
      d['animeTitle'] ?? '',
      d['animeUrl'] ?? '',
      d['episodeNumber'] ?? '',
      d['commentId'] ?? '',
      d['notificationId'] ?? '',
    ].join('|');
  }
}
