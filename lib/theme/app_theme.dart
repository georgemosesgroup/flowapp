import 'package:flutter/material.dart';
import 'tokens.dart';
import 'typography.dart';

/// Assemble a [ThemeData] from the Flow tokens. Screens still paint their
/// own cards/buttons for now, but defaults (scaffold color, default text
/// color, switch tint, etc.) come from here so the whole app shifts when
/// tokens change.
class FlowTheme {
  FlowTheme._();

  /// Build a [ThemeData] matching the supplied brightness.
  ///
  /// `FlowTokens` auto-resolves through `FlowThemeController`, so callers
  /// typically rebuild MaterialApp whenever the controller fires and we
  /// read the brightness from the controller rather than taking it as an
  /// argument. The parameter is there for tests that want to force a
  /// specific mode without touching the global controller.
  static ThemeData build({Brightness? brightness}) {
    final b = brightness ?? FlowThemeController.instance.brightness;
    final isLight = b == Brightness.light;

    final colorScheme = isLight
        ? ColorScheme.light(
            primary: FlowTokens.accent,
            onPrimary: Colors.white,
            secondary: FlowTokens.systemBlue,
            onSecondary: Colors.white,
            surface: FlowTokens.bgElevated,
            onSurface: FlowTokens.textPrimary,
            error: FlowTokens.systemRed,
            onError: Colors.white,
          )
        : ColorScheme.dark(
            primary: FlowTokens.accent,
            onPrimary: Colors.white,
            secondary: FlowTokens.systemBlue,
            onSecondary: Colors.white,
            surface: FlowTokens.bgElevated,
            onSurface: FlowTokens.textPrimary,
            error: FlowTokens.systemRed,
            onError: Colors.white,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: colorScheme,
      // Scaffold is fully transparent so the NSVisualEffectView sitting
      // behind the Flutter view composes through. Surfaces (sidebar,
      // cards, nav rows) bring their own tinted-translucent fills.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dialogTheme: DialogThemeData(
        backgroundColor: FlowTokens.bgElevated,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(FlowTokens.radiusLg)),
        ),
        titleTextStyle: FlowType.title,
        contentTextStyle: FlowType.body,
      ),
      textTheme: TextTheme(
        displayLarge: FlowType.largeTitle,
        displayMedium: FlowType.largeTitle,
        titleLarge: FlowType.title,
        titleMedium: FlowType.headline,
        titleSmall: FlowType.headline,
        bodyLarge: FlowType.body,
        bodyMedium: FlowType.body,
        bodySmall: FlowType.caption,
        labelLarge: FlowType.bodyStrong,
        labelMedium: FlowType.caption,
        labelSmall: FlowType.footnote,
      ),
      dividerTheme: DividerThemeData(
        color: FlowTokens.strokeDivider,
        thickness: 0.5,
        space: 0,
      ),
      iconTheme: IconThemeData(
        color: FlowTokens.textSecondary,
        size: 18,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isLight
              ? const Color(0xFFE5E5EA)
              : const Color(0xFFCDCDD1);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return FlowTokens.accent;
          return isLight
              ? const Color(0xFFC6C6CA)
              : const Color(0xFF3A3A3F);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: FlowTokens.accent,
        inactiveTrackColor:
            isLight ? const Color(0xFFD8D8DC) : const Color(0xFF2A2A2F),
        thumbColor: Colors.white,
        overlayColor: FlowTokens.accentSubtle,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: FlowTokens.bgElevated,
          borderRadius:
              BorderRadius.all(Radius.circular(FlowTokens.radiusSm)),
        ),
        textStyle: FlowType.caption,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          isLight ? const Color(0x40000000) : const Color(0x40FFFFFF),
        ),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FlowTokens.bgElevated,
        contentTextStyle: FlowType.body,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(FlowTokens.radiusMd)),
        ),
      ),
    );
  }
}
