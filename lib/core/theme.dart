import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Opciones de tema visibles al usuario.
/// [light] y [dark] usan el color fijo original (morado).
/// [custom] permite elegir un color de acento personalizado.
enum AppThemeOption { light, dark, custom }

class AppTheme {
  static const Color darkBackground = Color(0xFF0A0D14);
  static const Color cardColor = Color(0xFF161B26);
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color successColor = Color(0xFF10B981);

  /// Color semilla por defecto (morado original)
  static const Color defaultSeedColor = Color(0xFF8B5CF6);

  /// Constantes de color para uso estático (sin BuildContext).
  /// Para uso dinámico en widgets, usa `context.primaryColor` en su lugar.
  static const Color primaryColor = Color(0xFF8B5CF6);
  static const Color accentColor = Color(0xFF0EA5E9);

  /// Colores disponibles para todos los usuarios
  static const List<({Color color, String label})> accentColors = [
    (color: Color(0xFF8B5CF6), label: 'Morado'),
    (color: Color(0xFF6366F1), label: 'Índigo'),
    (color: Color(0xFF3B82F6), label: 'Azul'),
    (color: Color(0xFF06B6D4), label: 'Cyan'),
    (color: Color(0xFF10B981), label: 'Verde'),
    (color: Color(0xFF84CC16), label: 'Lima'),
    (color: Color(0xFFF59E0B), label: 'Ámbar'),
    (color: Color(0xFFF97316), label: 'Naranja'),
    (color: Color(0xFFEF4444), label: 'Rojo'),
    (color: Color(0xFFEC4899), label: 'Rosa'),
  ];

  /// Colores exclusivos para supporters (Patreon)
  static const List<({Color color, String label})> supporterAccentColors = [
    (color: Color(0xFF14B8A6), label: 'Jade'),
    (color: Color(0xFF0EA5E9), label: 'Celeste'),
    (color: Color(0xFFA855F7), label: 'Violeta'),
    (color: Color(0xFFD946EF), label: 'Fucsia'),
    (color: Color(0xFFFF6B6B), label: 'Coral'),
    (color: Color(0xFFFFD93D), label: 'Dorado'),
    (color: Color(0xFF6BCB77), label: 'Menta'),
    (color: Color(0xFF4D96FF), label: 'Zafiro'),
    (color: Color(0xFFFF9A3C), label: 'Mandarina'),
    (color: Color(0xFFB5838D), label: 'Malva'),
  ];

  static ThemeData darkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface: cardColor,
      onSurface: textPrimary,
      error: dangerColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBackground,
      cardColor: cardColor,
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 32),
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
          titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
          bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        hintStyle: const TextStyle(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerColor, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: textSecondary,
        elevation: 8,
      ),
    );
  }

  static ThemeData lightTheme(Color seedColor) {
    const lightBackground = Color(0xFFF3F4F6);
    const lightCard = Colors.white;
    const lightTextPrimary = Color(0xFF111827);
    const lightTextSecondary = Color(0xFF4B5563);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ).copyWith(
      surface: lightCard,
      onSurface: lightTextPrimary,
      error: dangerColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBackground,
      cardColor: lightCard,
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold, fontSize: 32),
          titleLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold, fontSize: 20),
          titleMedium: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          bodyLarge: TextStyle(color: lightTextPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: lightTextSecondary, fontSize: 14),
          bodySmall: TextStyle(color: lightTextSecondary, fontSize: 12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: lightTextPrimary),
        titleTextStyle: GoogleFonts.outfit(
          color: lightTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        hintStyle: const TextStyle(color: lightTextSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerColor, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightCard,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: lightTextSecondary,
        elevation: 8,
      ),
    );
  }
}

extension AppThemeExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get cardColor => Theme.of(this).cardColor;
  Color get backgroundColor => Theme.of(this).scaffoldBackgroundColor;

  Color get textPrimary => Theme.of(this).textTheme.bodyLarge?.color ??
      (isDarkMode ? const Color(0xFFF3F4F6) : const Color(0xFF111827));

  Color get textSecondary => Theme.of(this).textTheme.bodyMedium?.color ??
      (isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563));

  Color get primaryColor => Theme.of(this).colorScheme.primary;
  Color get accentColor => Theme.of(this).colorScheme.secondary;

  Color get dangerColor => AppTheme.dangerColor;
  Color get successColor => AppTheme.successColor;

  // Alias para mantener compatibilidad con widgets que usan Theme.of(context).colorScheme.primary
  Color get appPrimaryColor => Theme.of(this).colorScheme.primary;
}
