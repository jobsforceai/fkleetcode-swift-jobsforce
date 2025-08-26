import Cocoa

final class OverlayWindow: NSPanel {  // ← NSPanel, not NSWindow
  init(contentView: NSView) {
    let rect = NSRect(x: 240, y: 200, width: 380, height: 520)

    super.init(
      contentRect: rect,
      styleMask: [.nonactivatingPanel, .borderless],  // ← non-activating + borderless
      backing: .buffered,
      defer: false
    )

    // Floating panel behavior
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    worksWhenModal = true
    hidesOnDeactivate = false

    // Visuals
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    ignoresMouseEvents = false
    isMovableByWindowBackground = true

    // Space/fullscreen behavior
      collectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
      ]

    // Float above app content (you can bump to .popUpMenu if needed)
    level = .statusBar

    // Hide from screen share / modern capture (KVC fallback)
    if responds(to: Selector(("setSharingType:"))) {
      setValue(NSNumber(value: 0), forKey: "sharingType") // NSWindowSharingType.none
    }

    self.contentView = contentView
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func showFront() {
    // Nudge into the active Space and raise
makeKeyAndOrderFront(nil)
orderFrontRegardless()
NSApp.activate(ignoringOtherApps: true)
  }
}
