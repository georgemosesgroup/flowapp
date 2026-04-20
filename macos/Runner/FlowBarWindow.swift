import Cocoa
import FlutterMacOS

// Premium Apple-style FlowBar.
//
// Visual contract:
//   · Glass blur background (NSVisualEffectView .hudWindow).
//   · One single surface that morphs between sizes for each state —
//     no external tooltips for the common idle/listening hovers.
//   · Dual symmetric waveform (top + bottom mirror) with gradient fill.
//   · Soft ambient glow around active bars, strength tied to amplitude.
//   · Spring pulse on start/stop, gentle breathing when idle.
class FlowBarPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var flowBarWindow: NSWindow?
    private var containerView: FlowBarContainer?
    private var effectView: NSVisualEffectView?
    private var barsView: FlowBarsView?
    private var spinnerView: NSProgressIndicator?
    private var idleHintLabel: NSTextField?
    private var timerLabel: NSTextField?
    private var recordingDot: CALayer?
    private var dividerLayer: CALayer?
    private var stopButton: FlowBarStopButton?
    private var tooltipWindow: NSWindow?
    private var currentState: String = "idle"
    /// "dark" or "light" — drives `applyTheme()`. Seeded dark to
    /// match the pre-theme-aware behaviour; Flutter flips us on
    /// startup via the shared window-channel fan-out.
    private var currentTheme: String = "dark"
    private var tintLayer: CALayer?
    private var recordingStartedAt: Date?
    private var listeningTimer: Timer?

    // Size presets (outer window dimensions).
    private let idleW: CGFloat = 38
    private let idleH: CGFloat = 8
    // Populated from the actual text width in `createWindow()` so
    // the pill shrinks/grows to fit the hint instead of locking a
    // fixed 210 px; kept at a 110 px floor so short labels don't
    // look stumpy.
    private var hoverIdleW: CGFloat = 210
    private let hoverIdleH: CGFloat = 28
    private let listeningW: CGFloat = 100
    private let listeningH: CGFloat = 24
    private let hoverListeningW: CGFloat = 280
    private let hoverListeningH: CGFloat = 38
    private let transcribingW: CGFloat = 100
    private let transcribingH: CGFloat = 24

    private var isHovering = false
    private var lastHoverToggleAt: CFTimeInterval = 0

    // MARK: - Plugin plumbing

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.voiceassistant/flowbar",
            binaryMessenger: registrar.messenger
        )
        let instance = FlowBarPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            showFlowBar()
            result(true)
        case "hide":
            hideFlowBar()
            result(true)
        case "updateState":
            let args = call.arguments as? [String: Any]
            let state = args?["state"] as? String ?? "idle"
            let text = args?["text"] as? String
            updateState(state: state, text: text)
            result(true)
        case "setShortcutLabel":
            result(true)
        case "setTheme":
            let args = call.arguments as? [String: Any]
            let mode = (args?["mode"] as? String) ?? "dark"
            currentTheme = mode
            applyTheme()
            result(true)
        case "updateAudioLevel":
            let args = call.arguments as? [String: Any]
            let level = (args?["level"] as? NSNumber)?.floatValue ?? 0
            let urgency = (args?["urgency"] as? NSNumber)?.floatValue ?? 0
            barsView?.setLiveLevel(level, urgency: urgency)
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func showFlowBar() {
        if flowBarWindow == nil { createWindow() }
        positionCenter(width: idleW, height: idleH)
        flowBarWindow?.orderFrontRegardless()
        updateState(state: "idle", text: nil)
    }

    private func hideFlowBar() {
        flowBarWindow?.orderOut(nil)
        hideTooltip()
    }

    private func positionCenter(width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x = sf.origin.x + (sf.width - width) / 2
        let y = sf.origin.y + sf.height - height - 6
        flowBarWindow?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - Create Window

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: idleW, height: idleH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false

        let container = FlowBarContainer(frame: NSRect(x: 0, y: 0, width: idleW, height: idleH))
        container.wantsLayer = true
        container.layer?.cornerRadius = idleH / 2
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        container.plugin = self
        containerView = container

        // Glass blur background — Apple HUD material, auto-resizes with the
        // container as the window morphs between sizes.
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)
        effectView = effect

        // Soft tint layer on top of the blur so the UI stays readable
        // over bright desktop wallpapers. Colour is set in
        // `applyTheme()` — dark stacks black, light stacks white.
        let tint = CALayer()
        tint.frame = container.bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(tint)
        tintLayer = tint

        // Recording dot (hover-listening only).
        let dot = CALayer()
        dot.backgroundColor = NSColor(red: 0.95, green: 0.32, blue: 0.42, alpha: 1).cgColor
        dot.cornerRadius = 4
        dot.frame = CGRect(x: 14, y: (hoverListeningH - 8) / 2, width: 8, height: 8)
        dot.opacity = 0
        dot.shadowColor = NSColor(red: 0.95, green: 0.32, blue: 0.42, alpha: 1).cgColor
        dot.shadowOpacity = 0.9
        dot.shadowRadius = 4
        dot.shadowOffset = .zero
        container.layer?.addSublayer(dot)
        recordingDot = dot

        // Waveform view — sized for the hover-listening layout so the bars
        // can breathe; compact listening state uses the same view with an
        // offset frame.
        let bars = FlowBarsView(frame: NSRect(x: 0, y: 0, width: listeningW, height: listeningH))
        bars.isHidden = true
        container.addSubview(bars)
        barsView = bars

        // Spinner for the transcribing state.
        let spinner = NSProgressIndicator(frame: NSRect(
            x: (transcribingW - 14) / 2,
            y: (transcribingH - 14) / 2,
            width: 14, height: 14
        ))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(spinner)
        spinnerView = spinner

        // Hover-idle hint: lives inside the bar so there's no floating
        // tooltip on hover — the bar itself grows and reveals the hint.
        let hintText = "⌘ Hold ^ Ctrl to talk"
        let hintFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let measured = (hintText as NSString)
            .size(withAttributes: [.font: hintFont])
        // 28 px of horizontal padding (14 each side) keeps the pill
        // from feeling cramped. Floor at 110 so short labels don't
        // collapse to a stub.
        hoverIdleW = max(110, ceil(measured.width) + 28)

        let hint = NSTextField(labelWithString: hintText)
        hint.font = hintFont
        hint.textColor = NSColor(white: 0.96, alpha: 1)
        hint.alignment = .center
        hint.isEditable = false
        hint.isSelectable = false
        hint.isBordered = false
        hint.drawsBackground = false
        hint.alphaValue = 0
        hint.frame = NSRect(x: 0, y: 6, width: hoverIdleW, height: 16)
        container.addSubview(hint)
        idleHintLabel = hint

        // Hover-listening timer ("● 0:12" — the dot is a layer, this is
        // just the digits).
        let timer = NSTextField(labelWithString: "0:00")
        timer.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        timer.textColor = NSColor(white: 0.96, alpha: 1)
        timer.alignment = .left
        timer.isEditable = false
        timer.isSelectable = false
        timer.isBordered = false
        timer.drawsBackground = false
        timer.alphaValue = 0
        timer.frame = NSRect(x: 26, y: 11, width: 46, height: 16)
        container.addSubview(timer)
        timerLabel = timer

        // Vertical divider between waveform area and the Stop button.
        let divider = CALayer()
        divider.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        divider.frame = CGRect(x: hoverListeningW - 82, y: 9, width: 1, height: 20)
        divider.opacity = 0
        container.layer?.addSublayer(divider)
        dividerLayer = divider

        // Stop button — inline inside the bar, appears on hover only.
        let stop = FlowBarStopButton(frame: NSRect(
            x: hoverListeningW - 72, y: 9, width: 62, height: 20
        ))
        stop.title = "⏹ Stop"
        stop.font = .systemFont(ofSize: 11, weight: .semibold)
        stop.isBordered = false
        stop.bezelStyle = .inline
        stop.alphaValue = 0
        stop.contentTintColor = NSColor(red: 0.98, green: 0.45, blue: 0.52, alpha: 1)
        (stop.cell as? NSButtonCell)?.backgroundColor = .clear
        stop.plugin = self
        stop.target = stop
        stop.action = #selector(FlowBarStopButton.stopTapped)
        container.addSubview(stop)
        stopButton = stop

        window.contentView = container
        flowBarWindow = window

        // Paint the initial theme so the bar doesn't flash dark on
        // light mode before Flutter gets a chance to call setTheme.
        applyTheme()
    }

    // MARK: - Theme
    //
    // Light / dark swap. Driven by the shared `setVibrancy` fan-out
    // from Flutter — FlowThemeController calls both setVibrancy
    // (main window) and setTheme (FlowBar) so the two stay in sync.

    private func applyTheme() {
        let isLight = currentTheme == "light"

        // Border — subtle white in dark, subtle black in light.
        containerView?.layer?.borderColor = isLight
            ? NSColor.black.withAlphaComponent(0.10).cgColor
            : NSColor.white.withAlphaComponent(0.10).cgColor

        // Native vibrancy material + appearance — determines the
        // blur's own tint. `.menu` reads as a soft white frosted
        // panel in aqua, `.hudWindow` stays dark in darkAqua.
        effectView?.material = isLight ? .menu : .hudWindow
        effectView?.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)

        // Tint — additional wash stacked on top of the native
        // material so the surface reads solid. Dark gets a soft
        // black wash; light gets a warm near-white wash.
        tintLayer?.backgroundColor = isLight
            ? NSColor.white.withAlphaComponent(0.55).cgColor
            : NSColor.black.withAlphaComponent(0.18).cgColor

        // Text — black-ish in light so it stays legible against the
        // white frost; near-white in dark. Same ink on both inline
        // labels (hint + timer).
        let ink: NSColor = isLight
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)
        idleHintLabel?.textColor = ink
        timerLabel?.textColor = ink

        // Vertical divider next to the Stop button — a hairline on
        // the right contrast of the surface.
        dividerLayer?.backgroundColor = isLight
            ? NSColor.black.withAlphaComponent(0.15).cgColor
            : NSColor.white.withAlphaComponent(0.15).cgColor

        // Spinner appearance — light spinner on dark, vice versa.
        spinnerView?.appearance =
            NSAppearance(named: isLight ? .aqua : .darkAqua)
    }

    // MARK: - States

    func updateState(state: String, text: String?) {
        let previousState = currentState
        currentState = state

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let repeatingListening = previousState == "listening" && state == "listening"
            if !repeatingListening {
                self.isHovering = false
                self.barsView?.stopAnimating()
                self.barsView?.isHidden = true
                self.spinnerView?.stopAnimation(nil)
                self.spinnerView?.isHidden = true
                self.hideTooltip()
                self.fadeInlineUI(hint: 0, timer: 0, stop: 0, dot: 0, divider: 0, duration: 0.12)
                self.recordingDot?.removeAnimation(forKey: "dotPulse")
                self.listeningTimer?.invalidate()
                self.listeningTimer = nil
            }

            switch state {
            case "idle":
                self.isHovering = false
                self.recordingStartedAt = nil
                self.animateTo(width: self.idleW, height: self.idleH)

            case "listening":
                if self.recordingStartedAt == nil {
                    self.recordingStartedAt = Date()
                }
                if repeatingListening { break }
                self.animateTo(width: self.listeningW, height: self.listeningH) {
                    self.layoutBarsForListening(hover: false)
                    self.barsView?.isHidden = false
                    self.barsView?.startAnimating()
                    self.pulseContainer()
                }

            case "transcribing":
                self.recordingStartedAt = nil
                self.spinnerView?.frame = NSRect(
                    x: (self.transcribingW - 14) / 2,
                    y: (self.transcribingH - 14) / 2,
                    width: 14, height: 14
                )
                self.spinnerView?.isHidden = false
                self.spinnerView?.startAnimation(nil)
                self.animateTo(width: self.transcribingW, height: self.transcribingH)

            case "done":
                self.showDoneTooltip(text: text ?? "✓ Inserted")
                self.animateTo(width: self.idleW, height: self.idleH)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.currentState = "idle"
                    self?.channel?.invokeMethod("onFlowBarDismissed", arguments: nil)
                }

            case "clipboard":
                self.showTooltip(text: text ?? "⌘V to paste", color: NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0), duration: 3.5)
                self.animateTo(width: self.idleW, height: self.idleH)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    self?.currentState = "idle"
                }

            case "error":
                self.showTooltip(text: text ?? "Error", color: NSColor(red: 0.91, green: 0.27, blue: 0.37, alpha: 1.0), duration: 2.0)
                self.animateTo(width: self.idleW, height: self.idleH)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.currentState = "idle"
                }

            default:
                break
            }
        }
    }

    // MARK: - Animation

    /// Morph the window + container to the target size with a spring curve.
    /// Corner radius tracks height so the pill-shape stays consistent.
    private func animateTo(width: CGFloat, height: CGFloat, completion: (() -> Void)? = nil) {
        guard let window = flowBarWindow, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x = sf.origin.x + (sf.width - width) / 2
        let y = sf.origin.y + sf.height - height - 6

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            window.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            self.containerView?.animator().frame = NSRect(x: 0, y: 0, width: width, height: height)
        }, completionHandler: completion)

        // Animate corner radius on the CA layer for the same duration.
        let cr = CABasicAnimation(keyPath: "cornerRadius")
        cr.fromValue = containerView?.layer?.cornerRadius ?? height / 2
        cr.toValue = height / 2
        cr.duration = 0.24
        cr.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        containerView?.layer?.add(cr, forKey: "cornerRadius")
        containerView?.layer?.cornerRadius = height / 2
    }

    /// Subtle overshoot pulse when recording starts, gives haptic-like feel.
    private func pulseContainer() {
        guard let layer = containerView?.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.94
        spring.toValue = 1.0
        spring.damping = 10
        spring.stiffness = 180
        spring.mass = 0.8
        spring.initialVelocity = 2
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pulse")
    }

    /// Position the waveform centered in the current container size.
    /// The bars view is sized for the compact listening state and uses
    /// an autoresizingMask (flexible left/right/top/bottom margins) so it
    /// re-centers itself automatically as the container grows on hover —
    /// the waveform stays put in the screen center while timer/Stop
    /// fade in at the outer edges.
    private func layoutBarsForListening(hover: Bool) {
        guard let bars = barsView, let container = containerView else { return }
        let waveW: CGFloat = 80
        let waveH: CGFloat = 18
        let cw = container.bounds.width
        let ch = container.bounds.height
        bars.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        bars.frame = NSRect(
            x: (cw - waveW) / 2,
            y: (ch - waveH) / 2,
            width: waveW,
            height: waveH
        )
        bars.layoutBars()
    }

    /// Fade-in/out helper for the inline hover widgets (hint label, timer
    /// label, stop button, red dot, divider line).
    private func fadeInlineUI(hint: CGFloat, timer: CGFloat, stop: CGFloat, dot: Float, divider: Float, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            idleHintLabel?.animator().alphaValue = hint
            timerLabel?.animator().alphaValue = timer
            stopButton?.animator().alphaValue = stop
        }
        if let dotLayer = recordingDot {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = dotLayer.opacity
            a.toValue = dot
            a.duration = duration
            dotLayer.add(a, forKey: "op")
            dotLayer.opacity = dot
        }
        if let divLayer = dividerLayer {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = divLayer.opacity
            a.toValue = divider
            a.duration = duration
            divLayer.add(a, forKey: "op")
            divLayer.opacity = divider
        }
    }

    // MARK: - Hover handling

    func showHoverTooltip() {
        // Debounce: a tracking area on a pill that morphs can emit repeated
        // enter/exit events during a single user gesture. Guard on state as
        // well so hovers in transcribing/done/error are no-ops.
        guard !isHovering else { return }
        guard currentState == "idle" || currentState == "listening" else { return }
        let now = CACurrentMediaTime()
        if now - lastHoverToggleAt < 0.08 { return }
        lastHoverToggleAt = now
        isHovering = true

        // Pre-position inline subviews for the hover layout BEFORE animating.
        // Alpha is still 0, so they fade in at the correct coords as the
        // window grows around them — no mid-animation frame jump.
        positionInlineForHoverListening()

        if currentState == "idle" {
            idleHintLabel?.frame = NSRect(
                x: 0, y: (hoverIdleH - 16) / 2, width: hoverIdleW, height: 16
            )
            animateTo(width: hoverIdleW, height: hoverIdleH)
            fadeInlineUI(hint: 1, timer: 0, stop: 0, dot: 0, divider: 0, duration: 0.2)
            return
        }

        if currentState == "listening" {
            animateTo(width: hoverListeningW, height: hoverListeningH) { [weak self] in
                self?.layoutBarsForListening(hover: true)
            }
            fadeInlineUI(hint: 0, timer: 1, stop: 1, dot: 1, divider: 1, duration: 0.2)

            if let dot = recordingDot {
                let pulse = CABasicAnimation(keyPath: "transform.scale")
                pulse.fromValue = 1.0
                pulse.toValue = 1.25
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.duration = 0.75
                dot.add(pulse, forKey: "dotPulse")
            }

            listeningTimer?.invalidate()
            listeningTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.refreshTimerLabel()
            }
            refreshTimerLabel()
            return
        }
    }

    func hideHoverTooltip() {
        guard isHovering else { return }
        let now = CACurrentMediaTime()
        if now - lastHoverToggleAt < 0.08 { return }
        lastHoverToggleAt = now
        isHovering = false

        fadeInlineUI(hint: 0, timer: 0, stop: 0, dot: 0, divider: 0, duration: 0.18)
        recordingDot?.removeAnimation(forKey: "dotPulse")
        listeningTimer?.invalidate()
        listeningTimer = nil

        if currentState == "idle" {
            animateTo(width: idleW, height: idleH)
        } else if currentState == "listening" {
            animateTo(width: listeningW, height: listeningH) { [weak self] in
                self?.layoutBarsForListening(hover: false)
            }
        }
    }

    /// Park the timer + Stop + divider + dot at the hover-listening coords.
    /// They stay at these positions with alpha=0 the rest of the time; only
    /// alpha animates during hover transitions, avoiding the frame-jump
    /// that used to show up when completion handlers set frames after the
    /// window had already grown.
    private func positionInlineForHoverListening() {
        recordingDot?.frame = CGRect(
            x: 14, y: (hoverListeningH - 8) / 2, width: 8, height: 8
        )
        timerLabel?.frame = NSRect(x: 26, y: 11, width: 46, height: 16)
        dividerLayer?.frame = CGRect(
            x: hoverListeningW - 82, y: 9, width: 1, height: 20
        )
        stopButton?.frame = NSRect(
            x: hoverListeningW - 72, y: 9, width: 62, height: 20
        )
    }

    private func refreshTimerLabel() {
        guard let started = recordingStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(started))
        timerLabel?.stringValue = formatElapsed(elapsed)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    func handleStopTapped() {
        channel?.invokeMethod("onFlowBarStop", arguments: nil)
    }

    // MARK: - Legacy tooltips (still used for done / clipboard / error)

    private func showTooltip(text: String, color: NSColor, duration: TimeInterval) {
        hideTooltip()

        guard let barWindow = flowBarWindow else { return }

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrStr = NSAttributedString(string: text, attributes: [.font: font])
        let textW = ceil(attrStr.size().width) + 2
        let textH: CGFloat = 16
        let hPad: CGFloat = 10
        let vPad: CGFloat = 8
        let tw = textW + hPad * 2
        let th = textH + vPad * 2

        let barFrame = barWindow.frame
        let x = barFrame.origin.x + (barFrame.width - tw) / 2
        let y = barFrame.origin.y - th - 8

        let tipWindow = NSWindow(
            contentRect: NSRect(x: x, y: y, width: tw, height: th),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tipWindow.level = .floating
        tipWindow.isOpaque = false
        tipWindow.backgroundColor = .clear
        tipWindow.hasShadow = true
        tipWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let tipContainer = NSView(frame: NSRect(x: 0, y: 0, width: tw, height: th))
        tipContainer.wantsLayer = true
        tipContainer.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.95).cgColor
        tipContainer.layer?.cornerRadius = th / 2
        tipContainer.layer?.masksToBounds = true

        let label = NSTextField(frame: NSRect(x: hPad, y: vPad, width: textW, height: textH))
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.font = font
        label.textColor = color
        label.stringValue = text
        tipContainer.addSubview(label)

        tipWindow.contentView = tipContainer
        tipWindow.alphaValue = 0
        tipWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            tipWindow.animator().alphaValue = 1
        }

        tooltipWindow = tipWindow

        if duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.hideTooltip()
            }
        }
    }

    /// Shows a "done" tooltip with an Undo button that fires `onFlowBarUndo`
    /// back to Dart when clicked. Still an external pill — keeps the undo
    /// path simple and the "Inserted" confirmation unmissable.
    private func showDoneTooltip(text: String) {
        hideTooltip()

        guard let barWindow = flowBarWindow else { return }

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let undoFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let doneColor = NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
        let undoColor = NSColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1.0)

        let attrStr = NSAttributedString(string: text, attributes: [.font: font])
        let textW = ceil(attrStr.size().width) + 2
        let undoStr = NSAttributedString(string: "Undo", attributes: [.font: undoFont])
        let undoW = ceil(undoStr.size().width) + 2
        let separatorW: CGFloat = 12
        let textH: CGFloat = 16
        let hPad: CGFloat = 10
        let vPad: CGFloat = 8
        let tw = textW + separatorW + undoW + hPad * 2
        let th = textH + vPad * 2

        let barFrame = barWindow.frame
        let x = barFrame.origin.x + (barFrame.width - tw) / 2
        let y = barFrame.origin.y - th - 8

        let tipWindow = NSWindow(
            contentRect: NSRect(x: x, y: y, width: tw, height: th),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tipWindow.level = .floating
        tipWindow.isOpaque = false
        tipWindow.backgroundColor = .clear
        tipWindow.hasShadow = true
        tipWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let tipContainer = NSView(frame: NSRect(x: 0, y: 0, width: tw, height: th))
        tipContainer.wantsLayer = true
        tipContainer.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.95).cgColor
        tipContainer.layer?.cornerRadius = th / 2
        tipContainer.layer?.masksToBounds = true

        let label = NSTextField(frame: NSRect(x: hPad, y: vPad, width: textW, height: textH))
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.font = font
        label.textColor = doneColor
        label.stringValue = text
        tipContainer.addSubview(label)

        let sep = NSTextField(frame: NSRect(x: hPad + textW, y: vPad, width: separatorW, height: textH))
        sep.isEditable = false
        sep.isBordered = false
        sep.drawsBackground = false
        sep.alignment = .center
        sep.font = font
        sep.textColor = NSColor.white.withAlphaComponent(0.2)
        sep.stringValue = "|"
        tipContainer.addSubview(sep)

        let undoButton = FlowBarUndoButton(
            frame: NSRect(x: hPad + textW + separatorW, y: vPad, width: undoW, height: textH)
        )
        undoButton.title = "Undo"
        undoButton.font = undoFont
        undoButton.isBordered = false
        undoButton.bezelStyle = .inline
        (undoButton.cell as? NSButtonCell)?.backgroundColor = .clear
        undoButton.contentTintColor = undoColor
        undoButton.plugin = self
        undoButton.target = undoButton
        undoButton.action = #selector(FlowBarUndoButton.undoTapped)
        tipContainer.addSubview(undoButton)

        tipWindow.contentView = tipContainer
        tipWindow.alphaValue = 0
        tipWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            tipWindow.animator().alphaValue = 1
        }

        tooltipWindow = tipWindow

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hideTooltip()
        }
    }

    func handleUndoTapped() {
        channel?.invokeMethod("onFlowBarUndo", arguments: nil)
        hideTooltip()
    }

    private func hideTooltip() {
        guard let tip = tooltipWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            tip.animator().alphaValue = 0
        }, completionHandler: {
            tip.orderOut(nil)
        })
        tooltipWindow = nil
    }
}

