import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../providers/manga_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/auth_provider.dart' as app_auth;

/// Modos de lectura disponibles.
enum _ReadMode {
  webtoon,     // scroll continuo vertical, ancho completo (manhwa)
  vertical,    // paginado vertical (manga japonés)
  horizontal,  // paginado horizontal
}

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
  // ── Paged mode ────────────────────────────────────────────────────────────
  late PageController _pageController;
  bool _pageViewScrollEnabled = true;

  // ── Webtoon mode ──────────────────────────────────────────────────────────
  final ScrollController _webtoonController = ScrollController();
  bool _webtoonScrollEnabled = true;

  // ── Shared ────────────────────────────────────────────────────────────────
  int _currentPage = 0;
  bool _showControls = true;
  Timer? _controlsTimer;
  _ReadMode _readMode = _ReadMode.webtoon; // por defecto webtoon

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
    _webtoonController.dispose();
    super.dispose();
  }

  // ── Controls timer ────────────────────────────────────────────────────────
  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startControlsTimer();
    else _controlsTimer?.cancel();
  }

  // ── Mode cycling ──────────────────────────────────────────────────────────
  void _cycleReadMode() {
    setState(() {
      switch (_readMode) {
        case _ReadMode.webtoon:
          _readMode = _ReadMode.vertical;
          final cur = _currentPage;
          _pageController.dispose();
          _pageController = PageController(initialPage: cur);
        case _ReadMode.vertical:
          _readMode = _ReadMode.horizontal;
          final cur = _currentPage;
          _pageController.dispose();
          _pageController = PageController(initialPage: cur);
        case _ReadMode.horizontal:
          _readMode = _ReadMode.webtoon;
      }
    });
    _startControlsTimer();
  }

  IconData get _modeIcon {
    switch (_readMode) {
      case _ReadMode.webtoon:    return Icons.view_day_rounded;
      case _ReadMode.vertical:   return Icons.swap_vert_rounded;
      case _ReadMode.horizontal: return Icons.swap_horiz_rounded;
    }
  }

  String get _modeTooltip {
    switch (_readMode) {
      case _ReadMode.webtoon:    return 'Modo: Webtoon (continuo)';
      case _ReadMode.vertical:   return 'Modo: Paginado vertical';
      case _ReadMode.horizontal: return 'Modo: Paginado horizontal';
    }
  }

  // ── Progress ──────────────────────────────────────────────────────────────
  void _registerProgress(int pageIndex) {
    final page = pageIndex + 1;
    context.read<MangaProvider>().saveReadingProgress(
      widget.mangaId, widget.chapterId, widget.chapterNumber, page,
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mangaProvider = Provider.of<MangaProvider>(context);
    final pages = mangaProvider.chapterPages;
    final isLoading = mangaProvider.isLoadingPages;
    final error = mangaProvider.pagesError;
    final isOffline = mangaProvider.isPagesOffline;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Content ──────────────────────────────────────────────────────
          if (isLoading)
            Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
            ))
          else if (error != null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
                  const SizedBox(height: 12),
                  Text(error, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => mangaProvider.loadChapterPages(widget.chapterId, widget.mangaId),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ))
          else if (pages.isEmpty)
            const Center(child: Text(
              'No hay páginas disponibles para este capítulo.',
              style: TextStyle(color: Colors.white70),
            ))
          else if (_readMode == _ReadMode.webtoon)
            _buildWebtoon(pages, isOffline)
          else
            _buildPaged(pages, isOffline),

          // ── Top bar ───────────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            top: _showControls ? 0 : -110,
            left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 12, left: 8, right: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
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
                        Text(widget.mangaTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Row(children: [
                          Text('Capítulo ${widget.chapterNumber}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          if (isOffline) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('SIN CONEXIÓN',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  // Mode toggle
                  IconButton(
                    icon: Icon(_modeIcon, color: Colors.white),
                    tooltip: _modeTooltip,
                    onPressed: _cycleReadMode,
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom page indicator ─────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            bottom: _showControls ? 20 : -60,
            left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                pages.isEmpty ? '0 / 0' : '${_currentPage + 1} / ${pages.length}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            )),
          ),
        ],
      ),
    );
  }

  // ── Webtoon reader (continuous vertical scroll) ───────────────────────────
  Widget _buildWebtoon(List<String> pages, bool isOffline) {
    return GestureDetector(
      onTap: _toggleControls,
      child: ListView.builder(
        controller: _webtoonController,
        physics: _webtoonScrollEnabled
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: pages.length + 1, // +1 bottom padding
        itemBuilder: (context, index) {
          if (index == pages.length) return const SizedBox(height: 80);
          return _WebtoonPageItem(
            key: ValueKey('webtoon_$index'),
            imageUrl: isOffline ? '' : pages[index],
            localPath: isOffline ? pages[index] : null,
            onVisible: () {
              if (_currentPage != index) {
                setState(() => _currentPage = index);
                _registerProgress(index);
              }
            },
            onZoomChanged: (zoomed) {
              if (_webtoonScrollEnabled == zoomed) {
                setState(() => _webtoonScrollEnabled = !zoomed);
              }
            },
          );
        },
      ),
    );
  }

  // ── Paged reader (vertical or horizontal PageView) ────────────────────────
  Widget _buildPaged(List<String> pages, bool isOffline) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: _readMode == _ReadMode.vertical ? Axis.vertical : Axis.horizontal,
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
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Webtoon page item: full-width image with pinch-to-zoom
// ═════════════════════════════════════════════════════════════════════════════
class _WebtoonPageItem extends StatefulWidget {
  final String imageUrl;
  final String? localPath;
  final VoidCallback onVisible;
  final ValueChanged<bool> onZoomChanged;

