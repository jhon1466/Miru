import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme.dart';
import 'core/firebase_options.dart';
import 'core/app_navigator.dart';
import 'providers/anime_provider.dart';
import 'providers/manga_provider.dart';
import 'providers/manga_history_provider.dart';
import 'providers/novel_provider.dart';
import 'providers/novel_history_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/history_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/download_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/tv_provider.dart';
import 'providers/supporter_provider.dart';
import 'providers/cast_provider.dart';
import 'services/push_notification_service.dart';
import 'services/deep_link_service.dart';
import 'services/anilist_service.dart';
import 'services/download_notification_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Pre-detección nativa (UiModeManager); MediaQuery refina en el primer build
  final tvProvider = TVProvider();
  await tvProvider.detectNative();

  unawaited(PushNotificationService.initialize());
  unawaited(DownloadNotificationService.initialize());
  unawaited(DeepLinkService.initialize());
  unawaited(AniListService.init());
  runApp(MyApp(tvProvider: tvProvider));
}

class MyApp extends StatelessWidget {
  final TVProvider tvProvider;
  const MyApp({super.key, required this.tvProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TVProvider>.value(value: tvProvider),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AnimeProvider()),
        ChangeNotifierProvider(create: (_) => MangaProvider()),
        ChangeNotifierProvider(create: (_) => MangaHistoryProvider()),
        ChangeNotifierProvider(create: (_) => NovelProvider()),
        ChangeNotifierProvider(create: (_) => NovelHistoryProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()..startListening()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()..loadLibrary()),
        ChangeNotifierProvider(create: (_) => SupporterProvider()),
        ChangeNotifierProvider(create: (_) => CastProvider()),
        ChangeNotifierProvider(create: (_) => CastProvider()),
      ],
      child: Builder(
        builder: (context) {
          PushNotificationService.attachProvider(context.read<NotificationProvider>());
          final settings = context.watch<SettingsProvider>();
          return MaterialApp(
            navigatorKey: AppNavigator.key,
            title: 'Miru Client',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(settings.effectiveSeedColor),
            darkTheme: AppTheme.darkTheme(settings.effectiveSeedColor),
            themeMode: settings.themeMode,
            builder: (context, child) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: isDark
                    ? SystemUiOverlayStyle.light.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      )
                    : SystemUiOverlayStyle.dark.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
