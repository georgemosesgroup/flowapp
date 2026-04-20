import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Apple-style elevated card. Uses a subtle background color + thin inner
/// stroke instead of a visible border; shadow grows on hover for the
/// lift effect. Tappable when [onTap] is provided — animates a 1px
/// vertical rise like a proper macOS control.
class FlowCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? background;
  final bool selected;
  final bool interactive;

  const FlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FlowTokens.space16),
    this.radius = FlowTokens.radiusLg,
    this.onTap,
    this.background,
    this.selected = false,
    this.interactive = true,
  });

  @override
  State<FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends State<FlowCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isTappable = widget.onTap != null;
    final shouldInteract = isTappable && widget.interactive;

    final baseColor = widget.background ?? FlowTokens.bgElevated;
    final bg = widget.selected
        ? FlowTokens.accentSubtle
        : _pressed
            ? FlowTokens.bgPressed
            : _hover && shouldInteract
                ? FlowTokens.bgElevatedHover
                : baseColor;

    final strokeColor = widget.selected
        ? FlowTokens.strokeFocus
        : FlowTokens.strokeSubtle;

    final shadow = _hover && shouldInteract
        ? FlowTokens.shadowMd
        : FlowTokens.shadowSm;

    final card = AnimatedContainer(
      duration: FlowTokens.durFast,
      curve: FlowTokens.easeStandard,
      transform: Matrix4.translationValues(0, _hover && shouldInteract ? -1 : 0, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: strokeColor, width: 0.5),
        boxShadow: shadow,
      ),
      // ClipRRect prevents inner-row hover fills (grouped list rows,
      // divider strokes that run edge-to-edge) from bleeding over the
      // outer radius and squaring the corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Padding(
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );

    if (!shouldInteract) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}
