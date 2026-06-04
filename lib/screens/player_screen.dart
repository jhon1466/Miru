import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../models/anime.dart';
import '../widgets/comments_section.dart';
import '../widgets/episode_download_button.dart';
import '../widgets/native_video_player.dart';
import '../providers/connectivity_provider.dart';
import 'detail_screen.dart';

class PlayerScreen extends StatefulWidget {
  final String episodeUrl;
  final double episodeNumber;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;
  final String? focusCommentId;

  const PlayerScreen({
    super.key,
    required this.episodeUrl,
    required this.episodeNumber,
    required this.animeTitle,
    required this.animeUrl,
    this.animeImage = '',
    this.focusCommentId,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? _selectedServerUrl;
  String? _selectedServerName;
  bool _isSub = true;
  final _webViewKeepAlive = InAppWebViewKeepAlive();
  InAppWebViewController? _webViewController;

  // Resolutor de enlaces directos en segundo plano
  String? _originalEmbedUrl;
  bool _isResolvingUrl = false;
  bool _useWebViewFallback = false;
  Timer? _resolverTimeoutTimer;
  Timer? _jsExtractionTimer;

  @override
  void initState() {
    super.initState();
    _unlockPlayerOrientations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEpisodeAndAutoplay();
    });
  }

  void _unlockPlayerOrientations() {
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  /// Sin setState: evita recrear el WebView y congelar la app.
  Future<void> _onWebEnterFullscreen(InAppWebViewController controller) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _onWebExitFullscreen(InAppWebViewController controller) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _unlockPlayerOrientations();
  }

  Future<void> _restoreSystemUiAfterPlayer() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _loadEpisodeAndAutoplay() async {
    final provider = context.read<AnimeProvider>();
    
    // Cargar detalles del anime en segundo plano para conocer la lista de episodios
    if (provider.selectedAnime == null || provider.selectedAnime!.title != widget.animeTitle) {
      unawaited(provider.loadAnimeDetails(widget.animeUrl));
    }

    await provider.loadEpisodeLinks(widget.episodeUrl);
    if (!mounted) return;

    final links = provider.episodeLinks;
    if (links == null) return;

    final first = _firstPlayableLink(links, preferSub: true);
    if (first != null) {
      _playServer(first.url, first.server, first.isSub, logHistory: false);
    }
  }

  ({String url, String server, bool isSub})? _firstPlayableLink(
    EpisodeLinksResponse links, {
    required bool preferSub,
  }) {
    if (preferSub) {
      if (links.subStream.isNotEmpty) {
        return (url: links.subStream.first.url, server: links.subStream.first.server, isSub: true);
      }
      if (links.dubStream.isNotEmpty) {
        return (url: links.dubStream.first.url, server: links.dubStream.first.server, isSub: false);
      }
    } else {
      if (links.dubStream.isNotEmpty) {
        return (url: links.dubStream.first.url, server: links.dubStream.first.server, isSub: false);
      }
      if (links.subStream.isNotEmpty) {
        return (url: links.subStream.first.url, server: links.subStream.first.server, isSub: true);
      }
    }
    if (links.subDownload.isNotEmpty) {
      return (url: links.subDownload.first.url, server: links.subDownload.first.server, isSub: true);
    }
    if (links.dubDownload.isNotEmpty) {
      return (url: links.dubDownload.first.url, server: links.dubDownload.first.server, isSub: false);
    }
    return null;
  }

  @override
  void dispose() {
    _resolverTimeoutTimer?.cancel();
    _jsExtractionTimer?.cancel();
    _webViewController = null;
    unawaited(_restoreSystemUiAfterPlayer());
    super.dispose();
  }

