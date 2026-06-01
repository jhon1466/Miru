import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../utils/image_utils.dart';

/// Muestra la portada o banner de un anime con cabeceras HTTP y fallbacks.
class AnimePosterImage extends StatelessWidget {
  final String? imageUrl;
  final List<String>? urlCandidates;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const AnimePosterImage({
    super.key,
    this.imageUrl,
    this.urlCandidates,
    this.fallbackUrls,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  /// Compatibilidad con código que pasa [fallbackUrls].
  final List<String>? fallbackUrls;

  @override
  Widget build(BuildContext context) {
    final urls = _buildUrlList();
    return _NetworkImageWithFallback(
      urls: urls,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
    );
  }

  List<String> _buildUrlList() {
    if (urlCandidates != null && urlCandidates!.isNotEmpty) {
      return urlCandidates!;
    }

    final seen = <String>{};
    final list = <String>[];

    void add(String? raw) {
      final url = normalizeAnimeImageUrl(raw);
      if (url != null && seen.add(url)) list.add(url);
    }

    add(imageUrl);
    if (fallbackUrls != null) {
      for (final u in fallbackUrls!) {
        add(u);
      }
    }
    return list;
  }
}

class _NetworkImageWithFallback extends StatefulWidget {
  final List<String> urls;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const _NetworkImageWithFallback({
    required this.urls,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  State<_NetworkImageWithFallback> createState() => _NetworkImageWithFallbackState();
}

class _NetworkImageWithFallbackState extends State<_NetworkImageWithFallback> {
  int _index = 0;

  void _tryNextUrl() {
    if (!mounted) return;
    if (_index + 1 < widget.urls.length) {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingBox = Container(
      width: widget.width,
      height: widget.height,
      color: AppTheme.cardColor,
    );

    final errorBox = Container(
      width: widget.width,
      height: widget.height,
      color: AppTheme.cardColor,
      child: const Center(
        child: Icon(Icons.movie, color: AppTheme.textSecondary, size: 40),
      ),
    );

    if (widget.urls.isEmpty || _index >= widget.urls.length) {
      return errorBox;
    }

    final url = widget.urls[_index];
    final headers = imageHttpHeadersForUrl(url);

    Widget image = CachedNetworkImage(
      key: ValueKey('anime-img-$url'),
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      httpHeaders: headers,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => loadingBox,
      errorWidget: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNextUrl());
        // Mientras prueba la siguiente URL, mostrar carga (no icono de error)
        return _index + 1 < widget.urls.length ? loadingBox : errorBox;
      },
    );

    if (widget.width == null && widget.height == null) {
      image = SizedBox.expand(child: image);
    }

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }

    return image;
  }
}
