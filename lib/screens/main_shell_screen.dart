import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/tracked_series_service.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/novel_history_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/supporter_provider.dart';
import '../utils/auth_ui.dart';
import 'home_screen.dart';
import 'catalog_screen.dart';
import 'manga_tab_screen.dart';
import 'search_screen.dart';
import 'schedule_screen.dart';
import 'novel_tab_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  bool _welcomeChecked = false;
  String? _boundUserId;
  DateTime? _lastBackPress;

  static const _tabs = [
    _NavItem(icon: Icons.home_rounded, label: 'Inicio'),
    _NavItem(icon: Icons.grid_view_rounded, label: 'Catálogo'),
    _NavItem(icon: Icons.book_rounded, label: 'Manga'),
    _NavItem(icon: Icons.auto_stories_rounded, label: 'Novela'),
    _NavItem(icon: Icons.calendar_month_rounded, label: 'Horario'),
    _NavItem(icon: Icons.search_rounded, label: 'Buscar'),
  ];

  static const _screens = [
    HomeScreen(),
    CatalogScreen(embedded: true),
    MangaTabScreen(),
    NovelTabScreen(),
    ScheduleScreen(embedded: true),
    SearchScreen(embedded: true),
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

  void _onAuthChanged() => _syncUser(context.read<app_auth.AuthProvider>());


  Future<void> _syncUser(app_auth.AuthProvider auth) async {
    if (!mounted) return;
    context.read<NotificationProvider>().bindUser(auth.userId);
    context.read<SupporterProvider>().bindUser(auth.userId);
    if (_boundUserId == auth.userId) {
      _tryShowWelcome(auth);
      return;
    }
    _boundUserId = auth.userId;
    await context.read<HistoryProvider>().bindCloudHistory(auth.userId);
    await context.read<MangaHistoryProvider>().bindCloudHistory(auth.userId);
    await context.read<NovelHistoryProvider>().bindCloudHistory(auth.userId);
    // Registra los seguimientos previos para recibir avisos de nuevos capítulos.
    unawaited(TrackedSeriesService.backfillForUser(auth.userId));
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

    // Detección TV: pantalla grande (TV/tablet) O navegación D-pad activa
    final mq = MediaQuery.of(context);
    debugPrint('SCREEN shortestSide=${mq.size.shortestSide} longestSide=${mq.size.longestSide} navMode=${mq.navigationMode}');
    final isTV = mq.navigationMode == NavigationMode.directional ||
        mq.size.shortestSide > 480;

    final offlineBanner = !connectivity.isConnected
        ? Container(
            width: double.infinity,
            color: AppTheme.dangerColor,
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
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
          )
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final now = DateTime.now();
        final lastPress = _lastBackPress;
        if (lastPress != null && now.difference(lastPress) < const Duration(seconds: 2)) {
          // Segunda pulsación: salir de la app
          await SystemNavigator.pop();
        } else {
          _lastBackPress = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Presiona atrás de nuevo para salir'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      child: isTV
          ? _buildTV(context, offlineBanner)
          : _buildMobile(context, offlineBanner),
    );
  }

  // ── Vista móvil ────────────────────────────────────────────────────────────

  Widget _buildMobile(BuildContext context, Widget? offlineBanner) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Column(
        children: [
          if (offlineBanner != null)
            SafeArea(bottom: false, child: offlineBanner),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
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
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.25),
            ),
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
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : context.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : context.textSecondary,
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

  // ── Vista TV ───────────────────────────────────────────────────────────────

  Widget _buildTV(BuildContext context, Widget? offlineBanner) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          if (offlineBanner != null) offlineBanner,
          Expanded(
            child: Row(
              children: [
                // Sidebar navegación
                FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Container(
                    width: 200,
                    color: context.cardColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Row(
                            children: [
                              Icon(Icons.play_circle_fill_rounded,
                                  color: primary, size: 28),
                              const SizedBox(width: 10),
                              Text(
                                'Miru',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...List.generate(_tabs.length, (i) {
                          return FocusTraversalOrder(
                            order: NumericFocusOrder(i.toDouble()),
                            child: _TVNavItem(
                              icon: _tabs[i].icon,
                              label: _tabs[i].label,
                              selected: _currentIndex == i,
                              onTap: () =>
                                  setState(() => _currentIndex = i),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                    width: 1,
                    color: primary.withValues(alpha: 0.15)),
                // Contenido
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TV Nav Item ────────────────────────────────────────────────────────────

class _TVNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TVNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_TVNavItem> createState() => _TVNavItemState();
}

class _TVNavItemState extends State<_TVNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final active = widget.selected || _focused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          focusColor: primary.withValues(alpha: 0.18),
          onFocusChange: (f) => setState(() => _focused = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: widget.selected
                  ? primary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? primary.withValues(alpha: 0.7)
                    : widget.selected
                        ? primary.withValues(alpha: 0.4)
                        : Colors.transparent,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon,
                    color: active ? primary : context.textSecondary,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: active ? primary : context.textSecondary,
                      fontWeight: active
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
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
