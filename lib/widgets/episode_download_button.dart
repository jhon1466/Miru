import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/anime.dart';
import '../providers/download_provider.dart';
import '../screens/offline_player_screen.dart';

/// Botón de descarga / estado offline para un episodio.
class EpisodeDownloadButton extends StatelessWidget {
  final String episodeUrl;
  final double episodeNumber;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;
  final bool preferSub;
  final EpisodeLinksResponse? links;
  final bool iconOnly;

  const EpisodeDownloadButton({
    super.key,
    required this.episodeUrl,
    required this.episodeNumber,
    required this.animeTitle,
    required this.animeUrl,
    this.animeImage = '',
    this.preferSub = true,
    this.links,
    this.iconOnly = true,
  });

  Future<void> _start(BuildContext context) async {
    final downloads = context.read<DownloadProvider>();
    final ok = await downloads.startEpisodeDownload(
      episodeUrl: episodeUrl,
      episodeNumber: episodeNumber,
      animeTitle: animeTitle,
      animeUrl: animeUrl,
      animeImage: animeImage,
      preferSub: preferSub,
      links: links,
    );
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descarga completada'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } else {
      final task = downloads.taskFor(episodeUrl, preferSub);
      final msg = task?.error;
      if (msg != null && msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.dangerColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final saved = downloads.getDownloaded(episodeUrl, preferSub);
    final task = downloads.taskFor(episodeUrl, preferSub);

    if (saved != null) {
      return _buildControl(
        context,
        icon: Icons.download_done_rounded,
        color: AppTheme.successColor,
        label: 'Descargado',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OfflinePlayerScreen(episode: saved)),
          );
        },
      );
    }

    if (task != null) {
      final pct = task.progress > 0 ? (task.progress * 100).round() : null;
      return _buildControl(
        context,
        icon: Icons.downloading,
        color: AppTheme.primaryColor,
        label: pct != null ? '$pct%' : '...',
        onPressed: () => downloads.cancelDownload(episodeUrl, preferSub),
      );
    }

    return _buildControl(
      context,
      icon: Icons.download_rounded,
      color: Colors.white70,
      label: 'Descargar',
      onPressed: () => _start(context),
    );
  }

  Widget _buildControl(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    if (iconOnly) {
      return IconButton(
        icon: Icon(icon, color: color),
        tooltip: label,
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
