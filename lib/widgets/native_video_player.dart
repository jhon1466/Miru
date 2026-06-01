import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../core/theme.dart';

class NativeVideoPlayer extends StatefulWidget {
  final String url;
  final String title;

  const NativeVideoPlayer({
    super.key,
    required this.url,
    required this.title,
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

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startControlsTimer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      final uri = Uri.parse(widget.url);
      _controller = VideoPlayerController.networkUrl(uri);
      
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
      }
    }
  }

  void _playerListener() {
    if (_controller != null && _controller!.value.hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _controller!.value.errorDescription ?? 'Error de reproducción';
      });
    } else {
      // Rebuild to update progress slider
      setState(() {});
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
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
    setState(() {
      _isFullscreen = !_isFullscreen;
      _showControls = true;
    });
    _startControlsTimer();

    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
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
    _controller?.removeListener(_playerListener);
    _controller?.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
                ElevatedButton.icon(
                  onPressed: _initializePlayer,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
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
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
              SizedBox(height: 12),
              Text(
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

    final playerWidget = Center(
      child: FittedBox(
        fit: _videoFit,
        child: SizedBox(
          width: value.size.width,
          height: value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video widget
          playerWidget,

          // Double Tap Area Detection + Animation
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _onDoubleTapLeft,
                  onTap: _toggleControls,
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
                  onDoubleTap: _onDoubleTapRight,
                  onTap: _toggleControls,
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
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(Duration pos, Duration dur, bool isPlaying) {
    return Positioned.fill(
      child: Container(
        color: Colors.black38,
        child: Column(
          children: [
            // Top Controls Bar (Title + Options)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Aspect Ratio Button
                  IconButton(
                    icon: Icon(
                      _videoFit == BoxFit.contain
                          ? Icons.fit_screen_outlined
                          : (_videoFit == BoxFit.cover ? Icons.fullscreen : Icons.aspect_ratio),
                      color: Colors.white,
                    ),
                    tooltip: 'Ajuste de pantalla',
                    onPressed: _cycleVideoFit,
                  ),

                  // Speed Multiplier Menu
                  PopupMenuButton<double>(
                    initialValue: _playbackSpeed,
                    icon: const Icon(Icons.speed, color: Colors.white),
                    tooltip: 'Velocidad de reproducción',
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

            const Spacer(),

            // Playback Center Controls (Seek back, Play/Pause, Seek forward)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () {
                    _onDoubleTapLeft();
                    _startControlsTimer();
                  },
                ),
                const SizedBox(width: 24),
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
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () {
                    _onDoubleTapRight();
                    _startControlsTimer();
                  },
                ),
              ],
            ),

            const Spacer(),

            // Lower Controls Bar (Progress Slider + Timers + Fullscreen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Slider
                  SizedBox(
                    height: 18,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: AppTheme.primaryColor,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: AppTheme.primaryColor,
                        overlayColor: AppTheme.primaryColor.withOpacity(0.3),
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
                          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                        ),
                      ),
                      IconButton(
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
          ],
        ),
      ),
    );
  }
}
