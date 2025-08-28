import SwiftUI
import AppKit

// MARK: - Window config: allow true behind-window translucency
struct WindowClearConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let v = NSView()
    DispatchQueue.main.async {
      if let w = v.window {
        w.isOpaque = false
        w.backgroundColor = .clear
        w.titlebarAppearsTransparent = true
      }
    }
    return v
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Passive effect view (never steals clicks)
final class ConditionallyPassiveEffectView: NSVisualEffectView {
    var isPassive: Bool = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        isPassive ? nil : super.hitTest(point)
    }
}

// MARK: - Vibrant glass container that HOSTS SwiftUI INSIDE the effect view
struct VibrantGlassContainer<Content: View>: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let blending: NSVisualEffectView.BlendingMode
  let state: NSVisualEffectView.State
  let cornerRadius: CGFloat
  let whiteMilkiness: CGFloat   // subtle white lift inside the effect view
  let colorScheme: ColorScheme
  let isPassive: Bool
  let content: () -> Content    // stored WITHOUT @ViewBuilder

  // Custom init where the builder attribute is valid:
  init(
    material: NSVisualEffectView.Material = .sidebar,
    blending: NSVisualEffectView.BlendingMode = .behindWindow,
    state: NSVisualEffectView.State = .active,
    cornerRadius: CGFloat = 22,
    whiteMilkiness: CGFloat = 0.18,
    colorScheme: ColorScheme,
    isPassive: Bool,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.material = material
    self.blending = blending
    self.state = state
    self.cornerRadius = cornerRadius
    self.whiteMilkiness = whiteMilkiness
    self.colorScheme = colorScheme
    self.isPassive = isPassive
    self.content = content
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var hosting: NSHostingView<AnyView>?
    var milkView: NSView?
  }

  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = ConditionallyPassiveEffectView()
    v.isPassive = isPassive
    v.material = material
    v.blendingMode = blending
    v.state = state
    v.appearance = NSAppearance(named: colorScheme == .light ? .vibrantLight : .vibrantDark) // bright glass (dark text)
    v.wantsLayer = true
    v.layer?.cornerRadius = cornerRadius
    v.layer?.masksToBounds = true

    // Inner "milk" layer keeps the frosted, white look
    if whiteMilkiness > 0 {
      let milk = NSView()
      milk.wantsLayer = true
      let baseMilkColor = colorScheme == .light ? NSColor.white : NSColor.black
      milk.layer?.backgroundColor = baseMilkColor.withAlphaComponent(whiteMilkiness).cgColor
      milk.translatesAutoresizingMaskIntoConstraints = false
      v.addSubview(milk, positioned: .below, relativeTo: nil)
      NSLayoutConstraint.activate([
        milk.leadingAnchor.constraint(equalTo: v.leadingAnchor),
        milk.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        milk.topAnchor.constraint(equalTo: v.topAnchor),
        milk.bottomAnchor.constraint(equalTo: v.bottomAnchor),
      ])
      context.coordinator.milkView = milk
    }

    // Host SwiftUI content INSIDE the effect to gain vibrancy/legibility
    let hosted = AnyView(
      content()
        .environment(\.colorScheme, colorScheme) // dark/black text on bright glass
    )
    let hosting = NSHostingView(rootView: hosted)
    hosting.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: v.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: v.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: v.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: v.bottomAnchor),
    ])
    context.coordinator.hosting = hosting
    return v
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    if let v = view as? ConditionallyPassiveEffectView {
        v.isPassive = isPassive
    }
    view.material = material
    view.blendingMode = blending
    view.state = state
    view.appearance = NSAppearance(named: colorScheme == .light ? .vibrantLight : .vibrantDark)

    if let milk = context.coordinator.milkView {
        let baseMilkColor = colorScheme == .light ? NSColor.white : NSColor.black
        milk.layer?.backgroundColor = baseMilkColor.withAlphaComponent(whiteMilkiness).cgColor
    }

    if let hosting = context.coordinator.hosting {
      hosting.rootView = AnyView(
        content()
          .environment(\.colorScheme, colorScheme)
      )
    }
  }
}

// MARK: - One-stop "Liquid Glass" modifier (Apple-like)
struct LiquidGlass: ViewModifier {
  var radius: CGFloat = 22
  var material: NSVisualEffectView.Material = .sidebar
  var whiteMilkiness: CGFloat = 0.18
  var blending: NSVisualEffectView.BlendingMode = .behindWindow
  var dropShadow: CGFloat = 16
  var colorScheme: ColorScheme
  var isPassive: Bool

  func body(content: Content) -> some View {
    VibrantGlassContainer(
      material: material,
      blending: blending,
      state: .active,
      cornerRadius: radius,
      whiteMilkiness: whiteMilkiness,
      colorScheme: colorScheme,
      isPassive: isPassive
    ) { content }
    .overlay( // inner specular highlight
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.06), .clear],
            startPoint: .top, endPoint: .bottom
          ),
          lineWidth: 0.7
        )
        .blendMode(.screen)
    )
    .shadow(color: .black.opacity(0.10), radius: dropShadow, x: 0, y: 10)
    .shadow(color: .white.opacity(0.07), radius: 4, x: 0, y: 0)
  }
}

// Keep your original API name/signature
extension View {
  func liquidGlass(
    radius: CGFloat = 22,
    material: NSVisualEffectView.Material = .sidebar,
    tint: Color = .white,          // kept for compatibility
    tintOpacity: Double = 0.18,    // mapped to whiteMilkiness
    saturation: Double = 1.2,      // unused (vibrancy handles it)
    dropShadow: Double = 16,
    blending: NSVisualEffectView.BlendingMode = .behindWindow,
    colorScheme: ColorScheme,
    isPassive: Bool
  ) -> some View {
    modifier(
      LiquidGlass(
        radius: radius,
        material: material,
        whiteMilkiness: CGFloat(tintOpacity),
        blending: blending,
        dropShadow: CGFloat(dropShadow),
        colorScheme: colorScheme,
        isPassive: isPassive
      )
    )
  }
}
