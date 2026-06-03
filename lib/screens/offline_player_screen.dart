import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/downloaded_episode.dart';
import '../widgets/native_video_player.dart';

class OfflinePlayerScreen extends StatefulWidget {
  final DownloadedEpisode episode;

  const OfflinePlayerScreen({super.key, required this.episode});

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  bool _exists = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkFile();
    _unlockOrientations();
  }

  void _unlockOrientations() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _checkFile() async {
    final file = File(widget.episode.filePath);
    final exists = await file.exists();
    if (mounted) {
      setState(() {
        _exists = exists;
        _checking = false;
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _checking
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              )
            : !_exists
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'El archivo ya no está en el dispositivo',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                            child: const Text('Volver'),
                          ),
                        ],
                      ),
                    ),
                  )
                : NativeVideoPlayer(
                    url: widget.episode.filePath,
                    title: '${widget.episode.animeTitle} - ${widget.episode.episodeLabel}',
                  ),
      ),
    );
  }
}
