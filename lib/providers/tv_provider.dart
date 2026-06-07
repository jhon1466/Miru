import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detecta si la app corre en Android TV.
///
/// Usa dos señales complementarias:
/// 1. [detectNative] — consulta UiModeManager de Android vía MethodChannel.
/// 2. [updateFromContext] — usa MediaQuery.navigationMode que Flutter pone en
///    NavigationMode.directional cuando el sistema usa D-pad (más fiable en
///    dispositivos sideloaded que no reportan UI_MODE_TYPE_TELEVISION).
class TVProvider extends ChangeNotifier {
  static const _channel = MethodChannel('com.anime1v.app/foreground_service');

  bool _isTV = false;

  bool get isTV => _isTV;

  /// Llamar una vez en main() antes de runApp.
  Future<void> detectNative() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAndroidTV');
      if (result == true) {
        _isTV = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Llamar desde build() para refinar con MediaQuery.
  /// NavigationMode.directional = el sistema está en modo D-pad (TV, teclado).
  void updateFromContext(BuildContext context) {
    final isDpad =
        MediaQuery.of(context).navigationMode == NavigationMode.directional;
    if (isDpad != _isTV) {
      _isTV = isDpad;
      // post-frame para no llamar notifyListeners durante build
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    }
  }
}
