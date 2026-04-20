import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Apple-style button variants. Mirrors iOS UIButton.Configuration:
///   - filled:  solid accent fill, white text (primary CTA)
///   - tinted:  accent-at-12% background, accent text (secondary action)
///   - plain:   transparent, accent text (tertiary / inline)
///   - ghost:   transparent, secondary text (subtle / cancel)
///   - destructive: red fill (confirmation dialogs)
enum FlowButtonVariant { filled, tinted, plain, ghost, destructive }
enum FlowButtonSize { sm, md, lg }

class FlowButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final FlowButtonVariant variant;
  final FlowButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool fullWidth;

  const FlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = FlowButtonVariant.filled,
    this.size = FlowButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = false,
  });

  @override
  State<FlowButton> createState() => _FlowButtonState();
}

class _FlowButtonState extends State<FlowButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final height = switch (widget.size) {
      FlowButtonSize.sm => 26.0,
      FlowButtonSize.md => 32.0,
      FlowButtonSize.lg => 40.0,
    };
    final hPad = switch (widget.size) {
      FlowButtonSize.sm => 10.0,
      FlowButtonSize.md => 14.0,
      FlowButtonSize.lg => 18.0,
    };
    final fontSize = switch (widget.size) {
      FlowButtonSize.sm => 12.0,
      FlowButtonSize.md => 13.0,
      FlowButtonSize.lg => 15.0,
    };
    final radius = widget.size == FlowButtonSize.lg
        ? FlowTokens.radiusLg
        : FlowTokens.radiusMd;

    final (bg, fg) = _colors(enabled);

    final textStyle = FlowType.bodyStrong.copyWith(
      fontSize: fontSize,
      color: fg,
    );

    final child = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: fontSize + 2, color: fg),
          const SizedBox(width: 6),
        ],
        Text(widget.label, style: textStyle),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(widget.trailingIcon, size: fontSize + 2, color: fg),
        ],
      ],
    );

    final button = AnimatedContainer(
      duration: FlowTokens.durFast,
      curve: FlowTokens.easeStandard,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: widget.variant == FlowButtonVariant.ghost
            ? Border.all(color: FlowTokens.strokeSubtle, width: 0.5)
            : null,
      ),
      transform: _pressed
          ? (Matrix4.identity()..scaleByDouble(0.97, 0.97, 1.0, 1.0))
          : Matrix4.identity(),
      transformAlignment: Alignment.center,
      child: child,
    );

    if (!enabled) {
      return Opacity(opacity: 0.4, child: button);
    }

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
        onTap: widget.onPressed,
        child: widget.fullWidth
            ? SizedBox(width: double.infinity, child: button)
            : button,
      ),
    );
  }

  (Color bg, Color fg) _colors(bool enabled) {
    if (!enabled) {
      return (FlowTokens.bgElevated, FlowTokens.textDisabled);
    }
    switch (widget.variant) {
      case FlowButtonVariant.filled:
        return (
          _pressed
              ? FlowTokens.accentPressed
              : _hover
                  ? FlowTokens.accentHover
                  : FlowTokens.accent,
          Colors.white,
        );
      case FlowButtonVariant.tinted:
        return (
          _hover
              ? FlowTokens.accent.withValues(alpha: 0.18)
              : FlowTokens.accentSubtle,
          FlowTokens.accent,
        );
      case FlowButtonVariant.plain:
        return (
          _hover ? FlowTokens.hoverSubtle : Colors.transparent,
          FlowTokens.accent,
        );
      case FlowButtonVariant.ghost:
        return (
          _hover ? FlowTokens.bgElevatedHover : Colors.transparent,
          FlowTokens.textPrimary,
        );
      case FlowButtonVariant.destructive:
        return (
          _pressed
              ? FlowTokens.systemRed.withValues(alpha: 0.85)
              : _hover
                  ? FlowTokens.systemRed.withValues(alpha: 1.0)
                  : FlowTokens.systemRed,
          Colors.white,
        );
    }
  }
}
