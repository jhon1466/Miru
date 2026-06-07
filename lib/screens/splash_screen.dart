import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/anime_provider.dart';
import 'downloads_screen.dart';
import 'main_shell_screen.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  String _statusMessage = 'Iniciando Miru...';
  bool _connectionFailed = false;

  static const _onboardingKey = 'onboarding_complete';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.7, curve: Curves.elasticOut)),
    );
    _controller.forward();
    _boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Inicializar providers
    await Provider.of<HistoryProvider>(context, listen: false).init();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.load();
    if (!mounted) return;
    final animeProvider = context.read<AnimeProvider>();
    animeProvider.setAdultContentEnabled(settings.adultContentEnabled);
    animeProvider.selectProvider(settings.favoriteProviderDomain);

    if (!mounted) return;
    setState(() => _statusMessage = 'Conectando al servidor...');

    final baseUrl = await ApiClient.getBaseUrl();
    final isConnected = await ApiClient.testConnection(baseUrl);

    if (!mounted) return;

    if (isConnected) {
      setState(() => _statusMessage = '¡Conexión establecida!');
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // Verificar si es la primera vez
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool(_onboardingKey) ?? false;

      if (!mounted) return;

      if (!onboardingDone) {
        await prefs.setBool(_onboardingKey, true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShellScreen()),
        );
      }
    } else {
      setState(() {
        _connectionFailed = true;
        _statusMessage = 'No se pudo conectar al servidor.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colores adaptativos
    final bg1 = isDark ? AppTheme.darkBackground : const Color(0xFFF0F4FF);
    final bg2 = isDark ? const Color(0xFF0F172A) : const Color(0xFFE0E8FF);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? AppTheme.textSecondary : const Color(0xFF6B7280);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg1, bg2],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo animado con escala elástica
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.4 : 0.2),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Image.asset(
                        'assets/miruapp.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'MIRU',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5,
                    color: titleColor,
                    shadows: [
                      Shadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Multi-Provider Streaming Client',
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 72),

                if (!_connectionFailed) ...[
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.wifi_off_rounded,
                    color: AppTheme.dangerColor,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _connectionFailed = false;
                            _statusMessage = 'Reintentando...';
                          });
                          _boot();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: titleColor,
                          side: BorderSide(color: subtitleColor.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Configurar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                      );
                    },
                    icon: Icon(Icons.download_for_offline_rounded, color: Theme.of(context).colorScheme.primary),
                    label: Text(
                      'Modo sin conexión (Ver descargas)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
