import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // Always surface the main window — even when `flag` reports
    // visible windows, the MainFlutterWindow is often orderOut-ed
    // after windowShouldClose but still counted as "visible" by
    // AppKit's bookkeeping. The old `if !flag` guard meant a Dock
    // click after closing + re-enabling Dock visibility did nothing.
    for window in NSApp.windows where window is MainFlutterWindow {
      if !window.isVisible {
        // Promote back to .regular so the window and menu bar both
        // come back in sync — if the user disabled Show in Dock at
        // some point we want that click to restore everything.
        if NSApp.activationPolicy() != .regular {
          NSApp.setActivationPolicy(.regular)
        }
      }
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      break
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
