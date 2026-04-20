import Cocoa
import FlutterMacOS

class SuggestionsPopupPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var popupWindow: NSWindow?
    private var suggestions: [[String: String]] = []
    private var currentIndex = 0

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.voiceassistant/suggestions",
            binaryMessenger: registrar.messenger
        )
        let instance = SuggestionsPopupPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            let args = call.arguments as? [String: Any]
            let items = args?["suggestions"] as? [[String: String]] ?? []
            showPopup(items: items)
            result(true)
        case "hide":
            hidePopup()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Popup Window

    private func showPopup(items: [[String: String]]) {
        if items.isEmpty { return }
        suggestions = items
        currentIndex = 0

        hidePopup()
        createPopup()
        updateContent()
    }

    private func hidePopup() {
        if let w = popupWindow {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
            })
        }
        popupWindow = nil
    }

    private func createPopup() {
        let w: CGFloat = 320
        let h: CGFloat = 140

        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x = sf.origin.x + (sf.width - w) / 2
        let y = sf.origin.y + sf.height - h - 55 // Below Flow Bar

        let window = EditablePanel(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 0.97).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        // Title row
        let icon = NSTextField(frame: NSRect(x: 14, y: h - 28, width: 18, height: 18))
        icon.isEditable = false
        icon.isBordered = false
        icon.drawsBackground = false
        icon.stringValue = "✨"
        icon.font = NSFont.systemFont(ofSize: 12)
        container.addSubview(icon)

        let title = NSTextField(frame: NSRect(x: 34, y: h - 28, width: 200, height: 18))
        title.isEditable = false
        title.isBordered = false
        title.drawsBackground = false
        title.stringValue = "Add to Dictionary?"
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white
        container.addSubview(title)

        // Counter
        let counter = NSTextField(frame: NSRect(x: w - 60, y: h - 28, width: 46, height: 18))
        counter.isEditable = false
        counter.isBordered = false
        counter.drawsBackground = false
        counter.alignment = .right
        counter.font = NSFont.systemFont(ofSize: 10)
        counter.textColor = NSColor.white.withAlphaComponent(0.3)
        counter.tag = 100
        container.addSubview(counter)

        // Word field (editable)
        let wordField = NSTextField(frame: NSRect(x: 14, y: h - 62, width: w - 28, height: 26))
        wordField.isEditable = true
        wordField.isBordered = false
        wordField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        wordField.textColor = .white
        wordField.backgroundColor = NSColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 1.0)
        wordField.wantsLayer = true
        wordField.layer?.cornerRadius = 6
        wordField.focusRingType = .none
        wordField.tag = 200
        container.addSubview(wordField)

        // Reason
        let reason = NSTextField(frame: NSRect(x: 14, y: h - 82, width: w - 28, height: 14))
        reason.isEditable = false
        reason.isBordered = false
        reason.drawsBackground = false
        reason.font = NSFont.systemFont(ofSize: 10)
        reason.textColor = NSColor.white.withAlphaComponent(0.35)
        reason.tag = 300
        container.addSubview(reason)

        // Buttons
        let btnW: CGFloat = (w - 14 * 3) / 2
        let btnY: CGFloat = 12

        let skipBtn = NSButton(frame: NSRect(x: 14, y: btnY, width: btnW, height: 30))
        skipBtn.title = "Skip"
        skipBtn.bezelStyle = .rounded
        skipBtn.isBordered = false
        skipBtn.wantsLayer = true
        skipBtn.layer?.backgroundColor = NSColor(red: 0.15, green: 0.17, blue: 0.23, alpha: 1.0).cgColor
        skipBtn.layer?.cornerRadius = 8
        skipBtn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        skipBtn.font = NSFont.systemFont(ofSize: 12)
        skipBtn.target = self
        skipBtn.action = #selector(skipTapped)
        container.addSubview(skipBtn)

        let addBtn = NSButton(frame: NSRect(x: 14 * 2 + btnW, y: btnY, width: btnW, height: 30))
        addBtn.title = "Add"
        addBtn.bezelStyle = .rounded
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.backgroundColor = NSColor(red: 0.91, green: 0.27, blue: 0.37, alpha: 1.0).cgColor
        addBtn.layer?.cornerRadius = 8
        addBtn.contentTintColor = .white
        addBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addBtn.target = self
        addBtn.action = #selector(addTapped)
        container.addSubview(addBtn)

        window.contentView = container
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1
        }

        popupWindow = window

        // Focus the word field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let wordField = container.viewWithTag(200) as? NSTextField {
                window.makeFirstResponder(wordField)
                // Select all text for easy editing
                wordField.currentEditor()?.selectAll(nil)
            }
        }
    }

    private func updateContent() {
        guard currentIndex < suggestions.count else {
            hidePopup()
            return
        }

        let s = suggestions[currentIndex]
        let word = s["word"] ?? ""
        let replacement = s["replacement"] ?? ""
        let reasonText = s["reason"] ?? ""

        guard let container = popupWindow?.contentView else { return }

        // Counter
        if let counter = container.viewWithTag(100) as? NSTextField {
            counter.stringValue = "\(currentIndex + 1)/\(suggestions.count)"
        }

        // Word field — show replacement if available, otherwise word
        if let wordField = container.viewWithTag(200) as? NSTextField {
            wordField.stringValue = replacement.isEmpty ? word : replacement
        }

        // Reason
        if let reason = container.viewWithTag(300) as? NSTextField {
            let display = replacement.isEmpty ? reasonText : "\(word) → \(replacement.isEmpty ? word : replacement). \(reasonText)"
            reason.stringValue = display
        }
    }

    @objc private func skipTapped() {
        currentIndex += 1
        if currentIndex < suggestions.count {
            updateContent()
        } else {
            hidePopup()
        }
    }

    @objc private func addTapped() {
        // Get edited word from field
        guard let container = popupWindow?.contentView,
              let wordField = container.viewWithTag(200) as? NSTextField else { return }

        let editedWord = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = suggestions[currentIndex]["word"] ?? ""

        if !editedWord.isEmpty {
            channel?.invokeMethod("onWordAdded", arguments: [
                "word": original,
                "replacement": editedWord == original ? "" : editedWord,
            ])
        }

        currentIndex += 1
        if currentIndex < suggestions.count {
            updateContent()
        } else {
            hidePopup()
        }
    }
}

// Borderless window that can become key (for text editing)
class EditablePanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
