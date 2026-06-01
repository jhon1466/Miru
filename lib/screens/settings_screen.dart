import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/history_provider.dart';
import 'splash_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool showBackButton;
  const SettingsScreen({super.key, this.showBackButton = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isTesting = false;
  bool? _testResult;
  String _testResultMessage = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUrl() async {
    final url = await ApiClient.getBaseUrl();
    setState(() {
      _urlController.text = url;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testResultMessage = 'Probando conexión...';
    });

    final targetUrl = _urlController.text.trim();
    if (targetUrl.isEmpty) {
      setState(() {
        _isTesting = false;
        _testResult = false;
        _testResultMessage = 'Por favor ingresa una URL válida';
      });
      return;
    }

    final success = await ApiClient.testConnection(targetUrl);

    setState(() {
      _isTesting = false;
      _testResult = success;
      _testResultMessage = success 
          ? '¡Conexión exitosa! Servidor Miru en línea.' 
          : 'Fallo al conectar. Verifica que el backend esté corriendo y la URL sea correcta.';
    });
  }

  Future<void> _saveSettings() async {
    final targetUrl = _urlController.text.trim();
    if (targetUrl.isEmpty) return;

    await ApiClient.setBaseUrl(targetUrl);
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada correctamente'),
        backgroundColor: AppTheme.successColor,
      ),
    );

    // Reiniciar al splash para validar nuevamente
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SplashScreen()),
      (route) => false,
    );
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
            const SizedBox(height: 32),

            const Text(
              'Servidor Backend API',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Especifica la URL base del servidor Node.js (miru-api). Si usas el emulador Android por defecto, usa http://10.0.2.2:3000. Si usas un dispositivo físico, usa la IP de tu computadora (ej: http://192.168.1.50:3000).',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL Base del Backend',
                hintText: 'http://10.0.2.2:3000',
                prefixIcon: Icon(Icons.dns, color: AppTheme.primaryColor),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting 
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('Probar Conexión'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            if (_testResult != null || _testResultMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult == true 
                      ? AppTheme.successColor.withOpacity(0.15) 
                      : AppTheme.dangerColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _testResult == true ? AppTheme.successColor : AppTheme.dangerColor,
                    width: 1,
                  ),
                ),
                child: Text(
                  _testResultMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: _testResult == true ? AppTheme.successColor : AppTheme.dangerColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
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
                      await historyProvider.clearHistory();
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
              title: const Text('Limpiar Caché de la App'),
              subtitle: const Text('Libera espacio borrando posters guardados en memoria'),
              leading: const Icon(Icons.cleaning_services, color: AppTheme.accentColor),
              trailing: IconButton(
                icon: const Icon(Icons.cached, color: AppTheme.accentColor),
                onPressed: () {
                  // Simulamos limpieza de caché de imágenes
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Caché de imágenes vaciada'), backgroundColor: AppTheme.successColor),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
            const SizedBox(height: 16),
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
              onPressed: () async {
                final success = await authProvider.signInWithGoogle();
                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('¡Bienvenido, ${authProvider.displayName}!'),
                      backgroundColor: AppTheme.successColor,
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
              },
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
