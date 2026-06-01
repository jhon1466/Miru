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

            Text(
              'Preferencias',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notificaciones de actualizaciones'),
              subtitle: const Text('Avisarte cuando haya una nueva versión de Miru'),
              value: _notificationsEnabled,
              activeColor: context.primaryColor,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reproducción automática'),
              subtitle: const Text('Pasar al siguiente episodio al terminar (próximamente)'),
              value: _autoplayNextEpisode,
              activeColor: context.primaryColor,
              onChanged: (v) => setState(() => _autoplayNextEpisode = v),
            ),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Contenido +18'),
                      subtitle: Text(
                        settings.adultContentEnabled
                            ? 'HentaiLA visible en catálogo y buscador'
                            : 'Catálogo familiar sin contenido para adultos',
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                      value: settings.adultContentEnabled,
                      activeThumbColor: context.primaryColor,
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
                            backgroundColor: context.successColor,
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        settings.themeMode == ThemeMode.dark
                            ? Icons.dark_mode
                            : (settings.themeMode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto),
                        color: context.primaryColor,
                      ),
                      title: const Text('Tema de la aplicación'),
                      subtitle: Text(
                        settings.themeMode == ThemeMode.dark
                            ? 'Oscuro'
                            : (settings.themeMode == ThemeMode.light ? 'Claro' : 'Sistema'),
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                      trailing: DropdownButton<ThemeMode>(
                        value: settings.themeMode,
                        dropdownColor: context.cardColor,
                        underline: const SizedBox(),
                        icon: Icon(Icons.arrow_drop_down, color: context.textSecondary),
                        items: [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('Sistema', style: TextStyle(color: context.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Claro', style: TextStyle(color: context.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Oscuro', style: TextStyle(color: context.textPrimary)),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) {
                            settings.setThemeMode(mode);
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Datos de Aplicación',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            Divider(color: context.cardColor, height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limpiar Historial de Reproducción'),
              subtitle: const Text('Borra la lista de capítulos que has empezado a ver'),
              leading: Icon(Icons.history, color: context.dangerColor),
              trailing: IconButton(
                icon: Icon(Icons.delete_sweep, color: context.dangerColor),
                onPressed: () {
                  _showConfirmDeleteDialog(
                    context, 
                    'Historial', 
                    '¿Estás seguro de que deseas vaciar tu historial de reproducción?',
                    () async {
                      await historyProvider.clearHistory(userId: authProvider.userId);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Historial eliminado'), backgroundColor: context.successColor),
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
              leading: Icon(Icons.cleaning_services, color: context.accentColor),
              trailing: IconButton(
                icon: Icon(Icons.cached, color: context.accentColor),
                onPressed: () async {
                  await ApiCacheService.clearAll();
                  imageCache.clear();
                  imageCache.clearLiveImages();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Caché de API e imágenes vaciada'),
                      backgroundColor: context.successColor,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Acerca de Miru',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            Divider(color: context.cardColor, height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: context.primaryColor),
              title: const Text('Versión de la app'),
              subtitle: const Text('1.8.0'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.movie_filter_outlined, color: context.accentColor),
              title: const Text('Miru Anime'),
              subtitle: const Text('Tu biblioteca de anime en un solo lugar'),
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
        backgroundColor: context.cardColor,
        title: Text('Contenido para adultos', style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Confirmas que tienes 18 años o más. Se mostrará el proveedor HentaiLA en catálogo y buscador.',
          style: TextStyle(color: context.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Soy mayor de 18', style: TextStyle(color: context.primaryColor)),
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
        backgroundColor: context.cardColor,
        title: Text(title, style: TextStyle(color: context.textPrimary)),
        content: Text(content, style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text('Eliminar', style: TextStyle(color: context.dangerColor)),
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
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.primaryColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mi Cuenta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
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
                  backgroundColor: context.primaryColor.withOpacity(0.3),
                  child: authProvider.photoUrl == null
                      ? Text(
                          (authProvider.displayName ?? 'U')[0].toUpperCase(),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        authProvider.email ?? '',
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.successColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '✓ Cuenta en la nube',
                          style: TextStyle(fontSize: 10, color: context.successColor, fontWeight: FontWeight.bold),
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
                icon: Icon(Icons.account_circle_outlined, size: 18, color: context.primaryColor),
                label: Text('Ver mi perfil y favoritos', style: TextStyle(color: context.primaryColor)),
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
                    SnackBar(
                      content: const Text('Sesión cerrada correctamente'),
                      backgroundColor: context.successColor,
                    ),
                  );
                },
                icon: Icon(Icons.logout, size: 18, color: context.dangerColor),
                label: Text('Cerrar sesión', style: TextStyle(color: context.dangerColor)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.dangerColor, width: 1),
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
          colors: [context.primaryColor.withOpacity(0.15), context.cardColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: context.primaryColor, size: 22),
              const SizedBox(width: 8),
              Text(
                'Cuenta Miru',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Inicia sesión con Google para sincronizar tus favoritos y comentar en los animes que amas.',
            style: TextStyle(fontSize: 13, color: context.textSecondary, height: 1.4),
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
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.accentColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Perfil y Privacidad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Controla quién puede ver tu perfil y tus animes favoritos al tocar tu nombre en los comentarios.',
                style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Perfil público'),
                subtitle: Text(
                  isPublic
                      ? 'Cualquiera puede ver tus favoritos desde comentarios'
                      : 'Tu perfil y favoritos están ocultos para otros usuarios',
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
                value: isPublic,
                activeThumbColor: context.primaryColor,
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
                        backgroundColor: context.successColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } catch (e) {
                    setState(() => _overridePublic = !value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al guardar privacidad: $e'),
                        backgroundColor: context.dangerColor,
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
                  icon: Icon(Icons.person, size: 18, color: context.primaryColor),
                  label: Text('Ver mi perfil', style: TextStyle(color: context.primaryColor)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.primaryColor.withValues(alpha: 0.5)),
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
