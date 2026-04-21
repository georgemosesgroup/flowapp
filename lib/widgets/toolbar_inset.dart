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

/// Width of the current sidebar column, in logical pixels. Published by
/// `AppShell` as the sidebar expands/collapses so overlay UI (toasts,
/// popovers) can align themselves over the content area rather than the
/// whole window.
///
/// Separate from [ToolbarInset] because that inset describes header
/// padding (a small gutter near the traffic-lights), not the sidebar
/// width itself — the two values differ whenever the sidebar is pinned.
class SidebarMetrics extends InheritedWidget {
  final double sidebarWidth;

  const SidebarMetrics({
    super.key,
    required this.sidebarWidth,
    required super.child,
  });

  static SidebarMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarMetrics>();

  /// Convenience: sidebar width at the given context, or 0 when no
  /// [SidebarMetrics] ancestor is installed (pre-login screens, tests).
  static double widthOf(BuildContext context) =>
      maybeOf(context)?.sidebarWidth ?? 0;

  @override
  bool updateShouldNotify(SidebarMetrics old) =>
      old.sidebarWidth != sidebarWidth;
}
