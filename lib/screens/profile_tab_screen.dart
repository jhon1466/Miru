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
  int _tabIndex = 0; // 0: Favorites, 1: Following
  String _mediaType = 'anime'; // 'anime' | 'manga' | 'novel'

  String _getSectionTitle() {
    final typeName = _mediaType == 'anime'
        ? 'Anime'
        : _mediaType == 'manga'
            ? 'Manga'
            : 'Novela';
    final actionName = _tabIndex == 0
        ? 'Favoritos'
        : _tabIndex == 1
            ? 'Siguiendo'
            : 'Terminados';
    return '$typeName $actionName';
  }

  Widget _buildMediaChip(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? context.primaryColor : context.textSecondary.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: context.primaryColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : context.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_outlined, size: 16, color: context.textSecondary),
                    ],
                  ),
                ),
              ),
              Text(
                widget.authProvider.email ?? '',
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Toca tu nombre para editarlo · cámara para cambiar la foto',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.textSecondary.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Perfil público'),
                  subtitle: Text(
                    isPublic
                        ? 'Otros pueden ver tus favoritos desde comentarios'
                        : 'Tu perfil y favoritos están ocultos',
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
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
                  icon: Icon(Icons.download_for_offline_outlined, color: AppTheme.accentColor),
                  label: Text('Mis descargas', style: TextStyle(color: AppTheme.accentColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (!isPublic) ...[
                const OwnerPrivateNotice(),
                const SizedBox(height: 12),
              ],
              ProfileStatsSection(
                userId: uid,
                isOwner: true,
                mediaType: _mediaType,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMediaChip(
                    context,
                    title: 'Anime',
                    icon: Icons.movie_creation_rounded,
                    isActive: _mediaType == 'anime',
                    onTap: () => setState(() => _mediaType = 'anime'),
                  ),
                  const SizedBox(width: 8),
                  _buildMediaChip(
                    context,
                    title: 'Manga',
                    icon: Icons.book_rounded,
                    isActive: _mediaType == 'manga',
                    onTap: () => setState(() => _mediaType = 'manga'),
                  ),
                  const SizedBox(width: 8),
                  _buildMediaChip(
                    context,
                    title: 'Novelas',
                    icon: Icons.auto_stories_rounded,
                    isActive: _mediaType == 'novel',
                    onTap: () => setState(() => _mediaType = 'novel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getSectionTitle(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildTabButton(
                        context,
                        title: 'Favoritos',
                        isActive: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      _buildTabButton(
                        context,
                        title: 'Siguiendo',
                        isActive: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      _buildTabButton(
                        context,
                        title: 'Vistos',
                        isActive: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FavoritesGrid(
                userId: uid,
                tabIndex: _tabIndex,
                mediaType: _mediaType,
              ),
              const SizedBox(height: 28),
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
                  icon: Icon(Icons.logout, color: AppTheme.dangerColor),
                  label: Text('Cerrar sesión', style: TextStyle(color: AppTheme.dangerColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.dangerColor),
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

  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? context.primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? context.primaryColor : context.textSecondary.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        title: Text('Editar nombre', style: TextStyle(color: context.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: TextStyle(color: context.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tu nombre en comentarios',
            hintStyle: TextStyle(color: context.textSecondary),
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
            Icon(Icons.person_outline, size: 72, color: context.textSecondary),
            const SizedBox(height: 20),
            Text(
              'Inicia sesión',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Sincroniza favoritos, comenta y personaliza tu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary),
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
                icon: Icon(Icons.download_for_offline_outlined, color: AppTheme.accentColor),
                label: Text('Mis descargas', style: TextStyle(color: AppTheme.accentColor)),
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
