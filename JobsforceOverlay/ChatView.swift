import SwiftUI
import AppKit
import SocketIO

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

// HH:MM:SS from milliseconds
private func formatRemaining(_ ms: Int) -> String {
  let total = max(0, ms / 1000)
  let h = total / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  return String(format: "%02d:%02d:%02d", h, m, s)
}


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

  // 🎙️ Transcription
  @StateObject private var transcriber = TranscriptionDirector()

  var body: some View {
    ZStack {
      Color.clear
//        .liquidGlass(
//          radius: 22,
//          material: .popover, // clearest/least blur
//          tint: .white,
//          tintOpacity: 0.015,
//          saturation: 1.6,
//          dropShadow: 18
//        )
        
        // Two separate islands with a gap
        VStack(spacing: 12) {
          headerIsland
          contentIsland
        }
        .padding(35)

//      VStack(spacing: 0) {
//        header
//          
//          // Tiny presence strip under header
//          HStack(spacing: 10) {
//            Circle().frame(width: 8, height: 8)
//              .foregroundStyle(gateway.isConnected ? .green : .red)
//            Text(gateway.isConnected ? "Connected" : "Disconnected")
//              .font(.caption).foregroundStyle(.secondary)
//            if gateway.presence.count > 0 {
//              Text("Participants: \(gateway.presence.count) • Time left: \(gateway.presence.remainingMs/1000)s")
//                .font(.caption).foregroundStyle(.secondary)
//            }
//            Spacer()
//          }
//          .padding(.horizontal, 12)
//          .padding(.top, 4)
//
//        // Live transcription strip
//        VStack(spacing: 8) {
//          HStack {
//            Button(transcriber.isRunning ? "Stop Transcription" : "Start Transcription") {
//              if transcriber.isRunning {
//                transcriber.stop()
//              } else {
//                transcriber.requestSpeechAuth { ok in if ok { transcriber.start() } }
//              }
//            }
//            .buttonStyle(.borderedProminent)
//            Spacer()
//          }
//
//          HStack(spacing: 12) {
//            transcriptCard(title: "Mic",    text: transcriber.micText)
//            transcriptCard(title: "System", text: transcriber.systemText)
//          }
//          .frame(height: 120)
//        }
//        .padding(.horizontal, 12)
//        .padding(.vertical, 8)
//
//        Divider().opacity(0.18)
//
//        activePanel
//        footerHints
//      }
//      .frame(minWidth: 720, minHeight: 500)
//      .frame(maxWidth: .infinity, maxHeight: .infinity)
//      .background(.clear)
      .environmentObject(gateway)
      .onAppear {
          // 1) Build socket manager & listeners once
          gateway.configure()

          // 2) Append incoming messages to the chat column
          gateway.onIncomingMessage = { text in
            chatModel.items.append(.init(text: text, isAI: true))
          }
          
          if chatModel.items.isEmpty {
            chatModel.items.append(.init(text: "Enter your Host token to start.", isAI: true))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

        // live transcription block
        VStack(spacing: 8) {
          HStack {
            Button(transcriber.isRunning ? "Stop Transcription" : "Start Transcription") {
              if transcriber.isRunning {
                transcriber.stop()
              } else {
                transcriber.requestSpeechAuth { ok in if ok { transcriber.start() } }
              }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
          }

          HStack(spacing: 12) {
            transcriptCard(title: "Mic",    text: transcriber.micText)
            transcriptCard(title: "System", text: transcriber.systemText)
          }
          .frame(height: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

        Divider().opacity(0.16)

        // your panel + footer
        activePanel
        footerHints
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

  // MARK: Footer Hints

  private var footerHints: some View {
    HStack(spacing: 12) {
      HintPill(label: "Screenshot",   shortcut: "⌘⌥A")
      HintPill(label: "Toggle Theme", shortcut: "⌘⌥T")
      Spacer()
    }
    .padding(10)
    .background(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.03))
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

private struct HostTokenGateView: View {
    let title: String
    let isConnecting: Bool
    let error: String?
    let onStart: (String) -> Void

    @State private var hostToken: String = ""
    @State private var reveal = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        VStack(spacing: 16) {
            Image(systemName: "lock.open.laptopcomputer")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Enter your Host token to connect securely to the chat gateway.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 8) {
                if reveal {
                    TextField("Host Token (JWT)", text: $hostToken)
                        .textFieldStyle(.plain)
                } else {
                    SecureField("Host Token (JWT)", text: $hostToken)
                        .textFieldStyle(.plain)
                }
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
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
            .frame(width: 360)

            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button {
                onStart(hostToken)
            } label: {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(isConnecting ? "Connecting…" : "Start Session")
                }
                .font(.headline)
                .foregroundStyle(isLight ? .white : .black)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(isLight ? Color.black.opacity(0.9) : Color.white.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(hostToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            .opacity(hostToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLight ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
    }
}


private struct ChatPanelView: View {
    let title: String
    let badge: String
    @ObservedObject var model: ChatColumnModel
    @Binding var isLocked: Bool
    let onUnlockWithToken: (String) -> Bool
    @State private var draft: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var gateway: ChatGatewaySocket
    
    @State private var isNearBottom: Bool = true
    private let bottomSentinelID = "BOTTOM_SENTINEL"

    var body: some View {
        Group {
            if isLocked {
                HostTokenGateView(
                    title: "\(title) – Connect",
                    isConnecting: gateway.isConnecting,
                    error: gateway.lastError,
                    onStart: { token in
                        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        gateway.connect(token: trimmed)
                    }
                )
                .onChange(of: gateway.isConnected) { connected in
                    if connected {
                        withAnimation { isLocked = false }
                    }
                }
            } else {
                chatContent
            }
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

          if gateway.presence.count > 0 {
            Text("\(gateway.presence.count) • \(formatRemaining(gateway.presence.remainingMs))")
              .font(.caption).foregroundStyle(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.primary.opacity(0.06), in: Capsule())
          }

          Circle().frame(width: 8, height: 8)
            .foregroundStyle(gateway.isConnected ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        ScrollViewReader { proxy in
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
                                            colorScheme == .light
                                            ? (item.isAI ? Color.black.opacity(0.05) : Color.black.opacity(0.03))
                                            : (item.isAI ? Color.white.opacity(0.06) : Color.white.opacity(0.04))
                                        )
                                )
                            Spacer(minLength: 0)
                        }
                    }
                    
                    // 👇 Sentinel: when visible, we’re at/near the bottom
                    Color.clear
                        .frame(height: 1)
                        .id(bottomSentinelID)
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            // When a new message arrives, scroll *only if* user is already near bottom
            .onChange(of: model.items.count) { _ in
                if isNearBottom {
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(bottomSentinelID, anchor: .bottom)
                    }
                }
            }
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
        // Append locally for instant UX
        model.items.append(.init(text: trimmed, isAI: false))
          
        // Send to the gateway (the server will also broadcast a newMessage)
        // Access the gateway via an EnvironmentObject if you prefer;
        // here we just capture it from the outer scope.
          gateway.sendMessage(trimmed)

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
