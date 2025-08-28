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
  @State private var colorScheme: ColorScheme = .light
  @State private var isChatLocked = true
  @State private var isAILocked = true

  var body: some View {
    ZStack {
      Color.clear
        .background(WindowClearConfigurator()) // enable behind-window blur

      VStack(spacing: 0) {
        header
        Divider().opacity(0.18)
        activePanel
        footerHints
      }
      .liquidGlass(
        radius: 22,
        material: .popover,     // try .sidebar / .headerView too
        tintOpacity: 0.20,
        dropShadow: 18,
        blending: .behindWindow,
        colorScheme: colorScheme,
        isPassive: !isChatLocked && !isAILocked
      )
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
    .onReceive(NotificationCenter.default.publisher(for: .jfToggleTheme)) { _ in
        withAnimation(.easeInOut(duration: 0.18)) {
            colorScheme = colorScheme == .light ? .dark : .light
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
            .font(.headline)          // dark by default on vibrantLight
            .foregroundStyle(.primary)
          Text("Private Assist")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 12)

      // Center: segmented switch
      SegmentedTwoButton(selection: $focus, left: .chat, right: .ai)

      Spacer(minLength: 12)

      // Right: Hide button with hint
      Button {
        NSApp.keyWindow?.orderOut(nil)
      } label: {
        HStack(spacing: 8) {
          Text("Hide")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          KeyBadge("⌘⌥V")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.04), in: Capsule())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("v", modifiers: [.command, .option])
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: Single Active Panel

  private var activePanel: some View {
    ZStack {
      if focus == .chat {
        ChatPanelView(title: "Chat", badge: "⌘1", model: chatModel, isLocked: $isChatLocked, unlockKey: "1234")
          .transition(.move(edge: .leading).combined(with: .opacity))
      } else {
        ChatPanelView(title: "AI Chat", badge: "⌘2", model: aiModel, isLocked: $isAILocked, unlockKey: "5678")
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.18), value: focus)
  }

  // MARK: Footer Hints

  private var footerHints: some View {
    HStack(spacing: 12) {
      HintPill(label: "Screenshot", shortcut: "⌘⌥A")
      HintPill(label: "Toggle Theme", shortcut: "⌘⌥T")
      Spacer()
    }
    .padding(10)
    .background(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.03))
  }
}

// MARK: - Components

private struct LockScreenView: View {
    let title: String
    let onUnlock: (String) -> Bool // Returns true if unlock is successful
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Please enter your API key to unlock.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 280)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                if !onUnlock(apiKey) {
                    errorMessage = "Invalid API Key. Please try again."
                    apiKey = ""
                }
            } label: {
                Text("Unlock") 
                    .font(.headline)
                    .foregroundStyle(isLight ? .white : .black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(isLight ? Color.black.opacity(0.9) : Color.white.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(apiKey.isEmpty)
            .opacity(apiKey.isEmpty ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLight ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
    }
}

private struct KeyBadge: View {
  var text: String
  init(_ text: String) { self.text = text }
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let isLight = colorScheme == .light
    Text(text)
      .font(.system(size: 11, weight: .semibold, design: .monospaced))
      .foregroundStyle(isLight ? .black : .white)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        (isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.25)),
        in: RoundedRectangle(cornerRadius: 6)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(
            (isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)),
            lineWidth: 1
          )
      )
  }
}

private struct HintPill: View {
  let label: String
  let shortcut: String
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let isLight = colorScheme == .light
    HStack(spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.primary)
      KeyBadge(shortcut)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06), in: Capsule())
  }
}

private struct ChatPanelView: View {
  let title: String
  let badge: String
  @ObservedObject var model: ChatColumnModel
  @Binding var isLocked: Bool
  let unlockKey: String
  @State private var draft: String = ""
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    if isLocked {
        LockScreenView(title: "\(title) Locked") { key in
            if key == unlockKey {
                withAnimation {
                    isLocked = false
                }
                return true
            }
            return false
        }
    } else {
        chatContent
    }
  }

  private var chatContent: some View {
    let isLight = colorScheme == .light
    return VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
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
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
                .background(
                  RoundedRectangle(cornerRadius: 10)
                    .fill(
                      item.isAI
                        ? (isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                        : (isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                    )
                )
              Spacer(minLength: 0)
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }

      chatInputArea
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var chatInputArea: some View {
    let isLight = colorScheme == .light
    let textFieldBackground = (isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
    let textFieldOverlay = RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.1), lineWidth: 1)

    return HStack(spacing: 10) {
      TextField("Type a message…", text: $draft, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...4)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(textFieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(textFieldOverlay)
        .foregroundStyle(.primary)

      Button {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.items.append(.init(text: trimmed, isAI: false))
        draft = ""
      } label: {
          Image(systemName: "paperplane.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(isLight ? .white : .black)
              .padding(10)
              .background(isLight ? Color.black.opacity(0.9) : Color.white.opacity(0.9), in: Circle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.return, modifiers: [])
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
    }
    .padding(12)
    .background(isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.03))
  }
}

// MARK: - Segmented control

private struct SegmentedTwoButton: View {
  @Binding var selection: FocusMode
  let left: FocusMode
  let right: FocusMode
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let isLight = colorScheme == .light
    ZStack {
      RoundedRectangle(cornerRadius: 11)
        .fill(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.04))
      RoundedRectangle(cornerRadius: 11)
        .strokeBorder(isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.08), lineWidth: 1)

      HStack(spacing: 0) {
        segHalf(for: left, isSelected: selection == left)
        segHalf(for: right, isSelected: selection == right)
      }
    }
    .frame(width: 260, height: 34)
    .keyboardShortcut("1", modifiers: [.command])
    .keyboardShortcut("2", modifiers: [.command])
  }

  private func segHalf(for mode: FocusMode, isSelected: Bool) -> some View {
    let isLight = colorScheme == .light
    return Button {
      withAnimation(.easeInOut(duration: 0.16)) { selection = mode }
    } label: {
      ZStack {
        if isSelected {
          RoundedRectangle(cornerRadius: 9)
            .fill(isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.10))
            .padding(2)
            .transition(.opacity)
        }
        HStack(spacing: 8) {
          Text(mode.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          KeyBadge(mode == .chat ? "⌘1" : "⌘2")
            .opacity(0.95)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
  }
}
