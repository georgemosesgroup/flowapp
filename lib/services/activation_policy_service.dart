import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Flips `NSApp.activationPolicy` from the Dart side.
///
/// Flow ships with `LSUIElement=true` so it boots as a tray-only agent.
/// That mode hides the app from the Dock **and** suppresses the native
/// macOS menu bar, which kills our `PlatformMenuBar` output.
///
/// To get the best of both worlds — tray-only when the window is hidden,
/// menu bar when the window is open — we flip the activation policy at
/// runtime: `.regular` on show, `.accessory` on hide.
class ActivationPolicyService {
  const ActivationPolicyService._();

  static const _channel = MethodChannel('com.voiceassistant/window');

  /// Dock icon + menu bar. Use when the main window is visible.
  static Future<void> regular() => _set('regular');

  /// Tray-only agent, no Dock icon, no menu bar. Use when the main
  /// window is hidden.
  static Future<void> accessory() => _set('accessory');

  static Future<void> _set(String policy) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setActivationPolicy', {'policy': policy});
    } on PlatformException {
      // Non-macOS / older build without the Swift handler — safe to
      // swallow; the menu bar just won't change.
    }
  }
}
