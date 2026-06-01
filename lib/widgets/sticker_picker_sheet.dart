import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/theme.dart';
import '../models/sticker.dart';
import '../services/sticker_service.dart';
import 'sticker_creator_sheet.dart';

class StickerPickerSheet extends StatefulWidget {
  const StickerPickerSheet({super.key});

  static Future<StickerItem?> pick(BuildContext context) {
    return showModalBottomSheet<StickerItem>(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const StickerPickerSheet(),
    );
  }

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  List<StickerPack> _packs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customPacks = await StickerService.loadPacks();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final userPackId = StickerService.userPackId(uid);
      if (!customPacks.any((p) => p.id == userPackId)) {
        customPacks.add(StickerPack(id: userPackId, name: 'Mis stickers', stickers: []));
      }
    }
    final builtIn = StickerService.getBuiltInPacks();
    if (!mounted) return;
    setState(() {
      _packs = [...customPacks, ...builtIn];
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
        backgroundColor: AppTheme.cardColor,
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
      return const SizedBox(
        height: 250,
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return DefaultTabController(
      length: _packs.length,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Stickers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                    label: const Text('Crear', style: TextStyle(color: AppTheme.primaryColor)),
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primaryColor,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: AppTheme.textSecondary,
              dividerColor: Colors.transparent,
              tabs: _packs.map((p) => Tab(text: p.name)).toList(),
            ),
            SizedBox(
              height: 220,
              child: TabBarView(
                children: _packs.map((pack) {
                  if (pack.stickers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Aún no tienes stickers.\nCrea uno con una imagen o GIF/WebP.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.emoji_emotions_outlined),
                            label: const Text('Crear sticker'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                          ),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: pack.stickers.length,
                    itemBuilder: (context, index) {
                      final item = pack.stickers[index];
                      return InkWell(
                        onTap: () => Navigator.pop(context, item),
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: item.filePath.startsWith('http')
                              ? CachedNetworkImage(
                                  imageUrl: item.filePath,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => Container(
                                    color: AppTheme.cardColor,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => const ColoredBox(
                                    color: AppTheme.cardColor,
                                    child: Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                                  ),
                                )
                              : Image.file(
                                  File(item.filePath),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: AppTheme.cardColor,
                                    child: Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                                  ),
                                ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