  void _playServer(String url, String name, bool isSub, {bool logHistory = true}) {
    if (url.isEmpty) return;

    _resolverTimeoutTimer?.cancel();
    _jsExtractionTimer?.cancel();

    final isDirect = _isDirectMediaUrl(url);

    setState(() {
      _originalEmbedUrl = url;
      _selectedServerUrl = url;
      _selectedServerName = name;
      _isSub = isSub;
      _useWebViewFallback = false;
      _isResolvingUrl = !isDirect;
    });

    if (!isDirect) {
      _resolverTimeoutTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _isResolvingUrl) {
          setState(() {
            _isResolvingUrl = false;
            _useWebViewFallback = true;
          });
          // Inyectar JS de limpieza ahora que el WebView es visible
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _webViewController != null) {
              _injectPlayerCleanupJs(_webViewController!);
            }
          });
        }
      });
      // Cargar el URL en el webview persistente
      _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }

    if (logHistory) {
      final auth = context.read<app_auth.AuthProvider>();
      context.read<HistoryProvider>().addToHistory(
            animeUrl: widget.animeUrl,
            animeTitle: widget.animeTitle,
            animeImage: widget.animeImage,
            episodeNumber: widget.episodeNumber,
            episodeTitle: 'Episodio ${widget.episodeNumber.toString().replaceAll('.0', '')}',
            episodeUrl: widget.episodeUrl,
            userId: auth.userId,
          );
      if (AniListService.isConnected) {
        unawaited(AniListService.syncWatchProgress(widget.animeTitle, widget.episodeNumber));
      }
    }
  }

  void _onUrlResolved(String resolvedUrl) {
    _resolverTimeoutTimer?.cancel();
    _jsExtractionTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _selectedServerUrl = resolvedUrl;
      _isResolvingUrl = false;
      _useWebViewFallback = false;
    });
  }

  void _extractVideoUrl(InAppWebViewController controller) {
    _jsExtractionTimer?.cancel();
    _jsExtractionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted || !_isResolvingUrl) {
        timer.cancel();
        return;
      }
      try {
        final videoSrc = await controller.evaluateJavascript(source: """
          (function() {
            var video = document.querySelector('video');
            if (video && video.src && !video.src.startsWith('blob:') && !video.src.startsWith('about:')) return video.src;
            var source = document.querySelector('source');
            if (source && source.src && !source.src.startsWith('blob:') && !source.src.startsWith('about:')) return source.src;
            return '';
          })()
        """);
        if (videoSrc != null && videoSrc.toString().isNotEmpty) {
          final srcStr = videoSrc.toString().trim();
          if (_isDirectMediaUrl(srcStr)) {
            timer.cancel();
            _onUrlResolved(srcStr);
          }
        }
      } catch (_) {}
    });
  }

  /// Inyecta JS para limpiar anuncios y expandir el reproductor a pantalla completa en el WebView.
  /// Usa setTimeout escalonados en vez de setInterval para no interferir continuamente con el DOM.
  void _injectPlayerCleanupJs(InAppWebViewController controller) {
    const js = """
      (function() {
        function clean() {
          var video = document.querySelector('video');
          if (!video) return;
          var pc = video;
          while (pc && pc.parentElement && pc.parentElement.tagName !== 'BODY') {
            pc = pc.parentElement;
          }
          if (!pc) return;
          var ch = document.body.children;
          for (var i = 0; i < ch.length; i++) {
            var c = ch[i];
            var t = c.tagName;
            if (c !== pc && t !== 'SCRIPT' && t !== 'STYLE' && t !== 'LINK') {
              c.style.setProperty('display','none','important');
              c.style.setProperty('visibility','hidden','important');
              c.style.setProperty('pointer-events','none','important');
            }
          }
          pc.style.setProperty('position','fixed','important');
          pc.style.setProperty('top','0','important');
          pc.style.setProperty('left','0','important');
          pc.style.setProperty('width','100vw','important');
          pc.style.setProperty('height','100vh','important');
          pc.style.setProperty('z-index','999999','important');
          pc.style.setProperty('display','block','important');
          pc.style.setProperty('visibility','visible','important');
          video.style.setProperty('width','100%','important');
          video.style.setProperty('height','100%','important');
          video.style.setProperty('object-fit','contain','important');
        }
        // Intentar en varios momentos para cuando el player cargue tarde
        clean();
        setTimeout(clean, 500);
        setTimeout(clean, 1500);
        setTimeout(clean, 3000);
        setTimeout(clean, 6000);
      })();
    """;
    controller.evaluateJavascript(source: js);
  }

  Map<String, String> _buildHeaders() {
    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    
    try {
      final refererUrl = _originalEmbedUrl ?? _selectedServerUrl!;
      final refererUri = Uri.parse(refererUrl);
      headers['Referer'] = '${refererUri.scheme}://${refererUri.host}/';
      headers['Origin'] = '${refererUri.scheme}://${refererUri.host}';
    } catch (_) {
      if (widget.animeUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(widget.animeUrl);
          headers['Referer'] = '${uri.scheme}://${uri.host}/';
        } catch (_) {
          headers['Referer'] = widget.animeUrl;
        }
      }
    }
    return headers;
  }

  void _switchLanguage(bool subFlag, EpisodeLinksResponse links) {
    if (_isSub == subFlag) return;

    final streamList = subFlag ? links.subStream : links.dubStream;
    final downloadList = subFlag ? links.subDownload : links.dubDownload;

    if (streamList.isNotEmpty) {
      _playServer(streamList.first.url, streamList.first.server, subFlag);
      return;
    }
    if (downloadList.isNotEmpty) {
      _playServer(downloadList.first.url, downloadList.first.server, subFlag);
      return;
    }

    setState(() => _isSub = subFlag);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(subFlag ? 'No hay servidores SUB disponibles' : 'No hay servidores DUB disponibles'),
        backgroundColor: AppTheme.dangerColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchExternalPlayer() async {
    if (_selectedServerUrl == null) return;

    final uri = Uri.parse(_selectedServerUrl!);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el reproductor externo.'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  void _copyLinkToClipboard() {
    if (_selectedServerUrl == null) return;
    Clipboard.setData(ClipboardData(text: _selectedServerUrl!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace copiado al portapapeles'),
        backgroundColor: AppTheme.successColor,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = Provider.of<ConnectivityProvider>(context);
    final animeProvider = Provider.of<AnimeProvider>(context);
    final links = animeProvider.episodeLinks;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenSize = MediaQuery.of(context).size;
    // playerHeight fijo en el árbol: evita que NativeVideoPlayer se descarte al rotar
    final padding = MediaQuery.of(context).padding;
    final playerHeight = isLandscape
        ? (screenSize.height - padding.top - padding.bottom)
        : screenSize.width * 9 / 16;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_restoreSystemUiAfterPlayer());
      },
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: isLandscape
            ? null
            : AppBar(
                backgroundColor: context.backgroundColor,
                title: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DetailScreen(
                              animeUrl: widget.animeUrl,
                              animeTitle: widget.animeTitle,
                              animeImage: widget.animeImage,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        widget.animeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.primaryColor,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      'Episodio ${widget.episodeNumber.toString().replaceAll('.0', '')}',
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                  ],
                ),
                actions: [
                  if (links != null)
                    EpisodeDownloadButton(
                      episodeUrl: widget.episodeUrl,
                      episodeNumber: widget.episodeNumber,
                      animeTitle: widget.animeTitle,
                      animeUrl: widget.animeUrl,
                      animeImage: widget.animeImage,
                      preferSub: _isSub,
                      links: links,
                    ),
                ],
              ),
        // Player SIEMPRE como primer hijo de Column>SizedBox para preservar estado al rotar
        body: Column(
          children: [
            if (!isLandscape && !connectivity.isConnected)
              Container(
                width: double.infinity,
                color: AppTheme.dangerColor,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 8),
                    Text(
                      'Sin conexión a internet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: playerHeight,
              child: _buildPlayerWidget(),
            ),
            if (!isLandscape) _buildEpisodeNavigation(context),
            if (!isLandscape)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        color: context.backgroundColor,
                        width: double.infinity,
                        child: animeProvider.isLoadingEpisode
                            ? Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  children: [
                                    const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Buscando servidores de video...',
                                      style: TextStyle(color: context.textSecondary),
                                    ),
                                  ],
                                ),
                              )
                            : links == null
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      animeProvider.episodeError ?? 'Error al cargar servidores',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: context.textSecondary),
                                    ),
                                  )
                                : _buildServersPanel(links),
                      ),
                      CommentsSection(
                        animeSlug: Uri.parse(widget.animeUrl).pathSegments.lastWhere(
                              (s) => s.isNotEmpty,
                              orElse: () => widget.animeUrl.hashCode.toString(),
                            ),
                        animeTitle: widget.animeTitle,
                        animeUrl: widget.animeUrl,
                        episodeUrl: widget.episodeUrl,
                        episodeNumber: widget.episodeNumber,
                        focusCommentId: widget.focusCommentId,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // Ignorar urls de embed/iframe conocidas para que pasen por el resolutor
    if (lower.contains('/embed-') ||
        lower.contains('/embed/') ||
        lower.endsWith('.html') ||
        lower.contains('.html?') ||
        lower.contains('/e/') || // streamtape / streamwish / voe
        lower.contains('/v/') ||
        lower.contains('doodstream.com/e/') ||
        lower.contains('streamwish.to/e/') ||
        lower.contains('voe.sx/e/')) {
      return false;
    }

    // Si contiene mp4upload, solo es directo si tiene extensión de video o es descarga directa /d/
    if (lower.contains('mp4upload.com')) {
      final hasVideoExtension = lower.endsWith('.mp4') || 
                               lower.contains('.mp4?') ||
                               lower.contains('/d/');
      if (!hasVideoExtension) {
        return false;
      }
    }

    if (lower.contains('.mp4') ||
        lower.contains('.m3u8') ||
        lower.contains('/m3u8/') ||    // CDN paths like /m3u8/hash (ej: zilla-networks)
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('/get_video?') ||
        lower.contains('googleusercontent.com')) {
      return true;
    }
    return false;
  }

  String _getRootDomain(String host) {
    final parts = host.split('.');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
    }
    return host;
  }

  Widget _buildPlayerWidget() {
    if (_selectedServerUrl == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
        ),
      );
    }

    final isDirect = _isDirectMediaUrl(_selectedServerUrl!);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. El WebView (siempre en el árbol para evitar recrear la vista de plataforma y perder keepAlive)
        Positioned(
          left: _useWebViewFallback ? 0 : -2000,
          top: _useWebViewFallback ? 0 : -2000,
          right: _useWebViewFallback ? 0 : null,
          bottom: _useWebViewFallback ? 0 : null,
          width: _useWebViewFallback ? null : 1,
          height: _useWebViewFallback ? null : 1,
          child: InAppWebView(
            key: const ValueKey('player-webview'),
            keepAlive: _webViewKeepAlive,
            initialUrlRequest: URLRequest(url: WebUri(_originalEmbedUrl ?? _selectedServerUrl!)),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllowFullscreen: true,
              useShouldOverrideUrlLoading: true,
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: true,
              useHybridComposition: true,
              domStorageEnabled: true,
              contentBlockers: [
                // Bloquear scripts de dominios conocidos de publicidad y redirecciones
                ContentBlocker(
                  trigger: ContentBlockerTrigger(
                    urlFilter: ".*(slavirappels|slavir|onclickads|exoclick|juicyads|propellerads|popads|popmyads|adsterra|monetag|fastclick|clikstars|adkey|yandex|adnxs|doubleclick|adservice|googleadservices|googlesyndication|adskeeper|mgid|taboola|outbrain|bet365|1xbet).*\\.(js|html|css|php).*",
                  ),
                  action: ContentBlockerAction(
                    type: ContentBlockerActionType.BLOCK,
                  ),
                ),
                // Bloquear popups por recursos de tipo raw o script de terceros
                ContentBlocker(
                  trigger: ContentBlockerTrigger(
                    urlFilter: ".*\\.(pop|banner|ad|click).*\\.(js|html).*",
                  ),
                  action: ContentBlockerAction(
                    type: ContentBlockerActionType.BLOCK,
                  ),
                ),
              ],
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              // En modo fallback (el usuario ve el WebView), permitir TODA navegación
              // para no bloquear redirecciones que los reproductores necesitan
              if (_useWebViewFallback) return NavigationActionPolicy.ALLOW;
              final uri = navigationAction.request.url;
              if (uri != null) {
                final newHost = uri.host;
                final embedUrl = _originalEmbedUrl ?? _selectedServerUrl!;
                try {
                  final originalHost = Uri.parse(embedUrl).host;
                  final newRoot = _getRootDomain(newHost);
                  final originalRoot = _getRootDomain(originalHost);
                  if (newRoot == originalRoot ||
                      newHost.contains('google') ||
                      newHost.contains('recaptcha') ||
                      newHost.contains('jwplayer')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                } catch (_) {
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onCreateWindow: (controller, createWindowAction) async {
              return false; // Bloquea la creación de nuevas ventanas (popups de publicidad)
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint('WebView Console: ${consoleMessage.message}');
            },
            onReceivedError: (controller, request, error) {
              debugPrint('WebView Error: ${error.description} for ${request.url}');
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              debugPrint('WebView HTTP Error: ${errorResponse.statusCode} for ${request.url}');
            },
            onLoadStart: (controller, url) {
              debugPrint('WebView Load Start: $url');
            },
            onEnterFullscreen: (controller) {
              unawaited(_onWebEnterFullscreen(controller));
            },
            onExitFullscreen: (controller) {
              unawaited(_onWebExitFullscreen(controller));
            },
            onLoadStop: (controller, url) async {
              debugPrint('WebView Load Stop: $url');
              if (_isResolvingUrl && !_useWebViewFallback) {
                _extractVideoUrl(controller);
              }
              // Solo aplicar limpieza cuando el WebView es visible al usuario
              if (_useWebViewFallback) {
                _injectPlayerCleanupJs(controller);
              }
            },
            onLoadResource: (controller, resource) {
              final resUrl = resource.url?.toString();
              if (resUrl != null) {
                debugPrint('WebView Resource Loaded: $resUrl');
                if (_isResolvingUrl && !_useWebViewFallback && _isDirectMediaUrl(resUrl)) {
                  _onUrlResolved(resUrl);
                }
              }
            },
          ),
        ),

        // 2. El reproductor nativo (se dibuja encima si se tiene la URL directa resuelta)
        if (isDirect && !_useWebViewFallback)
          Positioned.fill(
            child: NativeVideoPlayer(
              key: ValueKey('native-player-$_selectedServerUrl'),
              url: _selectedServerUrl!,
              title: '${widget.animeTitle} - Ep. ${widget.episodeNumber.toString().replaceAll('.0', '')}',
              headers: _buildHeaders(),
              onVideoEnded: _handleVideoEnded,
              onErrorFallback: () {
                if (mounted) {
                  setState(() {
                    _isResolvingUrl = false;
                    _useWebViewFallback = true;
                  });
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (mounted && _webViewController != null) {
                      _injectPlayerCleanupJs(_webViewController!);
                    }
                  });
                }
              },
            ),
          ),

        // 3. El overlay de resolviendo (se dibuja encima mientras resuelve)
        if (_isResolvingUrl && !_useWebViewFallback)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Resolviendo enlace nativo en $_selectedServerName...',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        if (mounted) {
                          setState(() {
                            _isResolvingUrl = false;
                            _useWebViewFallback = true;
                          });
                          Future.delayed(const Duration(milliseconds: 400), () {
                            if (mounted && _webViewController != null) {
                              _injectPlayerCleanupJs(_webViewController!);
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.web, color: AppTheme.accentColor, size: 16),
                      label: const Text(
                        'Usar Web Player',
                        style: TextStyle(color: AppTheme.accentColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildServersPanel(EpisodeLinksResponse data, {VoidCallback? onSelected}) {
    final hasSub = data.subStream.isNotEmpty || data.subDownload.isNotEmpty;
    final hasDub = data.dubStream.isNotEmpty || data.dubDownload.isNotEmpty;
    final currentStreamServers = _isSub ? data.subStream : data.dubStream;
    final currentDownloadServers = _isSub ? data.subDownload : data.dubDownload;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _launchExternalPlayer,
                  icon: const Icon(Icons.launch, size: 18),
                  label: const Text('Reproductor externo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _copyLinkToClipboard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.cardColor,
                  foregroundColor: context.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Icon(Icons.copy, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Idioma',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (hasSub)
                Expanded(child: _buildLanguageButton('Subtitulado (SUB)', true, data, onSelected: onSelected)),
              if (hasSub && hasDub) const SizedBox(width: 12),
              if (hasDub)
                Expanded(child: _buildLanguageButton('Doblado (DUB)', false, data, onSelected: onSelected)),
            ],
          ),
          if (!hasSub && !hasDub)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No hay variantes de idioma disponibles.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
          if (currentStreamServers.isNotEmpty) ...[
            Text(
              'Servidores (${_isSub ? "SUB" : "DUB"})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 10),
            ...currentStreamServers.map((server) {
              final isCurrent = _selectedServerUrl == server.url;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isCurrent
                      ? AppTheme.primaryColor.withValues(alpha: 0.15)
                      : context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCurrent ? AppTheme.primaryColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    title: Text(
                      server.server,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? AppTheme.primaryColor : context.textPrimary,
                      ),
                    ),
                    subtitle: server.quality != null
                        ? Text(server.quality!, style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: isCurrent
                        ? const Icon(Icons.play_circle_fill, color: AppTheme.primaryColor)
                        : Icon(Icons.play_circle_outline, color: context.textSecondary),
                    onTap: () {
                      _playServer(server.url, server.server, _isSub);
                      onSelected?.call();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Reproduciendo en ${server.server}'),
                            duration: const Duration(seconds: 1),
                            backgroundColor: AppTheme.successColor,
                          ),
                        );
                      }
                    },
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
          if (currentDownloadServers.isNotEmpty) ...[
            Text(
              'Descarga directa',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 8),
            ...currentDownloadServers.map((server) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.download, color: AppTheme.accentColor),
                  title: Text(server.server, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(server.quality ?? 'HD', style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(Uri.parse(server.url), mode: LaunchMode.externalApplication),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageButton(
    String text,
    bool subFlag,
    EpisodeLinksResponse links, {
    VoidCallback? onSelected,
  }) {
    final isSelected = _isSub == subFlag;
    return InkWell(
      onTap: () {
        _switchLanguage(subFlag, links);
        onSelected?.call();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.2) : context.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : context.textSecondary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.primaryColor : context.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _handleVideoEnded() {
    final settings = context.read<SettingsProvider>();
    if (!settings.autoplayNextEpisode) return;

    final animeProvider = context.read<AnimeProvider>();
    final details = animeProvider.selectedAnime;
    if (details == null || details.episodes.isEmpty) return;

    final currentEpNum = widget.episodeNumber;
    Episode? nextEp;

    // Asegurarse de ordenar los episodios por número ascendentemente
    final sortedEpisodes = List<Episode>.from(details.episodes)
      ..sort((a, b) => a.number.compareTo(b.number));

    final currentIndex = sortedEpisodes.indexWhere((ep) => ep.number == currentEpNum);
    if (currentIndex != -1 && currentIndex < sortedEpisodes.length - 1) {
      nextEp = sortedEpisodes[currentIndex + 1];
    }

    if (nextEp != null) {
      _showAutoplayDialog(nextEp);
    }
  }

  void _showAutoplayDialog(Episode nextEp) {
    int countdown = 5;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown > 1) {
                setStateDialog(() {
                  countdown--;
                });
              } else {
                t.cancel();
                Navigator.pop(dialogContext); // Cerrar diálogo
                _playNextEpisode(nextEp); // Cargar siguiente episodio
              }
            });

            return AlertDialog(
              backgroundColor: context.cardColor,
              title: Text('Siguiente episodio', style: TextStyle(color: context.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reproduciendo ${nextEp.title} en $countdown segundos...',
                    style: TextStyle(color: context.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: countdown / 5.0,
                    color: AppTheme.primaryColor,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.pop(dialogContext); // Cancelar reproducción automática
                  },
                  child: const Text('Cancelar', style: TextStyle(color: AppTheme.dangerColor)),
                ),
                ElevatedButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.pop(dialogContext); // Reproducir de inmediato
                    _playNextEpisode(nextEp);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  child: const Text('Reproducir ahora'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _playEpisode(Episode ep) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          episodeUrl: ep.url,
          episodeNumber: ep.number,
          animeTitle: widget.animeTitle,
          animeUrl: widget.animeUrl,
          animeImage: widget.animeImage,
        ),
      ),
    );
  }

  void _playNextEpisode(Episode nextEp) {
    _playEpisode(nextEp);
  }

  Widget _buildEpisodeNavigation(BuildContext context) {
    final animeProvider = Provider.of<AnimeProvider>(context);
    final details = animeProvider.selectedAnime;
    final isLoading = animeProvider.isLoadingDetails;

    final isCorrectAnime = details != null && details.title == widget.animeTitle;

    if (isLoading || !isCorrectAnime) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        color: context.backgroundColor,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ),
        ),
      );
    }

    if (details.episodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedEpisodes = List<Episode>.from(details.episodes)
      ..sort((a, b) => a.number.compareTo(b.number));

    var currentIndex = sortedEpisodes.indexWhere((ep) => ep.url == widget.episodeUrl);
    if (currentIndex == -1) {
      currentIndex = sortedEpisodes.indexWhere((ep) => ep.number == widget.episodeNumber);
    }

    final previousEp = (currentIndex > 0) ? sortedEpisodes[currentIndex - 1] : null;
    final nextEp = (currentIndex != -1 && currentIndex < sortedEpisodes.length - 1)
        ? sortedEpisodes[currentIndex + 1]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: context.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: context.textSecondary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botón Anterior
          Expanded(
            child: previousEp != null
                ? OutlinedButton.icon(
                    onPressed: () => _playEpisode(previousEp),
                    icon: const Icon(Icons.skip_previous, size: 20),
                    label: Text(
                      'Ep. ${previousEp.number.toString().replaceAll('.0', '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.textPrimary,
                      side: BorderSide(color: context.textSecondary.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : Opacity(
                    opacity: 0.3,
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.skip_previous, size: 20),
                      label: const Text('Anterior', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Botón Lista / Info
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DetailScreen(
                    animeUrl: widget.animeUrl,
                    animeTitle: widget.animeTitle,
                    animeImage: widget.animeImage,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.list, size: 18, color: context.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    'Lista',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Botón Siguiente
          Expanded(
            child: nextEp != null
                ? ElevatedButton.icon(
                    onPressed: () => _playEpisode(nextEp),
                    icon: const Icon(Icons.skip_next, size: 20),
                    label: Text(
                      'Ep. ${nextEp.number.toString().replaceAll('.0', '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : Opacity(
                    opacity: 0.3,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.skip_next, size: 20),
                      label: const Text('Siguiente', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
