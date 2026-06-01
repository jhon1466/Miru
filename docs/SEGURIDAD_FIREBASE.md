# Firebase y Secret Scanning

GitHub detectó una API key en el historial del repo. **Ya se eliminó del historial de Git** y esos archivos **ya no se suben** (están en `.gitignore`).

## Archivos solo locales (no en GitHub)

| Archivo | Cómo obtenerlo |
|---------|----------------|
| `lib/core/firebase_options.dart` | `flutterfire configure --project=serie-938f4` |
| `android/app/google-services.json` | Se genera con el mismo comando |

Plantillas: `lib/core/firebase_options.example.dart` y `android/app/google-services.json.example`.

## Primera vez / otro PC

```powershell
cd anime_app
dart pub global activate flutterfire_cli
```

En Windows, si `flutterfire` no se reconoce, usa la ruta de Pub o añádela al PATH:

```powershell
$env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
flutterfire configure --project=serie-938f4 --platforms=android --yes
```

Alternativa sin PATH:

```powershell
dart pub global run flutterfire_cli:flutterfire configure --project=serie-938f4 --platforms=android --yes
```

Verifica que existan `lib/core/firebase_options.dart` y `android/app/google-services.json`.  
Si FlutterFire crea `lib/firebase_options.dart`, copia su contenido a `lib/core/` (la app importa desde `core/`).

## Si revocaste la clave en Google Cloud

1. [Google Cloud Console](https://console.cloud.google.com/) → **serie-938f4** → **Credenciales**.
2. Elimina la clave filtrada y crea una nueva (o deja que Firebase use la del proyecto).
3. Vuelve a ejecutar `flutterfire configure` en tu PC.

## Restringir la clave nueva (importante)

En Google Cloud → Credenciales → tu API key → **Restricciones de aplicación**:

- Tipo: **Aplicaciones de Android**
- Nombre del paquete: `com.jhondev146.pruebaseries`
- Huella SHA-1: la de tu keystore de release/debug (`keytool -list -v -keystore ...`)

En **Restricciones de API**, limita solo a las que usa Firebase (p. ej. Firebase Installations, FCM, etc.).

Activa **Firebase App Check** en producción si puedes.

## Historial de Git

La clave antigua **sigue en commits viejos** del repo público. Rotar la clave en Google es lo crítico. Para borrarla del historial hace falta `git filter-repo` o BFG y un force push (solo si sabes las consecuencias).

## No volver a filtrar el token de GitHub

Si en `git remote -v` aparece `ghp_...` en la URL, cámbialo:

```bash
git remote set-url origin https://github.com/jhon1466/Miru.git
```

Revoca ese token en GitHub → Settings → Developer settings → Personal access tokens.
