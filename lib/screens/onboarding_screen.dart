import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import 'main_shell_screen.dart';

/// Datos de cada página del onboarding.
class _OnboardPage {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  const _OnboardPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late List<AnimationController> _animControllers;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;

  static const _pages = [
    _OnboardPage(
      icon: Icons.play_circle_fill_rounded,
      iconColor: AppTheme.primaryColor,
      title: '¡Bienvenido a Miru!',
      description:
          'Tu cliente de streaming de anime, lector de manga y novelas ligeras. Encuentra, sigue y disfruta tus historias favoritas en un solo lugar.',
    ),
    _OnboardPage(
      icon: Icons.search_rounded,
      iconColor: Color(0xFF0EA5E9),
      title: 'Busca y Descubre',
      description:
          'Explora un catálogo enorme de animes, mangas y novelas. Busca por nombre, lee capítulos o descubre las series más populares.',
    ),
    _OnboardPage(
      icon: Icons.chat_bubble_rounded,
      iconColor: Color(0xFF10B981),
      title: 'Chat y Comunidad',
      description:
          'Participa en el chat público global, comenta episodios, responde mensajes, envía stickers e imágenes.',
    ),
    _OnboardPage(
      icon: Icons.notifications_active_rounded,
      iconColor: Color(0xFFF59E0B),
      title: 'Nunca te pierdas nada',
      description:
          'Sigue tus animes, mangas y novelas en emisión y recibe notificaciones push cuando salgan nuevos episodios o capítulos.',
    ),
    _OnboardPage(
      icon: Icons.bar_chart_rounded,
      iconColor: Color(0xFF8B5CF6),
      title: 'Tus Estadísticas',
      description:
          'Visualiza tus favoritos, elementos seguidos, historial y tiempo dedicado de anime, manga y novelas.',
    ),
  ];

  // Índice de la última página real + 1 = pantalla de login
  int get _totalPages => _pages.length + 1;

  @override
  void initState() {
    super.initState();
    _animControllers = List.generate(
      _totalPages,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _fadeAnims = _animControllers
        .map((c) => Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOut),
            ))
        .toList();
    _slideAnims = _animControllers
        .map((c) => Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();
    // Animar la primera página
    _animControllers[0].forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _animControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _goToPage(_currentPage + 1);
    }
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF07090F) : const Color(0xFFF0F4FF);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSec = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Botón saltar
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: TextButton(
                  onPressed: _goHome,
                  child: Text(
                    'Saltar',
                    style: TextStyle(
                      color: textSec,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  _animControllers[i].forward(from: 0);
                },
                itemBuilder: (context, index) {
                  if (index < _pages.length) {
                    return _buildFeaturePage(
                      context,
                      _pages[index],
                      index,
                      textPrimary,
                      textSec,
                      isDark,
                    );
                  }
                  return _buildLoginPage(context, textPrimary, textSec, isDark);
                },
              ),
            ),

            // Dots + botón siguiente
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Indicadores de página
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalPages, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.primaryColor
                              : textSec.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Botón acción
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: _currentPage < _totalPages - 1
                        ? ElevatedButton(
                            onPressed: _next,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Siguiente',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: _goHome,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Comenzar',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.rocket_launch_rounded),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePage(
    BuildContext context,
    _OnboardPage page,
    int index,
    Color textPrimary,
    Color textSec,
    bool isDark,
  ) {
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(
        position: _slideAnims[index],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ícono animado con aura
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.7, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: page.iconColor.withValues(alpha: isDark ? 0.12 : 0.1),
                    border: Border.all(
                      color: page.iconColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: page.iconColor.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(page.icon, size: 72, color: page.iconColor),
                ),
              ),
              const SizedBox(height: 48),

              Text(
                page.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: textSec,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginPage(
    BuildContext context,
    Color textPrimary,
    Color textSec,
    bool isDark,
  ) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
    final lastIndex = _totalPages - 1;

    return FadeTransition(
      opacity: _fadeAnims[lastIndex],
      child: SlideTransition(
        position: _slideAnims[lastIndex],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.9),
                      const Color(0xFF0EA5E9).withValues(alpha: 0.8),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_circle_filled_rounded,
                  size: 72,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 36),

              Text(
                '¡Todo listo!',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Inicia sesión con Google para guardar tus favoritos, seguir tus series y sincronizar tu historial de anime, manga y novelas.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: textSec,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              // Botón de Google Sign-In
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await authProvider.signInWithGoogle();
                    if (mounted) _goHome();
                  },
                  icon: _GoogleIcon(),
                  label: Text(
                    'Continuar con Google',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF1E2231)
                        : Colors.white,
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Saltar
              TextButton(
                onPressed: _goHome,
                child: Text(
                  'Continuar sin cuenta',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: textSec,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícono de Google dibujado con Canvas (sin assets externos).
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final length = size.width;
    final verticalOffset = (size.height / 2) - (length / 2);
    final bounds = Offset(0, verticalOffset) & Size.square(length);
    final center = bounds.center;
    final arcThickness = size.width / 4.5;
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcThickness
      ..strokeCap = StrokeCap.butt;

    void drawArc(double startAngle, double sweepAngle, Color color) {
      final p = paint..color = color;
      canvas.drawArc(bounds, startAngle, sweepAngle, false, p);
    }

    // Colores y ángulos exactos para el logo de Google G (en radianes)
    drawArc(3.5, 1.9, const Color(0xFFEA4335));    // Rojo (arriba)
    drawArc(2.5, 1.0, const Color(0xFFFBBC04));    // Amarillo (izquierda)
    drawArc(0.9, 1.6, const Color(0xFF34A853));    // Verde (abajo)
    drawArc(-0.18, 1.1, const Color(0xFF4285F4));  // Azul (derecha)

    // Barra horizontal azul para completar la 'G'
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - (arcThickness / 2),
        bounds.centerRight.dx + (arcThickness / 2) - (size.width / 75.0),
        bounds.centerRight.dy + (arcThickness / 2),
      ),
      paint
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.fill
        ..strokeWidth = 0,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
