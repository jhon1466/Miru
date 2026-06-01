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
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.system_update_rounded, color: AppTheme.primaryColor, size: 28),
          SizedBox(width: 12),
          Expanded(
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
              style: const TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_isDownloading || _progress != null) ...[
              LinearProgressIndicator(
                value: _progress != null ? _progress! / 100 : null,
                backgroundColor: AppTheme.darkBackground,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 8),
              Text(
                _progress != null ? 'Descargando: $_progress%' : (_statusMessage ?? 'Descargando...'),
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
            ] else if (_statusMessage != null) ...[
              Text(_statusMessage!, style: const TextStyle(color: AppTheme.dangerColor, fontSize: 12)),
              const SizedBox(height: 12),
            ],
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.darkBackground.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.releaseNotes,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                ),
              ),
            ),
            if (_canInstallInApp) ...[
              const SizedBox(height: 12),
              const Text(
                'La actualización se descargará e instalará dentro de la app.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading && !_finished)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Más tarde', style: TextStyle(color: AppTheme.textSecondary)),
          ),
        if (!_isDownloading && !_finished)
          ElevatedButton.icon(
            onPressed: _canInstallInApp ? _startDownload : _openBrowser,
            icon: Icon(_canInstallInApp ? Icons.download_rounded : Icons.open_in_browser, size: 18),
            label: Text(_canInstallInApp ? 'Actualizar ahora' : 'Abrir en navegador'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
          ),
      ],
    );
  }
}