// MARK: - Container (handles mouse hover)

class FlowBarContainer: NSView {
    weak var plugin: FlowBarPlugin?
    private var trackingArea: NSTrackingArea?

    // Fixed hover zone dimensions. Wider and taller than any bar state so
    // the tracking rect doesn't shrink out from under the cursor when the
    // bar morphs back to idle — that used to cause a mouseExited →
    // shrink → mouseEntered → grow feedback loop.
    private let hoverZoneW: CGFloat = 380
    private let hoverZoneH: CGFloat = 80

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // Anchor the tracking rect at the view's geometric center. The
        // window is always centered on the screen at the same X, so this
        // keeps a stable hover zone across every state transition.
        let rect = CGRect(
            x: bounds.midX - hoverZoneW / 2,
            y: bounds.midY - hoverZoneH / 2,
            width: hoverZoneW,
            height: hoverZoneH
        )
        trackingArea = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        plugin?.showHoverTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        plugin?.hideHoverTooltip()
    }
}

// MARK: - Buttons

class FlowBarUndoButton: NSButton {
    weak var plugin: FlowBarPlugin?

    @objc func undoTapped() {
        plugin?.handleUndoTapped()
    }
}

class FlowBarStopButton: NSButton {
    weak var plugin: FlowBarPlugin?

