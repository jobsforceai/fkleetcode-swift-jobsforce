import SwiftUI
import AppKit

// MARK: - Models

struct ChatBubble: Identifiable {
  let id = UUID()
  let text: String
  let isAI: Bool
}

final class ChatColumnModel: ObservableObject {
  @Published var items: [ChatBubble] = []
}

enum FocusMode: String, CaseIterable { case chat = "Chat", ai = "AI Chat" }

// MARK: - Main View

struct ChatView: View {
  @StateObject private var chatModel = ChatColumnModel()
  @StateObject private var aiModel   = ChatColumnModel()
  @State private var focus: FocusMode = .chat

  var body: some View {
    ZStack {
        Color.clear
            .liquidGlass(
              radius: 22,
              material: .popover, // ← clearest/least blur
              tint: .white,
              tintOpacity: 0.12,               // ← almost no milk
              saturation: 1.6,                   // keep colors punchy but not neon
              dropShadow: 18
            )

          VStack(spacing: 0) {
            header
            Divider().opacity(0.18)   // lighter divider on clear glass
            activePanel
            footerHints
          }
    }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .frame(minWidth: 720, minHeight: 420)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.clear)
    .onAppear {
      if chatModel.items.isEmpty {
        chatModel.items.append(.init(text: "Connected. Waiting for your first screenshot…", isAI: true))
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .jfShotReady)) { note in
      if let url = note.object as? URL {
        chatModel.items.append(.init(text: "Screenshot: \(url.lastPathComponent)", isAI: false))
      } else {
        chatModel.items.append(.init(text: "Screenshot failed (permission?)", isAI: true))
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .jfSetFocus)) { note in
      if let which = note.object as? String {
        withAnimation(.easeInOut(duration: 0.18)) {
          focus = (which == "ai") ? .ai : .chat
        }
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      // Left: logo + brand
      HStack(spacing: 10) {
        Image("logo-blacktext")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 6))

        VStack(alignment: .leading, spacing: 1) {
          Text("Jobsforce")
            .font(.headline)
          Text("Private Assist")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 12)

      // Center: sleek segmented switch with visible (but subtle) key hints
      SegmentedTwoButton(selection: $focus, left: .chat, right: .ai)

      Spacer(minLength: 12)

      // Right: Hide button with hint
      Button {
        NSApp.keyWindow?.orderOut(nil)
      } label: {
        HStack(spacing: 8) {
          Text("Hide")
            .font(.subheadline.weight(.semibold))
          KeyBadge("⌘⌥V")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.55), in: Capsule())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("v", modifiers: [.command, .option]) // local shortcut mirrors your global
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: Single Active Panel

  private var activePanel: some View {
    ZStack {
      if focus == .chat {
        ChatPanelView(title: "Chat", badge: "⌘1", model: chatModel)
          .transition(.move(edge: .leading).combined(with: .opacity))
      } else {
        ChatPanelView(title: "AI Chat", badge: "⌘2", model: aiModel)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.18), value: focus)
  }

  // MARK: Footer Hints

  private var footerHints: some View {
    HStack(spacing: 12) {
      HintPill(label: "Screenshot", shortcut: "⌘⌥A")
      Spacer()
    }
    .padding(10)
    .background(.thinMaterial.opacity(0.24))
//    .clipShape(Rectangle())
  }
}

// MARK: - Components

/// Crisp, non-merging key badge (good contrast + spacing)
private struct KeyBadge: View {
  var text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold, design: .monospaced))
      .foregroundStyle(.primary.opacity(0.8))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(.bar.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      )
  }
}

/// Subtle hint pill (label + badge)
private struct HintPill: View {
  let label: String
  let shortcut: String
  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption).foregroundStyle(.secondary)
      KeyBadge(shortcut)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.5), in: Capsule())
  }
}

/// Single chat panel; title shows its own key hint (does not toggle tabs)
private struct ChatPanelView: View {
  let title: String
  let badge: String
  @ObservedObject var model: ChatColumnModel
  @State private var draft: String = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        KeyBadge(badge)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(model.items) { item in
            HStack(alignment: .top, spacing: 8) {
              Text(item.isAI ? "AI" : "You")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

              Text(item.text)
                .textSelection(.enabled)
                .padding(10)
                .background(
                  RoundedRectangle(cornerRadius: 10)
                    .fill(item.isAI ? Color.white.opacity(0.10)
                                    : Color.white.opacity(0.06))
                  )
              Spacer(minLength: 0)
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }

      HStack(spacing: 8) {
        TextField("Type a message…", text: $draft, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .background(.thinMaterial.opacity(0.22))
        Button("Send") {
          let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          model.items.append(.init(text: trimmed, isAI: false))
          draft = ""
        }
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(12)
      .background(.thinMaterial.opacity(0.3))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Sleek two-button segmented control with FULL-AREA hit targets
private struct SegmentedTwoButton: View {
  @Binding var selection: FocusMode
  let left: FocusMode
  let right: FocusMode

  var body: some View {
    ZStack {
      // Track
      RoundedRectangle(cornerRadius: 11)
        .fill(Color.primary.opacity(0.05))
      RoundedRectangle(cornerRadius: 11)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)

      HStack(spacing: 0) {
        segHalf(for: left, isSelected: selection == left)
        segHalf(for: right, isSelected: selection == right)
      }
    }
    .frame(width: 260, height: 34)
    // Keyboard shortcuts for switching (local to app, not global)
    .keyboardShortcut("1", modifiers: [.command]) // ⌘1
    .keyboardShortcut("2", modifiers: [.command]) // ⌘2
  }

  private func segHalf(for mode: FocusMode, isSelected: Bool) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.16)) { selection = mode }
    } label: {
      ZStack {
        if isSelected {
          RoundedRectangle(cornerRadius: 9)
            .fill(Color.accentColor.opacity(0.2))
            .padding(2)
            .transition(.opacity)
        }
        HStack(spacing: 8) {
          Text(mode.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          KeyBadge(mode == .chat ? "⌘1" : "⌘2")
            .opacity(0.9)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, maxHeight: .infinity) // FULL HALF is clickable
    .contentShape(Rectangle())                         // make hit-test cover the half
  }
}
