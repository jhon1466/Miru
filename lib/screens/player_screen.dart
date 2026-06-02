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
import '../models/anime.dart';
import '../widgets/comments_section.dart';
import '../widgets/episode_download_button.dart';
import '../widgets/native_video_player.dart';

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
    _webViewController = null;
    unawaited(_restoreSystemUiAfterPlayer());
    super.dispose();
  }

  void _playServer(String url, String name, bool isSub, {bool logHistory = true}) {
    if (url.isEmpty) return;

    setState(() {
      _selectedServerUrl = url;
      _selectedServerName = name;
      _isSub = isSub;
    });

    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

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
    }
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
    final animeProvider = Provider.of<AnimeProvider>(context);
    final links = animeProvider.episodeLinks;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_restoreSystemUiAfterPlayer());
      },
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          title: Column(
            children: [
              Text(
                widget.animeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: context.textPrimary, fontWeight: FontWeight.bold),
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
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildPlayerWidget(),
            ),

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
    final lower = url.toLowerCase();
    if (lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('googleusercontent.com')) {
      return true;
    }
    return false;
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

    if (_isDirectMediaUrl(_selectedServerUrl!)) {
      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
      
      try {
        final serverUri = Uri.parse(_selectedServerUrl!);
        headers['Referer'] = '${serverUri.scheme}://${serverUri.host}/';
        headers['Origin'] = '${serverUri.scheme}://${serverUri.host}';
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

      return NativeVideoPlayer(
        key: ValueKey('native-player-$_selectedServerUrl'),
        url: _selectedServerUrl!,
        title: '${widget.animeTitle} - Ep. ${widget.episodeNumber.toString().replaceAll('.0', '')}',
        headers: headers,
      );
    }

    final webUri = WebUri(_selectedServerUrl!);
    final originalHost = Uri.parse(_selectedServerUrl!).host;

    return Stack(
      children: [
        InAppWebView(
          key: const ValueKey('player-webview'),
          keepAlive: _webViewKeepAlive,
          initialUrlRequest: URLRequest(url: webUri),
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
            supportMultipleWindows: false,
            useHybridComposition: true,
            domStorageEnabled: true,
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri != null) {
              final newHost = uri.host;
              if (newHost != originalHost &&
                  !newHost.contains('google') &&
                  !newHost.contains('recaptcha') &&
                  !newHost.contains('jwplayer')) {
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onEnterFullscreen: (controller) {
            unawaited(_onWebEnterFullscreen(controller));
          },
          onExitFullscreen: (controller) {
            unawaited(_onWebExitFullscreen(controller));
          },
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
}
