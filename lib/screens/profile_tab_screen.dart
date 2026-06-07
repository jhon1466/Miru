import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/supporter_provider.dart';
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
  bool _uploadingBanner = false;
  bool? _isPublicLocal;
  int _tabIndex = 0; // 0: Favorites, 1: Following
  String _mediaType = 'anime'; // 'anime' | 'manga' | 'novel'

  Future<void> _pickAndUploadBanner(BuildContext context, String uid) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null || !mounted) return;

    // Mostrar diálogo de ajuste de posición antes de subir
    final result = await showDialog<({double alignY, File file})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BannerPositionDialog(imageFile: File(picked.path)),
    );
    if (result == null || !mounted) return;

    setState(() => _uploadingBanner = true);
    try {
      final url = await FirebaseStorage.instance
          .ref('user_banners/$uid/banner.jpg')
          .putFile(result.file)
          .then((t) => t.ref.getDownloadURL());
      await UserService.updateBannerUrl(uid, url);
      await UserService.updateBannerAlign(uid, result.alignY);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Banner actualizado'), backgroundColor: context.successColor));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: context.dangerColor));
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  Future<void> _removeBanner(BuildContext context, String uid) async {
    setState(() => _uploadingBanner = true);
    try {
      await UserService.updateBannerUrl(uid, null);
      try { await FirebaseStorage.instance.ref('user_banners/$uid/banner.jpg').delete(); } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Banner eliminado'), backgroundColor: context.successColor));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: context.dangerColor));
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

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
    final isSupporter = context.watch<SupporterProvider>().isSupporter;

    return StreamBuilder<UserProfile?>(
      stream: UserService.profileStream(uid),
      builder: (context, snap) {
        final profile = snap.data;
        final isPublic = _isPublicLocal ?? profile?.isPublic ?? true;
        final photoUrl = profile?.photoUrl ?? widget.authProvider.photoUrl;
        final name = profile?.displayName ?? widget.authProvider.displayName ?? 'Usuario';
        final hasBanner = profile?.bannerUrl != null && profile!.bannerUrl!.isNotEmpty;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Banner + Avatar header ──────────────────────────────────
              _ProfileBannerHeader(
                profile: profile,
                photoUrl: photoUrl,
                name: name,
                isSupporter: isSupporter,
                hasBanner: hasBanner,
                uploadingBanner: _uploadingBanner,
                uploadingPhoto: _uploadingPhoto,
                onEditBanner: () => _pickAndUploadBanner(context, uid),
                onRemoveBanner: hasBanner ? () => _removeBanner(context, uid) : null,
                onEditPhoto: () => _changePhoto(context),
                onEditName: () => _editDisplayName(context, name),
                email: widget.authProvider.email,
                bannerAlignY: profile?.bannerAlignY ?? 0.0,
              ),

              // ── Resto del contenido ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
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
                  activeThumbColor: Theme.of(context).colorScheme.primary,
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
                  icon: Icon(Icons.download_for_offline_outlined, color: Theme.of(context).colorScheme.secondary),
                  label: Text('Mis descargas', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)),
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
                ), // inner Column
              ), // Padding
            ], // outer Column children
          ), // outer Column
        ); // SingleChildScrollView
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
                icon: Icon(Icons.download_for_offline_outlined, color: Theme.of(context).colorScheme.secondary),
                label: Text('Mis descargas', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)),
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

// ── Banner header editable ────────────────────────────────────────────────────
class _ProfileBannerHeader extends StatelessWidget {
  final UserProfile? profile;
  final String? photoUrl;
  final String name;
  final String? email;
  final bool isSupporter;
  final bool hasBanner;
  final bool uploadingBanner;
  final bool uploadingPhoto;
  final VoidCallback onEditBanner;
  final VoidCallback? onRemoveBanner;
  final VoidCallback onEditPhoto;
  final VoidCallback onEditName;
  final double bannerAlignY;

  static const double _bannerHeight = 140;
  static const double _avatarRadius = 48;

