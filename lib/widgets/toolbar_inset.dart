import 'package:flutter/widgets.dart';

/// Inherited descriptor of how much left padding screen-level toolbars
/// should add to clear window chrome (traffic lights, reveal chevron)
/// when the sidebar is collapsed.
///
/// `AppShell` wraps the content area with this. Each screen's toolbar
/// reads `ToolbarInset.of(context).leftInset` and applies it *only* to
/// the header row — not to the whole body — so page content keeps its
/// native gutter.
class ToolbarInset extends InheritedWidget {
  final double leftInset;

  const ToolbarInset({
    super.key,
    required this.leftInset,
    required super.child,
  });

  static ToolbarInset? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarInset>();

  /// Convenience: returns the current left inset or 0 when the ancestor
  /// isn't present (tests, previews, widget galleries).
  static double leftOf(BuildContext context) =>
      maybeOf(context)?.leftInset ?? 0;

  @override
  bool updateShouldNotify(ToolbarInset old) => old.leftInset != leftInset;
}
