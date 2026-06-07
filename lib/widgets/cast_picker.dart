import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';
import '../core/theme.dart';

/// Botón de Chromecast para usar en controles del reproductor.
/// Solo visible en Android.
class CastIconButton extends StatelessWidget {
  final String videoUrl;
  final String videoTitle;
  final String? posterUrl;
  final double currentPositionSeconds;

  const CastIconButton({
    super.key,
    required this.videoUrl,
    required this.videoTitle,
    this.posterUrl,
    this.currentPositionSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    return Consumer<CastProvider>(
      builder: (context, cast, _) {
        final icon = cast.isConnected
            ? Icons.cast_connected
            : Icons.cast;
        final color = cast.isConnected
            ? Theme.of(context).colorScheme.primary
            : Colors.white;

        return IconButton(
          icon: Icon(icon, color: color),
          tooltip: cast.isConnected
              ? 'Transmitiendo a ${cast.connectedDevice?.name}'
              : 'Transmitir a TV',
          onPressed: () => _showCastSheet(context, cast),
        );
      },
    );
  }

  void _showCastSheet(BuildContext context, CastProvider cast) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CastSheet(
        cast: cast,
        videoUrl: videoUrl,
        videoTitle: videoTitle,
        posterUrl: posterUrl,
        currentPositionSeconds: currentPositionSeconds,
      ),
    );
  }
}

class _CastSheet extends StatefulWidget {
  final CastProvider cast;
  final String videoUrl;
  final String videoTitle;
  final String? posterUrl;
  final double currentPositionSeconds;

  const _CastSheet({
    required this.cast,
    required this.videoUrl,
    required this.videoTitle,
    this.posterUrl,
    required this.currentPositionSeconds,
  });

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  @override
  void initState() {
    super.initState();
    // Inicia búsqueda automáticamente si no está conectado
    if (!widget.cast.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.cast.searchDevices();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cast,
      builder: (context, _) {
        final cast = widget.cast;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Icon(Icons.cast, color: context.primaryColor, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Transmitir a TV',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (!cast.isConnected)
                    TextButton.icon(
                      onPressed: cast.isSearching ? null : cast.searchDevices,
                      icon: cast.isSearching
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.primaryColor,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(cast.isSearching ? 'Buscando…' : 'Buscar'),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Connected state
              if (cast.isConnected) ...[
                _ConnectedTile(
                  deviceName: cast.connectedDevice?.name ?? 'Dispositivo',
                  onDisconnect: () async {
                    await cast.disconnect();
                    if (context.mounted) Navigator.pop(context);
                  },
                  onReload: () async {
                    await cast.loadMedia(
                      url: widget.videoUrl,
                      title: widget.videoTitle,
                      posterUrl: widget.posterUrl,
                      startTime: widget.currentPositionSeconds,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ]

              // Device list
              else if (cast.isSearching && cast.devices.isEmpty) ...[
                const _SearchingWidget(),
              ] else if (!cast.isSearching && cast.devices.isEmpty) ...[
                _EmptyWidget(onRetry: cast.searchDevices),
              ] else ...[
                Text(
                  'Dispositivos encontrados',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...cast.devices.map(
                  (device) => _DeviceTile(
                    device: device,
                    isConnecting: cast.isConnecting &&
                        cast.connectedDevice?.serviceName == device.serviceName,
                    onTap: () async {
                      final ok = await cast.connect(device);
                      if (!ok || !context.mounted) return;
                      // Esperar a que el receiver arranque y luego cargar media
                      await Future.delayed(const Duration(seconds: 2));
                      if (!context.mounted) return;
                      await cast.loadMedia(
                        url: widget.videoUrl,
                        title: widget.videoTitle,
                        posterUrl: widget.posterUrl,
                        startTime: widget.currentPositionSeconds,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
                if (cast.isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],

              // Error
              if (cast.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    cast.error!,
                    style: TextStyle(
                      color: context.dangerColor,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectedTile extends StatelessWidget {
  final String deviceName;
  final VoidCallback onDisconnect;
  final VoidCallback onReload;

  const _ConnectedTile({
    required this.deviceName,
    required this.onDisconnect,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.primaryColor.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected, color: context.primaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transmitiendo a',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                    Text(
                      deviceName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reenviar video'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.primaryColor),
                    foregroundColor: context.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Desconectar'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.dangerColor),
                    foregroundColor: context.dangerColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final dynamic device;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.primaryColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.tv, color: context.primaryColor, size: 20),
      ),
      title: Text(
        device.name,
        style: TextStyle(
          color: context.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        device.host,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: isConnecting
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.primaryColor,
              ),
            )
          : Icon(Icons.chevron_right, color: context.textSecondary),
      onTap: isConnecting ? null : onTap,
    );
  }
}

class _SearchingWidget extends StatelessWidget {
  const _SearchingWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Buscando dispositivos Chromecast\nen tu red Wi-Fi…',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.cast, size: 48, color: context.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No se encontraron dispositivos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Asegúrate de estar en la misma red Wi-Fi\nque tu Chromecast',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Buscar de nuevo'),
            ),
          ],
        ),
      ),
    );
  }
}
