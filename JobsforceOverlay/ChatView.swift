import SwiftUI

struct ChatBubble: Identifiable {
  let id = UUID()
  let text: String
  let isAI: Bool
}

final class ChatModel: ObservableObject {
  @Published var items: [ChatBubble] = [
    .init(text: "Connected. Waiting for your first screenshot…", isAI: true)
  ]
}

struct ChatView: View {
  @StateObject private var model = ChatModel()

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .shadow(radius: 16)

      VStack(spacing: 0) {
        HStack {
          Text("Jobsforce • Private Assist")
            .font(.headline)
          Spacer()
        }
        .padding()

        Divider()

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(model.items) { item in
              HStack(alignment: .top) {
                Text(item.isAI ? "AI:" : "You:")
                  .font(.caption).foregroundColor(.secondary)
                Text(item.text)
                Spacer()
              }
            }
          }
          .padding()
        }
      }
    }
    .frame(width: 380, height: 520)
    .background(.clear)
    .onReceive(NotificationCenter.default.publisher(for: .jfShotReady)) { note in
  if let url = note.object as? URL {
    model.items.append(.init(text: "Screenshot: \(url.lastPathComponent)", isAI: false))
  } else {
    model.items.append(.init(text: "Screenshot failed (permission?)", isAI: true))
  }
}

  }
}
