import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

/// macOS-style modal dialog. Designed to replace Material's `AlertDialog`
/// across the app — matches the rest of the Flow UI (squircle corners,
/// vibrancy-friendly fill, primary action on the right, Cancel on the
/// left of Confirm).
///
/// Use via [showFlowDialog], or drop this widget directly into
/// `showDialog(builder: (_) => FlowDialog(…))` if you need custom scrim
/// behaviour.
class FlowDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final List<FlowDialogAction> actions;
  final double maxWidth;

  const FlowDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 440,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FlowTokens.radiusXl),
            // Mild backdrop blur so the dialog reads as its own "pane"
            // even over busy backgrounds or the Liquid-Glass window.
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: FlowTokens.glassFillElevated,
                  borderRadius: BorderRadius.circular(FlowTokens.radiusXl),
                  border: Border.all(
                    color: FlowTokens.glassEdge,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: FlowTokens.scrim,
                      offset: const Offset(0, 20),
                      blurRadius: 48,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FlowTokens.space24,
                        FlowTokens.space20,
                        FlowTokens.space24,
                        FlowTokens.space16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: FlowType.title),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: FlowType.caption,
                            ),
                          ],
                          const SizedBox(height: FlowTokens.space16),
                          content,
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: FlowTokens.strokeSubtle,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FlowTokens.space16,
                          vertical: FlowTokens.space12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: FlowTokens.space8),
                              actions[i].build(context),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Declarative button spec for [FlowDialog]. The [isPrimary] and
/// [isDestructive] flags pick the correct [FlowButtonVariant]; if you
/// need something exotic, fall back to building your own button.
class FlowDialogAction {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;

  const FlowDialogAction({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  Widget build(BuildContext context) {
    final variant = isDestructive
        ? FlowButtonVariant.destructive
        : isPrimary
            ? FlowButtonVariant.filled
            : FlowButtonVariant.ghost;
    return FlowButton(
      label: label,
      variant: variant,
      size: FlowButtonSize.md,
      onPressed: onPressed,
    );
  }
}

/// Convenience helper — `showFlowDialog(context, dialog)` wires up the
/// dark scrim at the right alpha and passes through dismissal.
Future<T?> showFlowDialog<T>({
  required BuildContext context,
  required FlowDialog dialog,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: dialog.title,
    barrierColor: FlowTokens.scrim,
    transitionDuration: FlowTokens.durBase,
    pageBuilder: (_, _, _) => dialog,
    transitionBuilder: (_, anim, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: anim,
          curve: FlowTokens.easeStandard,
        ),
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: FlowTokens.easeStandard),
          ),
          child: child,
        ),
      );
    },
  );
}
