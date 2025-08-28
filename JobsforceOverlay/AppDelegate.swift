import Cocoa
import SwiftUI
import Foundation
import ScreenCaptureKit



final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: OverlayWindow!
  private var hotkeys: Hotkeys?
    private var oneShot: SingleFrameCapture?
    
    private let transcriber = TranscriptionManager()


  func applicationDidFinishLaunching(_ notification: Notification) {
    let hosting = NSHostingView(rootView: ChatView())
    window = OverlayWindow(contentView: hosting)
    window.makeKeyAndOrderFront(nil)
    window.showFront()

      hotkeys = Hotkeys(
        onToggle: { [weak self] in self?.toggleOverlay() },
        onNudge:  { [weak self] dx, dy in self?.nudge(dx: dx, dy: dy) },
        onShot:   { [weak self] in self?.captureFullScreen() },
        onFocusChat: {
            NotificationCenter.default.post(name: .jfSetFocus, object: "chat")
          },
          onFocusAI: {
            NotificationCenter.default.post(name: .jfSetFocus, object: "ai")
          }
      )
      
      transcriber.startAll()  

  }

  private func toggleOverlay() {
    DispatchQueue.main.async { [weak self] in
      guard let win = self?.window else { return }
      if win.isVisible { win.orderOut(nil) } else { win.showFront() }
    }
  }

  private func nudge(dx: CGFloat, dy: CGFloat) {
    DispatchQueue.main.async { [weak self] in
      guard let win = self?.window else { return }
      var f = win.frame

      f.origin.x += dx
      f.origin.y += dy

      // Clamp to the current screen’s visible frame
      let screen = win.screen ?? NSScreen.main
      let vf = screen?.visibleFrame ?? f

      f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.size.width)
      f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.size.height)

      win.setFrame(f, display: true, animate: false)
    }
  }
    private func captureFullScreen() {
      // run on main to manipulate the window safely
        // tiny delay to let compositor settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
          Task { [weak self] in
            guard let self, let win = self.window else { return }
            do {
              // Pick the main display
              let content = try await SCShareableContent.current
              let mainID = CGMainDisplayID()
              let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first

              guard let display else {
                if win.isVisible == false { win.showFront() }
                NotificationCenter.default.post(name: .jfShotReady, object: nil)
                return
              }

              let cap = SingleFrameCapture()
              self.oneShot = cap
              cap.captureFirstFrame(from: display) { url in
                // restore overlay
                if win.isVisible == false { win.showFront() }
                NotificationCenter.default.post(name: .jfShotReady, object: url as Any)
                self.oneShot = nil
              }
            } catch {
              if win.isVisible == false { win.showFront() }
              NotificationCenter.default.post(name: .jfShotReady, object: nil)
            }
          }
        }

    }

}

extension Notification.Name {
  static let jfShotReady = Notification.Name("JFShotReady")
    static let jfSetFocus  = Notification.Name("JFSetFocus")
    static let jfTranscript  = Notification.Name("JFTranscript")
}
