import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/theme.dart';
import '../services/sticker_service.dart';

/// Creador de stickers (recorte cuadrado estilo WhatsApp).
class StickerCreatorSheet extends StatefulWidget {
  final File imageFile;

  const StickerCreatorSheet({super.key, required this.imageFile});

  static Future<bool?> open(BuildContext context) async {
    final picked = await StickerService.pickImageForSticker();
    if (picked == null || !context.mounted) return false;

    final pathLower = picked.path.toLowerCase();
    final nameLower = picked.name.toLowerCase();
    final isAnimated = pathLower.endsWith('.gif') || pathLower.endsWith('.webp') ||
                       nameLower.endsWith('.gif') || nameLower.endsWith('.webp');

    if (isAnimated) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicia sesión para crear stickers')),
        );
        return false;
      }
      final item = await StickerService.saveToPack(
        packId: StickerService.userPackId(uid),
        sourceFile: File(picked.path),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(item != null ? 'Sticker animado guardado' : 'Error al guardar sticker animado'),
            backgroundColor: item != null ? AppTheme.successColor : AppTheme.dangerColor,
          ),
        );
      }
      return item != null;
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StickerCreatorSheet(imageFile: File(picked.path)),
    );
  }

  @override
  State<StickerCreatorSheet> createState() => _StickerCreatorSheetState();
}

class _StickerCreatorSheetState extends State<StickerCreatorSheet> {
  final _cropController = CropController();
  bool _saving = false;
  late final Future<Uint8List> _imageBytes = widget.imageFile.readAsBytes();

  Future<void> _save() async {
    setState(() => _saving = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Inicia sesión para crear stickers', style: TextStyle(color: context.textPrimary)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Crear sticker',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: FutureBuilder<Uint8List>(
              future: _imageBytes,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryColor),
                  );
                }
                return Crop(
                  controller: _cropController,
                  aspectRatio: null,
                  withCircleUi: false,
                  initialRectBuilder: InitialRectBuilder.withSizeAndRatio(size: 0.85),
                  image: snap.data!,
                  onCropped: (result) async {
                    if (result is! CropSuccess) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No se pudo recortar la imagen'),
                            backgroundColor: AppTheme.dangerColor,
                          ),
                        );
                      }
                      if (mounted) setState(() => _saving = false);
                      return;
                    }
                    final temp = File(
                      '${Directory.systemTemp.path}/miru_sticker_${DateTime.now().millisecondsSinceEpoch}.png',
                    );
                    await temp.writeAsBytes(result.croppedImage);
                    final item = await StickerService.saveToPack(
                      packId: StickerService.userPackId(uid),
                      sourceFile: temp,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, item != null);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Guardar sticker'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
