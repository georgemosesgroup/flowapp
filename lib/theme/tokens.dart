import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Design tokens for the Flow desktop app — Apple HIG-inspired.
///
/// Colors are theme-aware: `FlowTokens.bgCanvas` returns the right hue
/// for the currently active palette (dark/light). Spacing, radii,
/// shadows, and durations are immutable because they don't shift
/// between themes.
///
/// Theme switching is driven by [FlowThemeController.instance] — hook a
/// `ListenableBuilder` (or `AnimatedBuilder`) in the root of the app
/// around `MaterialApp` and rebuild whenever the controller fires.
class FlowTokens {
  FlowTokens._();

  // ───────────────────────── Surface / backgrounds ────────────────────
  //
  // These sit over a native vibrancy layer (NSVisualEffectView on macOS).
  // Values carry alpha so the system blur reads through them. Solid
  // *Opaque variants are kept for surfaces that can't afford legibility
  // loss (dense tables, popovers on a busy canvas).

  static Color get bgCanvas => _p.bgCanvas;
  static Color get bgSurface => _p.bgSurface;
  static Color get bgElevated => _p.bgElevated;
  static Color get bgElevatedHover => _p.bgElevatedHover;
  static Color get bgPressed => _p.bgPressed;
  static Color get bgScrim => _p.bgScrim;

  static Color get bgCanvasOpaque => _p.bgCanvasOpaque;
  static Color get bgSurfaceOpaque => _p.bgSurfaceOpaque;
  static Color get bgElevatedOpaque => _p.bgElevatedOpaque;

  // ───────────────────────── Strokes / dividers ───────────────────────
  static Color get strokeSubtle => _p.strokeSubtle;
  static Color get strokeDivider => _p.strokeDivider;
  static Color get strokeFocus => _p.strokeFocus;

  // ───────────────────────── Text ─────────────────────────────────────
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textTertiary => _p.textTertiary;
  static Color get textDisabled => _p.textDisabled;

  // ───────────────────────── Accents (iOS semantic) ───────────────────
  // These are identical in light and dark — semantic colors from iOS
  // are tuned to stay legible on either canvas.
  static const Color accent = Color(0xFFE84C5F);
  static const Color accentHover = Color(0xFFFF5F72);
  static const Color accentPressed = Color(0xFFCF3A4B);
  static Color get accentSubtle => _p.accentSubtle;

  static const Color systemBlue = Color(0xFF0A84FF);
  static const Color systemGreen = Color(0xFF30D158);
  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemRed = Color(0xFFFF453A);
  static const Color systemYellow = Color(0xFFFFD60A);

  // ────────────── State / glass / semantic (theme-aware) ──────────────
  static Color get hoverSurface => _p.hoverSurface;
  static Color get hoverSubtle => _p.hoverSubtle;
  static Color get pressedSurface => _p.pressedSurface;
  static Color get selectedNav => _p.selectedNav;

  static Color get glassFill => _p.glassFill;
  static Color get glassFillElevated => _p.glassFillElevated;
  static Color get glassHighlight => _p.glassHighlight;
  static Color get glassSheenMid => _p.glassSheenMid;
  static Color get glassSheenBottom => _p.glassSheenBottom;
  static Color get glassEdge => _p.glassEdge;

  static Color get scrim => _p.scrim;
  static Color get panelShadow => _p.panelShadow;
  static Color get contactShadow => _p.contactShadow;
  static Color get backdropSampleTint => _p.backdropSampleTint;

  static Color get warningSubtle => _p.warningSubtle;
  static Color get infoSubtle => _p.infoSubtle;
  static Color get successSubtle => _p.successSubtle;
  static Color get destructiveSubtle => _p.destructiveSubtle;

  static Color get sidebarFill => _p.sidebarFill;
  static Color get sidebarFillTop => _p.sidebarFillTop;
  static Color get sidebarFillBottom => _p.sidebarFillBottom;
  static Color get sidebarEdge => _p.sidebarEdge;
  static Color get sidebarShadow => _p.sidebarShadow;
  static Color get navActive => _p.navActive;
  static Color get navHover => _p.navHover;

