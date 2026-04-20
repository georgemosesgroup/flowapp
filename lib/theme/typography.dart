import 'package:flutter/material.dart';
import 'tokens.dart';

/// Apple HIG-aligned type ramp. Flutter on macOS resolves the default
/// font family to `.AppleSystemUIFont` which maps to SF Pro — we keep
/// the family unspecified and only set weight + size + tracking.
///
/// Colors are resolved lazily through getters because `FlowTokens`
/// text colors are theme-aware. `Text(style: FlowType.body)` therefore
/// picks up the right hue whenever the theme flips, and call sites
/// don't need to chain `.copyWith(color: ...)` by hand.
class FlowType {
  FlowType._();

  // Letter-spacing values mirror SF's optical tracking at each size.
  static const double _tightTracking = -0.4;
  static const double _snugTracking = -0.2;
  static const double _normalTracking = 0;

  /// Hero headers (screen titles).
  static TextStyle get largeTitle => TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: _tightTracking,
        height: 1.18,
        color: FlowTokens.textPrimary,
      );

  /// Section headers, card titles.
  static TextStyle get title => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: _tightTracking,
        height: 1.25,
        color: FlowTokens.textPrimary,
      );

  /// Dense headlines in lists, prominent labels.
  static TextStyle get headline => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: _snugTracking,
        height: 1.35,
        color: FlowTokens.textPrimary,
      );

  /// Default body copy.
  static TextStyle get body => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: _snugTracking,
        height: 1.4,
        color: FlowTokens.textPrimary,
      );

  /// Emphasized body (button labels).
  static TextStyle get bodyStrong => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: _snugTracking,
        height: 1.4,
        color: FlowTokens.textPrimary,
      );

  /// Helper text under fields, captions.
  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: _normalTracking,
        height: 1.35,
        color: FlowTokens.textSecondary,
      );

  /// Footnote — smallest label, for pills/badges.
  static TextStyle get footnote => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.3,
        color: FlowTokens.textSecondary,
      );

  /// Monospace for timers, numeric counters.
  static TextStyle get mono => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: FlowTokens.textPrimary,
      );
}
