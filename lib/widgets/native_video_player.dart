import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import '../core/theme.dart';
import 'cast_picker.dart';

class NativeVideoPlayer extends StatefulWidget {
  final String url;
  final String title;
  final Map<String, String>? headers;
  final VoidCallback? onVideoEnded;
  final VoidCallback? onErrorFallback;

  const NativeVideoPlayer({
    super.key,
    required this.url,
    required this.title,
    this.headers,
    this.onVideoEnded,
    this.onErrorFallback,
  });

  @override
  State<NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<NativeVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  
  bool _showControls = true;
  Timer? _controlsTimer;
  
  bool _isFullscreen = false;
  double _playbackSpeed = 1.0;
  BoxFit _videoFit = BoxFit.contain;

  // Double tap ripple indicators
  bool _showLeftDoubleTap = false;
  bool _showRightDoubleTap = false;

  bool _endedTriggered = false;

  // Gestos de arrastre (brillo y volumen)
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  Timer? _indicatorTimer;

  bool _isLocked = false;

  static const _channel = MethodChannel('com.anime1v.app/foreground_service');

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startControlsTimer();
    // Evitar que la pantalla se apague durante la reproducción
    _channel.invokeMethod('keepScreenOn').catchError((_) {});

    // Inicializar volumen y brillo actuales de forma segura
    try {
      VolumeController().getVolume().then((v) {
        if (mounted) _volume = v;
      });
    } catch (_) {}
    try {
      ScreenBrightness().current.then((b) {
        if (mounted) _brightness = b;
      });
    } catch (_) {}
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      if (widget.url.startsWith('http://') || widget.url.startsWith('https://')) {
        final uri = Uri.parse(widget.url);
        // Detectar HLS aunque la URL no tenga extensión .m3u8
        // (ej: /m3u8/hash, /hls/hash en CDNs como zilla-networks)
        final lower = widget.url.toLowerCase();
        final isHls = lower.contains('.m3u8') ||
            lower.contains('/m3u8/') ||
            lower.contains('/hls/');
        _controller = VideoPlayerController.networkUrl(
          uri,
          httpHeaders: widget.headers ?? const <String, String>{},
          formatHint: isHls ? VideoFormat.hls : VideoFormat.other,
        );
      } else {
        final path = widget.url.startsWith('file://')
            ? Uri.parse(widget.url).toFilePath()
            : widget.url;
        _controller = VideoPlayerController.file(File(path));
      }
      
