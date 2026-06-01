import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/user_service.dart';
import '../utils/auth_ui.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';
import 'downloads_screen.dart';

/// Pestaña Perfil: cuenta, foto, privacidad y acceso a ajustes.
class ProfileTabScreen extends StatelessWidget {
  const ProfileTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<app_auth.AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen(showBackButton: true)),
              );
            },
          ),
        ],
      ),
      body: auth.isLoggedIn
          ? _LoggedInBody(authProvider: auth)
          : _LoggedOutBody(authProvider: auth),
    );
  }
}

class _LoggedInBody extends StatefulWidget {
  final app_auth.AuthProvider authProvider;

  const _LoggedInBody({required this.authProvider});

  @override
  State<_LoggedInBody> createState() => _LoggedInBodyState();
}

class _LoggedInBodyState extends State<_LoggedInBody> {
  bool _uploadingPhoto = false;
  bool? _isPublicLocal;

  @override
  Widget build(BuildContext context) {
    final uid = widget.authProvider.userId!;

    return StreamBuilder<UserProfile?>(
      stream: UserService.profileStream(uid),
      builder: (context, snap) {
        final profile = snap.data;
        final isPublic = _isPublicLocal ?? profile?.isPublic ?? true;
        final photoUrl = profile?.photoUrl ?? widget.authProvider.photoUrl;
        final name = profile?.displayName ?? widget.authProvider.displayName ?? 'Usuario';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? NetworkImage(photoUrl)
                        : null,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: AppTheme.primaryColor,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _uploadingPhoto ? null : () => _changePhoto(context),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: _uploadingPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _editDisplayName(context, name),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
              Text(
                widget.authProvider.email ?? '',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Toca tu nombre para editarlo · cámara para cambiar la foto',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Perfil público'),
                  subtitle: Text(
                    isPublic
                        ? 'Otros pueden ver tus favoritos desde comentarios'
                        : 'Tu perfil y favoritos están ocultos',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  value: isPublic,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: (value) async {
                    setState(() => _isPublicLocal = value);
                    try {
                      await UserService.setProfilePublic(uid, value);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(value ? 'Perfil público activado' : 'Perfil privado activado'),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    } catch (e) {
                      setState(() => _isPublicLocal = !value);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('No se pudo cambiar la privacidad: $e'),
                          backgroundColor: AppTheme.dangerColor,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                    );
                  },
                  icon: const Icon(Icons.download_for_offline_outlined, color: AppTheme.accentColor),
                  label: const Text('Mis descargas', style: TextStyle(color: AppTheme.accentColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(
                          userId: uid,
                          displayName: name,
                          photoUrl: photoUrl,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.collections_bookmark_outlined, color: AppTheme.primaryColor),
                  label: const Text('Ver mis favoritos', style: TextStyle(color: AppTheme.primaryColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await widget.authProvider.signOut();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sesión cerrada'), backgroundColor: AppTheme.successColor),
                    );
                  },
                  icon: const Icon(Icons.logout, color: AppTheme.dangerColor),
                  label: const Text('Cerrar sesión', style: TextStyle(color: AppTheme.dangerColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.dangerColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editDisplayName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Editar nombre', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Tu nombre en comentarios',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    try {
      await widget.authProvider.updateDisplayName(controller.text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nombre actualizado en tu perfil y comentarios'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerColor),
      );
    }
  }

  Future<void> _changePhoto(BuildContext context) async {
    setState(() => _uploadingPhoto = true);
    try {
      await widget.authProvider.updateProfilePhotoFromGallery();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada'), backgroundColor: AppTheme.successColor),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir foto: $e'), backgroundColor: AppTheme.dangerColor),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }
}

class _LoggedOutBody extends StatelessWidget {
  final app_auth.AuthProvider authProvider;

  const _LoggedOutBody({required this.authProvider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_outline, size: 72, color: AppTheme.textSecondary),
            const SizedBox(height: 20),
            const Text(
              'Inicia sesión',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sincroniza favoritos, comenta y personaliza tu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  );
                },
                icon: const Icon(Icons.download_for_offline_outlined, color: AppTheme.accentColor),
                label: const Text('Mis descargas', style: TextStyle(color: AppTheme.accentColor)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => signInWithGoogleAndWelcome(context, authProvider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Continuar con Google', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
