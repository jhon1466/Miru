import 'dart:async';
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
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
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
    // Volver a crear PageController para resetear posición al cambiar eje
    final current = _currentPage;
    _pageController.dispose();
    _pageController = PageController(initialPage: current);
    _startControlsTimer();
  }

  void _registerProgress(int pageIndex) {
    final page = pageIndex + 1;
    // Guardar progreso en SharedPreferences (para el botón "Continuar leyendo" en detail screen)
    context.read<MangaProvider>().saveReadingProgress(
      widget.mangaId,
      widget.chapterId,
      widget.chapterNumber,
      page,
    );
    // Guardar en historial global (para la sección "Continuar leyendo" en el tab de Manga)
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
          // Lector de Páginas
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
                      onPressed: () {
                        mangaProvider.loadChapterPages(widget.chapterId, widget.mangaId);
                      },
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
            GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.translucent,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: _scrollDirection,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  _registerProgress(index);
                  if (_showControls) {
                    _startControlsTimer();
                  }
                },
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 3.5,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: pages[index],
                        httpHeaders: const {
                          'User-Agent': 'MiruApp/2.0.1 (Contact: support@miru.app)',
                        },
                        fit: BoxFit.contain,
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
                              Text('Error al cargar página', style: TextStyle(color: Colors.white30, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Barra Superior Flotante
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            top: _showControls ? 0 : -100,
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
                        Text(
                          'Capítulo ${widget.chapterNumber}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
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

          // Indicador de Progreso Inferior Flotante
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
                  pages.isEmpty
                      ? '0 / 0'
                      : '${_currentPage + 1} / ${pages.length}',
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
