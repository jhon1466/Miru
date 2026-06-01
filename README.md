# Miru (anime_app)

Cliente Flutter para ver anime con catálogo, horario, descargas offline, comentarios y notificaciones.

## Configuración inicial

### Firebase (obligatorio para compilar)

Los archivos con claves **no están en el repositorio**. En tu máquina:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=serie-938f4 --platforms=android
```

Asegúrate de tener `lib/core/firebase_options.dart` y `android/app/google-services.json`.  
Más detalles: [docs/SEGURIDAD_FIREBASE.md](docs/SEGURIDAD_FIREBASE.md).

### Ejecutar

```bash
flutter pub get
flutter run
```

## Releases

APK en [GitHub Releases](https://github.com/jhon1466/Miru/releases).
