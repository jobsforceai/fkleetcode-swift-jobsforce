import Cocoa

final class OverlayWindow: NSPanel {  // ← NSPanel, not NSWindow
  init(contentView: NSView) {
      // pick the main screen
          let screen = NSScreen.main ?? NSScreen.screens.first!
          let vf = screen.visibleFrame
      // target width = 80% of screen
          let targetWidth = vf.width * 0.5
          // pick an aspect ratio, e.g. 16:9, or reuse your old height/width ratio
          let aspect: CGFloat = 16.0/9.0
          let targetHeight = targetWidth / aspect
      // center the rect on screen
          let originX = vf.midX - targetWidth/2
          let originY = vf.midY - targetHeight/2
          let rect = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

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
//    if responds(to: Selector(("setSharingType:"))) {
//      setValue(NSNumber(value: 0), forKey: "sharingType") // NSWindowSharingType.none
//    }

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
