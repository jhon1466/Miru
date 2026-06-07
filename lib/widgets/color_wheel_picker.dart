import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Diálogo completo con rueda de colores HSV + slider de brillo
/// Solo para supporters. Llama onColorSelected con el color elegido.
class ColorWheelDialog extends StatefulWidget {
  final Color initialColor;

  const ColorWheelDialog({super.key, required this.initialColor});

  @override
  State<ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<ColorWheelDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _hsv.toColor();

    return Dialog(
      backgroundColor: const Color(0xFF18181f),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título
            Row(
              children: [
                const Text('🎨', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Elige tu color',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFD93D).withValues(alpha: 0.4), width: 0.5),
                  ),
                  child: const Text(
                    '👑 Supporter',
                    style: TextStyle(fontSize: 10, color: Color(0xFFFFD93D), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Rueda de colores (Hue + Saturation)
            _ColorWheel(
              hsv: _hsv,
              onChanged: (h, s) => setState(() {
                _hsv = HSVColor.fromAHSV(_hsv.alpha, h, s, _hsv.value);
              }),
            ),
            const SizedBox(height: 16),

            // Slider de brillo (Value)
            _BrightnessSlider(
              hsv: _hsv,
              onChanged: (v) => setState(() {
                _hsv = HSVColor.fromAHSV(_hsv.alpha, _hsv.hue, _hsv.saturation, v);
              }),
            ),
            const SizedBox(height: 20),

            // Preview del color
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: selected,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: selected.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _colorToHex(selected),
                  style: TextStyle(
                    color: _contrastColor(selected),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2a2a38)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selected,
                      foregroundColor: _contrastColor(selected),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  Color _contrastColor(Color c) {
    final luminance = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}

// ── Rueda HSV ─────────────────────────────────────────────────────────────────
class _ColorWheel extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double hue, double saturation) onChanged;

  const _ColorWheel({required this.hsv, required this.onChanged});

  Offset _hsvToOffset(double hue, double saturation, double radius) {
    final angle = (hue - 90) * math.pi / 180;
    return Offset(
      radius + math.cos(angle) * saturation * radius,
      radius + math.sin(angle) * saturation * radius,
    );
  }

  void _updateFromOffset(Offset local, double size) {
    final radius = size / 2;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    final dist = math.sqrt(dx * dx + dy * dy);
    final saturation = (dist / radius).clamp(0.0, 1.0);
    final angle = math.atan2(dy, dx) * 180 / math.pi + 90;
    final hue = (angle % 360 + 360) % 360;
    onChanged(hue, saturation);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 240.0);
        final radius = size / 2;
        final thumbPos = _hsvToOffset(hsv.hue, hsv.saturation, radius);

        return Center(
          child: GestureDetector(
            onPanStart: (d) => _updateFromOffset(d.localPosition, size),
            onPanUpdate: (d) => _updateFromOffset(d.localPosition, size),
            onTapDown: (d) => _updateFromOffset(d.localPosition, size),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _WheelPainter(value: hsv.value),
                child: Stack(
                  children: [
                    Positioned(
                      left: thumbPos.dx - 12,
                      top: thumbPos.dy - 12,
                      child: _Thumb(color: hsv.toColor()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double value;
  _WheelPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hue sweep (outer ring)
    final huePaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: List.generate(
          361,
          (i) => HSVColor.fromAHSV(1, i.toDouble(), 1, value).toColor(),
        ),
      ).createShader(rect);

    canvas.drawCircle(center, radius, huePaint);

    // Saturation (radial white→transparent)
    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(255, 255, 255, value.clamp(0.0, 1.0)),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, satPaint);

    // Dark overlay when value < 1
    if (value < 1) {
      final darkPaint = Paint()
        ..color = Colors.black.withValues(alpha: 1 - value);
      canvas.drawCircle(center, radius, darkPaint);
    }

    // Border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.value != value;
}

// ── Thumb ─────────────────────────────────────────────────────────────────────
class _Thumb extends StatelessWidget {
  final Color color;
  const _Thumb({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
    );
  }
}

// ── Slider de brillo ──────────────────────────────────────────────────────────
class _BrightnessSlider extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double value) onChanged;

  const _BrightnessSlider({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Brillo', style: TextStyle(fontSize: 12, color: Colors.white60)),
            Text(
              '${(hsv.value * 100).round()}%',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              onHorizontalDragUpdate: (d) {
                final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                onChanged(v);
              },
              onTapDown: (d) {
                final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                onChanged(v);
              },
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    colors: [
                      Colors.black,
                      HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: (hsv.value * width - 11).clamp(0, width - 22),
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: hsv.toColor(),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