  // ───────────────────────── Spacing (8px grid) ───────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  // ───────────────────────── Radii ────────────────────────────────────
  // Tuned for macOS 26 Liquid-Glass — larger continuous (squircle)
  // rounding on containers; small radii tight so chips still feel
  // pill-like.
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 22;
  static const double radius2xl = 28;
  static const double radiusFull = 999;

  // ───────────────────────── Shadows ──────────────────────────────────
  static List<BoxShadow> get shadowSm => _p.shadowSm;
  static List<BoxShadow> get shadowMd => _p.shadowMd;
  static List<BoxShadow> get shadowLg => _p.shadowLg;

  // ───────────────────────── Durations ────────────────────────────────
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durBase = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 340);

  /// Longer, gentler duration for bigger-footprint transitions — sidebar
  /// collapse/expand is the main customer. 420 ms is at the upper edge
  /// of what still feels "responsive" to a click while giving the motion
  /// room to breathe.
  static const Duration durSidebar = Duration(milliseconds: 420);

  /// Material-3 "emphasized" easing: eases in slowly, accelerates
  /// through the middle, decelerates into rest. More "physical" than a
  /// straight ease-out and Google's recommended curve for layout-changing
  /// transitions. Used everywhere the sidebar collapse/expand animates.
  /// See: https://m3.material.io/styles/motion/easing-and-duration/tokens-specs#emphasized
  static const Curve easeSidebar = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Apple's standard ease — accelerates gently, then glides to rest.
  static const Curve easeStandard = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Spring-like overshoot for emphasis transitions.
  static const Curve easeEmphasis = Cubic(0.34, 1.56, 0.64, 1.0);

  // ───────────────────────── Palette plumbing ────────────────────────

  /// Active palette. Private — callers read through the getters above
  /// so call sites stay untouched as we toggle themes.
  static FlowPalette get _p => FlowThemeController.instance.palette;

  /// Explicit helper for widgets that want to react to brightness
  /// changes (e.g. custom painters). Prefer the static getters on
  /// `FlowTokens` for the 99% case.
  static FlowPalette paletteOf(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? FlowPalette.light
        : FlowPalette.dark;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Palette — concrete color values for a single brightness.
// ─────────────────────────────────────────────────────────────────────

@immutable
class FlowPalette {
  final Brightness brightness;

  // Surfaces
  final Color bgCanvas;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgElevatedHover;
  final Color bgPressed;
  final Color bgScrim;

  final Color bgCanvasOpaque;
  final Color bgSurfaceOpaque;
  final Color bgElevatedOpaque;

  // Strokes
  final Color strokeSubtle;
  final Color strokeDivider;
  final Color strokeFocus;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  // Accent tints (accent hue is shared across themes; only the alpha
  // wash changes so it stays visible on either canvas)
  final Color accentSubtle;

  // ────────────── Interaction / state overlays ──────────────
  //
  // These are the "add a splash of contrast" colors — tiny washes that
  // sit on top of any surface to indicate hover/active/pressed. Alpha
  // is tuned per theme (white wash on dark, black wash on light).
  final Color hoverSurface; // default hover on transparent/elevated
  final Color hoverSubtle; // faint hover (sidebar nav, inline icons)
  final Color pressedSurface; // pressed / selected list row
  final Color selectedNav; // 12% wash behind active sidebar item

  // ────────────── Glass / floating surfaces ──────────────
  //
  // The glass-look capsule (sticky chip bar, modal surfaces) needs a
  // fill that biases dark on dark themes and light on light themes —
  // otherwise the "glass" reads as a painted pill rather than floating.
  final Color glassFill; // ~30% tint over vibrancy
  final Color glassFillElevated; // ~80-90% tint for heavier surfaces
  final Color glassHighlight; // top-edge sheen line (1-3 alpha)
  final Color glassSheenMid; // mid-gradient stop (transparent)
  final Color glassSheenBottom; // bottom-gradient stop (subtle darker)
  final Color glassEdge; // 1px border on the capsule

  // ────────────── Scrims / shadows ──────────────
  final Color scrim; // modal barrier
  final Color panelShadow; // ambient shadow behind panels
  final Color contactShadow; // close-in contact shadow

  // Canvas tint that sits behind scroll content purely so a
  // `BackdropFilter` has something to sample on translucent windows.
  final Color backdropSampleTint;

  // ────────────── Semantic status tints ──────────────
  //
  // Same hues in both themes, different alpha so the tint still
  // reads on either canvas.
  final Color warningSubtle; // systemOrange wash
  final Color infoSubtle; // systemBlue wash
  final Color successSubtle; // systemGreen wash
  final Color destructiveSubtle; // systemRed / accent wash

  // Sidebar chrome (the custom pane on the left). Rendered as a glass
  // panel: two-stop gradient (top → bottom) plus a bright edge. Lets
  // us get a proper Liquid-Glass feel without a BackdropFilter (which
  // is a no-op on our translucent window).
  final Color sidebarFill;
  final Color sidebarFillTop; // lighter top stop of the glass gradient
  final Color sidebarFillBottom; // darker bottom stop
  final Color sidebarEdge; // bright 1px border on the glass
  final Color sidebarShadow;
  final Color navActive;
  final Color navHover;

  // Shadows
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  const FlowPalette({
    required this.brightness,
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgElevatedHover,
    required this.bgPressed,
    required this.bgScrim,
    required this.bgCanvasOpaque,
    required this.bgSurfaceOpaque,
    required this.bgElevatedOpaque,
    required this.strokeSubtle,
    required this.strokeDivider,
    required this.strokeFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accentSubtle,
    required this.hoverSurface,
    required this.hoverSubtle,
    required this.pressedSurface,
    required this.selectedNav,
    required this.glassFill,
    required this.glassFillElevated,
    required this.glassHighlight,
    required this.glassSheenMid,
    required this.glassSheenBottom,
    required this.glassEdge,
    required this.scrim,
    required this.panelShadow,
    required this.contactShadow,
    required this.backdropSampleTint,
    required this.warningSubtle,
    required this.infoSubtle,
    required this.successSubtle,
    required this.destructiveSubtle,
    required this.sidebarFill,
    required this.sidebarFillTop,
    required this.sidebarFillBottom,
    required this.sidebarEdge,
    required this.sidebarShadow,
    required this.navActive,
    required this.navHover,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
  });

  // ─────────────────── Dark (default) ───────────────────
  //
  // `final` (not const) so hot-reload picks up palette tweaks without a
  // full restart — Dart canonicalizes const values and doesn't replace
  // them on reassemble.
  static final FlowPalette dark = const FlowPalette(
    brightness: Brightness.dark,

    bgCanvas: Color(0xF5050507), // 96% near-black (was 90%)
    bgSurface: Color(0xFA111114), // 98%
    bgElevated: Color(0xFE17171B), // ~99.6%
    bgElevatedHover: Color(0xFE1F1F25),
    bgPressed: Color(0xFA0B0B0E),
    bgScrim: Color(0xF5000000),

    bgCanvasOpaque: Color(0xFF0A0A0C),
    bgSurfaceOpaque: Color(0xFF111114),
    bgElevatedOpaque: Color(0xFF17171B),

    strokeSubtle: Color(0x14FFFFFF),
    strokeDivider: Color(0x1AFFFFFF),
    strokeFocus: Color(0x66E84C5F),

    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xB3EBEBF0),
    textTertiary: Color(0x808E8E93),
    textDisabled: Color(0x4D8E8E93),

    accentSubtle: Color(0x1FE84C5F),

    // Hover / press — white washes on dark canvas.
    hoverSurface: Color(0x14FFFFFF), // 8% white
    hoverSubtle: Color(0x0AFFFFFF), // 4% white
    pressedSurface: Color(0x1FFFFFFF), // 12% white
    selectedNav: Color(0x1FFFFFFF), // 12% white

    // Dark-glass capsule — mirrors the light palette's 90% alpha so
    // the glass effect looks the same on both themes, just with a
    // dark tint instead of a white one.
    glassFill: Color(0xE60E0E12), // 90% near-black
    glassFillElevated: Color(0xF217171B), // 95% near-black
    glassHighlight: Color(0x1AFFFFFF), // 10% white sheen top
    glassSheenMid: Color(0x00FFFFFF),
    glassSheenBottom: Color(0x14000000),
    glassEdge: Color(0x3DFFFFFF), // 24% white

    scrim: Color(0x99000000),
    panelShadow: Color(0x66000000),
    contactShadow: Color(0x26000000),

    backdropSampleTint: Color(0x0A000000), // ~4% dark

    warningSubtle: Color(0x1FFF9F0A),
    infoSubtle: Color(0x1F0A84FF),
    successSubtle: Color(0x1F30D158),
    destructiveSubtle: Color(0x1FFF453A),

    // Dark sidebar mirrors the light palette's proportions so the glass
    // effect reads the same way on both themes — translucent enough
    // to let the native blur through at a soft-focus level, not
    // opaque. 70% fill, 80% top sheen, 60% bottom matches light's
    // 0xB3/0xCC/0x99 alphas.
    sidebarFill: Color(0xB32A2A32), // 70% charcoal
    sidebarFillTop: Color(0xCC303038), // 80% slightly lighter top
    sidebarFillBottom: Color(0x991B1B22), // 60% near-black bottom
    sidebarEdge: Color(0x33FFFFFF), // 20% white rim light
    sidebarShadow: Color(0xB3000000),
    navActive: Color(0x1FFFFFFF), // 12% white
    navHover: Color(0x0FFFFFFF), // 6% white

    shadowSm: [
      BoxShadow(
        color: Color(0x26000000),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color(0x0DFFFFFF),
        offset: Offset(0, -0.5),
        blurRadius: 0,
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x3D000000),
        offset: Offset(0, 4),
        blurRadius: 12,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Color(0x14FFFFFF),
        offset: Offset(0, -0.5),
        blurRadius: 0,
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x66000000),
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -4,
      ),
    ],
  );

  // ─────────────────── Light ───────────────────
  //
  // Tuned against the macOS 26 light-mode vibrancy. Surfaces bias
  // white with a soft alpha so the system material shows through;
  // opaque fallbacks are near-white with a faint warm tint.
  static final FlowPalette light = const FlowPalette(
    brightness: Brightness.light,

    bgCanvas: Color(0x26F7F7FB), // ~15% light tint
    bgSurface: Color(0xCCFFFFFF), // 80% white
    bgElevated: Color(0xF7FFFFFF), // 97% white — clearly white cards
    bgElevatedHover: Color(0xFFF8F8FB),
    bgPressed: Color(0xF2EBEBF0),
    bgScrim: Color(0x4D000000),

    bgCanvasOpaque: Color(0xFFF7F7FB),
    bgSurfaceOpaque: Color(0xFFFFFFFF),
    bgElevatedOpaque: Color(0xFFFFFFFF),

    // Hairlines in light mode use dark-on-light for crisp edges.
    strokeSubtle: Color(0x14000000), // 8% black
    strokeDivider: Color(0x1A000000), // 10% black
    strokeFocus: Color(0x66E84C5F), // accent 40% — same as dark

    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0x993C3C43), // 60% iOS label secondary
    textTertiary: Color(0x4D3C3C43), // 30%
    textDisabled: Color(0x3D3C3C43), // ~24%

    accentSubtle: Color(0x1FE84C5F),

    // Hover / press — black washes on a light canvas.
    hoverSurface: Color(0x0A000000), // 4% black
    hoverSubtle: Color(0x05000000), // 2% black
    pressedSurface: Color(0x14000000), // 8% black
    selectedNav: Color(0x14000000), // 8% black — mirrors Finder sidebar

    // Light-glass capsule — crisp near-white frosted look.
    glassFill: Color(0xE6FFFFFF), // 90% white
    glassFillElevated: Color(0xF7FFFFFF), // 97% white
    glassHighlight: Color(0x80FFFFFF), // 50% white sheen top
    glassSheenMid: Color(0x00FFFFFF),
    glassSheenBottom: Color(0x08000000),
    glassEdge: Color(0x1F000000), // 12% black edge

    scrim: Color(0x33000000),
    panelShadow: Color(0x33000000),
    contactShadow: Color(0x14000000),

    backdropSampleTint: Color(0x0AFFFFFF), // ~4% light wash

    warningSubtle: Color(0x1FFF9F0A),
    infoSubtle: Color(0x1F0A84FF),
    successSubtle: Color(0x1F30D158),
    destructiveSubtle: Color(0x1FFF453A),

    sidebarFill: Color(0xB3FFFFFF), // ~70% white — glass pane
    sidebarFillTop: Color(0xCCFFFFFF), // brighter sheen at top
    sidebarFillBottom: Color(0x99F7F7FA), // softer warm-white bottom
    sidebarEdge: Color(0x2E000000), // ~18% black rim
    sidebarShadow: Color(0x1F000000),
    navActive: Color(0x14000000),
    navHover: Color(0x0A000000),

    shadowSm: [
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1F000000),
        offset: Offset(0, 4),
        blurRadius: 12,
        spreadRadius: -2,
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x33000000),
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -4,
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────
// Theme controller — holds the active mode (system / light / dark) and
// the resolved palette. Rebuilds that depend on theme should listen to
// this and repaint on change.
// ─────────────────────────────────────────────────────────────────────