  const _ProfileBannerHeader({
    required this.profile, required this.photoUrl, required this.name,
    required this.email, required this.isSupporter, required this.hasBanner,
    required this.uploadingBanner, required this.uploadingPhoto,
    required this.onEditBanner, required this.onRemoveBanner,
    required this.onEditPhoto, required this.onEditName,
    this.bannerAlignY = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: _bannerHeight + _avatarRadius,
        child: Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: isSupporter ? onEditBanner : null,
            child: Container(
              height: _bannerHeight, width: double.infinity,
              decoration: BoxDecoration(color: context.cardColor),
              child: hasBanner
                  ? Image.network(
                      profile!.bannerUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment(0, bannerAlignY),
                      width: double.infinity,
                      height: _bannerHeight,
                      errorBuilder: (_, __, ___) => _placeholder(context),
                    )
                  : _placeholder(context),
            ),
          ),
          if (isSupporter)
            Positioned(right: 10, top: _bannerHeight - 42,
              child: Row(children: [
                if (onRemoveBanner != null) ...[
                  _SmallBtn(icon: Icons.delete_outline_rounded, loading: false, onTap: onRemoveBanner!),
                  const SizedBox(width: 6),
                ],
                _SmallBtn(
                  icon: uploadingBanner ? null : Icons.add_photo_alternate_outlined,
                  loading: uploadingBanner, onTap: onEditBanner),
              ]),
            ),
          if (!isSupporter)
            Positioned(right: 10, top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 5),
                  Text('Banner exclusivo 👑', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          Positioned(bottom: 0, left: 0, right: 0,
            child: Center(child: Stack(children: [
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.backgroundColor, width: 4)),
                child: CircleAvatar(
                  radius: _avatarRadius,
                  backgroundImage: photoUrl != null && photoUrl!.isNotEmpty ? NetworkImage(photoUrl!) : null,
                  backgroundColor: context.primaryColor.withValues(alpha: 0.3),
                  child: photoUrl == null || photoUrl!.isEmpty
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: TextStyle(fontSize: _avatarRadius * 0.65, fontWeight: FontWeight.bold, color: Colors.white))
                      : null,
                ),
              ),
              Positioned(right: 2, bottom: 2,
                child: Material(color: context.primaryColor, shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: uploadingPhoto ? null : onEditPhoto,
                    child: Padding(padding: const EdgeInsets.all(8),
                      child: uploadingPhoto
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt, color: Colors.white, size: 16))))),
            ]))),
        ]),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: onEditName,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (profile?.isSupporter == true) ...[const Text('👑', style: TextStyle(fontSize: 16)), const SizedBox(width: 6)],
            Flexible(child: Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary), textAlign: TextAlign.center)),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, size: 16, color: context.textSecondary),
          ])),
      ),
      if (email != null) Text(email!, style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const SizedBox(height: 4),
      Text('Toca tu nombre · cámara para foto', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.textSecondary.withValues(alpha: 0.7))),
    ]);
  }

  Widget _placeholder(BuildContext context) => Container(
    height: _bannerHeight,
    decoration: BoxDecoration(gradient: LinearGradient(
      colors: [context.primaryColor.withValues(alpha: 0.3), context.primaryColor.withValues(alpha: 0.08)],
      begin: Alignment.topLeft, end: Alignment.bottomRight)),
  );
}

// ── Diálogo de ajuste de posición del banner antes de subir ──────────────────
class _BannerPositionDialog extends StatefulWidget {
  final File imageFile;
  const _BannerPositionDialog({required this.imageFile});

  @override
  State<_BannerPositionDialog> createState() => _BannerPositionDialogState();
}

class _BannerPositionDialogState extends State<_BannerPositionDialog> {
  double _alignY = 0.0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(0),
      backgroundColor: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Título
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.crop_free_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ajusta la posición del banner',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Preview con drag
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) {
              setState(() {
                _alignY = (_alignY + d.delta.dy / 90).clamp(-1.0, 1.0);
              });
            },
            child: Stack(
              children: [
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.cover,
                    alignment: Alignment(0, _alignY),
                  ),
                ),
                // Hint de arrastre
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_vert_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Arrastra para reposicionar',
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Slider + botones
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.arrow_upward_rounded, color: Colors.white54, size: 16),
                Expanded(
                  child: Slider(
                    value: _alignY,
                    min: -1.0,
                    max: 1.0,
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => _alignY = v),
                  ),
                ),
                const Icon(Icons.arrow_downward_rounded, color: Colors.white54, size: 16),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white24)),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, (alignY: _alignY, file: widget.imageFile)),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData? icon;
  final bool loading;
  final VoidCallback onTap;
  const _SmallBtn({required this.icon, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(width: 32, height: 32,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Center(child: loading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 16, color: Colors.white))));
}
