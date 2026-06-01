import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/anime_provider.dart';
import '../services/api_cache_service.dart';
import '../services/user_service.dart';
import 'package:flutter/painting.dart';
import '../utils/auth_ui.dart';
import 'user_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool showBackButton;
  const SettingsScreen({super.key, this.showBackButton = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _autoplayNextEpisode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final historyProvider = Provider.of<HistoryProvider>(context);
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        leading: widget.showBackButton 
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Sección de Cuenta ───────────────────────────────────────
            _buildAccountSection(context, authProvider),
            if (authProvider.isLoggedIn) ...[
              const SizedBox(height: 24),
              _buildProfileOptionsSection(context, authProvider),
            ],
            const SizedBox(height: 32),

            const Text(
              'Preferencias',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notificaciones de actualizaciones'),
              subtitle: const Text('Avisarte cuando haya una nueva versión de Miru'),
              value: _notificationsEnabled,
              activeColor: AppTheme.primaryColor,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reproducción automática'),
              subtitle: const Text('Pasar al siguiente episodio al terminar (próximamente)'),
              value: _autoplayNextEpisode,
              activeColor: AppTheme.primaryColor,
              onChanged: (v) => setState(() => _autoplayNextEpisode = v),
            ),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Contenido +18'),
                  subtitle: Text(
                    settings.adultContentEnabled
                        ? 'HentaiLA visible en catálogo y buscador'
                        : 'Catálogo familiar sin contenido para adultos',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  value: settings.adultContentEnabled,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: (value) async {
                    if (value) {
                      final ok = await _confirmAdultContent(context);
                      if (!ok || !context.mounted) return;
                    }
                    await settings.setAdultContentEnabled(value);
                    if (!context.mounted) return;
                    context.read<AnimeProvider>().setAdultContentEnabled(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Contenido +18 activado'
                              : 'Contenido +18 desactivado',
                        ),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'Datos de Aplicación',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: AppTheme.cardColor, height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limpiar Historial de Reproducción'),
              subtitle: const Text('Borra la lista de capítulos que has empezado a ver'),
              leading: const Icon(Icons.history, color: AppTheme.dangerColor),
              trailing: IconButton(
                icon: const Icon(Icons.delete_sweep, color: AppTheme.dangerColor),
                onPressed: () {
                  _showConfirmDeleteDialog(
                    context, 
                    'Historial', 
                    '¿Estás seguro de que deseas vaciar tu historial de reproducción?',
                    () async {
                      await historyProvider.clearHistory(userId: authProvider.userId);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Historial eliminado'), backgroundColor: AppTheme.successColor),
                      );
                    }
                  );
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limpiar caché de la app'),
              subtitle: const Text('Borra datos de catálogo guardados y miniaturas en disco'),
              leading: const Icon(Icons.cleaning_services, color: AppTheme.accentColor),
              trailing: IconButton(
                icon: const Icon(Icons.cached, color: AppTheme.accentColor),
                onPressed: () async {
                  await ApiCacheService.clearAll();
                  imageCache.clear();
                  imageCache.clearLiveImages();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Caché de API e imágenes vaciada'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Acerca de Miru',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: AppTheme.cardColor, height: 24),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: AppTheme.primaryColor),
              title: Text('Versión de la app'),
              subtitle: Text('1.4.0'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.movie_filter_outlined, color: AppTheme.accentColor),
              title: Text('Miru Anime'),
              subtitle: Text('Tu biblioteca de anime en un solo lugar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOptionsSection(BuildContext context, app_auth.AuthProvider authProvider) {
    return _ProfilePrivacyCard(
      userId: authProvider.userId!,
      displayName: authProvider.displayName ?? 'Usuario',
      photoUrl: authProvider.photoUrl,
    );
  }

  Future<bool> _confirmAdultContent(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Contenido para adultos', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Confirmas que tienes 18 años o más. Se mostrará el proveedor HentaiLA en catálogo y buscador.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Soy mayor de 18', style: TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showConfirmDeleteDialog(BuildContext context, String title, String content, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.dangerColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context, app_auth.AuthProvider authProvider) {
    if (authProvider.isLoggedIn) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mi Cuenta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundImage: authProvider.photoUrl != null
                      ? NetworkImage(authProvider.photoUrl!)
                      : null,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.3),
                  child: authProvider.photoUrl == null
                      ? Text(
                          (authProvider.displayName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authProvider.displayName ?? 'Usuario',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        authProvider.email ?? '',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '✓ Cuenta en la nube',
                          style: TextStyle(fontSize: 10, color: AppTheme.successColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: authProvider.userId!,
                        displayName: authProvider.displayName ?? 'Usuario',
                        photoUrl: authProvider.photoUrl,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.account_circle_outlined, size: 18, color: AppTheme.primaryColor),
                label: const Text('Ver mi perfil y favoritos', style: TextStyle(color: AppTheme.primaryColor)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await authProvider.signOut();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sesión cerrada correctamente'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
                icon: const Icon(Icons.logout, size: 18, color: AppTheme.dangerColor),
                label: const Text('Cerrar sesión', style: TextStyle(color: AppTheme.dangerColor)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.dangerColor, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // No logueado
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor.withOpacity(0.15), AppTheme.cardColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_outline, color: AppTheme.primaryColor, size: 22),
              SizedBox(width: 8),
              Text(
                'Cuenta Miru',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Inicia sesión con Google para sincronizar tus favoritos y comentar en los animes que amas.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => signInWithGoogleAndWelcome(context, authProvider),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.g_mobiledata_rounded, size: 26, color: Color(0xFF4285F4)),
                  SizedBox(width: 8),
                  Text(
                    'Continuar con Google',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePrivacyCard extends StatefulWidget {
  final String userId;
  final String displayName;
  final String? photoUrl;

  const _ProfilePrivacyCard({
    required this.userId,
    required this.displayName,
    this.photoUrl,
  });

  @override
  State<_ProfilePrivacyCard> createState() => _ProfilePrivacyCardState();
}

class _ProfilePrivacyCardState extends State<_ProfilePrivacyCard> {
  bool? _overridePublic;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: UserService.profileStream(widget.userId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final isPublic = _overridePublic ?? profile?.isPublic ?? true;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perfil y Privacidad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Controla quién puede ver tu perfil y tus animes favoritos al tocar tu nombre en los comentarios.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Perfil público'),
                subtitle: Text(
                  isPublic
                      ? 'Cualquiera puede ver tus favoritos desde comentarios'
                      : 'Tu perfil y favoritos están ocultos para otros usuarios',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                value: isPublic,
                activeThumbColor: AppTheme.primaryColor,
                onChanged: (value) async {
                  setState(() => _overridePublic = value);
                  try {
                    await UserService.setProfilePublic(widget.userId, value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value ? 'Perfil configurado como público' : 'Perfil configurado como privado',
                        ),
                        backgroundColor: AppTheme.successColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } catch (e) {
                    setState(() => _overridePublic = !value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al guardar privacidad: $e'),
                        backgroundColor: AppTheme.dangerColor,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(
                          userId: widget.userId,
                          displayName: widget.displayName,
                          photoUrl: widget.photoUrl,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person, size: 18, color: AppTheme.primaryColor),
                  label: const Text('Ver mi perfil', style: TextStyle(color: AppTheme.primaryColor)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
