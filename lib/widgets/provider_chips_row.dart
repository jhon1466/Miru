import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../providers/anime_provider.dart';

/// Selector horizontal de proveedor (catálogo, buscador, etc.).
class ProviderChipsRow extends StatelessWidget {
  final AnimeProvider provider;
  final EdgeInsets padding;

  const ProviderChipsRow({
    super.key,
    required this.provider,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final items = provider.providers;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = items[index];
          final domain = p['domain'] ?? '';
          final selected = provider.selectedProviderDomain == domain;
          return FilterChip(
            label: Text(p['name'] ?? 'Todos'),
            selected: selected,
            onSelected: (_) => provider.selectProvider(domain),
            selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
            checkmarkColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              fontSize: 12,
              color: selected ? Theme.of(context).colorScheme.primary : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        },
      ),
    );
  }
}