      await _controller!.initialize();
      _controller!.addListener(_playerListener);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        await _controller!.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
        // Auto-fallback al WebView si el reproductor nativo falla al inicializar
        if (widget.onErrorFallback != null) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && _hasError) {
              widget.onErrorFallback!();
            }
          });
        }
      }
    }
  }

  void _playerListener() {
    if (_controller != null && _controller!.value.hasError) {
      if (!_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = _controller!.value.errorDescription ?? 'Error de reproducción';
        });
        // Auto-fallback al WebView si el reproductor falla durante la reproducción
        if (widget.onErrorFallback != null) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && _hasError) {
              widget.onErrorFallback!();
            }
          });
        }
      }
    } else if (_controller != null) {
      final value = _controller!.value;
      if (_isInitialized && 
          value.duration > Duration.zero &&
          value.position >= value.duration && 
          !_endedTriggered) {
        _endedTriggered = true;
        if (widget.onVideoEnded != null) {
          widget.onVideoEnded!();
        }
      }
      setState(() {});
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    if (_showControls) {
      // Si ya están visibles → ocultar inmediatamente
      _controlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      // Si están ocultos → mostrar y arrancar timer
      setState(() => _showControls = true);
      if (_isLocked) {
        _controlsTimer?.cancel();
        _controlsTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showControls = false);
        });
      } else {
        _startControlsTimer();
      }
    }
  }

  void _onDoubleTapLeft() {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final target = current - const Duration(seconds: 10);
    _controller!.seekTo(target < Duration.zero ? Duration.zero : target);
    
    setState(() {
      _showLeftDoubleTap = true;
      _showControls = true;
    });
    _startControlsTimer();
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showLeftDoubleTap = false);
    });
  }

  void _onDoubleTapRight() {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final max = _controller!.value.duration;
    final target = current + const Duration(seconds: 10);
    _controller!.seekTo(target > max ? max : target);
    
    setState(() {
      _showRightDoubleTap = true;
      _showControls = true;
    });
    _startControlsTimer();
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showRightDoubleTap = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    final newFullscreen = !_isFullscreen;
    setState(() {
      _isFullscreen = newFullscreen;
      _showControls = true;
    });
    _startControlsTimer();

    if (newFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      if (_isTV()) {
        // TV: mantener landscape siempre
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
  }

  bool _isTV() {
    try {
      final mq = MediaQuery.maybeOf(context);
      if (mq == null) return false;
      return mq.navigationMode == NavigationMode.directional ||
          mq.size.shortestSide > 480;
    } catch (_) {
      return false;
    }
  }

  void _cycleVideoFit() {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
      } else {
        _videoFit = BoxFit.contain;
      }
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _indicatorTimer?.cancel();
    _controller?.removeListener(_playerListener);
    _controller?.dispose();
    // Liberar wakelock al salir del reproductor
    _channel.invokeMethod('releaseScreenOn').catchError((_) {});
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      if (_isTV()) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (duration.inHours > 0) {
      return '${duration.inHours}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Error al cargar video nativo:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _initializePlayer,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                    ),
                    if (widget.onErrorFallback != null) ...[
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: widget.onErrorFallback,
                        icon: Icon(Icons.web, color: Theme.of(context).colorScheme.secondary),
                        label: Text('Usar Web Player', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 12),
              const Text(
                'Cargando reproductor nativo...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final value = _controller!.value;
    final pos = value.position;
    final dur = value.duration;

    final playerWidget = SizedBox.expand(
      child: FittedBox(
        fit: _videoFit,
        child: SizedBox(
          width: value.size.width,
          height: value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );

    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video widget
          playerWidget,

          // Double Tap Area Detection + Animation + Vertical Drag
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _isLocked ? null : _onDoubleTapLeft,
                  onTap: _toggleControls,
                  onVerticalDragStart: _isLocked ? null : (details) => _onDragStart(details, screenWidth),
                  onVerticalDragUpdate: _isLocked ? null : (details) => _onDragUpdate(details, screenWidth, screenHeight),
                  onVerticalDragEnd: _isLocked ? null : _onDragEnd,
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showLeftDoubleTap ? 0.8 : 0.0,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_rewind, color: Colors.white, size: 28),
                              SizedBox(height: 4),
                              Text('-10s', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _isLocked ? null : _onDoubleTapRight,
                  onTap: _toggleControls,
                  onVerticalDragStart: _isLocked ? null : (details) => _onDragStart(details, screenWidth),
                  onVerticalDragUpdate: _isLocked ? null : (details) => _onDragUpdate(details, screenWidth, screenHeight),
                  onVerticalDragEnd: _isLocked ? null : _onDragEnd,
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showRightDoubleTap ? 0.8 : 0.0,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward, color: Colors.white, size: 28),
                              SizedBox(height: 4),
                              Text('+10s', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Custom Controls Overlay
          if (_showControls) _buildControlsOverlay(pos, dur, value.isPlaying),

          // Indicator HUD Overlay
          if (_showVolumeIndicator)
            _buildVerticalHud(
              icon: _volume == 0
                  ? Icons.volume_off
                  : (_volume < 0.4 ? Icons.volume_down : Icons.volume_up),
              value: _volume,
              isLeft: false,
            ),
          if (_showBrightnessIndicator)
            _buildVerticalHud(
              icon: Icons.brightness_6,
              value: _brightness,
              isLeft: true,
            ),
        ],
      ),
    ), // Container
    ); // Focus
  }

  /// Manejo de teclas D-pad / teclado para Android TV.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_controller == null || !_isInitialized) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Play / Pause — botón central D-pad o Space/Enter
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      setState(() => _showControls = true);
      _startControlsTimer();
      return KeyEventResult.handled;
    }

    // Seek atrás ← o MediaRewind
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      final current = _controller!.value.position;
      final target = current - const Duration(seconds: 10);
      _controller!.seekTo(target < Duration.zero ? Duration.zero : target);
      setState(() {
        _showLeftDoubleTap = true;
        _showControls = true;
      });
      _startControlsTimer();
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showLeftDoubleTap = false);
      });
      return KeyEventResult.handled;
    }

    // Seek adelante → o MediaFastForward
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      final current = _controller!.value.position;
      final max = _controller!.value.duration;
      final target = current + const Duration(seconds: 10);
      _controller!.seekTo(target > max ? max : target);
      setState(() {
        _showRightDoubleTap = true;
        _showControls = true;
      });
      _startControlsTimer();
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showRightDoubleTap = false);
      });
      return KeyEventResult.handled;
    }

    // Volumen ↑
    if (key == LogicalKeyboardKey.arrowUp) {
      try {
        final newVol = (_volume + 0.1).clamp(0.0, 1.0);
        VolumeController().setVolume(newVol);
        setState(() {
          _volume = newVol;
          _showVolumeIndicator = true;
          _showControls = true;
        });
        _indicatorTimer?.cancel();
        _indicatorTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showVolumeIndicator = false);
        });
      } catch (_) {}
      return KeyEventResult.handled;
    }

    // Volumen ↓
    if (key == LogicalKeyboardKey.arrowDown) {
      try {
        final newVol = (_volume - 0.1).clamp(0.0, 1.0);
        VolumeController().setVolume(newVol);
        setState(() {
          _volume = newVol;
          _showVolumeIndicator = true;
          _showControls = true;
        });
        _indicatorTimer?.cancel();
        _indicatorTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showVolumeIndicator = false);
        });
      } catch (_) {}
      return KeyEventResult.handled;
    }

    // Botón Atrás / Escape → ocultar controles o salir
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (_showControls) {
        setState(() => _showControls = false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _onDragStart(DragStartDetails details, double screenWidth) {
    _indicatorTimer?.cancel();
    final isLeft = details.localPosition.dx < screenWidth / 2;
    if (isLeft) {
      try {
        ScreenBrightness().current.then((b) {
          if (mounted) {
            setState(() {
              _brightness = b;
              _showBrightnessIndicator = true;
              _showVolumeIndicator = false;
            });
          }
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _showBrightnessIndicator = true;
            _showVolumeIndicator = false;
          });
        }
      }
    } else {
      try {
        VolumeController().getVolume().then((v) {
          if (mounted) {
            setState(() {
              _volume = v;
              _showVolumeIndicator = true;
              _showBrightnessIndicator = false;
            });
          }
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _showVolumeIndicator = true;
            _showBrightnessIndicator = false;
          });
        }
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double screenWidth, double screenHeight) {
    final isLeft = details.localPosition.dx < screenWidth / 2;
    final delta = -details.primaryDelta! / screenHeight;

    if (isLeft) {
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
      });
      try {
        ScreenBrightness().setScreenBrightness(_brightness);
      } catch (_) {}
    } else {
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
      });
      try {
        VolumeController().setVolume(_volume, showSystemUI: false);
      } catch (_) {}
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _indicatorTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  Widget _buildVerticalHud({
    required IconData icon,
    required double value,
    required bool isLeft,
  }) {
    return Positioned(
      left: isLeft ? 24 : null,
      right: isLeft ? null : 24,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: 1.0,
          child: Container(
            width: 38,
            height: 180,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(height: 12),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 90,
                        height: 6,
                        child: LinearProgressIndicator(
                          value: value,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(Duration pos, Duration dur, bool isPlaying) {
    if (_isLocked) {
      return Positioned(
        left: 24,
        top: 0,
        bottom: 0,
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _showControls ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                child: IconButton(
                  iconSize: 28,
                  icon: Icon(Icons.lock, color: Theme.of(context).colorScheme.primary),
                  onPressed: () {
                    setState(() {
                      _isLocked = false;
                      _showControls = true;
                    });
                    _startControlsTimer();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: Container(
            color: Colors.transparent,
            child: Column(
              children: [
            // Top Controls Bar (Back + Title + Options) - Glassmorphism Floating
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () {
                              if (_isFullscreen) {
                                _toggleFullscreen().then((_) {
                                  Navigator.pop(context);
                                });
                              } else {
                                Navigator.pop(context);
                              }
                            },
                          ),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Botón Chromecast
                          CastIconButton(
                            videoUrl: widget.url,
                            videoTitle: widget.title,
                            currentPositionSeconds: _controller != null
                                ? _controller!.value.position.inSeconds.toDouble()
                                : 0,
                          ),

                          // Speed Multiplier Menu
                          PopupMenuButton<double>(
                            initialValue: _playbackSpeed,
                            icon: const Icon(Icons.speed, color: Colors.white),
                            tooltip: 'Velocidad',
                            onSelected: (speed) {
                              _controller?.setPlaybackSpeed(speed);
                              setState(() {
                                _playbackSpeed = speed;
                              });
                              _startControlsTimer();
                            },
                            itemBuilder: (context) => [0.5, 1.0, 1.25, 1.5, 2.0].map((s) {
                              return PopupMenuItem(
                                value: s,
                                child: Text('${s}x', style: TextStyle(fontWeight: s == _playbackSpeed ? FontWeight.bold : FontWeight.normal)),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Center Controls (Lock | Seek -10s | Play/Pause | Seek +10s | Aspect Ratio)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 22,
                    icon: const Icon(Icons.lock_open, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isLocked = true;
                        _showControls = true;
                      });
                      _controlsTimer?.cancel();
                      _controlsTimer = Timer(const Duration(seconds: 3), () {
                        if (mounted) setState(() => _showControls = false);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () {
                    _onDoubleTapLeft();
                    _startControlsTimer();
                  },
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 64,
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      _controller?.pause();
                    } else {
                      _controller?.play();
                    }
                    setState(() {});
                    _startControlsTimer();
                  },
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () {
                    _onDoubleTapRight();
                    _startControlsTimer();
                  },
                ),
                const SizedBox(width: 24),
                Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 22,
                    icon: Icon(
                      _videoFit == BoxFit.contain
                          ? Icons.fit_screen_outlined
                          : (_videoFit == BoxFit.cover ? Icons.fullscreen : Icons.aspect_ratio),
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _cycleVideoFit();
                      _startControlsTimer();
                    },
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Lower Controls Bar (Slider + Duration + Fullscreen) - Glassmorphism Floating
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Slider
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.0,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: Theme.of(context).colorScheme.primary,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Theme.of(context).colorScheme.primary,
                              overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                            ),
                            child: Slider(
                              value: pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                              max: dur.inSeconds.toDouble(),
                              onChanged: (val) {
                                _controller?.seekTo(Duration(seconds: val.toInt()));
                                _startControlsTimer();
                              },
                            ),
                          ),

                          // Position Timer + Fullscreen button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                  color: Colors.white,
                                ),
                                onPressed: _toggleFullscreen,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
            ),
          ),
    );
  }
}