    @objc func stopTapped() {
        plugin?.handleStopTapped()
    }
}

// MARK: - Dual Waveform

/// Symmetric dual-waveform view. Top and bottom bars mirror off a shared
/// centerline; heights are driven by a 12-sample ring buffer of smoothed
/// RMS levels so the newest sample scrolls in from the right. Colour
/// transitions red → amber → yellow based on silence urgency, and a soft
/// ambient glow brightens with peak amplitude.
class FlowBarsView: NSView {
    private var topBars: [CALayer] = []
    private var bottomBars: [CALayer] = []
    private var gradient: CAGradientLayer?
    private var displayTimer: Timer?
    private let barCount = 12
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 2.0

    private var liveLevel: Float = 0
    private var levelHistory: [Float]
    private var lastLevelAt: CFTimeInterval = 0
    private var urgency: Float = 0

    override init(frame: NSRect) {
        self.levelHistory = Array(repeating: 0, count: 12)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        self.levelHistory = Array(repeating: 0, count: 12)
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    func layoutBars() {
        topBars.forEach { $0.removeFromSuperlayer() }
        bottomBars.forEach { $0.removeFromSuperlayer() }
        gradient?.removeFromSuperlayer()
        topBars.removeAll()
        bottomBars.removeAll()

        let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (frame.width - totalW) / 2
        let center = frame.height / 2

        // Container layer for the bars — we run the gradient-fill as a mask
        // over it so all bars share one coherent colour sweep.
        let masked = CALayer()
        masked.frame = bounds
        layer?.addSublayer(masked)

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)

            let top = CALayer()
            top.frame = CGRect(x: x, y: center, width: barWidth, height: 1)
            top.backgroundColor = NSColor.white.cgColor
            top.cornerRadius = barWidth / 2
            masked.addSublayer(top)
            topBars.append(top)

            let bottom = CALayer()
            bottom.frame = CGRect(x: x, y: center - 1, width: barWidth, height: 1)
            bottom.backgroundColor = NSColor.white.cgColor
            bottom.cornerRadius = barWidth / 2
            masked.addSublayer(bottom)
            bottomBars.append(bottom)
        }