  const _WebtoonPageItem({
    super.key,
    required this.imageUrl,
    this.localPath,
    required this.onVisible,
    required this.onZoomChanged,
  });

  @override
  State<_WebtoonPageItem> createState() => _WebtoonPageItemState();
}

class _WebtoonPageItemState extends State<_WebtoonPageItem> {
  final TransformationController _transform = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
      widget.onZoomChanged(_isZoomed);
    }
  }

  void _resetZoom() {
    setState(() => _transform.value = Matrix4.identity());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return VisibilityDetectorWrapper(
      onVisible: widget.onVisible,
      child: GestureDetector(
        onDoubleTapDown: (details) {
          if (_isZoomed) {
            _resetZoom();
          } else {
            final renderBox = context.findRenderObject() as RenderBox?;
            if (renderBox == null) return;
            final local = renderBox.globalToLocal(details.globalPosition);
            final tx = -(local.dx * 2.0 - renderBox.size.width / 2.0);
            final ty = -(local.dy * 2.0 - renderBox.size.height / 2.0);
            final matrix = Matrix4.diagonal3Values(2.0, 2.0, 1.0)
              ..setTranslationRaw(tx, ty, 0);
            setState(() => _transform.value = matrix);
          }
        },
        onDoubleTap: () {},
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: _isZoomed,   // solo panea cuando hay zoom; deja pasar scroll al ListView
          scaleEnabled: true,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: screenWidth,
            child: _buildImage(screenWidth),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(double width) {
    final errorWidget = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.broken_image, color: Colors.white30, size: 40),
          SizedBox(height: 8),
          Text('Error al cargar página', style: TextStyle(color: Colors.white30, fontSize: 12)),
        ]),
      ),
    );

    if (widget.localPath != null) {
      return Image.file(
        File(widget.localPath!),
        width: width,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => errorWidget,
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      httpHeaders: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
        'Referer': 'https://zonatmo.org/',
        'Origin': 'https://zonatmo.org',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      },
      width: width,
      fit: BoxFit.fitWidth,
      placeholder: (context, url) => SizedBox(
        width: width,
        height: width * 1.4, // aprox. aspecto manhwa mientras carga
        child: const Center(child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.white30),
        )),
      ),
      errorWidget: (_, __, ___) => errorWidget,
    );
  }
}

// ─── Simple visibility wrapper (sin paquete externo) ─────────────────────────
/// Llama a [onVisible] cuando el widget entra en el viewport por primera vez.
class VisibilityDetectorWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onVisible;
  const VisibilityDetectorWrapper({super.key, required this.child, required this.onVisible});

  @override
  State<VisibilityDetectorWrapper> createState() => _VisibilityDetectorWrapperState();
}

class _VisibilityDetectorWrapperState extends State<VisibilityDetectorWrapper> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    if (!_reported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final position = box.localToGlobal(Offset.zero);
        final screen = MediaQuery.of(context).size;
        final isVisible = position.dy < screen.height && position.dy + box.size.height > 0;
        if (isVisible && !_reported) {
          _reported = true;
          widget.onVisible();
        }
      });
    }
    return widget.child;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Paged mode: one page at a time with zoom
// ═════════════════════════════════════════════════════════════════════════════
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
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
      widget.onZoomChanged(_isZoomed);
    }
  }

  void _resetZoom() {
    setState(() => _transformController.value = Matrix4.identity());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isZoomed ? null : widget.onTap,
      onDoubleTapDown: (details) {
        if (_isZoomed) {
          _resetZoom();
        } else {
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;
          final local = renderBox.globalToLocal(details.globalPosition);
          final tx = -(local.dx * 2.0 - renderBox.size.width / 2.0);
          final ty = -(local.dy * 2.0 - renderBox.size.height / 2.0);
          final matrix = Matrix4.diagonal3Values(2.0, 2.0, 1.0)
            ..setTranslationRaw(tx, ty, 0);
          setState(() => _transformController.value = matrix);
        }
      },
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 5.0,
        boundaryMargin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        panEnabled: true,
        scaleEnabled: true,
        child: Center(
          child: widget.localPath != null
              ? Image.file(
                  File(widget.localPath!),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white30, size: 40),
                      SizedBox(height: 8),
                      Text('Error al cargar página', style: TextStyle(color: Colors.white30, fontSize: 12)),
                    ],
                  )),
                )
              : CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  httpHeaders: const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
                    'Referer': 'https://zonatmo.org/',
                    'Origin': 'https://zonatmo.org',
                    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                  },
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white30),
                  )),
                  errorWidget: (context, url, err) => const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white30, size: 40),
                      SizedBox(height: 8),
                      Text('Error al cargar página', style: TextStyle(color: Colors.white30, fontSize: 12)),
                    ],
                  )),
                ),
        ),
      ),
    );
  }
}
