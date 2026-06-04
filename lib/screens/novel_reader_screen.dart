import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/novel.dart';
import '../providers/novel_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/novel_history_provider.dart';

enum ReaderTheme {
  dark,
  light,
  sepia,
}

class NovelReaderScreen extends StatefulWidget {
  final String novelId;
  final String novelTitle;
  final String novelUrl;
  final String novelCover;
  final NovelChapter chapter;
  final List<NovelChapter> allChapters;

  const NovelReaderScreen({
    super.key,
    required this.novelId,
    required this.novelTitle,
    required this.novelUrl,
    required this.novelCover,
    required this.chapter,
    required this.allChapters,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  double _fontSize = 16.0;
  ReaderTheme _theme = ReaderTheme.dark;
  final ScrollController _scrollController = ScrollController();
  bool _historyRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NovelProvider>().loadChapterContent(
        widget.chapter.url,
        novelId: widget.novelId,
        chapterId: widget.chapter.id,
      );
      _registerHistory();
    });
  }

  void _registerHistory() {
    if (_historyRegistered) return;
    _historyRegistered = true;

    final auth = context.read<app_auth.AuthProvider>();
    context.read<NovelHistoryProvider>().addToHistory(
          novelId: widget.novelId,
          novelTitle: widget.novelTitle,
          coverUrl: widget.novelCover,
          chapterId: widget.chapter.id,
          chapterTitle: widget.chapter.title,
          chapterNumber: widget.chapter.number,
          userId: auth.userId,
        );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeFontSize(bool increase) {
    setState(() {
      if (increase && _fontSize < 30) {
        _fontSize += 2.0;
      } else if (!increase && _fontSize > 12) {
        _fontSize -= 2.0;
      }
    });
  }

  void _setTheme(ReaderTheme targetTheme) {
    setState(() {
      _theme = targetTheme;
    });
  }

  Color _getBgColor(BuildContext context) {
    switch (_theme) {
      case ReaderTheme.dark:
        return const Color(0xFF0F172A);
      case ReaderTheme.light:
        return const Color(0xFFF8FAFC);
      case ReaderTheme.sepia:
        return const Color(0xFFFDF6E3);
    }
  }

  Color _getTextColor(BuildContext context) {
    switch (_theme) {
      case ReaderTheme.dark:
        return const Color(0xFFE2E8F0);
      case ReaderTheme.light:
        return const Color(0xFF1E293B);
      case ReaderTheme.sepia:
        return const Color(0xFF586E75);
    }
  }

  void _navigateToChapter(NovelChapter targetChapter) {
    // Guardar historial para el nuevo capítulo
    final auth = context.read<app_auth.AuthProvider>();
    context.read<NovelHistoryProvider>().addToHistory(
          novelId: widget.novelId,
          novelTitle: widget.novelTitle,
          coverUrl: widget.novelCover,
          chapterId: targetChapter.id,
          chapterTitle: targetChapter.title,
          chapterNumber: targetChapter.number,
          userId: auth.userId,
        );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => NovelReaderScreen(
          novelId: widget.novelId,
          novelTitle: widget.novelTitle,
          novelUrl: widget.novelUrl,
          novelCover: widget.novelCover,
          chapter: targetChapter,
          allChapters: widget.allChapters,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final isLoading = novelProvider.isLoadingContent;
    final error = novelProvider.contentError;
    final paragraphs = novelProvider.chapterParagraphs;

    // Navigation setup
    final sortedChapters = List<NovelChapter>.from(widget.allChapters)
      ..sort((a, b) => a.number.compareTo(b.number));
    final currentIndex =
        sortedChapters.indexWhere((c) => c.url == widget.chapter.url);

    final prevChapter =
        (currentIndex > 0) ? sortedChapters[currentIndex - 1] : null;
    final nextChapter =
        (currentIndex != -1 && currentIndex < sortedChapters.length - 1)
            ? sortedChapters[currentIndex + 1]
            : null;

    final bgColor = _getBgColor(context);
    final textColor = _getTextColor(context);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.novelTitle,
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.6), fontSize: 11),
                ),
                if (novelProvider.isContentOffline) ...[ 
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'OFFLINE',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              widget.chapter.title,
              style: TextStyle(
                  color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Font size buttons
          IconButton(
            icon: Icon(Icons.remove, color: textColor),
            onPressed: () => _changeFontSize(false),
            tooltip: 'Reducir letra',
          ),
          IconButton(
            icon: Icon(Icons.add, color: textColor),
            onPressed: () => _changeFontSize(true),
            tooltip: 'Aumentar letra',
          ),
          // Theme button
          PopupMenuButton<ReaderTheme>(
            icon: Icon(Icons.palette_rounded, color: textColor),
            onSelected: _setTheme,
            color: context.cardColor,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ReaderTheme.dark,
                child: Text('Modo Oscuro',
                    style: TextStyle(color: context.textPrimary)),
              ),
              PopupMenuItem(
                value: ReaderTheme.light,
                child: Text('Modo Claro',
                    style: TextStyle(color: context.textPrimary)),
              ),
              PopupMenuItem(
                value: ReaderTheme.sepia,
                child: Text('Modo Sepia',
                    style: TextStyle(color: context.textPrimary)),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.primaryColor),
              ),
            )
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: context.dangerColor),
                        const SizedBox(height: 16),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textColor),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => novelProvider
                              .loadChapterContent(widget.chapter.url, novelId: widget.novelId, chapterId: widget.chapter.id),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Progress bar capítulo
                    LinearProgressIndicator(
                      value: currentIndex >= 0
                          ? (currentIndex + 1) / sortedChapters.length
                          : 0,
                      backgroundColor:
                          textColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(
                          context.primaryColor.withValues(alpha: 0.7)),
                      minHeight: 2,
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: paragraphs.length + 1,
                          itemBuilder: (context, index) {
                            if (index == paragraphs.length) {
                              // Navigation row at bottom of content
                              return Padding(
                                padding: const EdgeInsets.only(top: 40.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (prevChapter != null)
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _navigateToChapter(prevChapter),
                                        icon: Icon(Icons.arrow_back,
                                            color: textColor),
                                        label: Text('Anterior',
                                            style:
                                                TextStyle(color: textColor)),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(
                                              color: textColor.withValues(
                                                  alpha: 0.3)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                    if (nextChapter != null)
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _navigateToChapter(nextChapter),
                                        icon: const Icon(Icons.arrow_forward,
                                            color: Colors.white),
                                        label: const Text('Siguiente',
                                            style: TextStyle(
                                                color: Colors.white)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              context.primaryColor,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                  ],
                                ),
                              );
                            }

                            final paragraph = paragraphs[index];
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 16.0),
                              child: Text(
                                paragraph,
                                style: TextStyle(
                                  fontSize: _fontSize,
                                  color: textColor,
                                  height: 1.6,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