        let grad = CAGradientLayer()
        grad.frame = bounds
        grad.startPoint = CGPoint(x: 0, y: 0.5)
        grad.endPoint = CGPoint(x: 1, y: 0.5)
        grad.colors = gradientColors(for: 0)
        layer?.replaceSublayer(masked, with: grad)

        // Use the bars as a mask so the gradient bleeds through only in
        // the bar silhouettes — produces the pink→amber sweep across the
        // whole waveform rather than per-bar.
        let maskContainer = CALayer()
        maskContainer.frame = bounds
        for bar in topBars + bottomBars {
            maskContainer.addSublayer(bar)
        }
        grad.mask = maskContainer
        gradient = grad

        // Ambient glow under the gradient — same tint as the dominant bar
        // color, radius driven by amplitude during animate().
        grad.shadowColor = NSColor(red: 0.95, green: 0.32, blue: 0.42, alpha: 1).cgColor
        grad.shadowOpacity = 0
        grad.shadowRadius = 4
        grad.shadowOffset = .zero
    }

    func setLiveLevel(_ level: Float, urgency: Float) {
        let clamped = max(0, min(1, level))
        liveLevel = liveLevel * 0.6 + clamped * 0.4
        levelHistory.removeFirst()
        levelHistory.append(liveLevel)
        lastLevelAt = CACurrentMediaTime()
        let clampedU = max(0, min(1, urgency))
        let alpha: Float = clampedU > self.urgency ? 0.5 : 0.15
        self.urgency = self.urgency * (1 - alpha) + clampedU * alpha
    }

    private func gradientColors(for u: Float) -> [CGColor] {
        // u = 0 → warm red-pink palette; u = 1 → amber-gold palette.
        let t = max(0, min(1, u))
        let r1: CGFloat = 0.95, g1: CGFloat = 0.32 + CGFloat(t) * 0.4, b1: CGFloat = 0.42 - CGFloat(t) * 0.25
        let r2: CGFloat = 0.98, g2: CGFloat = 0.55 + CGFloat(t) * 0.3, b2: CGFloat = 0.58 - CGFloat(t) * 0.4
        return [
            NSColor(red: r1, green: g1, blue: b1, alpha: 1).cgColor,
            NSColor(red: r2, green: g2, blue: b2, alpha: 1).cgColor,
        ]
    }

    func startAnimating() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.animate()
        }
    }

    func stopAnimating() {
        displayTimer?.invalidate()
        displayTimer = nil
        liveLevel = 0
        levelHistory = Array(repeating: 0, count: barCount)
        lastLevelAt = 0
        urgency = 0
    }

    private func animate() {
        let now = CACurrentMediaTime()
        let half = (frame.height - 2) / 2
        let minH: CGFloat = 0.8
        let center = frame.height / 2
        let hasLive = (now - lastLevelAt) < 0.3 && liveLevel > 0.015

        gradient?.colors = gradientColors(for: urgency)
        gradient?.shadowOpacity = hasLive ? Float(0.25 + 0.55 * Double(liveLevel)) : 0
        gradient?.shadowColor = (gradientColors(for: urgency).first) ?? NSColor.systemRed.cgColor

        for i in 0..<topBars.count {
            let targetH: CGFloat
            if hasLive {
                let sample = levelHistory[i]
                let eased = CGFloat(pow(sample, 0.6))
                targetH = max(minH, eased * half)
            } else {
                let phase = Double(i) * 0.55 + now * 2.2
                let breathe = CGFloat(0.15 + 0.12 * sin(phase))
                targetH = minH + breathe * (half - minH)
            }

            let top = topBars[i]
            let bottom = bottomBars[i]
            let currentTop = top.frame.size.height
            let nextTop = currentTop + (targetH - currentTop) * 0.32
            let clamped = max(minH, min(nextTop, half))

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            top.frame = CGRect(x: top.frame.origin.x, y: center, width: barWidth, height: clamped)
            bottom.frame = CGRect(x: bottom.frame.origin.x, y: center - clamped, width: barWidth, height: clamped)
            CATransaction.commit()
        }
    }

    override func removeFromSuperview() {
        stopAnimating()
        super.removeFromSuperview()
    }
}