enum FlowThemeMode { system, light, dark }

class FlowThemeController extends ChangeNotifier {
  FlowThemeController._() {
    _systemBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _onSystemBrightnessChanged;
    // Sync native window chrome (NSVisualEffectView material + window
    // appearance) once on construction so the vibrancy layer isn't
    // stuck in dark mode when the user boots the app into light.
    _syncNativeVibrancy();
  }

  static final FlowThemeController instance = FlowThemeController._();

  /// Bridge to `MainFlutterWindow.swift` for re-theming the native
  /// NSVisualEffectView that sits behind the Flutter view. Without
  /// this, the "glass" behind every surface stays dark in light mode.
  static const _windowChannel = MethodChannel('com.voiceassistant/window');

  /// Bridge to `FlowBarWindow.swift` — the floating status pill has
  /// its own native NSWindow with hard-coded dark colours. We fan
  /// the theme signal out to it so the pill's border/tint/text
  /// track the app theme.
  static const _flowBarChannel = MethodChannel('com.voiceassistant/flowbar');

  FlowThemeMode _mode = FlowThemeMode.system;
  late Brightness _systemBrightness;

  FlowThemeMode get mode => _mode;

  /// Effective brightness the app should paint in, respecting "system"
  /// mode by looking at the OS-reported brightness.
  Brightness get brightness {
    switch (_mode) {
      case FlowThemeMode.light:
        return Brightness.light;
      case FlowThemeMode.dark:
        return Brightness.dark;
      case FlowThemeMode.system:
        return _systemBrightness;
    }
  }

  /// Palette currently in use — flips whenever `brightness` flips.
  FlowPalette get palette =>
      brightness == Brightness.light ? FlowPalette.light : FlowPalette.dark;

  /// Update the app-level override. Pass `system` to follow the OS.
  void setMode(FlowThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _syncNativeVibrancy();
    notifyListeners();
  }

  void _onSystemBrightnessChanged() {
    final next =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    if (next == _systemBrightness) return;
    _systemBrightness = next;
    if (_mode == FlowThemeMode.system) {
      _syncNativeVibrancy();
      notifyListeners();
    }
  }

  /// Fire-and-forget the native message. We don't care about the
  /// return value — if the channel isn't wired (e.g. running in
  /// Chrome for UI iteration) this silently no-ops.
  void _syncNativeVibrancy() {
    final isLight = brightness == Brightness.light;
    final mode = isLight ? 'light' : 'dark';
    _windowChannel
        .invokeMethod<void>('setVibrancy', {'mode': mode})
        .catchError((_) {}); // swallow "not implemented" on non-macOS.
    _flowBarChannel
        .invokeMethod<void>('setTheme', {'mode': mode})
        .catchError((_) {});
  }
}
