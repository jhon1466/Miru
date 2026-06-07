import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import '../providers/manga_history_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/anime_provider.dart';
import '../services/api_cache_service.dart';
import '../services/user_service.dart';
import '../services/anilist_service.dart';
import 'package:flutter/painting.dart';
import '../utils/auth_ui.dart';
import '../providers/supporter_provider.dart';
import '../widgets/color_wheel_picker.dart';
import 'user_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool showBackButton;
  const SettingsScreen({super.key, this.showBackButton = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

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
    final mangaHistoryProvider = Provider.of<MangaHistoryProvider>(context);
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
            const SizedBox(height: 24),
            _SupporterBannerCard(),
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
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reproducción automática'),
                      subtitle: const Text('Pasar al siguiente episodio al terminar'),
                      value: settings.autoplayNextEpisode,
                      activeThumbColor: context.primaryColor,
                      onChanged: (v) => settings.setAutoplayNextEpisode(v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Descargas en segundo plano'),
                      subtitle: const Text('Mostrar notificaciones del progreso de descargas'),
                      value: settings.backgroundDownloadsEnabled,
                      activeThumbColor: context.primaryColor,
                      onChanged: (v) => settings.setBackgroundDownloadsEnabled(v),
                    ),
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
                        settings.themeOption == AppThemeOption.dark
                            ? Icons.dark_mode
                            : (settings.themeOption == AppThemeOption.light
                                ? Icons.light_mode
                                : Icons.palette_outlined),
                        color: context.primaryColor,
                      ),
                      title: const Text('Tema de la aplicación'),
                      subtitle: Text(
                        settings.themeOption == AppThemeOption.dark
                            ? 'Oscuro'
                            : (settings.themeOption == AppThemeOption.light
                                ? 'Claro'
                                : 'Personalizado'),
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                      trailing: DropdownButton<AppThemeOption>(
                        value: settings.themeOption,
                        dropdownColor: context.cardColor,
                        underline: const SizedBox(),
                        icon: Icon(Icons.arrow_drop_down, color: context.textSecondary),
                        items: [
                          DropdownMenuItem(
                            value: AppThemeOption.light,
                            child: Text('Claro', style: TextStyle(color: context.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: AppThemeOption.dark,
                            child: Text('Oscuro', style: TextStyle(color: context.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: AppThemeOption.custom,
                            child: Text('Personalizado', style: TextStyle(color: context.primaryColor)),
                          ),
                        ],
                        onChanged: (option) {
                          if (option != null) settings.setThemeOption(option);
                        },
                      ),
                    ),
                    // ── Color de acento (solo en modo Personalizado) ─────
                    if (settings.themeOption == AppThemeOption.custom)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.color_lens_outlined, color: context.primaryColor, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Color de acento',
                                      style: TextStyle(fontSize: 16, color: context.textPrimary),
                                    ),
                                    Text(
                                      'Elige el color principal de la app',
                                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Consumer<SupporterProvider>(
                            builder: (context, supporter, _) {
                              final allColors = [
                                ...AppTheme.accentColors.map((e) => (entry: e, exclusive: false)),
                                ...AppTheme.supporterAccentColors.map((e) => (entry: e, exclusive: true)),
                              ];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: allColors.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (context, i) {
                                        final item = allColors[i];
                                        final entry = item.entry;
                                        final locked = item.exclusive && !supporter.isSupporter;
                                        final isSelected = settings.seedColor.value == entry.color.value;
                                        return Tooltip(
                                          message: locked ? '${entry.label} (Supporter)' : entry.label,
                                          child: GestureDetector(
                                            onTap: locked
                                                ? () => _showSupporterLockedSnack(context)
                                                : () => settings.setSeedColor(entry.color),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: locked ? entry.color.withOpacity(0.35) : entry.color,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected ? Colors.white : Colors.transparent,
                                                  width: 3,
                                                ),
                                                boxShadow: isSelected
                                                    ? [
                                                        BoxShadow(
                                                          color: entry.color.withOpacity(0.6),
                                                          blurRadius: 8,
                                                          spreadRadius: 2,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: locked
                                                  ? const Icon(Icons.lock_rounded, color: Colors.white70, size: 18)
                                                  : isSelected
                                                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                                                      : null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Botón rueda de colores (solo supporters)
                                  if (supporter.isSupporter)
                                    GestureDetector(
                                      onTap: () async {
                                        final picked = await showDialog<Color>(
                                          context: context,
                                          builder: (_) => ColorWheelDialog(
                                            initialColor: settings.seedColor,
                                          ),
                                        );
                                        if (picked != null && context.mounted) {
                                          settings.setSeedColor(picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              context.supporterColor.withValues(alpha: 0.12),
                                              const Color(0xFFFF9A3C).withValues(alpha: 0.08),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: context.supporterColor.withValues(alpha: 0.35),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Mini arcoíris circular
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: SweepGradient(
                                                  colors: [
                                                    Color(0xFFFF0000),
                                                    Color(0xFFFFFF00),
                                                    Color(0xFF00FF00),
                                                    Color(0xFF00FFFF),
                                                    Color(0xFF0000FF),
                                                    Color(0xFFFF00FF),
                                                    Color(0xFFFF0000),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Rueda de colores',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: context.supporterColor,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text('👑', style: TextStyle(fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    )
                                  else ...[
                                    Row(
                                      children: [
                                        Icon(Icons.lock_rounded, size: 12, color: context.supporterColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          '10 colores extra + rueda de colores para supporters',
                                          style: TextStyle(fontSize: 11, color: context.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Consumer<AnimeProvider>(
                      builder: (context, animeProvider, _) {
                        final currentFavorite = settings.favoriteProviderDomain;
                        final availableProviders = animeProvider.providers;
                        final exists = availableProviders.any((p) => p['domain'] == currentFavorite);
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.star_border,
                            color: context.primaryColor,
                          ),
                          title: const Text('Proveedor favorito (Home)'),
                          subtitle: const Text('Por defecto para capítulos recientes y populares'),
                          trailing: DropdownButton<String>(
                            value: exists ? currentFavorite : '',
                            dropdownColor: context.cardColor,
                            underline: const SizedBox(),
                            icon: Icon(Icons.arrow_drop_down, color: context.textSecondary),
                            items: availableProviders.map((p) {
                              return DropdownMenuItem<String>(
                                value: p['domain'] ?? '',
                                child: Text(p['name'] ?? 'Todos', style: TextStyle(color: context.textPrimary)),
                              );
                            }).toList(),
                            onChanged: (domain) {
                              if (domain != null) {
                                settings.setFavoriteProviderDomain(domain);
                                animeProvider.selectProvider(domain);
                              }
                            },
                          ),
                        );
                      },
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
                      await mangaHistoryProvider.clearHistory(userId: authProvider.userId);
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
              leading: Icon(Icons.new_releases_outlined, color: context.accentColor),
              title: const Text('¿Qué hay de nuevo?'),
              subtitle: const Text('Novedades de la versión actual'),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => _showWhatsNewDialog(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: context.primaryColor),
              title: const Text('Versión de la app'),
              subtitle: const Text('2.0.8'),
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

  void _showSupporterLockedSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.lock_rounded, color: context.supporterColor, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Color exclusivo para supporters de Patreon 👑',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Apoyar',
          onPressed: () => launchUrl(Uri.parse('https://www.patreon.com/cw/Miruapp'), mode: LaunchMode.externalApplication),
        ),
        duration: const Duration(seconds: 3),
      ),
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

  void _showWhatsNewDialog(BuildContext context) {
    const changelog = [
      _ChangelogEntry(
        version: '2.0.8',
        date: 'Junio 2025',
        highlights: [
          '👑 Sistema de Supporters con beneficios exclusivos',
          '🎨 10 colores de acento exclusivos para supporters',
          '💬 Chat mejorado: cooldown, límite de caracteres y stickers VIP',
          '🏆 Insignia de Supporter en perfil, comentarios y chat',
          '🔎 Historial de búsquedas guardado localmente',
          '📖 Tema del lector de novelas persistente entre capítulos',
          '🖼️ Lector de novelas: eliminación de imágenes embebidas en texto',
          '🔔 Markdown en notas de actualización (negritas, listas, etc.)',
        ],
      ),
      _ChangelogEntry(
        version: '2.0.7',
        date: 'Mayo 2025',
        highlights: [
          '📚 Novelas con SkyNovels integrado',
          '📺 Episodios con MonosChinos',
          '🖼️ Mejoras de imágenes y caché',
          '🌙 Modo OLED en el lector de novelas',
        ],
      ),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: context.accentColor, size: 24),
            const SizedBox(width: 10),
            const Text('¿Qué hay de nuevo?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: changelog.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'v${entry.version}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: context.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.date,
                          style: TextStyle(fontSize: 11, color: context.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...entry.highlights.map((h) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        h,
                        style: TextStyle(fontSize: 13, color: context.textPrimary, height: 1.4),
                      ),
                    )),
                    const SizedBox(height: 16),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
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

// ── Supporter Banner ────────────────────────────────────────────────────────
class _SupporterBannerCard extends StatelessWidget {
  static const _patreonUrl = 'https://www.patreon.com/cw/Miruapp';

  const _SupporterBannerCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<SupporterProvider>(
      builder: (context, supporter, _) {
        if (supporter.isSupporter) {
          // Ya es supporter: tarjeta de agradecimiento compacta
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  context.supporterColor.withValues(alpha: 0.12),
                  const Color(0xFFFF9A3C).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.supporterColor.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(
              children: [
                const Text('👑', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¡Eres Supporter de Miru!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.supporterColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Gracias por apoyar el proyecto. Todos tus beneficios están activos.',
                        style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // No es supporter: banner motivador
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1A1025),
                const Color(0xFF201530),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD93D).withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD93D).withValues(alpha: 0.07),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Header dorado
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD93D).withValues(alpha: 0.18),
                      const Color(0xFFFF9A3C).withValues(alpha: 0.10),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Apoya Miru en Patreon',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFD93D),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mantén la app viva y obtén beneficios exclusivos',
                            style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Beneficios
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Column(
                  children: [
                    _benefitRow('🎨', 'Colores de acento exclusivos', '10 colores extra que nadie más puede usar'),
                    const SizedBox(height: 8),
                    _benefitRow('💬', 'Chat sin límites', 'Mensajes largos y sin tiempo de espera'),
                    const SizedBox(height: 8),
                    _benefitRow('🏆', 'Insignia en perfil y comentarios', 'Destaca con la corona de Supporter'),
                    const SizedBox(height: 8),
                    _benefitRow('⬇️', 'Descarga temporadas completas', 'Un toque para descargar todos los episodios'),
                    const SizedBox(height: 8),
                    _benefitRow('🎭', 'Stickers exclusivos en el chat', 'Acceso a stickers que no están disponibles para todos'),
                  ],
                ),
              ),

              // Separador
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Divider(color: const Color(0xFFFFD93D).withValues(alpha: 0.15), height: 20),
              ),

              // CTA
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => launchUrl(
                          Uri.parse(_patreonUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF424D), // color Patreon
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('❤️', style: TextStyle(fontSize: 16)),
                            SizedBox(width: 8),
                            Text(
                              'Unirme en Patreon',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cancela cuando quieras · Sin compromisos',
                      style: TextStyle(fontSize: 10, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _benefitRow(String emoji, String title, String subtitle) {
    return Builder(
      builder: (context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  final String version;
  final String date;
  final List<String> highlights;

  const _ChangelogEntry({
    required this.version,
    required this.date,
    required this.highlights,
  });
}
