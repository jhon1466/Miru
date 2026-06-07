import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../core/update_installer.dart';
import '../core/update_service.dart';

void showAppUpdateDialog(BuildContext context, UpdateInfo info) {
  showDialog(
    context: context,
    barrierDismissible: !info.downloadUrl.toLowerCase().endsWith('.apk'),
    builder: (dialogContext) => _UpdateDialogContent(info: info),
  );
}

class _UpdateDialogContent extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialogContent({required this.info});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  StreamSubscription<UpdateDownloadProgress>? _sub;
  int? _progress;
  String? _statusMessage;
  bool _isDownloading = false;
  bool _finished = false;

  bool get _canInstallInApp =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      widget.info.downloadUrl.toLowerCase().endsWith('.apk');

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _statusMessage = 'Iniciando descarga...';
    });

    _sub = UpdateInstaller.downloadAndInstall(widget.info.downloadUrl).listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _statusMessage = event.message;
          if (event.percent != null) _progress = event.percent;
          if (event.status == OtaStatus.INSTALLING) {
            _statusMessage = 'Instalando actualización...';
            _finished = true;
          }
          if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR ||
              event.status == OtaStatus.INTERNAL_ERROR ||
              event.status == OtaStatus.ALREADY_RUNNING_ERROR) {
            _isDownloading = false;
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _finished = true;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Error: $e';
        });
      },
    );
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(widget.info.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), width: 1.5),
      ),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Actualización disponible',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión ${widget.info.latestVersion}',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_isDownloading || _progress != null) ...[
              LinearProgressIndicator(
                value: _progress != null ? _progress! / 100 : null,
                backgroundColor: context.backgroundColor,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                _progress != null ? 'Descargando: $_progress%' : (_statusMessage ?? 'Descargando...'),
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              const SizedBox(height: 12),
            ] else if (_statusMessage != null) ...[
              Text(_statusMessage!, style: TextStyle(color: AppTheme.dangerColor, fontSize: 12)),
              const SizedBox(height: 12),
            ],
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.backgroundColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: _MarkdownText(
                  text: widget.info.releaseNotes,
                  baseStyle: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.4),
                ),
              ),
            ),
            if (_canInstallInApp) ...[
              const SizedBox(height: 12),
              Text(
                'La actualización se descargará e instalará dentro de la app.',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading && !_finished)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Más tarde', style: TextStyle(color: context.textSecondary)),
          ),
        if (!_isDownloading && !_finished)
          ElevatedButton.icon(
            onPressed: _canInstallInApp ? _startDownload : _openBrowser,
            icon: Icon(_canInstallInApp ? Icons.download_rounded : Icons.open_in_browser, size: 18),
            label: Text(_canInstallInApp ? 'Actualizar ahora' : 'Abrir en navegador'),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          ),
      ],
    );
  }
}

/// Renderiza texto con soporte básico de Markdown:
/// **negrita**, *cursiva*, - listas, ### títulos
class _MarkdownText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _MarkdownText({required this.text, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) => _buildLine(line)).toList(),
    );
  }

  Widget _buildLine(String line) {
    if (line.trim().isEmpty) return const SizedBox(height: 4);

    // Títulos: ### ## #
    final headerMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    if (headerMatch != null) {
      final level = headerMatch.group(1)!.length;
      final content = headerMatch.group(2)!;
      final size = level == 1 ? 15.0 : level == 2 ? 13.5 : 12.5;
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          content,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: size),
        ),
      );
    }

    // Listas: - item o * item
    final listMatch = RegExp(r'^\s*[-*•]\s+(.+)$').firstMatch(line);
    if (listMatch != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, top: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: baseStyle),
            Expanded(child: _buildRichText(listMatch.group(1)!)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: _buildRichText(line),
    );
  }

  Widget _buildRichText(String line) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|([^*]+)');
    for (final m in pattern.allMatches(line)) {
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: baseStyle));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
