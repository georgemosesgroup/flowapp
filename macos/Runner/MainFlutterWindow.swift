import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var windowChannel: FlutterMethodChannel?
  /// Weak ref to the vibrancy pane so we can re-theme it when Flutter
  /// tells us the user flipped to light or dark mode.
  private weak var vfxView: NSVisualEffectView?
  /// Solid-color tint layer on top of the vibrancy pane. NSVisualEffectView's
  /// own `layer.backgroundColor` sits *behind* the material and reads as
  /// barely any tint — we instead stack a real NSView with an explicit
  /// backgroundColor over it, which darkens the vibrancy pane to a
  /// proper "black glass" appearance.
  private weak var tintView: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // ── Liquid-Glass translucent window ──────────────────────────────
    // Let the system desktop blur through the window background. Flutter
    // renders on top with its own (partially-transparent) surfaces.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = true
    self.styleMask.insert(.fullSizeContentView)

    // Transparent Flutter view so the NSVisualEffectView shows through.
    flutterViewController.backgroundColor = .clear

    // Insert a vibrancy layer *behind* the Flutter view. We default to
    // the dark hudWindow material and swap it at runtime when Flutter
    // tells us the user flipped theme (see the "setVibrancy" method
    // handler below).
    let vfx = NSVisualEffectView()
    // `.sidebar` gives the same Apple-frosted blur as light mode.
    // The dark look is driven by the tint layer on top + darkAqua
    // NSAppearance, not by the material choice itself.
    vfx.material = .sidebar
    vfx.blendingMode = .behindWindow
    vfx.state = .active
    vfx.wantsLayer = true
    vfx.appearance = NSAppearance(named: .darkAqua)
    vfx.frame = flutterViewController.view.bounds
    vfx.autoresizingMask = [.width, .height]
    flutterViewController.view.addSubview(vfx, positioned: .below, relativeTo: nil)
    self.vfxView = vfx

    // Solid tint layer ON TOP of the vibrancy pane. Setting
    // `vfx.layer.backgroundColor` tints *behind* the material, which
    // barely moves the needle — we need a separate overlay view above
    // the material to actually tint what the user sees. ~55% black
    // preserves the native frosted-blur effect (same feel as light
    // mode) while coloring the whole window dark.
    let tint = NSView()
    tint.wantsLayer = true
    tint.layer = CALayer()
    tint.layer?.backgroundColor =
      NSColor.black.withAlphaComponent(0.62).cgColor
    tint.frame = flutterViewController.view.bounds
    tint.autoresizingMask = [.width, .height]
    if #available(macOS 11.0, *) {
      tint.layer?.cornerCurve = .continuous
    }
    tint.layer?.cornerRadius = 24
    tint.layer?.masksToBounds = true
    // Insert above the vfx pane but still BELOW the Flutter view.
    flutterViewController.view.addSubview(tint, positioned: .above, relativeTo: vfx)
    self.tintView = tint

    // Squircle window corners — matches macOS 26 Liquid-Glass window shape.
    flutterViewController.view.wantsLayer = true
    if let contentLayer = flutterViewController.view.layer {
      contentLayer.cornerRadius = 24
      contentLayer.masksToBounds = true
      if #available(macOS 11.0, *) {
        contentLayer.cornerCurve = .continuous
      }
    }
    vfx.layer?.cornerRadius = 24
    vfx.layer?.masksToBounds = true
    if #available(macOS 11.0, *) {
      vfx.layer?.cornerCurve = .continuous
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    SpeechRecognizerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "SpeechRecognizerPlugin")
    )

    FlowBarPlugin.register(
      with: flutterViewController.registrar(forPlugin: "FlowBarPlugin")
    )

    HotkeyPlugin.register(
      with: flutterViewController.registrar(forPlugin: "HotkeyPlugin")
    )

    SuggestionsPopupPlugin.register(
      with: flutterViewController.registrar(forPlugin: "SuggestionsPopupPlugin")
    )

    // Bridge for the custom traffic-light taps in Flutter.
    let windowChannel = FlutterMethodChannel(
      name: "com.voiceassistant/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.windowChannel = windowChannel
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "window gone", details: nil))
        return
      }
      switch call.method {
      case "close":
        // Route through the delegate so "close" still hides-not-destroys.
        self.performClose(nil)
        result(nil)
      case "minimize":
        self.miniaturize(nil)
        result(nil)
      case "zoom":
        self.zoom(nil)
        result(nil)
      case "getFocusState":
        result(self.isKeyWindow)
      case "quit":
        // Ask AppKit to terminate cleanly. AppDelegate's
        // applicationShouldTerminate hook still runs, so any pending
        // work (e.g. flushing settings to disk) gets a chance to
        // finish. Called from Dart when the user accepts an update —
        // they need Flow.app dead before the new DMG can replace it
        // in /Applications.
        result(nil)
        // Fire on the next runloop tick so the FlutterMethodChannel
        // reply can actually make it back to Dart before the process
        // vanishes. Without this the dialog's `await invokeMethod`
        // can hang forever on a completer that never resolves.
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      case "setActivationPolicy":
        // "regular"   → Dock icon + menu bar (needed for PlatformMenuBar
        //                to actually render on screen).
        // "accessory" → tray-only agent, hidden from Dock, no menu bar.
        // "prohibited"→ completely hidden process; we don't use it but
        //                keep the case for completeness.
        //
        // The app starts with LSUIElement=true (see Info.plist) so it
        // boots as an accessory. We flip to .regular whenever the
        // Flutter window is visible so the user sees a real menu bar,
        // and back to .accessory when the window is hidden so Flow
        // stays a menu-bar-tray app in spirit.
        let args = call.arguments as? [String: Any]
        let policy = (args?["policy"] as? String) ?? "regular"
        let target: NSApplication.ActivationPolicy
        switch policy {
        case "regular":    target = .regular
        case "accessory":  target = .accessory
        case "prohibited": target = .prohibited
        default:           target = .regular
        }
        // Idempotent — AppKit short-circuits if policy is unchanged.
        NSApp.setActivationPolicy(target)
        if target == .regular {
          // Bring the menu bar up immediately; without an activation
          // step macOS waits for the next click before drawing it.
          NSApp.activate(ignoringOtherApps: true)
        }
        result(nil)
      case "setVibrancy":
        // Flutter sends "light" or "dark"; we map to a macOS material
        // that plays nicely with the Liquid-Glass window chrome.
        //
        // Dark stacks a ~50% black tint layer ON TOP of the vibrancy
        // pane so the window reads as a deep dark-glass surface rather
        // than a thin translucent veil. The vibrancy still works — you
        // can see the desktop/wallpaper bleed through — it's just
        // dimmed way down.
        let args = call.arguments as? [String: Any]
        let mode = (args?["mode"] as? String) ?? "dark"
        if let vfx = self.vfxView {
          if mode == "light" {
            vfx.material = .sidebar
            vfx.appearance = NSAppearance(named: .aqua)
            vfx.layer?.backgroundColor = nil
            // Light mode: faint white wash — lets the native frosted
            // material stay visible so the wallpaper reads through
            // as soft blur.
            self.tintView?.layer?.backgroundColor =
              NSColor.white.withAlphaComponent(0.05).cgColor
          } else {
            // Use `.sidebar` in dark mode too (not `.hudWindow`) so
            // the native macOS blur behaves the same as in light mode
            // — we just flip the NSAppearance to darkAqua to recolor
            // the vibrancy. Then a ~55% black tint on top darkens it
            // without killing the glass effect. Goal: same Apple-feel
            // blur that light mode has, rendered in a dark palette.
            vfx.material = .sidebar
            vfx.appearance = NSAppearance(named: .darkAqua)
            vfx.layer?.backgroundColor = nil
            self.tintView?.layer?.backgroundColor =
              NSColor.black.withAlphaComponent(0.62).cgColor
          }
          vfx.isEmphasized = true
          // Re-theme the native traffic lights & window chrome too.
          self.appearance = vfx.appearance
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    self.delegate = self
    self.hidesOnDeactivate = false

    // Opt out of macOS native fullscreen. Flow is a menu-bar-first app;
    // native fullscreen auto-hides the system menu bar, which makes our
    // PlatformMenuBar effectively invisible and breaks the dictation
    // workflow (no menu → no Cmd-Q, no About, etc. without a hover).
    // Removing .fullScreenPrimary + adding .fullScreenNone turns the
    // green traffic-light button into a zoom (maximize) button and
    // greys out View → Enter Full Screen, matching the behaviour of
    // other tray-resident apps like Alfred / Raycast.
    var behavior = self.collectionBehavior
    behavior.remove(.fullScreenPrimary)
    behavior.insert(.fullScreenNone)
    self.collectionBehavior = behavior

    // Shift the native traffic-lights into the Flutter-drawn sidebar
    // pane. Apple's own apps (Finder, Mail) as well as Slack / Figma /
    // Tower do this by observing the title-bar container's
    // `frameDidChange` notifications and re-pinning the button origins
    // every time the system lays them out. Simply setting the origin
    // once in awakeFromNib doesn't stick.
    setUpTrafficLightReposition()
  }

  // MARK: - Traffic-light repositioning
  //
  // Using Auto Layout constraints (left/top pinning relative to the
  // button's superview) — the same technique the popular
  // `macos_window_utils` Flutter package uses. setFrameOrigin gets
  // reverted by the system's layout pass; constraints hold.

  /// Distance from the pane's left edge to the CLOSE button's origin,
  /// and from the pane's top edge to the top of the buttons. These
  /// land them inside the Flutter sidebar's reserved 38 px top strip.
  private let trafficLightOffset = CGPoint(x: 20, y: 20)

  private func setUpTrafficLightReposition() {
    pinTrafficLightButton(.closeButton, offsetX: trafficLightOffset.x)
    pinTrafficLightButton(.miniaturizeButton, offsetX: trafficLightOffset.x + 20)
    pinTrafficLightButton(.zoomButton, offsetX: trafficLightOffset.x + 40)
  }

  private func pinTrafficLightButton(
    _ type: NSWindow.ButtonType,
    offsetX: CGFloat
  ) {
    guard let btn = self.standardWindowButton(type),
          let superview = btn.superview else { return }

    btn.translatesAutoresizingMaskIntoConstraints = false

    // Drop any system-added constraints so ours are the only ones
    // pinning the button.
    let toRemove = superview.constraints.filter {
      ($0.firstItem as? NSButton) == btn ||
      ($0.secondItem as? NSButton) == btn
    }
    superview.removeConstraints(toRemove)

    superview.addConstraint(NSLayoutConstraint(
      item: btn, attribute: .left,
      relatedBy: .equal,
      toItem: superview, attribute: .left,
      multiplier: 1, constant: offsetX
    ))
    superview.addConstraint(NSLayoutConstraint(
      item: btn, attribute: .top,
      relatedBy: .equal,
      toItem: superview, attribute: .top,
      multiplier: 1, constant: trafficLightOffset.y
    ))
  }

  // Intercept close button — hide instead of destroy. We also drop the
  // activation policy to .accessory so Flow stops showing a menu bar
  // and Dock icon while only the tray remains.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
    return false
  }

  // Becoming the key window is the most reliable signal that the user
  // is interacting with the Flutter surface — promote to .regular so
  // the native menu bar is drawn. Re-entry from the tray funnels
  // through makeKeyAndOrderFront which triggers this hook.
  func windowDidBecomeKey(_ notification: Notification) {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
  }
}
