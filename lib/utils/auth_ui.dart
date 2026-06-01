import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;

/// Diálogo de bienvenida tras iniciar sesión.
Future<void> showWelcomeDialog(BuildContext context, String name) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.waving_hand, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '¡Bienvenido!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Text(
        'Hola, $name.\n\nTu historial y favoritos se sincronizan con tu cuenta.',
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Empezar', style: TextStyle(color: AppTheme.primaryColor)),
        ),
      ],
    ),
  );
}

/// Inicia sesión con Google y muestra pantalla de bienvenida.
Future<void> signInWithGoogleAndWelcome(
  BuildContext context,
  app_auth.AuthProvider authProvider,
) async {
  final name = await authProvider.signInWithGoogle();
  if (!context.mounted) return;
  if (name != null) {
    await showWelcomeDialog(context, name);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo iniciar sesión. Inténtalo de nuevo.'),
        backgroundColor: AppTheme.dangerColor,
      ),
    );
  }
}
