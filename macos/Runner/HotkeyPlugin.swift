import Cocoa
import FlutterMacOS
import Carbon

class HotkeyPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var eventMonitor: Any?
    private var localMonitor: Any?
    private var hotkeyRef: EventHotKeyRef?

    // Current hotkey config
    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private var hotkeyMode: String = "double_ctrl" // "double_ctrl", "hold_ctrl", "custom"

    // Double-tap detection
    private var lastKeyDownTime: Date?
    private let doubleTapThreshold: TimeInterval = 0.35

    // Hold detection
    private var isHolding = false
    private var holdTimer: Timer?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.voiceassistant/hotkey",
            binaryMessenger: registrar.messenger
        )
        let instance = HotkeyPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private func log(_ msg: String) {
        // Debug logging disabled for production
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startListening":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? String ?? "double_ctrl"
            let keyCode = args?["keyCode"] as? Int
            let modifiers = args?["modifiers"] as? Int
            log("handle startListening mode=\(mode) keyCode=\(keyCode ?? -1) modifiers=\(modifiers ?? -1)")
            startListening(mode: mode, keyCode: keyCode, modifiers: modifiers)
            result(true)
        case "stopListening":
            stopListening()
            result(true)
        case "setMode":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? String ?? "double_ctrl"
            hotkeyMode = mode
            restartListening()
            result(true)
        case "startRecording":
            // Start recording a custom hotkey combo
            startRecordingHotkey()
            result(true)
        case "stopRecording":
            stopRecordingHotkey()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Global Event Monitor

    private func startListening(mode: String, keyCode: Int?, modifiers: Int?) {
        stopListening()
        hotkeyMode = mode

        if let kc = keyCode {
            currentKeyCode = UInt32(kc)
        }
        if let mod = modifiers {
            currentModifiers = UInt32(mod)
        }

        log("startListening mode=\(mode) keyCode=\(currentKeyCode) modifiers=\(currentModifiers)")

        switch hotkeyMode {
        case "double_ctrl":
            startDoubleTapMonitor()
        case "hold_ctrl":
            startHoldMonitor()
        case "custom":
            if currentKeyCode > 0 {
                startCustomMonitor()
            } else {
                NSLog("[HotkeyPlugin] custom mode but keyCode=0, skipping registration")
            }
        default:
            startHoldMonitor()
        }
    }

    private func stopListening() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        unregisterCustomHotkey()
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func restartListening() {
        startListening(mode: hotkeyMode, keyCode: Int(currentKeyCode), modifiers: Int(currentModifiers))
    }

    // MARK: - Double-tap Ctrl

    private func startDoubleTapMonitor() {
        // Check accessibility and prompt if needed
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        if !trusted {
            NSLog("[HotkeyPlugin] Accessibility not granted — prompting user")
        }

        // Global monitor (works in all apps, needs accessibility)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also add local monitor (works when our app is active, no accessibility needed)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Check if Control key was pressed
        let isCtrl = event.modifierFlags.contains(.control)

        if isCtrl {
            // Key down
            let now = Date()
            if let lastTime = lastKeyDownTime, now.timeIntervalSince(lastTime) < doubleTapThreshold {
                // Double tap detected!
                lastKeyDownTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.channel?.invokeMethod("onHotkeyPressed", arguments: nil)
                }
            } else {
                lastKeyDownTime = now
            }
        }
    }

    // MARK: - Hold Ctrl

    private func startHoldMonitor() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        if !trusted {
            NSLog("[HotkeyPlugin] Accessibility not granted for hold mode")
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHoldFlags(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHoldFlags(event)
            return event
        }
    }

    private func handleHoldFlags(_ event: NSEvent) {
        let isCtrl = event.modifierFlags.contains(.control)

        if isCtrl && !isHolding {
            isHolding = true
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onHotkeyDown", arguments: nil)
            }
        } else if !isCtrl && isHolding {
            isHolding = false
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onHotkeyUp", arguments: nil)
            }
        }
    }

    // MARK: - Custom Hotkey (Carbon Global)

    private var carbonEventHandler: EventHandlerRef?

    private func cocoaToCarbonModifiers(_ cocoaMods: UInt32) -> UInt32 {
        var carbon: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoaMods))
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private var customHoldActive = false
    private var customReleaseMonitor: Any?
    private var customReleaseLocalMonitor: Any?

    private func startCustomMonitor() {
        unregisterCustomHotkey()
        customHoldActive = false

        let carbonMods = cocoaToCarbonModifiers(currentModifiers)

        log("startCustomMonitor keyCode=\(currentKeyCode) carbonMods=\(carbonMods) cocoaMods=\(currentModifiers)")

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x464C4F57) // "FLOW"
        hotKeyID.id = 1

        let status = RegisterEventHotKey(
            currentKeyCode,
            carbonMods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let pluginPtr = Unmanaged.passUnretained(self).toOpaque()

            InstallEventHandler(
                GetEventDispatcherTarget(),
                { (_, inEvent, userData) -> OSStatus in
                    guard let ud = userData else { return OSStatus(eventNotHandledErr) }
                    let plugin = Unmanaged<HotkeyPlugin>.fromOpaque(ud).takeUnretainedValue()
                    plugin.handleCustomDown()
                    return noErr
                },
                1,
                &eventType,
                pluginPtr,
                &carbonEventHandler
            )

            // Monitor key/modifier release to detect "hold released"
            customReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] event in
                self?.handleCustomRelease(event)
            }
            customReleaseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] event in
                self?.handleCustomRelease(event)
                return event
            }

            log("Carbon hotkey registered OK (hold mode)")
        } else {
            log("Carbon hotkey FAILED status=\(status)")
        }
    }

    private func handleCustomDown() {
        guard !customHoldActive else { return }
        customHoldActive = true
        log("Custom hotkey DOWN — start recording")
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onHotkeyDown", arguments: nil)
        }
    }

    private func handleCustomRelease(_ event: NSEvent) {
        guard customHoldActive else { return }

        // Check if the key or any required modifier was released
        if event.type == .keyUp && UInt32(event.keyCode) == currentKeyCode {
            customHoldActive = false
            log("Custom hotkey UP (key released)")
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onHotkeyUp", arguments: nil)
            }
        } else if event.type == .flagsChanged {
            let currentMods = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            if (currentMods & currentModifiers) != currentModifiers {
                customHoldActive = false
                log("Custom hotkey UP (modifier released)")
                DispatchQueue.main.async { [weak self] in
                    self?.channel?.invokeMethod("onHotkeyUp", arguments: nil)
                }
            }
        }
    }

    private func unregisterCustomHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = carbonEventHandler {
            RemoveEventHandler(handler)
            carbonEventHandler = nil
        }
        if let m = customReleaseMonitor { NSEvent.removeMonitor(m); customReleaseMonitor = nil }
        if let m = customReleaseLocalMonitor { NSEvent.removeMonitor(m); customReleaseLocalMonitor = nil }
        customHoldActive = false
    }

    // MARK: - Hotkey Recording (for settings UI)

    private var recordingMonitors: [Any] = []
    private var recordedKeys: Set<UInt16> = []
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var peakModifiers: NSEvent.ModifierFlags = []
    private var peakKeyCode: UInt16? = nil
    private var hadKeys = false

    private func startRecordingHotkey() {
        recordedKeys = []
        recordedModifiers = []
        peakModifiers = []
        peakKeyCode = nil
        hadKeys = false

        // Flags — track modifiers live
        let flagsLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleRecordingFlags(event)
            return event
        }
        recordingMonitors.append(flagsLocal as Any)

        // KeyDown — track pressed keys
        let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordingKeyDown(event)
            return nil
        }
        recordingMonitors.append(keyDown as Any)

        // KeyUp — finalize on release
        let keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleRecordingKeyUp(event)
            return nil
        }
        recordingMonitors.append(keyUp as Any)
    }

    private func handleRecordingFlags(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        recordedModifiers = mods

        // Track peak (maximum modifiers held)
        if mods.rawValue > peakModifiers.rawValue {
            peakModifiers = mods
        }

        let names = modifierFlagsToNames(mods)

        // If modifiers released and we had a combo — finalize
        if mods.isEmpty && hadKeys {
            finalizeRecording()
            return
        }

        // If only modifiers released (no key was pressed) and we had modifiers
        if mods.isEmpty && !peakModifiers.isEmpty && peakKeyCode == nil {
            // User only pressed modifiers then released — don't save, reset
            peakModifiers = []
            channel?.invokeMethod("onHotkeyRecordingUpdate", arguments: [
                "displayName": "Press a key combo...",
            ])
            return
        }

        // Live preview
        if names.isEmpty {
            if !hadKeys {
                channel?.invokeMethod("onHotkeyRecordingUpdate", arguments: [
                    "displayName": "Press a key combo...",
                ])
            }
        } else {
            var preview = names.joined(separator: " + ")
            if let kc = peakKeyCode {
                preview += " + " + keyCodeToName(kc)
            } else {
                preview += " + ..."
            }
            channel?.invokeMethod("onHotkeyRecordingUpdate", arguments: [
                "displayName": preview,
            ])
        }
    }

    private func handleRecordingKeyDown(_ event: NSEvent) {
        peakKeyCode = event.keyCode
        hadKeys = true
        log("recordingKeyDown keyCode=\(event.keyCode) mods=\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)")

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.rawValue > peakModifiers.rawValue {
            peakModifiers = mods
        }

        let names = modifierFlagsToNames(peakModifiers)
        let keyName = keyCodeToName(event.keyCode)
        let preview = (names + [keyName]).joined(separator: " + ")

        channel?.invokeMethod("onHotkeyRecordingUpdate", arguments: [
            "displayName": preview,
        ])
    }

    private func handleRecordingKeyUp(_ event: NSEvent) {
        // Key released — finalize
        finalizeRecording()
    }

    private func finalizeRecording() {
        guard let keyCode = peakKeyCode else { return }
        let modNames = modifierFlagsToNames(peakModifiers)

        guard !modNames.isEmpty else {
            channel?.invokeMethod("onHotkeyRecordingUpdate", arguments: [
                "displayName": "Need modifier (⌘/⌥/^/⇧) + key",
            ])
            hadKeys = false
            peakKeyCode = nil
            peakModifiers = []
            return
        }

        let keyName = keyCodeToName(keyCode)
        let displayName = (modNames + [keyName]).joined(separator: " + ")
        let modifiers = UInt(peakModifiers.rawValue)

        log("finalizeRecording keyCode=\(keyCode) modifiers=\(modifiers) display=\(displayName)")

        channel?.invokeMethod("onHotkeyRecorded", arguments: [
            "keyCode": Int(keyCode),
            "modifiers": Int(modifiers),
            "displayName": displayName,
        ])

        stopRecordingHotkey()
    }

    private func stopRecordingHotkey() {
        for monitor in recordingMonitors {
            NSEvent.removeMonitor(monitor)
        }
        recordingMonitors.removeAll()
        recordedKeys = []
        recordedModifiers = []
        peakModifiers = []
        peakKeyCode = nil
        hadKeys = false
    }

    // MARK: - Helpers

    private func modifierFlagsToNames(_ flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.command) { names.append("⌘") }
        if flags.contains(.shift) { names.append("⇧") }
        if flags.contains(.option) { names.append("⌥") }
        if flags.contains(.control) { names.append("^") }
        return names
    }

    private func keyCodeToName(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2",
            122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}
