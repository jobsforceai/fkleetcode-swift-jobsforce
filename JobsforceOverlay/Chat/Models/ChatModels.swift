import Foundation
import SwiftUI

// MARK: - Models

struct ChatBubble: Identifiable {
  let id = UUID()
  let type: String // "text" or "code"
  let text: String
  let senderName: String
  let isAI: Bool
}

final class ChatColumnModel: ObservableObject {
  @Published var items: [ChatBubble] = []
}

enum FocusMode: String, CaseIterable { case chat = "Chat", ai = "AI Chat" }
