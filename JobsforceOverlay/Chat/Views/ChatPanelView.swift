import SwiftUI

struct ChatPanelView: View {
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

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.items) { item in
                        ChatBubbleView(item: item)
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
        model.items.append(.init(type: "text", text: trimmed, imageUrl: nil, senderName: "You", isAI: false))
          
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
