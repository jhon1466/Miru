import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/anime_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/adult_content.dart';

/// En catálogo solo se muestra HentaiLA cuando +18 está activo (sin selector de otros proveedores).
class CatalogHentaiChip extends StatelessWidget {
  final AnimeProvider provider;

  const CatalogHentaiChip({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        if (!settings.adultContentEnabled) return const SizedBox.shrink();

        final isHentai = provider.selectedProviderDomain == AdultContent.hentaiDomain;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('HentaiLA (+18)'),
              selected: isHentai,
              onSelected: (selected) {
                provider.selectProvider(
                  selected ? AdultContent.hentaiDomain : '',
                );
                provider.loadCatalog(forceNetwork: true);
              },
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.25),
              checkmarkColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                fontSize: 12,
                color: isHentai ? AppTheme.primaryColor : AppTheme.textSecondary,
                fontWeight: isHentai ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
