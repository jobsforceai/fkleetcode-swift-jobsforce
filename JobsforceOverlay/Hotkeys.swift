import Foundation
import AppKit
import HotKey

final class Hotkeys {
  private var toggle: HotKey?
  private var left: HotKey?
  private var right: HotKey?
  private var up: HotKey?
  private var down: HotKey?
    
    // Tab switching hotkeys
      private var focusChat: HotKey?
      private var focusAI: HotKey?
    
    private var leftTimer: Timer?
    private var rightTimer: Timer?
    private var upTimer: Timer?
    private var downTimer: Timer?
    private var shot: HotKey?
    
    
    private func currentStep() -> CGFloat {
      NSEvent.modifierFlags.contains(.shift) ? 120 : 24   // tweak as you like
    }
    private func startRepeat(_ slot: inout Timer?, tick: @escaping () -> Void) {
      slot?.invalidate()
      tick() // move once immediately
      slot = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in tick() } // ~50 Hz
      RunLoop.main.add(slot!, forMode: .common)
    }

    private func stopRepeat(_ slot: inout Timer?) {
      slot?.invalidate()
      slot = nil
    }


    init(
        onToggle: @escaping () -> Void,
         onNudge: @escaping (_ dx: CGFloat, _ dy: CGFloat) -> Void,
         onShot:  @escaping () -> Void,
    onFocusChat: @escaping () -> Void,
        onFocusAI:   @escaping () -> Void
    )
    {
        // ⌘⌥V → toggle overlay
            toggle = HotKey(key: .v, modifiers: [.command, .option])
            toggle?.keyDownHandler = onToggle

        // ⌘⌥⌃ + arrows → nudge (with Shift for bigger step)
            left  = HotKey(key: .leftArrow,  modifiers: [.command, .option, .control])
            right = HotKey(key: .rightArrow, modifiers: [.command, .option, .control])
            up    = HotKey(key: .upArrow,    modifiers: [.command, .option, .control])
            down  = HotKey(key: .downArrow,  modifiers: [.command, .option, .control])

      left?.keyDownHandler  = { [weak self] in self?.startRepeat(&self!.leftTimer)  { onNudge(-self!.currentStep(), 0) } }
      right?.keyDownHandler = { [weak self] in self?.startRepeat(&self!.rightTimer) { onNudge( self!.currentStep(), 0) } }
      up?.keyDownHandler    = { [weak self] in self?.startRepeat(&self!.upTimer)    { onNudge(0,  self!.currentStep()) } }
      down?.keyDownHandler  = { [weak self] in self?.startRepeat(&self!.downTimer)  { onNudge(0, -self!.currentStep()) } }

      left?.keyUpHandler  = { [weak self] in self?.stopRepeat(&self!.leftTimer) }
      right?.keyUpHandler = { [weak self] in self?.stopRepeat(&self!.rightTimer) }
      up?.keyUpHandler    = { [weak self] in self?.stopRepeat(&self!.upTimer) }
      down?.keyUpHandler  = { [weak self] in self?.stopRepeat(&self!.downTimer) }
        
        // ⌘⌥A → capture full screen silently
        shot = HotKey(key: .a, modifiers: [.command, .option])
        shot?.keyDownHandler = onShot
        
        // ⌘1 → focus Chat
            focusChat = HotKey(key: .one, modifiers: [.command])
            focusChat?.keyDownHandler = onFocusChat

            // ⌘2 → focus AI Chat
            focusAI = HotKey(key: .two, modifiers: [.command])
            focusAI?.keyDownHandler = onFocusAI

  }
}
