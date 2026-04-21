import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'toolbar_inset.dart';

/// Visual tone of a [FlowToast]. Drives icon choice + accent color.
enum FlowToastVariant { success, info, error }

/// App-wide toast notifications. Replaces Material's SnackBar with a
/// single glass-card pill that slides up from the bottom of the main
/// window, centered over the content area, and auto-dismisses.
///
/// Design notes:
///
/// - **Overlay-based.** We insert an [OverlayEntry] onto the nearest
///   root overlay instead of relying on ScaffoldMessenger. That lets us
///   own the animation + blur surface completely, and works the same
///   whether the caller is inside a Scaffold or not (e.g. the macOS
///   PlatformMenuBar callbacks, which don't have Scaffold ancestry).
///
/// - **Single-slot.** A second `show()` while one toast is already on
///   screen replaces the previous entry — the user's latest action is
///   what they care about; stacking toasts is noise.
///
/// - **Width is capped.** maxWidth=520 centers the pill over the
///   content area without colliding with the sidebar on wide layouts
///   and without stretching grotesquely wide on maximised windows.
///
/// Use the named constructors (`success` / `info` / `error`) rather
/// than `show(...)` directly — they keep call sites short and ensure
/// every toast picks up a consistent accent.
class FlowToast {
  FlowToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Shorthand for a positive-outcome toast (green ✓).
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1800),
  }) =>
      show(context,
          message: message,
          variant: FlowToastVariant.success,
          duration: duration);

  /// Shorthand for a neutral informational toast (blue ⓘ).
  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2000),
  }) =>
      show(context,
          message: message,
          variant: FlowToastVariant.info,
          duration: duration);

  /// Shorthand for a failure toast (red ⚠). Held on screen slightly
  /// longer — errors deserve more reading time.
  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2600),
  }) =>
      show(context,
          message: message,
          variant: FlowToastVariant.error,
          duration: duration);

  /// Primary entrypoint. Prefer the named constructors above.
  static void show(
    BuildContext context, {
    required String message,
    FlowToastVariant variant = FlowToastVariant.info,
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    // Two-step lookup: root overlay first (scaffolded pages), then
    // plain ancestor (fallback if `context` is already inside the
    // overlay element — e.g. the OverlayState's own context, which
    // happens when callers come from PlatformMenu callbacks via
    // navigatorKey.currentState.overlay.context).
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return;
    _showInOverlay(
      overlay,
      sidebarWidth: SidebarMetrics.widthOf(context),
      message: message,
      variant: variant,
      duration: duration,
    );
  }

  /// Overlay-first entrypoint. Use this when you already have an
  /// [OverlayState] (e.g. `navigatorKey.currentState?.overlay`) and
  /// want to avoid the InheritedWidget look-up entirely. Saves us
  /// from the PlatformMenuBar context-isolation problem on macOS.
  static void showInOverlay(
    OverlayState overlay, {
    required String message,
    FlowToastVariant variant = FlowToastVariant.info,
    Duration duration = const Duration(milliseconds: 1800),
    double sidebarWidth = 0,
  }) {
    _showInOverlay(
      overlay,
      sidebarWidth: sidebarWidth,
      message: message,
      variant: variant,
      duration: duration,
    );
  }

  static void _showInOverlay(
    OverlayState overlay, {
    required String message,
    required FlowToastVariant variant,
    required Duration duration,
    required double sidebarWidth,
  }) {
    _dismissImmediate();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlowToastOverlay(
        message: message,
        variant: variant,
        visibleFor: duration,
        leftInset: sidebarWidth,
        onGone: () {
          if (identical(_current, entry)) {
            _current = null;
          }
          entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  static void _dismissImmediate() {
    _timer?.cancel();
    _timer = null;
    final existing = _current;
    _current = null;
    existing?.remove();
  }
}

/// Internal: the animated pill itself. Drives its own enter + exit
/// animations and calls [onGone] once the exit is complete so the
/// OverlayEntry can be removed from the tree.
class _FlowToastOverlay extends StatefulWidget {
  const _FlowToastOverlay({
    required this.message,
    required this.variant,
    required this.visibleFor,
    required this.leftInset,
    required this.onGone,
  });

  final String message;
  final FlowToastVariant variant;
  final Duration visibleFor;
  final double leftInset;
  final VoidCallback onGone;

  @override
  State<_FlowToastOverlay> createState() => _FlowToastOverlayState();
}

class _FlowToastOverlayState extends State<_FlowToastOverlay>
    with SingleTickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 260);
  static const _exitDuration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _enterDuration,
      reverseDuration: _exitDuration,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      _holdTimer = Timer(widget.visibleFor, _beginDismiss);
    });
  }

  void _beginDismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (!mounted) return;
      widget.onGone();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (widget.variant) {
      FlowToastVariant.success => (
          Icons.check_circle_rounded,
          FlowTokens.systemGreen,
        ),
      FlowToastVariant.info => (
          Icons.info_outline_rounded,
          FlowTokens.systemBlue,
        ),
      FlowToastVariant.error => (
          Icons.error_outline_rounded,
          FlowTokens.systemRed,
        ),
    };

    return Positioned(
      // Skip the sidebar column so the pill centers over the content
      // area, not the whole window. leftInset=0 on screens without a
      // sidebar (login, permissions) keeps the window-center fallback.
      left: widget.leftInset,
      right: 0,
      bottom: 28,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                // Material gives us a DefaultTextStyle so Text inside
                // the pill inherits theme typography. Without it, Flutter
                // paints the "debug yellow underline" on orphaned Text
                // widgets living in a raw Overlay.
                child: Material(
                  type: MaterialType.transparency,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _beginDismiss,
                      child: _Pill(
                        icon: icon,
                        accent: accent,
                        message: widget.message,
                      ),
                    ),
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.accent,
    required this.message,
  });

  final IconData icon;
  final Color accent;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            // Glass wash — a notch stronger than FlowSection's elevated
            // fill so the pill reads as floating, not inset.
            color: FlowTokens.bgElevated.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: FlowTokens.strokeSubtle,
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: FlowType.body.copyWith(
                    fontSize: 13,
                    color: FlowTokens.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
