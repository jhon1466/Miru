import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/connectivity_provider.dart';
import '../utils/auth_ui.dart';
import 'home_screen.dart';
import 'catalog_screen.dart';
import 'manga_tab_screen.dart';
import 'search_screen.dart';
import 'schedule_screen.dart';
import 'profile_tab_screen.dart';

/// Contenedor principal con barra de navegación flotante inferior.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  bool _welcomeChecked = false;
  String? _boundUserId;

  static const _tabs = [
    _NavItem(icon: Icons.home_rounded, label: 'Inicio'),
    _NavItem(icon: Icons.grid_view_rounded, label: 'Catálogo'),
    _NavItem(icon: Icons.book_rounded, label: 'Manga'),
    _NavItem(icon: Icons.calendar_month_rounded, label: 'Horario'),
    _NavItem(icon: Icons.search_rounded, label: 'Buscar'),
    _NavItem(icon: Icons.person_rounded, label: 'Perfil'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<app_auth.AuthProvider>();
      auth.addListener(_onAuthChanged);
      _syncUser(auth);
    });
  }

  @override
  void dispose() {
    context.read<app_auth.AuthProvider>().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    _syncUser(context.read<app_auth.AuthProvider>());
  }

  Future<void> _syncUser(app_auth.AuthProvider auth) async {
    if (!mounted) return;
    context.read<NotificationProvider>().bindUser(auth.userId);
    if (_boundUserId == auth.userId) {
      _tryShowWelcome(auth);
      return;
    }
    _boundUserId = auth.userId;
    await context.read<HistoryProvider>().bindCloudHistory(auth.userId);
    await context.read<MangaHistoryProvider>().bindCloudHistory(auth.userId);
    _tryShowWelcome(auth);
  }

  void _tryShowWelcome(app_auth.AuthProvider auth) {
    if (_welcomeChecked || !auth.isLoggedIn) return;
    final name = auth.consumeWelcomeName();
    if (name == null || !mounted) return;
    _welcomeChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showWelcomeDialog(context, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = Provider.of<ConnectivityProvider>(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Column(
        children: [
          if (!connectivity.isConnected)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: AppTheme.dangerColor,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Sin conexión a internet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                HomeScreen(),
                CatalogScreen(embedded: true),
                MangaTabScreen(),
                ScheduleScreen(embedded: true),
                SearchScreen(embedded: true),
                ProfileTabScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final item = _tabs[i];
              final selected = _currentIndex == i;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = i),
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        color: selected ? AppTheme.primaryColor : context.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? AppTheme.primaryColor : context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
