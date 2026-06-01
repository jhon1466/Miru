import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../utils/image_utils.dart';

/// Muestra la portada de un anime con URL normalizada y placeholder si falla.
class AnimePosterImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const AnimePosterImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final url = normalizeAnimeImageUrl(imageUrl);
    final placeholder = Container(
      width: width,
      height: height,
      color: AppTheme.cardColor,
      child: const Icon(Icons.movie, color: AppTheme.textSecondary),
    );

    if (url == null) {
      return placeholder;
    }

    final loadingPlaceholder = Container(
      width: width,
      height: height,
      color: AppTheme.cardColor,
    );

    Widget image = (width == null && height == null)
        ? SizedBox.expand(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: fit,
              placeholder: (_, __) => loadingPlaceholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
          )
        : CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            placeholder: (_, __) => loadingPlaceholder,
            errorWidget: (_, __, ___) => placeholder,
          );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}
