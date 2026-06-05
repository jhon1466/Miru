import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../providers/manga_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/auth_provider.dart' as app_auth;

class MangaReaderScreen extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;
  final String chapterId;
  final String chapterNumber;
  final String coverUrl;
  final int startPage;

  const MangaReaderScreen({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterId,
    required this.chapterNumber,
    this.coverUrl = '',
    this.startPage = 1,
  });

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _showControls = true;
  Timer? _controlsTimer;
  Axis _scrollDirection = Axis.vertical;

  // Controla si el PageView puede desplazarse (false cuando hay zoom activo)
  bool _pageViewScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.startPage - 1;
    _pageController = PageController(initialPage: _currentPage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MangaProvider>().loadChapterPages(widget.chapterId, widget.mangaId);
      _startControlsTimer();
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _toggleScrollDirection() {
    setState(() {
      _scrollDirection = _scrollDirection == Axis.vertical ? Axis.horizontal : Axis.vertical;
    });
    final current = _currentPage;
    _pageController.dispose();
    _pageController = PageController(initialPage: current);
    _startControlsTimer();
  }

  void _registerProgress(int pageIndex) {
    final page = pageIndex + 1;
    context.read<MangaProvider>().saveReadingProgress(
      widget.mangaId,
      widget.chapterId,
      widget.chapterNumber,
      page,
    );
    final authProvider = context.read<app_auth.AuthProvider>();
    context.read<MangaHistoryProvider>().addToHistory(
      mangaId: widget.mangaId,
      mangaTitle: widget.mangaTitle,
      coverUrl: widget.coverUrl,
      chapterId: widget.chapterId,
      chapterNumber: widget.chapterNumber,
      page: page,
      userId: authProvider.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mangaProvider = Provider.of<MangaProvider>(context);
    final pages = mangaProvider.chapterPages;
    final isLoading = mangaProvider.isLoadingPages;
    final error = mangaProvider.pagesError;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Lector de Páginas ──────────────────────────────────────────
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
            )
          else if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => mangaProvider.loadChapterPages(widget.chapterId, widget.mangaId),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else if (pages.isEmpty)
            const Center(
              child: Text(
                'No hay páginas disponibles para este capítulo.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: _scrollDirection,
              // Deshabilitar el scroll del PageView cuando hay zoom activo
              physics: _pageViewScrollEnabled
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: pages.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
                _registerProgress(index);
                if (_showControls) _startControlsTimer();
              },
              itemBuilder: (context, index) {
                final isOffline = mangaProvider.isPagesOffline;
                return _ZoomablePage(
                  imageUrl: isOffline ? '' : pages[index],
                  localPath: isOffline ? pages[index] : null,
                  onTap: _toggleControls,
                  onZoomChanged: (isZoomed) {
                    if (_pageViewScrollEnabled == isZoomed) {
                      setState(() => _pageViewScrollEnabled = !isZoomed);
                    }
                  },
                );
              },
            ),

          // ── Barra Superior Flotante ────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            top: _showControls ? 0 : -110,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 12,
                left: 8,
                right: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'Capítulo ${widget.chapterNumber}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            if (mangaProvider.isPagesOffline) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'SIN CONEXIÓN',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _scrollDirection == Axis.vertical
                          ? Icons.swap_vert_rounded
                          : Icons.swap_horiz_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Cambiar orientación',
                    onPressed: _toggleScrollDirection,
                  ),
                ],
              ),
            ),
          ),

          // ── Indicador de Progreso Inferior ────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            bottom: _showControls ? 20 : -60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  pages.isEmpty ? '0 / 0' : '${_currentPage + 1} / ${pages.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget de página individual con zoom mediante InteractiveViewer.
/// Notifica al padre cuando el zoom está activo para pausar el PageView.
class _ZoomablePage extends StatefulWidget {
  final String imageUrl;
  final String? localPath;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePage({
    required this.imageUrl,
    this.localPath,
    required this.onTap,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _transformController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    // Escala 1.0 = sin zoom. Cualquier valor mayor = zoom activo.
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
      widget.onZoomChanged(_isZoomed);
    }
  }

  void _resetZoom() {
    setState(() {
      _transformController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap simple alterna controles (solo si no hay zoom activo)
      onTap: _isZoomed ? null : widget.onTap,
      // Doble tap: resetea el zoom si está activo, o acerca al 2x si no
      onDoubleTapDown: (details) {
        if (_isZoomed) {
          _resetZoom();
        } else {
          // Calcular punto de doble tap y hacer zoom 2x centrado ahí
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          final local = renderBox.globalToLocal(details.globalPosition);
          final x = local.dx;
          final y = local.dy;
          final w = renderBox.size.width;
          final h = renderBox.size.height;

          final tx = -(x * 2.0 - w / 2.0);
          final ty = -(y * 2.0 - h / 2.0);
          final matrix = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
          matrix.setTranslationRaw(tx, ty, 0);
          setState(() {
            _transformController.value = matrix;
          });
        }
      },
      onDoubleTap: () {}, // necesario para activar onDoubleTapDown
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 5.0,
        // Restringir el margen para que no flote fuera de la pantalla
        boundaryMargin: EdgeInsets.zero,
        // Recortar bordes para evitar superposición con otras páginas del PageView
        clipBehavior: Clip.hardEdge,
        // Habilitar el desplazamiento interno cuando hay zoom
        panEnabled: true,
        scaleEnabled: true,
        child: Center(
          child: widget.localPath != null
              ? Image.file(
                  File(widget.localPath!),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white30, size: 40),
                        SizedBox(height: 8),
                        Text('Error al cargar página', style: TextStyle(color: Colors.white30, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  httpHeaders: const {
                    'User-Agent': 'MiruApp/2.0.7 (Contact: support@miru.app)',
                  },
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white30),
                    ),
                  ),
                  errorWidget: (context, url, err) => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white30, size: 40),
                        SizedBox(height: 8),
                        Text(
                          'Error al cargar página',
                          style: TextStyle(color: Colors.white30, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
