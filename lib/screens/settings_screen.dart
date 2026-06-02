import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/anime_provider.dart';
import '../services/api_cache_service.dart';
import '../services/user_service.dart';
import '../services/anilist_service.dart';
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
                      title: const Text('Notificaciones de actualizaciones'),
                      subtitle: const Text('Avisarte cuando haya una nueva versión de Miru'),
                      value: settings.updateNotificationsEnabled,
                      activeThumbColor: context.primaryColor,
                      onChanged: (v) => settings.setUpdateNotificationsEnabled(v),
                    ),
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
             _buildSincronizacionSection(context),
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
              subtitle: const Text('1.9.6'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.movie_filter_outlined, color: context.accentColor),
              title: const Text('Miru Anime'),
              subtitle: const Text('Tu biblioteca de anime en un solo lugar'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.description_outlined, color: context.primaryColor),
              title: const Text('Términos y Condiciones de Uso'),
              subtitle: const Text('Términos legales del servicio de Miru'),
              onTap: () => _showTermsDialog(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.privacy_tip_outlined, color: context.accentColor),
              title: const Text('Política de Privacidad'),
              subtitle: const Text('Protección de tus datos y privacidad en Miru'),
              onTap: () => _showPrivacyDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSincronizacionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sincronización',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF3DB4F2).withValues(alpha: 0.1),
            child: const Icon(Icons.sync_outlined, color: Color(0xFF3DB4F2)),
          ),
          title: const Text('AniList'),
          subtitle: Text(
            AniListService.isConnected
                ? 'Conectado como ${AniListService.username}'
                : 'Conectar cuenta para sincronizar capítulos vistos',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          trailing: AniListService.isConnected
              ? IconButton(
                  icon: const Icon(Icons.link_off, color: AppTheme.dangerColor),
                  tooltip: 'Desconectar',
                  onPressed: () async {
                    await AniListService.disconnect();
                    setState(() {});
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cuenta de AniList desconectada')),
                    );
                  },
                )
              : IconButton(
                  icon: Icon(Icons.link, color: context.primaryColor),
                  tooltip: 'Conectar',
                  onPressed: () => _showAniListConnectDialog(context),
                ),
        ),
      ],
    );
  }

  void _showAniListConnectDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.sync, color: Color(0xFF3DB4F2)),
                  const SizedBox(width: 10),
                  Text(
                    'Conectar AniList',
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sigue estos pasos para conectar tu cuenta:',
                    style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Presiona el botón de abajo para autorizar a Miru en AniList.\n'
                    '2. Copia el token o código que te muestre la página.\n'
                    '3. Pega el token aquí abajo y dale a conectar.',
                    style: TextStyle(color: context.textSecondary, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3DB4F2),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://anilist.co/api/v2/oauth/authorize?client_id=23348&response_type=token',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('Autorizar en AniList', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Pega el token aquí...',
                      errorText: errorMessage,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primaryColor,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final token = controller.text.trim();
                          if (token.isEmpty) {
                            setDialogState(() {
                              errorMessage = 'El token no puede estar vacío';
                            });
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            errorMessage = null;
                          });

                          final success = await AniListService.connect(token);

                          if (success) {
                            if (mounted) {
                              setState(() {});
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('¡Conectado como ${AniListService.username}!'),
                                  backgroundColor: context.successColor,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isLoading = false;
                              errorMessage = 'Token inválido o expirado';
                            });
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Conectar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileOptionsSection(BuildContext context, app_auth.AuthProvider authProvider) {
    return _ProfilePrivacyCard(
      userId: authProvider.userId!,
      displayName: authProvider.displayName ?? 'Usuario',
      photoUrl: authProvider.photoUrl,
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.cardColor,
          title: Text(
            'Términos y Condiciones de Uso',
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                'El presente documento establece los términos y condiciones de uso de la aplicación Miru. Al acceder, navegar o utilizar esta aplicación, usted acepta sin reservas estos términos, los cuales podrán ser modificados sin previo aviso.\n\n'
                '1. Uso de la Aplicación\n'
                'Miru es una plataforma que presenta una interfaz de usuario orientada a la visualización y gestión de contenido relacionado con el anime. Esta aplicación no aloja directamente archivos de video ni contenido protegido por derechos de autor. Toda la información y contenido disponible en esta plataforma ha sido vinculado o compartido por usuarios, terceros o proveedores externos. Miru no es responsable por el contenido compartido o transmitido a través de enlaces, iframes o reproductores incrustados. Toda la responsabilidad recae en el usuario final.\n\n'
                '2. Responsabilidad del Usuario\n'
                'El usuario es el único responsable por el uso que haga de la plataforma, incluyendo el acceso a contenido enlazado o compartido por terceros. Al utilizar esta aplicación, usted declara ser mayor de edad y acepta asumir toda responsabilidad legal derivada de sus acciones, incluyendo el cumplimiento de las leyes locales respecto a la visualización de contenido protegido.\n\n'
                '3. Propiedad Intelectual\n'
                'Miru no reclama propiedad sobre ninguna obra audiovisual. Todos los nombres, marcas, logotipos y demás elementos protegidos que aparezcan son propiedad de sus respectivos dueños. La aplicación no promueve la distribución de contenido ilegal, y cualquier reclamo será atendido sin ningún problema.\n\n'
                '4. Publicidad y Servicios de Terceros\n'
                'Esta aplicación utiliza servicios de terceros para ofrecer publicidad personalizada y mejorar la experiencia del usuario. Miru no controla el contenido de los anuncios, ni la información recolectada por dichos servicios. Cada empresa de publicidad es responsable por sus políticas de tratamiento de datos.\n\n'
                '5. Modificaciones\n'
                'Miru se reserva el derecho de modificar estos términos y condiciones en cualquier momento. Recomendamos revisar este documento de manera periódica para estar informado de posibles cambios.\n\n'
                '6. Aceptación\n'
                'El uso continuado de la aplicación implica la aceptación de estos términos. Si no está de acuerdo con alguna parte del contenido de este documento, por favor absténgase de utilizar la aplicación.',
                style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.cardColor,
          title: Text(
            'Política de Privacidad',
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                'En Miru nos tomamos en serio la privacidad de nuestros usuarios. Este documento detalla cómo recolectamos, utilizamos y protegemos la información de los visitantes.\n\n'
                '1. Información Recopilada\n'
                'Podemos recopilar automáticamente ciertos datos a través del uso de cookies y tecnologías similares, incluyendo: dirección IP, tipo de navegador, sistema operativo, páginas visitadas, duración de la visita, entre otros.\n\n'
                '2. Uso de la Información\n'
                'La información recolectada se utiliza para mejorar la experiencia del usuario, personalizar el contenido y publicidad, y analizar patrones de tráfico. No vendemos, compartimos ni divulgamos datos personales identificables sin consentimiento, salvo requerimientos legales.\n\n'
                '3. Servicios de Terceros\n'
                'Utilizamos herramientas de terceros que pueden colocar cookies en su navegador. Recomendamos revisar las políticas de privacidad de estos servicios para más información.\n\n'
                '4. Seguridad\n'
                'Aunque tomamos medidas para proteger la información, ningún método de transmisión por internet o almacenamiento electrónico es completamente seguro. Usar la aplicación implica aceptar estos riesgos inherentes.\n\n'
                '5. Cambios en esta Política\n'
                'Nos reservamos el derecho de actualizar esta política en cualquier momento. Le sugerimos revisar esta página periódicamente.\n\n'
                '6. Contacto\n'
                'Para cualquier duda sobre esta política puede escribir a nuestro soporte oficial.',
                style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
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
