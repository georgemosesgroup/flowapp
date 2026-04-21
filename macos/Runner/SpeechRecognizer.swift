import Cocoa
import FlutterMacOS
import AVFoundation

class SpeechRecognizerPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var isRecording = false

    // Realtime streaming state (additive — does NOT touch batch recording)
    private var isRealtimeRecording = false
    private var realtimeConverter: AVAudioConverter?
    private var realtimePcmBuffer = Data()
    private let realtimeFrameBytes = 6400 // ~200 ms at 16 kHz, 16-bit mono (16000 * 2 * 0.2)
    private let realtimeLock = NSLock()

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.voiceassistant/speech",
            binaryMessenger: registrar.messenger
        )
        let instance = SpeechRecognizerPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermissions":
            checkPermissions(result: result)
        case "requestMicrophonePermission":
            requestMicrophonePermission(result: result)
        case "startRecording":
            startRecording(result: result)
        case "stopRecording":
            stopRecording(result: result)
        case "cancelRecording":
            cancelRecording(result: result)
        case "pasteText":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? ""
            pasteText(text: text, result: result)
        case "openSystemPreferences":
            let args = call.arguments as? [String: Any]
            let pane = args?["pane"] as? String ?? "microphone"
            openSystemPreferences(pane: pane, result: result)
        case "setLaunchAtLogin":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            setLaunchAtLogin(enabled: enabled, result: result)
        case "setDockVisibility":
            let args = call.arguments as? [String: Any]
            let visible = args?["visible"] as? Bool ?? true
            setDockVisibility(visible: visible, result: result)
        case "listMicrophones":
            listMicrophones(result: result)
        case "playSound":
            let args = call.arguments as? [String: Any]
            let sound = args?["sound"] as? String ?? "start"
            playSound(name: sound, result: result)
        case "checkAccessibility":
            checkAccessibility(result: result)
        case "openAccessibilitySettings":
            openAccessibilitySettings(result: result)
        case "setupStatusBar":
            setupStatusBar(result: result)
        case "startRealtimeRecording":
            startRealtimeRecording(result: result)
        case "stopRealtimeRecording":
            stopRealtimeRecording(result: result)
        case "simulateUndo":
            simulateUndo(result: result)
        case "setSilenceDetection":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? true
            silenceDetectionEnabled = enabled
            result(true)
        case "setSilenceTimeout":
            let args = call.arguments as? [String: Any]
            let seconds = args?["seconds"] as? Double ?? 1.5
            silenceTimeoutSeconds = max(0.5, min(5.0, seconds))
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Permissions

    private func checkPermissions(result: @escaping FlutterResult) {
        let micStatus: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = "granted"
        case .denied: micStatus = "denied"
        case .restricted: micStatus = "denied"
        case .notDetermined: micStatus = "notDetermined"
        @unknown default: micStatus = "notDetermined"
        }

        let accessibilityGranted = AXIsProcessTrusted()

        result([
            "microphone": micStatus,
            "accessibility": accessibilityGranted ? "granted" : "denied"
        ])
    }

    private func requestMicrophonePermission(result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }

    private func checkAccessibility(result: @escaping FlutterResult) {
        result(AXIsProcessTrusted())
    }

    private func openAccessibilitySettings(result: @escaping FlutterResult) {
        // Try the system prompt first
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            // Also open System Settings → Privacy → Accessibility directly
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        result(trusted)
    }

    // MARK: - VAD (Voice Activity Detection)

    private var noiseFloor: Float = 0.01
    private let noiseFloorAlpha: Float = 0.995
    private let silenceThresholdMultiplier: Float = 2.0
    private var silenceTimeoutSeconds: Double = 1.5
    private var silenceStartTime: Date?
    private var silenceDetectionEnabled: Bool = true
    private var configChangeObserver: NSObjectProtocol?

    // MARK: - Audio Level Metering

    private var lastLevelEmitTime: Date = .distantPast
    private let levelEmitInterval: TimeInterval = 1.0 / 20.0  // 20 Hz max

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }

    // MARK: - Audio Recording

    private func startRecording(result: @escaping FlutterResult) {
        if isRecording {
            result(FlutterError(code: "already_recording", message: "Already recording", details: nil))
            return
        }

        let tempDir = NSTemporaryDirectory()
        let fileName = "voice_recording_\(Int(Date().timeIntervalSince1970)).wav"
        recordingURL = URL(fileURLWithPath: tempDir + fileName)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        do {
            audioFile = try AVAudioFile(forWriting: recordingURL!, settings: recordingFormat.settings)
        } catch {
            result(FlutterError(code: "file_error", message: "Cannot create audio file: \(error)", details: nil))
            return
        }

        // Reset VAD state
        noiseFloor = 0.01
        silenceStartTime = nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Write audio data
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                NSLog("[SpeechRecognizer] buffer write error: \(error)")
            }

            // VAD: compute RMS, track silence, emit level+urgency
            let rms = self.computeRMS(buffer: buffer)
            self.noiseFloor = self.noiseFloorAlpha * self.noiseFloor + (1 - self.noiseFloorAlpha) * rms
            let threshold = self.noiseFloor * self.silenceThresholdMultiplier
            let now = Date()

            // Silence bookkeeping BEFORE emitting so urgency reflects current state.
            if self.silenceDetectionEnabled {
                if rms < threshold {
                    if self.silenceStartTime == nil {
                        self.silenceStartTime = now
                    }
                } else {
                    self.silenceStartTime = nil
                }
            } else {
                self.silenceStartTime = nil
            }

            // Emit level + silence urgency at ~20 Hz for visualization.
            if now.timeIntervalSince(self.lastLevelEmitTime) >= self.levelEmitInterval {
                self.lastLevelEmitTime = now
                let normalizer = max(self.noiseFloor * 20.0, 0.001)
                let normalized = min(max(rms / normalizer, 0.0), 1.0)
                var urgency: Float = 0
                if self.silenceDetectionEnabled, let start = self.silenceStartTime {
                    let elapsed = now.timeIntervalSince(start)
                    urgency = Float(min(max(elapsed / self.silenceTimeoutSeconds, 0), 1))
                }
                DispatchQueue.main.async {
                    self.channel?.invokeMethod("onAudioLevel", arguments: [
                        "level": normalized,
                        "urgency": urgency,
                    ])
                }
            }

            // Fire autostop if silence budget elapsed.
            if self.silenceDetectionEnabled, let start = self.silenceStartTime,
               now.timeIntervalSince(start) >= self.silenceTimeoutSeconds {
                DispatchQueue.main.async {
                    self.channel?.invokeMethod("onSilenceDetected", arguments: nil)
                }
                self.silenceStartTime = nil
            }
        }

        // Observe mic disconnection
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            // Check if input is still available
            let inputNode = self.audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            if format.channelCount == 0 {
                NSLog("[SpeechRecognizer] Microphone disconnected during recording")
                self.channel?.invokeMethod("onMicDisconnected", arguments: nil)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            result(true)
        } catch {
            result(FlutterError(code: "audio_error", message: "Cannot start audio: \(error)", details: nil))
        }
    }

    private func stopRecording(result: @escaping FlutterResult) {
        guard isRecording else {
            result(FlutterError(code: "not_recording", message: "Not recording", details: nil))
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        silenceStartTime = nil

        // Remove mic disconnect observer
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }

        guard let wavURL = recordingURL else {
            result(FlutterError(code: "no_file", message: "No recording file", details: nil))
            return
        }

        // Convert WAV → M4A for faster upload (10-15x smaller)
        let m4aURL = wavURL.deletingPathExtension().appendingPathExtension("m4a")
        convertToM4A(source: wavURL, destination: m4aURL) { success in
            if success {
                try? FileManager.default.removeItem(at: wavURL)
                result(m4aURL.path)
            } else {
                // Fallback to WAV if conversion fails
                result(wavURL.path)
            }
        }
    }

    private func convertToM4A(source: URL, destination: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(false)
            return
        }
        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exportSession.status == .completed)
            }
        }
    }

    private func cancelRecording(result: @escaping FlutterResult) {
        if isRecording {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            isRecording = false
        }
        // Delete temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        result(true)
    }

    // MARK: - Realtime Streaming Recording

    private func startRealtimeRecording(result: @escaping FlutterResult) {
        if isRealtimeRecording || isRecording {
            result(FlutterError(
                code: "already_recording",
                message: isRealtimeRecording ? "Realtime recording already active" : "Batch recording active",
                details: nil
            ))
            return
        }

        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRealtimeRecording(result: result)
                    } else {
                        result(FlutterError(code: "permission_denied", message: "Microphone permission denied", details: nil))
                    }
                }
            }
            return
        default:
            result(FlutterError(code: "permission_denied", message: "Microphone permission denied", details: nil))
            return
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: 16 kHz, 16-bit signed integer (PCM16LE), mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            result(FlutterError(code: "format_error", message: "Cannot create target audio format", details: nil))
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            result(FlutterError(code: "converter_error", message: "Cannot create audio converter from \(inputFormat) to \(targetFormat)", details: nil))
            return
        }
        realtimeConverter = converter

        realtimeLock.lock()
        realtimePcmBuffer = Data()
        realtimeLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRealtimeRecording else { return }
            guard let converter = self.realtimeConverter else { return }

            // Visualization: compute RMS from the original float buffer and
            // emit at ~20 Hz. Realtime mode has no client-side silence VAD
            // (Gemini Live decides end-of-speech), so urgency is always 0.
            let rms = self.computeRMS(buffer: buffer)
            self.noiseFloor = self.noiseFloorAlpha * self.noiseFloor + (1 - self.noiseFloorAlpha) * rms
            let now = Date()
            if now.timeIntervalSince(self.lastLevelEmitTime) >= self.levelEmitInterval {
                self.lastLevelEmitTime = now
                let normalizer = max(self.noiseFloor * 20.0, 0.001)
                let normalized = min(max(rms / normalizer, 0.0), 1.0)
                DispatchQueue.main.async {
                    self.channel?.invokeMethod("onAudioLevel", arguments: [
                        "level": normalized,
                        "urgency": Float(0),
                    ])
                }
            }

            // Calculate output frame capacity based on sample rate ratio
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

            var error: NSError?
            var allConsumed = false
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if allConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let error = error {
                NSLog("[SpeechRecognizer] Realtime conversion error: \(error)")
                return
            }

            guard outputBuffer.frameLength > 0 else { return }

            // Extract raw bytes from the int16 buffer
            let byteCount = Int(outputBuffer.frameLength) * 2 // 16-bit = 2 bytes per sample
            let rawData = Data(bytes: outputBuffer.int16ChannelData![0], count: byteCount)

            self.realtimeLock.lock()
            self.realtimePcmBuffer.append(rawData)

            // Drain complete frames (each realtimeFrameBytes = 6400 bytes = 200 ms)
            while self.realtimePcmBuffer.count >= self.realtimeFrameBytes {
                let chunk = self.realtimePcmBuffer.prefix(self.realtimeFrameBytes)
                self.realtimePcmBuffer.removeFirst(self.realtimeFrameBytes)
                self.realtimeLock.unlock()

                let base64String = chunk.base64EncodedString()
                DispatchQueue.main.async {
                    self.channel?.invokeMethod("onAudioFrame", arguments: ["data": base64String])
                }

                self.realtimeLock.lock()
            }
            self.realtimeLock.unlock()
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRealtimeRecording = true
            result(true)
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            realtimeConverter = nil
            result(FlutterError(code: "audio_error", message: "Cannot start audio engine: \(error)", details: nil))
        }
    }

    private func stopRealtimeRecording(result: @escaping FlutterResult) {
        guard isRealtimeRecording else {
            result(FlutterError(code: "not_recording", message: "Realtime recording not active", details: nil))
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRealtimeRecording = false
        realtimeConverter = nil

        // Flush any remaining bytes as a final frame
        realtimeLock.lock()
        let remaining = realtimePcmBuffer
        realtimePcmBuffer = Data()
        realtimeLock.unlock()

        if !remaining.isEmpty {
            let base64String = remaining.base64EncodedString()
            channel?.invokeMethod("onAudioFrame", arguments: ["data": base64String])
        }

        result(true)
    }

    // MARK: - System Preferences

    private func openSystemPreferences(pane: String, result: @escaping FlutterResult) {
        let urls: [String]

        switch pane {
        case "microphone":
            urls = [
                // macOS Ventura+ (System Settings)
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
            ]
        case "accessibility":
            urls = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            ]
        default:
            urls = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        }

        var opened = false
        for urlString in urls {
            if let url = URL(string: urlString) {
                if NSWorkspace.shared.open(url) {
                    opened = true
                    break
                }
            }
        }

        if !opened {
            // Last resort: just open System Settings app
            if let url = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(url)
            }
        }

        result(true)
    }

    // MARK: - Text Insertion

    private func pasteText(text: String, result: @escaping FlutterResult) {
        // Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Check if there's a focused text element in the frontmost app
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            result(["inserted": false, "reason": "no_app"])
            return
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedElement: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if focusErr == .success, let element = focusedElement {
            // Check if the focused element accepts text input
            var role: AnyObject?
            AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
            let roleStr = role as? String ?? ""

            let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"]
            let isTextInput = textRoles.contains(roleStr)

            if isTextInput {
                // Simulate Cmd+V to paste
                simulatePaste()
                result(["inserted": true, "reason": "pasted"])
                return
            }
        }

        // No text input focused — text is on clipboard, user can paste manually
        result(["inserted": false, "reason": "no_text_field"])
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    private func simulateUndo(result: @escaping FlutterResult) {
        let source = CGEventSource(stateID: .hidSystemState)
        // 0x06 = virtual key code for 'z'
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x06, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x06, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
        result(true)
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(enabled: Bool, result: @escaping FlutterResult) {
        if #available(macOS 13.0, *) {
            // Use SMAppService for macOS 13+
            // For now use AppleScript approach which works universally
        }

        let script: String
        if enabled {
            script = """
                tell application "System Events"
                    make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:false}
                end tell
            """
        } else {
            script = """
                tell application "System Events"
                    delete login item "\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Flow")"
                end tell
            """
        }
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        result(true)
    }

    // MARK: - Status Bar

    private static var statusItem: NSStatusItem?
    private static var statusHelper: StatusBarHelper?

    private func setupStatusBar(result: @escaping FlutterResult) {
        if SpeechRecognizerPlugin.statusItem != nil {
            result(true)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        SpeechRecognizerPlugin.statusItem = item

        guard let button = item.button else {
            result(false)
            return
        }

        if #available(macOS 11.0, *),
           let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Flow") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "F"
        }

        let helper = StatusBarHelper(channel: channel)
        SpeechRecognizerPlugin.statusHelper = helper

        let menu = NSMenu()
        menu.delegate = helper

        // Show/Hide Flow
        let showItem = NSMenuItem(title: "Show Flow", action: #selector(StatusBarHelper.showWindow), keyEquivalent: "")
        showItem.target = helper
        menu.addItem(showItem)

        menu.addItem(.separator())

        // Language submenu
        let langMenu = NSMenu()
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        helper.langSubmenu = langMenu
        menu.addItem(langItem)

        // Translation mode submenu
        let transMenu = NSMenu()
        let transItem = NSMenuItem(title: "Translation", action: nil, keyEquivalent: "")
        transItem.submenu = transMenu
        helper.transSubmenu = transMenu
        menu.addItem(transItem)

        // Microphone submenu
        let micMenu = NSMenu()
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        helper.micSubmenu = micMenu
        menu.addItem(micItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(StatusBarHelper.openSettings), keyEquivalent: ",")
        settingsItem.target = helper
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Flow", action: #selector(StatusBarHelper.quitApp), keyEquivalent: "q")
        quitItem.target = helper
        menu.addItem(quitItem)

        item.menu = menu
        result(true)
    }

    // MARK: - Dock Visibility

    private func setDockVisibility(visible: Bool, result: @escaping FlutterResult) {
        if visible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
            // Bring our window back to front since accessory hides it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        result(true)
    }

    // MARK: - Microphone List

    private func listMicrophones(result: @escaping FlutterResult) {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices

        // System default input as reported by macOS. Used both to pin
        // the "main" mic to the top of the list AND to fall back on
        // when the user hasn't picked one yet — without this the Dart
        // side defaulted to whatever random device landed first in
        // `DiscoverySession.devices`, which is a virtual loopback on
        // machines with BlackHole / VB-Cable installed.
        let defaultId = AVCaptureDevice.default(for: .audio)?.uniqueID

        // Sort: default mic first, rest alphabetised by localizedName.
        var sorted = devices.sorted { a, b in
            a.localizedName.localizedCaseInsensitiveCompare(b.localizedName)
                == .orderedAscending
        }
        if let defaultId,
           let idx = sorted.firstIndex(where: { $0.uniqueID == defaultId }) {
            let d = sorted.remove(at: idx)
            sorted.insert(d, at: 0)
        }

        let list = sorted.map { device -> [String: String] in
            return [
                "id": device.uniqueID,
                "name": device.localizedName,
                "isDefault": device.uniqueID == defaultId ? "true" : "false",
            ]
        }
        result(list)
    }

    // MARK: - Sounds

    private func playSound(name: String, result: @escaping FlutterResult) {
        let soundName: NSSound.Name
        switch name {
        case "start":
            soundName = NSSound.Name("Tink")
        case "stop":
            soundName = NSSound.Name("Pop")
        case "done":
            soundName = NSSound.Name("Glass")
        case "error":
            soundName = NSSound.Name("Basso")
        default:
            soundName = NSSound.Name("Tink")
        }

        NSSound(named: soundName)?.play()
        result(true)
    }
}

// MARK: - Status Bar Helper

class StatusBarHelper: NSObject, NSMenuDelegate {
    weak var channel: FlutterMethodChannel?
    var micSubmenu: NSMenu?
    var langSubmenu: NSMenu?
    var transSubmenu: NSMenu?

    private let languages: [(code: String, name: String)] = [
        ("ru", "Русский"), ("en", "English"), ("uk", "Українська"),
        ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"),
        ("it", "Italiano"), ("pt", "Português"), ("pl", "Polski"),
        ("nl", "Nederlands"), ("tr", "Türkçe"), ("ar", "العربية"),
        ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
        ("hi", "हिन्दी"), ("hy", "Հայերեն"), ("ka", "ქართული"),
        ("he", "עברית"), ("sv", "Svenska"), ("", "Auto-detect"),
    ]

    private let translationModes: [(mode: String, name: String)] = [
        ("off", "Off"),
        ("auto", "Auto-translate"),
        ("voice_trigger", "Voice trigger"),
    ]

    init(channel: FlutterMethodChannel?) {
        self.channel = channel
    }

    @objc func showWindow() {
        for window in NSApp.windows where window is MainFlutterWindow {
            // Promote to .regular before bringing the window up so the
            // native menu bar is drawn on the same frame as the window.
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
    }

    @objc func hideWindow() {
        for window in NSApp.windows where window is MainFlutterWindow {
            window.orderOut(nil)
            // Back to tray-only agent — drops menu bar and Dock icon.
            NSApp.setActivationPolicy(.accessory)
            return
        }
    }

    @objc func openSettings() {
        // Show window and navigate to settings via channel
        showWindow()
        channel?.invokeMethod("navigateTo", arguments: "settings")
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func selectMicrophone(_ sender: NSMenuItem) {
        guard let micId = sender.representedObject as? String else { return }
        // Save with flutter. prefix to match SharedPreferences
        UserDefaults.standard.set(micId, forKey: "flutter.selected_mic_id")
        channel?.invokeMethod("selectMicrophone", arguments: micId)
        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = (item == sender) ? .on : .off
            }
        }
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        UserDefaults.standard.set(code, forKey: "flutter.language")
        channel?.invokeMethod("selectLanguage", arguments: code)
        if let menu = sender.menu {
            for item in menu.items { item.state = (item == sender) ? .on : .off }
        }
    }

    @objc func selectTranslationMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        UserDefaults.standard.set(mode, forKey: "flutter.translation_mode")
        channel?.invokeMethod("selectTranslationMode", arguments: mode)
        if let menu = sender.menu {
            for item in menu.items { item.state = (item == sender) ? .on : .off }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Keep the first item fixed at "Show Flow" — tapping it always
        // brings the window to the front regardless of current state.
        // The old Hide/Show toggle caused accidental hides (user opens
        // the tray menu looking for Settings, clicks the wrong item,
        // loses the window) and adds no value: Cmd-H / red traffic
        // light already cover "make the window go away".
        if let item = menu.items.first {
            item.title = "Show Flow"
            item.action = #selector(showWindow)
            item.target = self
        }

        refreshLanguageMenu()
        refreshTranslationMenu()
        refreshMicrophoneMenu()
    }

    private func refreshLanguageMenu() {
        guard let langMenu = langSubmenu else { return }
        langMenu.removeAllItems()

        let currentLang = UserDefaults.standard.string(forKey: "flutter.language") ?? "ru"

        for lang in languages {
            let item = NSMenuItem(title: lang.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = (lang.code == currentLang) ? .on : .off
            langMenu.addItem(item)
        }
    }

    private func refreshTranslationMenu() {
        guard let transMenu = transSubmenu else { return }
        transMenu.removeAllItems()

        let currentMode = UserDefaults.standard.string(forKey: "flutter.translation_mode") ?? "off"

        for mode in translationModes {
            let item = NSMenuItem(title: mode.name, action: #selector(selectTranslationMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.mode
            item.state = (mode.mode == currentMode) ? .on : .off
            transMenu.addItem(item)
        }
    }

    private func refreshMicrophoneMenu() {
        guard let micMenu = micSubmenu else { return }
        micMenu.removeAllItems()

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices

        // Match the ordering used by the Settings → Microphone chips:
        // system default pinned at the top, everyone else alphabetical.
        // Without this the tray menu is whatever random order macOS
        // hands us — BlackHole, VB-Cable and Zoom typically float to
        // the top, which confused the user testing the 1.0.2 build.
        let defaultId = AVCaptureDevice.default(for: .audio)?.uniqueID
        var sorted = devices.sorted { a, b in
            a.localizedName.localizedCaseInsensitiveCompare(b.localizedName)
                == .orderedAscending
        }
        if let defaultId,
           let idx = sorted.firstIndex(where: { $0.uniqueID == defaultId }) {
            let d = sorted.remove(at: idx)
            sorted.insert(d, at: 0)
        }

        let currentId = UserDefaults.standard.string(forKey: "flutter.selected_mic_id") ?? ""

        for device in sorted {
            let item = NSMenuItem(title: device.localizedName, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            // Checkmark logic: either the user explicitly picked this
            // one, or they haven't picked anything and this is the
            // system default (which is now guaranteed to be `first`).
            item.state = (device.uniqueID == currentId
                || (currentId.isEmpty && device.uniqueID == defaultId)) ? .on : .off
            micMenu.addItem(item)
        }

        if devices.isEmpty {
            let item = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            micMenu.addItem(item)
        }
    }
}
