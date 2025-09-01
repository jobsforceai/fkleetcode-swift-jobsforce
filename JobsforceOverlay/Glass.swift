import SwiftUI
import AppKit

// Native macOS blur
struct BlurView: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .popover   // clearer than .hudWindow
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

// Thin, high-quality glass edge
private extension Shape {
  func glassEdge(cornerRadius: CGFloat) -> some View {
    self
      .stroke(
        LinearGradient(
          colors: [
            .white.opacity(0.55), // top-left edge
            .white.opacity(0.55),
            .white.opacity(0.55),
            .white.opacity(0.55) // bottom-right
          ],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        lineWidth: 1
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

// One-stop “liquid glass” styling
struct LiquidGlass: ViewModifier {
    var radius: CGFloat = 22 // rounding for every plate/corner
    var material: NSVisualEffectView.Material = .toolTip
    var tint: Color = .white
    var tintOpacity: Double = 0.8  // how milky (0 = clear)
    var saturation: Double = 1.6  // how vivid the blurred content looks
    var dropShadow: Double = 18  // softness/lift of the card
    
    func body(content: Content) -> some View {
      content
        .background(
          ZStack {
//            // Frosted blur
            BlurView(material: material)
              .opacity(0.7)
              .blur(radius: 30, opaque: true)
//
//            // Milky wash tint
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .fill(tint.opacity(tintOpacity))
          }
          // Clip the entire background to rounded shape
          .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
          // Drop shadows for depth
          .shadow(color: .black.opacity(0.18), radius: dropShadow, x: 0, y: dropShadow * 0.45)
          .shadow(color: .white.opacity(0.10), radius: 6, x: 0, y: 0)
        )
    }

//  func body(content: Content) -> some View {
//    content
//      .background(
//        // Base frosted  plate
//        RoundedRectangle(cornerRadius: radius, style: .continuous)
//          .fill(.clear)
//        // blurring
//            .background(BlurView(material: material).opacity(0.5).blur(radius: 30, opaque: true))
//          .saturation(saturation)
//          // milky wash over the blur
//          .overlay(RoundedRectangle(cornerRadius: radius).fill(tint.opacity(tintOpacity)))
//          // glossy background color
//          .overlay(
//            RoundedRectangle(cornerRadius: radius, style: .continuous)
//                .fill(.black.opacity(0.05))
//                .blendMode(.plusLighter)
//                .blur(radius: 30, opaque: false)
//          )
//          // crisp edge highlight
//          .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).glassEdge(cornerRadius: radius))
//          // soft outer shadow to lift the plate
//          .shadow(color: .black.opacity(0.18), radius: dropShadow, x: 0, y: dropShadow * 0.45)
//          // faint top glow for depth
//          .shadow(color: .white.opacity(0.10), radius: 6, x: 0, y: 0)
//      )
//  }
}

extension View {
  func liquidGlass(
    radius: CGFloat = 22,
    material: NSVisualEffectView.Material = .popover,
    tint: Color = .white,
    tintOpacity: Double = 0.12,
    saturation: Double = 1.6,
    dropShadow: Double = 18
  ) -> some View {
    modifier(LiquidGlass(
      radius: radius,
      material: material,
      tint: tint,
      tintOpacity: tintOpacity,
      saturation: saturation,
      dropShadow: dropShadow
    ))
  }
}
