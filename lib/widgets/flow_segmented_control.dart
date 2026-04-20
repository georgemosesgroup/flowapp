import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// App-wide segmented pill control. One source of truth for "tabs" on
/// macOS-style screens (Settings / Style / etc.) so they all share the
/// same metrics, animation, and feel.
///
/// Selection is by `value` (opaque key). Supply a list of
/// [FlowSegment]s — the built-in `copyWith`-style constructor keeps
/// call-sites tight at the call-site (no tuples, no (String, String)
/// records with obscure `$1/$2`).
class FlowSegmentedControl<T> extends StatelessWidget {
  final T selected;
  final List<FlowSegment<T>> segments;
  final ValueChanged<T> onChanged;

  /// Compact — used inside toolbars where vertical space is tight.
  /// Regular — used when the control sits on its own row.
  final FlowSegmentSize size;

  const FlowSegmentedControl({
    super.key,
    required this.selected,
    required this.segments,
    required this.onChanged,
    this.size = FlowSegmentSize.md,
  });

  @override
  Widget build(BuildContext context) {
    final height = switch (size) {
      FlowSegmentSize.sm => 26.0,
      FlowSegmentSize.md => 30.0,
    };
    final hPad = switch (size) {
      FlowSegmentSize.sm => FlowTokens.space10,
      FlowSegmentSize.md => FlowTokens.space12,
    };
    final fontSize = switch (size) {
      FlowSegmentSize.sm => 12.0,
      FlowSegmentSize.md => 13.0,
    };

    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FlowTokens.bgPressed,
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((s) {
          final active = s.value == selected;
          return _Segment(
            active: active,
            fontSize: fontSize,
            hPad: hPad,
            label: s.label,
            icon: s.icon,
            onTap: () => onChanged(s.value),
          );
        }).toList(),
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  final bool active;
  final double fontSize;
  final double hPad;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _Segment({
    required this.active,
    required this.fontSize,
    required this.hPad,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? FlowTokens.textPrimary
        : _hover
            ? FlowTokens.textPrimary.withValues(alpha: 0.9)
            : FlowTokens.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          curve: FlowTokens.easeStandard,
          padding: EdgeInsets.symmetric(horizontal: widget.hPad),
          decoration: BoxDecoration(
            color: widget.active
                ? FlowTokens.pressedSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
            boxShadow: widget.active ? FlowTokens.shadowSm : null,
            border: widget.active
                ? Border.all(color: FlowTokens.hoverSurface, width: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 1, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: FlowType.body.copyWith(
                  fontSize: widget.fontSize,
                  color: color,
                  fontWeight:
                      widget.active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FlowSegment<T> {
  final T value;
  final String label;
  final IconData? icon;

  const FlowSegment({
    required this.value,
    required this.label,
    this.icon,
  });
}

enum FlowSegmentSize { sm, md }
