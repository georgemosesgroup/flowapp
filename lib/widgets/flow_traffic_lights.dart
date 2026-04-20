import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Custom macOS-style traffic lights. Native buttons are hidden in
/// `MainFlutterWindow.swift` and this widget renders replacements that
/// call back into `NSWindow` via a MethodChannel.
///
/// Why custom: macOS aggressively re-lays out the standard window
/// buttons on launch/resize/full-screen, so nudging them into the
/// sidebar's inset pane was unreliable. Drawing our own trio means the
/// position is whatever we say it is.
///
/// Focus state: Swift pushes key/resign-key notifications over the
/// `setFocusState` channel method so the lights dim when the window
/// isn't frontmost — matching the native macOS look.
class FlowTrafficLights extends StatefulWidget {
  const FlowTrafficLights({super.key});

  @override
  State<FlowTrafficLights> createState() => _FlowTrafficLightsState();
}

class _FlowTrafficLightsState extends State<FlowTrafficLights> {
  static const _channel = MethodChannel('com.voiceassistant/window');
  bool _groupHover = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    // We don't proactively query `getFocusState` on launch — during app
    // launch the window isn't always key yet, and a `false` result from
    // Swift would wrongly dim the lights. Swift re-broadcasts the real
    // state on windowDidBecomeKey / didResignKey; that drives us.
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    if (call.method == 'setFocusState') {
      final v = call.arguments;
      if (v is bool && mounted) {
        setState(() => _focused = v);
      }
    }
    return null;
  }

  Future<void> _send(String method) async {
    try {
      await _channel.invokeMethod(method);
    } catch (_) {
      // Swallow — the channel is only wired on macOS; in tests / web
      // builds invoking it is a no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _groupHover = true),
      onExit: (_) => setState(() => _groupHover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LightButton(
            color: const Color(0xFFFF5F57),
            icon: Icons.close,
            iconSize: 9,
            groupHover: _groupHover,
            focused: _focused,
            onTap: () => _send('close'),
          ),
          const SizedBox(width: 8),
          _LightButton(
            color: const Color(0xFFFEBC2E),
            icon: Icons.horizontal_rule,
            iconSize: 11,
            groupHover: _groupHover,
            focused: _focused,
            onTap: () => _send('minimize'),
          ),
          const SizedBox(width: 8),
          _LightButton(
            color: const Color(0xFF28C840),
            icon: Icons.unfold_more_rounded,
            iconSize: 10,
            iconQuarterTurns: 1,
            groupHover: _groupHover,
            focused: _focused,
            onTap: () => _send('zoom'),
          ),
        ],
      ),
    );
  }
}

class _LightButton extends StatefulWidget {
  final Color color;
  final IconData icon;
  final double iconSize;
  final int iconQuarterTurns;
  final bool groupHover;
  final bool focused;
  final VoidCallback onTap;

  const _LightButton({
    required this.color,
    required this.icon,
    this.iconSize = 10,
    this.iconQuarterTurns = 0,
    required this.groupHover,
    required this.focused,
    required this.onTap,
  });

  @override
  State<_LightButton> createState() => _LightButtonState();
}

class _LightButtonState extends State<_LightButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Unfocused → flat neutral grey, matching macOS's native behaviour
    // when the window is not key. Focused → the familiar brand colour.
    final fill = widget.focused
        ? (_hover ? widget.color : widget.color.withValues(alpha: 0.95))
        : const Color(0xFF595959);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          // Icons appear only when focused AND hovering — matches native.
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 90),
            opacity: widget.focused && widget.groupHover ? 1.0 : 0.0,
            child: RotatedBox(
              quarterTurns: widget.iconQuarterTurns,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                weight: 900,
                grade: 200,
                color: Colors.black.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
