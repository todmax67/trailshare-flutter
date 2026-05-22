import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Testo descrizione con clamp a [maxCollapsedLines] linee + bottone
/// "Leggi di più" che espande tutto. Quando già espanso, mostra
/// "Mostra meno".
///
/// Originariamente introdotto per le Tour detail page (Epic 11) per
/// evitare che descrizioni lunghe spingessero giù le statistiche.
/// Promosso a widget condiviso (community track, business, trail OSM).
class ExpandableDescription extends StatefulWidget {
  final String text;
  final int maxCollapsedLines;
  final TextStyle? style;

  const ExpandableDescription({
    super.key,
    required this.text,
    this.maxCollapsedLines = 3,
    this.style,
  });

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ??
        TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          height: 1.45,
          fontSize: 14,
        );

    // Misura se il testo necessita davvero del clamp. Usiamo TextPainter
    // perché solo testi sufficientemente lunghi da occupare > N righe
    // hanno il bisogno del "Leggi di più".
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(text: widget.text, style: textStyle);
        final tp = TextPainter(
          text: span,
          maxLines: widget.maxCollapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final needsToggle = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: textStyle,
              maxLines: _expanded ? null : widget.maxCollapsedLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (needsToggle) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Mostra meno' : 'Leggi di più',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
