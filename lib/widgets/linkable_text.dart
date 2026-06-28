import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renderiza texto con URLs clickeables. Funciona en Android e iOS.
class LinkableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;

  const LinkableText(this.text, {super.key, this.style, this.linkStyle});

  static final _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final base = style ?? TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface, height: 1.4);
    final link = linkStyle ?? base.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    final spans = <InlineSpan>[];
    int last = 0;

    for (final m in _urlRegex.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: link,
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return RichText(text: TextSpan(style: base, children: spans));
  }
}
