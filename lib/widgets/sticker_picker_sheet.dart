import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    final packs = await StickerService.loadPacks();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final userPackId = StickerService.userPackId(uid);
      if (!packs.any((p) => p.id == userPackId)) {
        packs.add(StickerPack(id: userPackId, name: 'Mis stickers', stickers: []));
      }
    }
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final ok = await StickerCreatorSheet.open(context);
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final allStickers = _packs.expand((p) => p.stickers).toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          else if (allStickers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Aún no tienes stickers.\nCrea el primero con una imagen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    label: const Text('Crear sticker'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 220,
              child: GridView.builder(
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
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(item.filePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: AppTheme.cardColor,
                          child: Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
