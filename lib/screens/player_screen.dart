import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../providers/history_provider.dart';
import '../models/anime.dart';
import '../widgets/comments_section.dart';

class PlayerScreen extends StatefulWidget {
  final String episodeUrl;
  final double episodeNumber;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;

  const PlayerScreen({
    super.key,
    required this.episodeUrl,
    required this.episodeNumber,
    required this.animeTitle,
    required this.animeUrl,
    required this.animeImage,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  String? _selectedServerUrl;
  String? _selectedServerName;
  bool _isSub = true; // SUB por defecto, si no hay cambia a DUB
  final GlobalKey _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Bloquear orientaciones verticales por defecto
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimeProvider>().loadEpisodeLinks(widget.episodeUrl).then((_) {
        // Seleccionar automáticamente el primer servidor disponible
        final links = context.read<AnimeProvider>().episodeLinks;
        if (links != null) {
          if (links.subStream.isNotEmpty) {
            _playServer(links.subStream.first.url, links.subStream.first.server, true);
          } else if (links.dubStream.isNotEmpty) {
            _playServer(links.dubStream.first.url, links.dubStream.first.server, false);
          } else if (links.subDownload.isNotEmpty) {
            _playServer(links.subDownload.first.url, links.subDownload.first.server, true);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    // Restaurar orientación vertical al salir del reproductor
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _playServer(String url, String name, bool isSub) {
    setState(() {
      _selectedServerUrl = url;
      _selectedServerName = name;
      _isSub = isSub;
    });

    // Registrar en el historial de reproducción
    Provider.of<HistoryProvider>(context, listen: false).addToHistory(
      animeUrl: widget.animeUrl,
      animeTitle: widget.animeTitle,
      animeImage: widget.animeImage,
      episodeNumber: widget.episodeNumber,
      episodeTitle: 'Episodio ${widget.episodeNumber.toString().replaceAll('.0', '')}',
      episodeUrl: widget.episodeUrl,
    );
  }

  Future<void> _launchExternalPlayer() async {
    if (_selectedServerUrl == null) return;
    
    final uri = Uri.parse(_selectedServerUrl!);
    
    // Alerta al usuario de que intentaremos lanzar el link externamente.
    // Si tienen VLC, MX Player o un navegador, podrán reproducirlo directamente
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir el reproductor externo. Copia el enlace en tu navegador.'),
              backgroundColor: AppTheme.dangerColor,
            ),
          );
        }
      }
    } catch (_) {
      // Fallback a navegador por defecto
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

    return Scaffold(
      backgroundColor: Colors.black, // Fondo ultra oscuro para modo cine
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          children: [
            Text(
              widget.animeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Text(
              'Episodio ${widget.episodeNumber.toString().replaceAll('.0', '')}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          
          if (isLandscape) {
            // En modo horizontal, el reproductor toma el 100% de la pantalla para máxima inmersión
            return _buildPlayerWidget();
          }

          // En modo vertical, mostramos el reproductor arriba y los controles/servidores abajo
          return Column(
            children: [
              // Área del Reproductor
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildPlayerWidget(),
              ),

              // Detalles, Servidores y Comentarios
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        color: AppTheme.darkBackground,
                        child: animeProvider.isLoadingEpisode
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
                                      SizedBox(height: 12),
                                      Text('Buscando servidores de video...', style: TextStyle(color: AppTheme.textSecondary)),
                                    ],
                                  ),
                                ),
                              )
                            : links == null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Text(
                                        animeProvider.episodeError ?? 'Error al cargar los servidores del episodio',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppTheme.textSecondary),
                                      ),
                                    ),
                                  )
                                : _buildServersSection(links),
                      ),
                      // Comentarios del Episodio
                      CommentsSection(
                        animeSlug: Uri.parse(widget.animeUrl).pathSegments.lastWhere(
                          (s) => s.isNotEmpty,
                          orElse: () => widget.animeUrl.hashCode.toString(),
                        ),
                        animeTitle: widget.animeTitle,
                        episodeNumber: widget.episodeNumber,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
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

    // Usar WebUri de flutter_inappwebview
    final webUri = WebUri(_selectedServerUrl!);
    final originalHost = Uri.parse(_selectedServerUrl!).host;

    return Stack(
      children: [
        InAppWebView(
          key: _webViewKey,
          initialUrlRequest: URLRequest(url: webUri),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useShouldOverrideUrlLoading: true,
            // Bloquear ventanas emergentes para evitar anuncios molestos
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri != null) {
              final newHost = uri.host;
              // Si la redirección intenta sacarnos del servidor de video original (bloqueo de publicidad popup)
              if (newHost != originalHost && 
                  !newHost.contains('google') && 
                  !newHost.contains('recaptcha') && 
                  !newHost.contains('jwplayer')) {
                return NavigationActionPolicy.CANCEL; // Cancelar redirección de anuncio
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onEnterFullscreen: (controller) async {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            await SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          },
          onExitFullscreen: (controller) async {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
            await SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
          },
        ),
        // Indicador discreto del servidor reproduciéndose (solo visible arriba a la izquierda si no está en fullscreen)
        Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Servidor: ${_selectedServerName ?? "Cargando..."}',
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServersSection(EpisodeLinksResponse data) {
    final hasSub = data.subStream.isNotEmpty || data.subDownload.isNotEmpty;
    final hasDub = data.dubStream.isNotEmpty || data.dubDownload.isNotEmpty;

    // Servidores actuales según idioma seleccionado
    final currentStreamServers = _isSub ? data.subStream : data.dubStream;
    final currentDownloadServers = _isSub ? data.subDownload : data.dubDownload;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila de acciones principales
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _launchExternalPlayer,
                  icon: const Icon(Icons.launch, size: 18),
                  label: const Text('Reproductor Externo'),
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
                  backgroundColor: AppTheme.cardColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.copy, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              '💡 Tip: Usa Reproductor Externo si tienes VLC o MX Player instalado para evitar publicidad',
              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ),
          
          const SizedBox(height: 24),
          // Selector de Idioma (Subtitulado vs Doblado)
          if (hasSub && hasDub) ...[
            const Text(
              'Idioma',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildLanguageButton('Subtitulado (SUB)', true),
                const SizedBox(width: 12),
                _buildLanguageButton('Doblado (DUB)', false),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Lista de Servidores Online
          if (currentStreamServers.isNotEmpty) ...[
            const Text(
              'Servidores de Streaming',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currentStreamServers.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final server = currentStreamServers[index];
                final isCurrent = _selectedServerUrl == server.url;
                return InkWell(
                  onTap: () => _playServer(server.url, server.server, _isSub),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent ? AppTheme.primaryColor.withOpacity(0.15) : AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? AppTheme.primaryColor : AppTheme.cardColor,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            server.server,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? AppTheme.primaryColor : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          if (server.quality != null)
                            Text(
                              server.quality!,
                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Lista de Servidores de Descarga
          if (currentDownloadServers.isNotEmpty) ...[
            const Text(
              'Enlaces de Descarga (Directo)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currentDownloadServers.length,
              itemBuilder: (context, index) {
                final server = currentDownloadServers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.download, color: AppTheme.accentColor),
                    title: Text(server.server, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(server.quality ?? 'Calidad HD', style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => launchUrl(Uri.parse(server.url), mode: LaunchMode.externalApplication),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageButton(String text, bool subFlag) {
    final isSelected = _isSub == subFlag;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _isSub = subFlag;
            // Seleccionar automáticamente primer servidor de esta variante
            final links = context.read<AnimeProvider>().episodeLinks;
            if (links != null) {
              final streamList = subFlag ? links.subStream : links.dubStream;
              final downloadList = subFlag ? links.subDownload : links.dubDownload;
              if (streamList.isNotEmpty) {
                _playServer(streamList.first.url, streamList.first.server, subFlag);
              } else if (downloadList.isNotEmpty) {
                _playServer(downloadList.first.url, downloadList.first.server, subFlag);
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withOpacity(0.2) : AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
