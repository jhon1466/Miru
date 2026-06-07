import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';
import '../core/theme.dart';

/// Botón cast para los controles del reproductor. Solo visible en Android.
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
        return IconButton(
          icon: Icon(
            cast.isConnected ? Icons.cast_connected : Icons.cast,
            color: cast.isConnected ? Theme.of(context).colorScheme.primary : Colors.white,
          ),
          tooltip: cast.isConnected
              ? 'Transmitiendo a ${cast.connectedDevice?.name}'
              : 'Enviar a TV / Chromecast',
          onPressed: () => _show(context, cast),
        );
      },
    );
  }

  void _show(BuildContext context, CastProvider cast) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CastSheet(
        cast: cast,
        videoUrl: videoUrl,
        videoTitle: videoTitle,
        posterUrl: posterUrl,
        posSeconds: currentPositionSeconds,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CastSheet extends StatefulWidget {
  final CastProvider cast;
  final String videoUrl;
  final String videoTitle;
  final String? posterUrl;
  final double posSeconds;

  const _CastSheet({
    required this.cast,
    required this.videoUrl,
    required this.videoTitle,
    this.posterUrl,
    required this.posSeconds,
  });

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  @override
  void initState() {
    super.initState();
    if (!widget.cast.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.cast.searchDevices());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cast,
      builder: (context, _) {
        final cast = widget.cast;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
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
                  const SizedBox(width: 8),
                  Text(
                    'Enviar a TV',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (!cast.isConnected)
                    TextButton.icon(
                      onPressed: cast.isSearching ? null : cast.searchDevices,
                      icon: cast.isSearching
                          ? SizedBox(
                              width: 13, height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.primaryColor),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(cast.isSearching ? 'Buscando…' : 'Buscar'),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Conectado ──
              if (cast.isConnected)
                _ConnectedCard(
                  name: cast.connectedDevice?.name ?? 'Dispositivo',
                  onReload: () async {
                    await cast.loadMedia(
                      url: widget.videoUrl,
                      title: widget.videoTitle,
                      posterUrl: widget.posterUrl,
                      startTime: widget.posSeconds,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  onDisconnect: () async {
                    await cast.disconnect();
                    if (context.mounted) Navigator.pop(context);
                  },
                )

              // ── Buscando sin resultados ──
              else if (cast.isSearching && cast.devices.isEmpty)
                const _Searching()

              // ── Sin dispositivos ──
              else if (!cast.isSearching && cast.devices.isEmpty)
                _Empty(onRetry: cast.searchDevices)

              // ── Lista de dispositivos ──
              else ...[
                Text(
                  'Dispositivos en tu red',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 6),
                ...cast.devices.map((device) => _DeviceTile(
                      name: device.name,
                      host: device.host,
                      isConnecting: cast.isConnecting &&
                          cast.connectedDevice?.serviceName == device.serviceName,
                      onTap: () async {
                        final ok = await cast.connectAndPlay(
                          device: device,
                          url: widget.videoUrl,
                          title: widget.videoTitle,
                          posterUrl: widget.posterUrl,
                          startTime: widget.posSeconds,
                        );
                        if (ok && context.mounted) Navigator.pop(context);
                      },
                    )),
                if (cast.isSearching)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(color: context.primaryColor),
                  ),
              ],

              if (cast.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(cast.error!,
                      style: TextStyle(color: context.dangerColor, fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _ConnectedCard extends StatelessWidget {
  final String name;
  final VoidCallback onReload;
  final VoidCallback onDisconnect;
  const _ConnectedCard({required this.name, required this.onReload, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.primaryColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.cast_connected, color: context.primaryColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Transmitiendo a',
                    style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(name,
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Reenviar'),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.primaryColor),
                    foregroundColor: context.primaryColor,
                    visualDensity: VisualDensity.compact),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.stop_circle_outlined, size: 15),
                label: const Text('Detener'),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.dangerColor),
                    foregroundColor: context.dangerColor,
                    visualDensity: VisualDensity.compact),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final String name;
  final String host;
  final bool isConnecting;
  final VoidCallback onTap;
  const _DeviceTile(
      {required this.name, required this.host, required this.isConnecting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        backgroundColor: context.primaryColor.withValues(alpha: 0.12),
        child: Icon(Icons.tv, color: context.primaryColor, size: 20),
      ),
      title: Text(name,
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(host, style: TextStyle(color: context.textSecondary, fontSize: 11)),
      trailing: isConnecting
          ? SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.primaryColor))
          : Icon(Icons.chevron_right, color: context.textSecondary),
      onTap: isConnecting ? null : onTap,
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(children: [
          SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.primaryColor)),
          const SizedBox(height: 10),
          Text('Buscando dispositivos en tu red Wi-Fi…',
              style: TextStyle(color: context.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onRetry;
  const _Empty({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(children: [
          Icon(Icons.cast, size: 44, color: context.textSecondary.withValues(alpha: 0.35)),
          const SizedBox(height: 10),
          Text('No se encontraron dispositivos',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text('Asegúrate de estar en la misma red Wi-Fi que el Chromecast',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Buscar de nuevo'),
          ),
        ]),
      ),
    );
  }
}
