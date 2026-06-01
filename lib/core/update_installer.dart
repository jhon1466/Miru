import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';

/// Progreso de descarga/instalación OTA del APK.
class UpdateDownloadProgress {
  final OtaStatus status;
  final int? percent;
  final String? message;

  const UpdateDownloadProgress({
    required this.status,
    this.percent,
    this.message,
  });
}

class UpdateInstaller {
  /// Descarga e instala el APK en Android sin abrir el navegador.
  static Stream<UpdateDownloadProgress> downloadAndInstall(String apkUrl) async* {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      yield const UpdateDownloadProgress(
        status: OtaStatus.INTERNAL_ERROR,
        message: 'La actualización in-app solo está disponible en Android.',
      );
      return;
    }

    if (!apkUrl.toLowerCase().endsWith('.apk')) {
      yield const UpdateDownloadProgress(
        status: OtaStatus.INTERNAL_ERROR,
        message: 'No hay un APK válido en el release de GitHub.',
      );
      return;
    }

    final storage = await Permission.storage.request();
    final install = await Permission.requestInstallPackages.request();
    if (!storage.isGranted && !install.isGranted) {
      // Android 13+ puede no requerir storage para descarga en caché de la app
      final manage = await Permission.manageExternalStorage.request();
      if (!install.isGranted && !manage.isGranted) {
        yield const UpdateDownloadProgress(
          status: OtaStatus.PERMISSION_NOT_GRANTED_ERROR,
          message: 'Se necesita permiso para instalar actualizaciones.',
        );
        return;
      }
    }

    yield* OtaUpdate()
        .execute(
          apkUrl,
          destinationFilename: 'miru_update.apk',
          androidProviderAuthority: 'com.jhondev146.pruebaseries.fileprovider',
        )
        .map((event) {
      switch (event.status) {
        case OtaStatus.DOWNLOADING:
          return UpdateDownloadProgress(
            status: event.status,
            percent: event.value != null ? int.tryParse(event.value!) : null,
          );
        case OtaStatus.INSTALLING:
          return const UpdateDownloadProgress(
            status: OtaStatus.INSTALLING,
            message: 'Abriendo instalador...',
          );
        case OtaStatus.ALREADY_RUNNING_ERROR:
          return const UpdateDownloadProgress(
            status: OtaStatus.ALREADY_RUNNING_ERROR,
            message: 'Ya hay una descarga en curso.',
          );
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          return const UpdateDownloadProgress(
            status: OtaStatus.PERMISSION_NOT_GRANTED_ERROR,
            message: 'Permiso denegado para instalar el APK.',
          );
        case OtaStatus.INTERNAL_ERROR:
          return UpdateDownloadProgress(
            status: OtaStatus.INTERNAL_ERROR,
            message: event.value ?? 'Error interno al actualizar.',
          );
        default:
          return UpdateDownloadProgress(status: event.status, percent: null);
      }
    });
  }
}
