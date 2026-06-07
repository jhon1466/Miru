import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/sticker.dart';
import '../providers/supporter_provider.dart';
import '../services/sticker_service.dart';
import 'sticker_creator_sheet.dart';

/// Stickers exclusivos para supporters (URLs de CDN públicas o assets locales).
/// Reemplaza estas URLs con las reales cuando estén disponibles.
const _kSupporterStickers = [
  (id: 'sup_01', emoji: '👑', label: 'Corona'),
  (id: 'sup_02', emoji: '🌟', label: 'Estrella'),
  (id: 'sup_03', emoji: '💎', label: 'Diamante'),
  (id: 'sup_04', emoji: '🔥', label: 'Fuego'),
  (id: 'sup_05', emoji: '⚡', label: 'Rayo'),
  (id: 'sup_06', emoji: '🦄', label: 'Unicornio'),
  (id: 'sup_07', emoji: '🎭', label: 'Máscara'),
  (id: 'sup_08', emoji: '🎪', label: 'Circo'),
  (id: 'sup_09', emoji: '🐉', label: 'Dragón'),
  (id: 'sup_10', emoji: '🌈', label: 'Arcoíris'),
  (id: 'sup_11', emoji: '🎸', label: 'Guitarra'),
  (id: 'sup_12', emoji: '🍣', label: 'Sushi'),
];

class StickerPickerSheet extends StatefulWidget {
  final bool isSupporter;
  const StickerPickerSheet({super.key, this.isSupporter = false});

  static Future<StickerItem?> pick(BuildContext context) {
    // Leer isSupporter ANTES de abrir el sheet para que el nuevo contexto
    // del modal no pierda el valor del Provider.
    final isSupporter = context.read<SupporterProvider>().isSupporter;
    return showModalBottomSheet<StickerItem>(
      context: context,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => StickerPickerSheet(isSupporter: isSupporter),
    );
  }

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  List<StickerPack> _packs = [];
  bool _loading = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await StickerService.syncStickersWithCloud(uid);
    }
    
    final customPacks = await StickerService.loadPacks();
    if (uid != null) {
      final userPackId = StickerService.userPackId(uid);
      if (!customPacks.any((p) => p.id == userPackId)) {
        customPacks.add(StickerPack(id: userPackId, name: 'Mis stickers', stickers: []));
      }
    }
    if (!mounted) return;
    setState(() {
      _packs = customPacks;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final picked = await StickerService.pickImageForSticker();
    if (picked == null || !mounted) return;

    final pathLower = picked.path.toLowerCase();
    final isAnimated = pathLower.endsWith('.gif') || pathLower.endsWith('.webp');

    if (isAnimated) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      setState(() => _loading = true);
      final item = await StickerService.saveToPack(
        packId: StickerService.userPackId(uid),
        sourceFile: File(picked.path),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(item != null ? 'Sticker animado guardado' : 'Error al guardar sticker animado'),
            backgroundColor: item != null ? AppTheme.successColor : AppTheme.dangerColor,
          ),
        );
      }
    } else {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => StickerCreatorSheet(imageFile: File(picked.path)),
      );
      if (ok == true) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 250,
        child: Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    final allStickers = _packs.expand((p) => p.stickers).toList();
    final isSupporter = widget.isSupporter;

    return SafeArea(
      child: SizedBox(
        height: 320,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Stickers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _create,
                    icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                    label: Text('Crear', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: context.textSecondary,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: 'Mis stickers'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('👑 Exclusivos'),
                    ],
                  ),
                ),
              ],
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: User stickers
                  allStickers.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Aún no tienes stickers.\nCrea uno con una imagen o GIF/WebP.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.textSecondary, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.emoji_emotions_outlined),
                                label: const Text('Crear sticker'),
                                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: allStickers.length,
                          itemBuilder: (context, index) {
                            final item = allStickers[index];
                            return InkWell(
                              onTap: () => Navigator.pop(context, item),
                              onLongPress: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;

                      final pack = _packs.firstWhere(
                        (p) => p.stickers.any((s) => s.id == item.id),
                        orElse: () => _packs.first,
                      );

                      final delete = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: context.cardColor,
                          title: Text('Eliminar sticker', style: TextStyle(color: context.textPrimary)),
                          content: Text(
                            '¿Deseas eliminar este sticker permanentemente?',
                            style: TextStyle(color: context.textSecondary),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Eliminar', style: TextStyle(color: AppTheme.dangerColor)),
                            ),
                          ],
                        ),
                      );

                      if (delete == true) {
                        setState(() => _loading = true);
                        await StickerService.deleteSticker(pack.id, item.id);
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sticker eliminado'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.filePath.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: item.filePath,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => Container(
                                color: context.cardColor,
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: context.cardColor,
                                child: Icon(Icons.broken_image_outlined, color: context.textSecondary),
                              ),
                            )
                          : Image.file(
                              File(item.filePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: context.cardColor,
                                child: Icon(Icons.broken_image_outlined, color: context.textSecondary),
                              ),
                            ),
                            ),
                          );
                          },
                        ),

                  // Tab 2: Supporter exclusive stickers
                  isSupporter
                      ? GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _kSupporterStickers.length,
                          itemBuilder: (context, index) {
                            final s = _kSupporterStickers[index];
                            return InkWell(
                              onTap: () => Navigator.pop(
                                context,
                                StickerItem(
                                  id: s.id,
                                  filePath: s.emoji, // emoji as "path" — renderer handles it
                                  label: s.label,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD93D).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFFD93D).withOpacity(0.25),
                                  ),
                                ),
                                child: Center(
                                  child: Text(s.emoji, style: const TextStyle(fontSize: 32)),
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('👑', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  'Stickers exclusivos para supporters de Patreon',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Apoya el proyecto en Patreon y desbloquea estos stickers y mucho más.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
