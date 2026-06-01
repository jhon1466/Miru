class StickerItem {
  final String id;
  final String filePath;
  final String? label;

  StickerItem({required this.id, required this.filePath, this.label});

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'label': label,
      };

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      label: json['label'] as String?,
    );
  }
}

class StickerPack {
  final String id;
  final String name;
  final List<StickerItem> stickers;

  StickerPack({
    required this.id,
    required this.name,
    required this.stickers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'stickers': stickers.map((s) => s.toJson()).toList(),
      };

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    final list = json['stickers'] as List? ?? [];
    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Stickers',
      stickers: list
          .whereType<Map>()
          .map((e) => StickerItem.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.filePath.isNotEmpty)
          .toList(),
    );
  }
}
