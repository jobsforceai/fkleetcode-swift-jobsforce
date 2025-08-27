import SwiftUI
import AppKit

// Native macOS blur
struct BlurView: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .hudWindow // very glassy
  var blending: NSVisualEffectView.BlendingMode = .behindWindow
  var state: NSVisualEffectView.State = .active

  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = material
    v.blendingMode = blending
    v.state = state
    return v
  }
  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
    view.blendingMode = blending
    view.state = state
  }
}

// One-stop "liquid glass" styling
struct LiquidGlass: ViewModifier {
  var radius: CGFloat = 22
  var material: NSVisualEffectView.Material = .hudWindow
  var tint: Color = .white
  var tintOpacity: Double = 0.08  // how milky the glass is (lower = clearer)
  var saturation: Double = 1.7    // punchy colors behind the blur
  var dropShadow: Double = 28

  func body(content: Content) -> some View {
    content
      .background(
        BlurView(material: material)
          .saturation(saturation)
          .background(tint.opacity(tintOpacity))
          .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      )
      // outer glass edge
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [Color.white.opacity(0.05), Color.white.opacity(0.06)],
              startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      )
      // inner highlight for that liquid look
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [Color.white.opacity(0.05), Color.clear],
              startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 0.7
          )
          .blendMode(.overlay)
      )
      // soft drop shadow + a faint top glow
      .shadow(color: .black.opacity(0.22), radius: dropShadow, x: 0, y: 18)
      .shadow(color: .white.opacity(0.10), radius: 6, x: 0, y: 0)
  }
}

extension View {
  func liquidGlass(
    radius: CGFloat = 22,
    material: NSVisualEffectView.Material = .hudWindow,
    tint: Color = .white,
    tintOpacity: Double = 0.08,
    saturation: Double = 1.7,
    dropShadow: Double = 28
  ) -> some View {
    modifier(LiquidGlass(radius: radius, material: material, tint: tint,
                         tintOpacity: tintOpacity, saturation: saturation,
                         dropShadow: dropShadow))
  }
}
