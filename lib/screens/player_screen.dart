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
import '../providers/tv_provider.dart';
import 'detail_screen.dart';
import '../services/server_probe_service.dart';
import '../services/server_extractor_service.dart';

class PlayerScreen extends StatefulWidget {
  final String episodeUrl;
  final double episodeNumber;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;
  final String? focusCommentId;
  /// Lista de episodios del anime para la reproducción automática.
  final List<Episode> episodes;

  const PlayerScreen({
    super.key,
    required this.episodeUrl,
    required this.episodeNumber,
    required this.animeTitle,
    required this.animeUrl,
    this.animeImage = '',
    this.focusCommentId,
    this.episodes = const [],
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

  // Cacheado en el primer build para poder usarlo en dispose (sin contexto)
  bool _cachedIsTV = false;

  // Resultados del escaneo: embedUrl → ProbeResult
  final Map<String, ProbeResult> _probeResults = {};
  // URLs reales extraídas: embedUrl → directUrl
  final Map<String, String> _extractedUrls = {};
  bool _isScanning = false;
  bool _jsHandlerRegistered = false;

  @override
  void initState() {
    super.initState();
    // Detectar TV después del primer frame (cuando MediaQuery ya está disponible)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final mq = MediaQuery.of(context);
        _cachedIsTV = mq.navigationMode == NavigationMode.directional ||
            mq.size.shortestSide > 480;
        _unlockPlayerOrientations();
      }
      _loadEpisodeAndAutoplay();
    });
  }

  void _unlockPlayerOrientations() {
    if (_cachedIsTV) {
      unawaited(SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    } else {
      unawaited(SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
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
    // Usar el valor cacheado: nunca depende del contexto (ya puede estar muerto)
    if (_cachedIsTV) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _loadEpisodeAndAutoplay() async {
    final provider = context.read<AnimeProvider>();

    if (provider.selectedAnime == null || provider.selectedAnime!.title != widget.animeTitle) {
      unawaited(provider.loadAnimeDetails(widget.animeUrl));
    }

    await provider.loadEpisodeLinks(widget.episodeUrl);
    if (!mounted) return;

    final links = provider.episodeLinks;
    if (links == null) return;

    // Recopilar todas las URLs de stream disponibles
    final allServers = [
      ...links.subStream,
      ...links.dubStream,
    ];

    if (allServers.isEmpty) {
      final first = _firstPlayableLink(links, preferSub: true);
      if (first != null) _playServer(first.url, first.server, first.isSub, logHistory: false);
      return;
    }

    // Reproducir el primer servidor disponible inmediatamente para no quedar en blanco
    final firstAny = _firstPlayableLink(links, preferSub: true);
    if (firstAny != null) {
      _playServer(firstAny.url, firstAny.server, firstAny.isSub, logHistory: false);
    }

    // Escanear todos los servidores en paralelo buscando reproducción nativa
    _scanServers(allServers.map((s) => s.url).toList(), links);
  }

  /// Escanea todos los servidores usando extractores específicos.
  /// Primero verifica estáticamente, luego intenta extracción HTTP.
  Future<void> _scanServers(List<String> urls, EpisodeLinksResponse links) async {
    if (!mounted) return;
    setState(() => _isScanning = true);

    await Future.wait(urls.map((embedUrl) => _probeOne(embedUrl, links)));

    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _probeOne(String embedUrl, EpisodeLinksResponse links) async {
    if (!mounted) return;

    // 1. Verificación rápida estática
    final quick = ServerProbeService.quickCheck(embedUrl);
    if (quick == ProbeResult.native) {
      if (mounted) setState(() => _probeResults[embedUrl] = ProbeResult.native);
      _autoSwitchIfBetter(embedUrl, embedUrl, links);
      return;
    }

    // 2. Extracción HTTP específica por servidor
    try {
      final result = await ServerExtractorService.extract(embedUrl);
      if (!mounted) return;

      if (result != null && result.success) {
        final directUrl = result.url!;
        setState(() {
          _probeResults[embedUrl] = ProbeResult.native;
          _extractedUrls[embedUrl] = directUrl;
        });
        _autoSwitchIfBetter(embedUrl, directUrl, links);
        debugPrint('[Scan] ✅ $embedUrl → $directUrl');
      } else {
        if (mounted) setState(() => _probeResults[embedUrl] = ProbeResult.webview);
        debugPrint('[Scan] 🌐 $embedUrl: ${result?.error}');
      }
    } catch (e) {
      if (mounted) setState(() => _probeResults[embedUrl] = ProbeResult.webview);
    }
  }

  /// Cambia al servidor nativo si la extracción tuvo éxito.
  /// Solo cambia si es el servidor actualmente cargado O si aún no hay servidor nativo.
  void _autoSwitchIfBetter(String embedUrl, String directUrl, EpisodeLinksResponse links) {
    if (!mounted) return;

    final allServers = [...links.subStream, ...links.dubStream];
    final match = allServers.where((s) => s.url == embedUrl).firstOrNull;
    if (match == null) return;

    final isSub = links.subStream.any((s) => s.url == embedUrl);

    // Cambiar si:
    // 1. Este es el servidor actualmente activo y todavía está resolviendo/fallback
    // 2. O aún no hay ningún servidor activo
    final isCurrentServer = _originalEmbedUrl == embedUrl ||
        _selectedServerUrl == embedUrl || _selectedServerUrl == null;
    final needsSwitch = _useWebViewFallback || _isResolvingUrl || isCurrentServer;

    if (needsSwitch) {
      debugPrint('[AutoSwitch] ✅ Cambiando a nativo: $embedUrl → $directUrl');
      _playServer(directUrl, match.server, isSub, logHistory: false);
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

    // Guardar la URL embed original ANTES de resolverla
    final embedUrl = url;

    // Si ya tenemos una URL directa extraída para este embed, usarla
    final resolved = _extractedUrls[url];
    if (resolved != null && resolved.isNotEmpty) {
      url = resolved;
    }

    final isDirect = _isDirectMediaUrl(url);

    setState(() {
      _originalEmbedUrl = embedUrl; // Siempre guardar la URL embed, no la resuelta
      _selectedServerUrl = url;
      _selectedServerName = name;
      _isSub = isSub;
      _useWebViewFallback = false;
      _isResolvingUrl = !isDirect;
    });

    if (!isDirect) {
      // Cargar el URL en el webview persistente
      _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(embedUrl)));
      // Timeout: si no se resuelve en 20 segundos, mostrar WebView directamente
      _resolverTimeoutTimer = Timer(const Duration(seconds: 20), () {
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
    final embedUrl = _originalEmbedUrl ?? resolvedUrl;
    setState(() {
      _selectedServerUrl = resolvedUrl;
      _isResolvingUrl = false;
      _useWebViewFallback = false;
      // Marcar el servidor como nativo ahora que tenemos la URL directa
      _probeResults[embedUrl] = ProbeResult.native;
      _extractedUrls[embedUrl] = resolvedUrl;
    });
  }

  /// Inyecta hooks de XHR/fetch + MutationObserver para capturar la URL de video
  /// antes de que llegue al player (mucho más efectivo que onLoadResource solo).
  void _injectInterceptionJs(InAppWebViewController controller) {
    const js = r"""
      (function() {
        if (window.__miru_hooked) return;
        window.__miru_hooked = true;

        function send(url) {
          if (!url || typeof url !== 'string' || url.length < 12) return;
          if (url.startsWith('blob:') || url.startsWith('data:') || url.startsWith('about:')) return;
          var l = url.toLowerCase();
          if (l.match(/\.(m3u8|mp4|mkv|webm|ts|avi|flv)([?#&]|$)/) ||
              l.includes('/m3u8') || l.includes('/hls/') ||
              l.includes('/get_video') || l.includes('googleusercontent.com')) {
            try { window.flutter_inappwebview.callHandler('videoUrlFound', url); } catch(e) {}
          }
        }

        // Hook XMLHttpRequest.open
        var _xhrOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function() {
          try { if (arguments[1]) send(String(arguments[1])); } catch(e) {}
          return _xhrOpen.apply(this, arguments);
        };

        // Hook fetch
        var _fetch = window.fetch;
        if (_fetch) {
          window.fetch = function(input, init) {
            try {
              var u = typeof input === 'string' ? input
                    : (input instanceof Request ? input.url : String(input));
              send(u);
            } catch(e) {}
            return _fetch.apply(this, arguments);
          };
        }

        // Scan <video> y <source> existentes y futuros
        function scan() {
          try {
            document.querySelectorAll('video, source').forEach(function(el) {
              var s = el.src || el.getAttribute('src') || '';
              if (s && !s.startsWith('blob:')) send(s);
            });
          } catch(e) {}
        }

        // MutationObserver para detectar cambios en el DOM
        try {
          new MutationObserver(function() { scan(); }).observe(
            document.documentElement || document,
            { childList: true, subtree: true, attributes: true }
          );
        } catch(e) {}

        scan();
        [300, 800, 1500, 3000, 6000, 10000].forEach(function(t) {
          setTimeout(scan, t);
        });
      })();
    """;
    try {
      controller.evaluateJavascript(source: js);
    } catch (e) {
      debugPrint('[Interception] JS inject error: $e');
    }
  }

  void _extractVideoUrl(InAppWebViewController controller) {
    // La extracción principal ahora se hace via _injectInterceptionJs (XHR/fetch hooks).
    // Este método es un fallback de polling para videos con src directo.
    _jsExtractionTimer?.cancel();
    _jsExtractionTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      if (!mounted || !_isResolvingUrl) {
        timer.cancel();
        return;
      }
      try {
        final videoSrc = await controller.evaluateJavascript(source: """
          (function() {
            var video = document.querySelector('video');
            if (video && video.src && !video.src.startsWith('blob:') && !video.src.startsWith('about:') && video.src.length > 12) return video.src;
            var sources = document.querySelectorAll('source');
            for (var i = 0; i < sources.length; i++) {
              var s = sources[i].src;
              if (s && !s.startsWith('blob:') && s.length > 12) return s;
            }
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
    final mq = MediaQuery.of(context);
    final isTV = mq.navigationMode == NavigationMode.directional ||
        mq.size.shortestSide > 480;
    // Actualizar caché en cada build (mientras el contexto es válido)
    _cachedIsTV = isTV;
    // En TV siempre es landscape/fullscreen
    final isLandscape = isTV ||
        MediaQuery.of(context).orientation == Orientation.landscape;
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
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
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
        lower.contains('doodstream.com/e/') ||
        lower.contains('streamwish.to/e/') ||
        lower.contains('voe.sx/e/') ||
        lower.contains('filemoon.sx/e/') ||
        lower.contains('mixdrop.co/e/') ||
        lower.contains('streamtape.com/e/')) {
      return false;
    }

    // Si contiene mp4upload, solo es directo si tiene extensión de video o es descarga directa /d/
    if (lower.contains('mp4upload.com')) {
      final hasVideoExtension = lower.endsWith('.mp4') ||
                               lower.contains('.mp4?') ||
                               lower.contains('/d/');
      if (!hasVideoExtension) return false;
    }

    // Extensiones de video conocidas (con o sin query string)
    final extMatch = RegExp(r'\.(m3u8|mp4|mkv|webm|ts|avi|flv|ogv)([?#&]|$)').hasMatch(lower);
    if (extMatch) return true;

    // Rutas CDN comunes que no tienen extensión pero son streams directos
    if (lower.contains('/m3u8') ||     // /m3u8/hash, /m3u8?token=...
        lower.contains('/hls/') ||     // /hls/video.m3u8 o /hls/stream
        lower.contains('/dash/') ||    // MPEG-DASH
        lower.contains('/get_video') ||
        lower.contains('googleusercontent.com') ||
        lower.contains('/media/') && (lower.contains('cdn') || lower.contains('stream'))) {
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
        child: Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
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
              // Registrar handler UNA sola vez para recibir URLs de video desde JS
              if (!_jsHandlerRegistered) {
                _jsHandlerRegistered = true;
                controller.addJavaScriptHandler(
                  handlerName: 'videoUrlFound',
                  callback: (args) {
                    if (!mounted || args.isEmpty) return;
                    final url = args[0].toString().trim();
                    if (url.isEmpty || url.startsWith('blob:')) return;
                    if (_isResolvingUrl && !_useWebViewFallback && _isDirectMediaUrl(url)) {
                      debugPrint('[JS Hook] ✅ Video URL interceptada: $url');
                      _onUrlResolved(url);
                    }
                  },
                );
              }
            },
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllowFullscreen: true,
              useShouldOverrideUrlLoading: true,
              useShouldInterceptRequest: true, // Interceptar TODAS las peticiones (iframes, XHR, fetch)
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
              // Inyectar hooks XHR/fetch lo antes posible
              if (_isResolvingUrl && !_useWebViewFallback) {
                _injectInterceptionJs(controller);
              }
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
                // Inyectar hooks (refuerzo: la página ya cargó, re-hookear XHR/fetch)
                _injectInterceptionJs(controller);
                // Polling fallback para src directo en <video>
                _extractVideoUrl(controller);
              }
              // Solo aplicar limpieza cuando el WebView es visible al usuario
              if (_useWebViewFallback) {
                _injectPlayerCleanupJs(controller);
              }
            },
            shouldInterceptRequest: (controller, request) async {
              // Este callback intercepta TODAS las peticiones de red:
              // frame principal, iframes, XHR, fetch, media segments.
              // Es la forma más fiable de capturar la URL real del video.
              if (_isResolvingUrl && !_useWebViewFallback) {
                final url = request.url.toString();
                // Ignorar segmentos .ts individuales (evitar llamadas duplicadas)
                if (!url.endsWith('.ts') && !url.contains('.ts?') && _isDirectMediaUrl(url)) {
                  debugPrint('[Intercept] ✅ URL de video interceptada: $url');
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _isResolvingUrl && !_useWebViewFallback) {
                      _onUrlResolved(url);
                    }
                  });
                }
              }
              return null; // Dejar pasar la petición normalmente
            },
            onLoadResource: (controller, resource) {
              final resUrl = resource.url?.toString();
              if (resUrl != null) {
                if (_isResolvingUrl && !_useWebViewFallback && _isDirectMediaUrl(resUrl)) {
                  debugPrint('[Resource] ✅ $resUrl');
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
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
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
                      icon: Icon(Icons.web, color: Theme.of(context).colorScheme.secondary, size: 16),
                      label: Text(
                        'Usar Web Player',
                        style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
            Row(
              children: [
                Text(
                  'Servidores (${_isSub ? "SUB" : "DUB"})',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...currentStreamServers.map((server) {
              final isCurrent = _selectedServerUrl == server.url;
              final probe = _probeResults[server.url];
              final isNative = probe == ProbeResult.native;
              final isWebView = probe == ProbeResult.webview;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            server.server,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? Theme.of(context).colorScheme.primary : context.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: server.quality != null
                        ? Text(server.quality!, style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: isCurrent
                        ? Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.primary)
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
                  leading: Icon(Icons.download, color: Theme.of(context).colorScheme.secondary),
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
          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : context.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : context.textSecondary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Theme.of(context).colorScheme.primary : context.textSecondary,
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

    // Usar la lista de episodios pasada directamente; como fallback usar el provider
    List<Episode> allEpisodes = widget.episodes;
    if (allEpisodes.isEmpty) {
      final details = context.read<AnimeProvider>().selectedAnime;
      allEpisodes = details?.episodes ?? [];
    }
    if (allEpisodes.isEmpty) return;

    final sortedEpisodes = List<Episode>.from(allEpisodes)
      ..sort((a, b) => a.number.compareTo(b.number));

    final currentIndex = sortedEpisodes.indexWhere((ep) => ep.number == widget.episodeNumber);
    if (currentIndex == -1 || currentIndex >= sortedEpisodes.length - 1) return;

    _showAutoplayDialog(sortedEpisodes[currentIndex + 1]);
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
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
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
    // Propagar la lista de episodios para que el siguiente reproductor
    // también pueda usar la reproducción automática sin depender del provider
    final episodes = widget.episodes.isNotEmpty
        ? widget.episodes
        : (context.read<AnimeProvider>().selectedAnime?.episodes ?? []);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          episodeUrl: ep.url,
          episodeNumber: ep.number,
          animeTitle: widget.animeTitle,
          animeUrl: widget.animeUrl,
          animeImage: widget.animeImage,
          episodes: episodes,
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
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
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
