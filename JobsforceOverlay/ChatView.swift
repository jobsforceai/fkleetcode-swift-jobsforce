import SwiftUI
import AppKit
import SocketIO

// MARK: - Main View

struct ChatView: View {
    @StateObject private var chatModel = ChatColumnModel()
    @StateObject private var aiModel   = ChatColumnModel()
    @State private var focus: FocusMode = .chat
    
    @StateObject private var gateway = ChatGatewaySocket(env: .local)

    // 🔒 Locking + theme state (added)
    @State private var colorScheme: ColorScheme = .light
    @State private var isChatLocked = true
    @State private var isAILocked  = true
    @State private var showShortcuts = false

  // 🎙️ Transcription
  @StateObject private var transcriber = TranscriptionDirector()

  var body: some View {
    ZStack {
      Color.clear
        
        // Two separate islands with a gap
        VStack(spacing: 12) {
          headerIsland
          contentIsland
        }
        .padding(35)

      .environmentObject(gateway)
      .onAppear {
          // 1) Build socket manager & listeners once
          gateway.configure()

          // 2) Append incoming messages to the chat column
          gateway.onIncomingMessage = { msg in
            chatModel.items.append(.init(type: msg.type, text: msg.content, senderName: msg.senderName, isAI: true))
          }
          
          if chatModel.items.isEmpty {
            chatModel.items.append(.init(type: "text", text: "Enter your Host token to start.", senderName: "System", isAI: true))
          }
      }
      .onReceive(NotificationCenter.default.publisher(for: .jfShotReady)) { note in
        if let url = note.object as? URL {
          chatModel.items.append(.init(type: "text", text: "Screenshot: \(url.lastPathComponent)", senderName: "You", isAI: false))
        } else {
          chatModel.items.append(.init(type: "text", text: "Screenshot failed (permission?)", senderName: "System", isAI: true))
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .jfSetFocus)) { note in
        if let which = note.object as? String {
          withAnimation(.easeInOut(duration: 0.18)) {
            focus = (which == "ai") ? .ai : .chat
          }
        }
      }
      // Optional: theme toggle hook (matches your first snippet)
      .onReceive(NotificationCenter.default.publisher(for: .jfToggleTheme)) { _ in
        withAnimation(.easeInOut(duration: 0.18)) {
          colorScheme = (colorScheme == .light ? .dark : .light)
        }
      }
    }
  }

  private func transcriptCard(title: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
    }
    .padding(10)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
  }
    
    // The top, small “toolbar” island
    private var headerIsland: some View {
      header
        .padding(.horizontal, 10)
        .background(
          .ultraThinMaterial,
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }

    // The big content island underneath
    private var contentIsland: some View {
      VStack(spacing: 0) {

          // presence strip just under the header
          HStack(spacing: 10) {
            Circle().frame(width: 8, height: 8)
              .foregroundStyle(gateway.isConnected ? .green : .red)
            Text(gateway.isConnected ? "Connected" : "Disconnected")
              .font(.caption).foregroundStyle(.secondary)

            if gateway.presence.count > 0 {
              let left = formatRemaining(gateway.presence.remainingMs)
              Text("Participants: \(gateway.presence.count) • Time left: \(left)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Spacer()
          }
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 4)

        // your panel + footer
        activePanel
      }
      .padding(10)
      .background(
        .ultraThinMaterial,
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
      )
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 10)
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
        
      Button {
        showShortcuts.toggle()
      } label: {
        HStack(spacing: 2) {
          Image(systemName: "keyboard.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(8)
            .background(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.04), in: Circle())
            .contentShape(Circle())
          KeyBadge("⌘⌥K")
        }
      }
      .buttonStyle(.plain)
      .keyboardShortcut("k", modifiers: [.command, .option])
      .popover(isPresented: $showShortcuts, arrowEdge: .bottom) {
        shortcutsPopoverContent
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: Single Active Panel

  private var activePanel: some View {
    ZStack {
        if focus == .chat {
          ChatPanelView(title: "Chat", badge: "⌘1",
                        model: chatModel,
                        isLocked: $isChatLocked,
                        onUnlockWithToken: { token in
                          // Kick off the authenticated WS connect here
                          gateway.connect(token: token)
                          // Optimistically unlock; you can re-lock on connectError if you prefer
                          return true
                        })
          .transition(.move(edge: .leading).combined(with: .opacity))
        }
        else {
          ChatPanelView(title: "AI Chat", badge: "⌘2",
                        model: aiModel,
                        isLocked: $isAILocked,
                        onUnlockWithToken: { token in
                          gateway.connect(token: token)
                          return true
                        })
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
    .animation(.easeInOut(duration: 0.18), value: focus)
  }

  // MARK: Shortcuts Popover

  private var shortcutsPopoverContent: some View {
      VStack(alignment: .leading, spacing: 10) {
          Text("Shortcuts").font(.headline).padding(.bottom, 4)
          ShortcutHint(label: "Focus Chat", shortcut: "⌘1")
          ShortcutHint(label: "Focus AI Chat", shortcut: "⌘2")
          Divider()
          ShortcutHint(label: "Screenshot", shortcut: "⌘⌥A")
          ShortcutHint(label: "Toggle Theme", shortcut: "⌘⌥T")
          ShortcutHint(label: "Hide Window", shortcut: "⌘⌥V")
          Divider()
          ShortcutHint(label: "Toggle Shortcuts", shortcut: "⌘⌥K")
      }
      .padding(12)
      .frame(width: 230)
  }
}
