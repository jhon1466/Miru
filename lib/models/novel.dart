class Novel {
  final String id;
  final String title;
  final String url;
  final String? coverUrl;
  final String? status;
  final String? author;

  Novel({
    required this.id,
    required this.title,
    required this.url,
    this.coverUrl,
    this.status,
    this.author,
  });

  factory Novel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final idStr = rawId?.toString() ?? '';
    final title = json['nvl_title']?.toString() ?? '';
    final image = json['image']?.toString();
    String? coverUrl;
    if (image != null && image.isNotEmpty) {
      if (image.startsWith('http')) {
        coverUrl = image;
      } else {
        coverUrl = 'https://api.skynovels.net/api/get-image/$image/novels/true';
      }
    }
    final status = json['nvl_status']?.toString();
    final author = json['nvl_writer']?.toString();

    return Novel(
      id: idStr,
      title: title,
      url: idStr, // We can use the ID as the URL parameter
      coverUrl: coverUrl,
      status: status,
      author: author,
    );
  }

  factory Novel.fromHtmlBlock(String block) {
    // Left for backward compatibility if needed
    final urlRegex = RegExp(r'href="([^"]+)"');
    final titleRegex = RegExp(r'title="([^"]+)"');
    final srcRegex = RegExp(r'src="([^"]+)"');
    final dataSrcRegex = RegExp(r'data-src="([^"]+)"');

    final urlMatch = urlRegex.firstMatch(block);
    final titleMatch = titleRegex.firstMatch(block);
    
    String? coverUrl;
    final dataSrcMatch = dataSrcRegex.firstMatch(block);
    if (dataSrcMatch != null) {
      coverUrl = dataSrcMatch.group(1);
    } else {
      final srcMatch = srcRegex.firstMatch(block);
      if (srcMatch != null) {
        coverUrl = srcMatch.group(1);
      }
    }

    final url = urlMatch?.group(1) ?? '';
    final title = titleMatch?.group(1) ?? '';

    String id = '';
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        id = segments.last;
      }
    } catch (_) {}

    return Novel(
      id: id.isNotEmpty ? id : url,
      title: title,
      url: url,
      coverUrl: coverUrl,
    );
  }
}

class NovelChapter {
  final String id;
  final double number;
  final String title;
  final String url;
  final bool isVip;

  NovelChapter({
    required this.id,
    required this.number,
    required this.title,
    required this.url,
    this.isVip = false,
  });

  factory NovelChapter.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final idStr = rawId?.toString() ?? '';
    
    final rawNum = json['chp_number'];
    double number = 1.0;
    if (rawNum != null) {
      if (rawNum is num) {
        number = rawNum.toDouble();
      } else {
        number = double.tryParse(rawNum.toString()) ?? 1.0;
      }
    }

    final title = json['chp_index_title']?.toString() ?? json['chp_name']?.toString() ?? 'Capítulo $number';
    final isVipStr = json['isVip']?.toString() ?? '0';

    return NovelChapter(
      id: idStr,
      number: number,
      title: title,
      url: idStr, // We can use the ID as the URL parameter
      isVip: isVipStr == '1',
    );
  }

  factory NovelChapter.fromHtml(String href, String text) {
    // Left for backward compatibility if needed
    String id = '';
    try {
      final uri = Uri.parse(href);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        id = segments.last;
      }
    } catch (_) {}

    double number = 1.0;
    try {
      final cleanText = text.toLowerCase();
      final numRegex = RegExp(r'(?:capítulo|capitulo|cap|ch\.?)\s*(\d+(?:\.\d+)?)');
      final match = numRegex.firstMatch(cleanText);
      if (match != null) {
        number = double.tryParse(match.group(1) ?? '1') ?? 1.0;
      } else {
        final slugRegex = RegExp(r'capitulo-(\d+(?:-\d+)?)');
        final slugMatch = slugRegex.firstMatch(id);
        if (slugMatch != null) {
          number = double.tryParse(slugMatch.group(1)!.replaceAll('-', '.')) ?? 1.0;
        }
      }
    } catch (_) {}

    return NovelChapter(
      id: id.isNotEmpty ? id : href,
      number: number,
      title: text,
      url: href,
    );
  }
}

