import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Pantalla de imagen/GIF/WebP a pantalla completa con zoom y gestos.
/// Se invoca con [FullscreenImageViewer.show(context, url)].
class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  /// Abre el viewer en pantalla completa con una animación Hero.
  static void show(BuildContext context, String imageUrl, {String? heroTag}) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullscreenImageViewer(
          imageUrl: imageUrl,
          heroTag: heroTag ?? imageUrl,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _showControls = true;
  TapDownDetails? _doubleTapDetails;

  ImageStreamListener? _listener;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_animation != null) {
          _transformController.value = _animation!.value;
        }
      });
    _resolveImage();
  }

  void _resolveImage() {
    try {
      final provider = CachedNetworkImageProvider(widget.imageUrl);
      final stream = provider.resolve(ImageConfiguration.empty);
      _listener = ImageStreamListener((ImageInfo info, bool _) {
        if (mounted) {
          setState(() {
            _aspectRatio = info.image.width / info.image.height;
          });
        }
      });
      stream.addListener(_listener!);
    } catch (_) {}
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    if (_listener != null) {
      try {
        final provider = CachedNetworkImageProvider(widget.imageUrl);
        provider.resolve(ImageConfiguration.empty).removeListener(_listener!);
      } catch (_) {}
    }
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _onDoubleTap() {
    final isZoomedIn =
        _transformController.value.getMaxScaleOnAxis() > 1.0;

    Matrix4 targetMatrix;
    if (isZoomedIn) {
      // Zoom out → identidad
      targetMatrix = Matrix4.identity();
    } else {
      // Zoom in × 2.5 centrado en el tap
      final position = _doubleTapDetails!.localPosition;
      final x = -position.dx * 1.5;
      final y = -position.dy * 1.5;
      targetMatrix = Matrix4.identity()
        ..translate(x, y)
        ..scale(2.5);
    }

    _animation = Matrix4Tween(
      begin: _transformController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward(from: 0);
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.heroTag ?? widget.imageUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.55),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: SizedBox.expand(
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.5,
            maxScale: 6.0,
            child: Hero(
              tag: tag,
              child: _aspectRatio == null
                  ? SizedBox.expand(
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                        ),
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: _aspectRatio!,
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget que envuelve una imagen/GIF en miniatura y la abre en
/// [FullscreenImageViewer] al hacer tap.
class TappableNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? heroTag;

  const TappableNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final tag = heroTag ?? imageUrl;
    final image = Hero(
      tag: tag,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => SizedBox(
          width: width ?? 100,
          height: height ?? 100,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      ),
    );

    final wrapped = borderRadius != null
        ? ClipRRect(borderRadius: borderRadius!, child: image)
        : image;

    return GestureDetector(
      onTap: () => FullscreenImageViewer.show(context, imageUrl, heroTag: tag),
      child: wrapped,
    );
  }
}
