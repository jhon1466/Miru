import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;

/// Inicia sesión con Google y muestra mensaje de bienvenida con el nombre del usuario.
Future<void> signInWithGoogleAndWelcome(
  BuildContext context,
  app_auth.AuthProvider authProvider,
) async {
  final name = await authProvider.signInWithGoogle();
  if (!context.mounted) return;
  if (name != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('¡Bienvenido, $name!'),
        backgroundColor: AppTheme.successColor,
        duration: const Duration(seconds: 3),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo iniciar sesión. Inténtalo de nuevo.'),
        backgroundColor: AppTheme.dangerColor,
      ),
    );
  }
}
