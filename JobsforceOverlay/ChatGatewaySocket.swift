import Foundation
import SocketIO
import Combine
import UniformTypeIdentifiers

private func fileExtension(for mime: String) -> String {
  switch mime.lowercased() {
  case "image/jpeg", "image/jpg": return "jpg"
  case "image/png": return "png"
  case "image/webp": return "webp"
  case "image/gif":  return "gif"
  default: return "bin"
  }
}

private func writeTempFile(data: Data, suggestedName: String, mime: String) -> URL? {
  let ext = fileExtension(for: mime)
  let base = suggestedName.isEmpty ? "image" : (suggestedName as NSString).deletingPathExtension
  let filename = "\(base)-\(UUID().uuidString).\(ext)"
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
  do {
    try data.write(to: url, options: .atomic)
    return url
  } catch {
    print("Temp write failed:", error)
    return nil
  }
}

private func coerceToData(_ any: Any) -> Data? {
  if let d = any as? Data { return d }
  if let arr = any as? [UInt8] { return Data(arr) }
  if let arr = any as? [NSNumber] { return Data(arr.map { $0.uint8Value }) }
  if let dict = any as? [String: Any],
     let type = dict["type"] as? String,
     type.lowercased() == "buffer" {
    if let arr = dict["data"] as? [UInt8] {
      return Data(arr)
    }
    if let arr = dict["data"] as? [NSNumber] {
      return Data(arr.map { $0.uint8Value })
    }
  }
  return nil
}

private func bestMimeType(imageName: String, fallback: String?) -> String {
  if let m = fallback, !m.isEmpty { return m }
  switch (imageName as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png":         return "image/png"
    case "gif":         return "image/gif"
    case "webp":        return "image/webp"
    default:            return "application/octet-stream"
  }
}

@MainActor
final class ChatGatewaySocket: ObservableObject {
  enum Env {
    case local, prod
    var baseURL: URL {
      switch self {
      // Use http for local dev; the client upgrades to WS automatically.
//      case .local: return URL(string: "http://localhost:8081")!
      case .local: return URL(string: "http://127.0.0.1:8081")!
      // Use https for prod (TLS). You can also set .secure(true) if needed.
      case .prod:  return URL(string: "https://your-chat-gateway-domain.com")!
      }
    }
  }

  struct ReceivedMessage {
    let type: String
    let content: String?
    let imageUrl: String?
    let senderName: String
  }

  struct Presence: Equatable { let count: Int; let remainingMs: Int }

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var presence = Presence(count: 0, remainingMs: 0)
    @Published var isConnecting = false

  // Hook the UI in: whenever a server message arrives, call this.
  var onIncomingMessage: ((ReceivedMessage) -> Void)?

  private var manager: SocketManager?
  private var socket: SocketIOClient?
  private var presenceTimer: Timer?

  private let env: Env
  private let path: String

  init(env: Env, path: String = "/ws") {
    self.env = env
    self.path = path
  }

    func configure() {
      let cfg: SocketIOClientConfiguration = [
        .log(false),
        .compress,
        .path(path),                 // <- ensure this matches your server; default Socket.IO is "/socket.io"
        .reconnects(true),
        .reconnectAttempts(-1),
        .reconnectWait(2),
        .reconnectWaitMax(10),
        .randomizationFactor(0.5)
//        .forceWebsockets(true)
      ]

      let mgr = SocketManager(socketURL: env.baseURL, config: cfg)
      let sock = mgr.defaultSocket

      // --- Core lifecycle ---
      sock.on(clientEvent: .connect) { [weak self] _, _ in
        guard let self else { return }
        Task { @MainActor in
          self.isConnecting = false
          self.isConnected  = true
          self.lastError    = nil
        }
        // Ask server to join presence-able room (optional, if your server expects it)
        sock.emit("join")
        // Proactively request a presence snapshot (optional)
        sock.emit("presence:request")
      }

      sock.on(clientEvent: .disconnect) { [weak self] data, _ in
        guard let self else { return }
        let reason = (data.first as? String).flatMap { $0.isEmpty ? nil : $0 }
        Task { @MainActor in
          self.isConnecting = false
          self.isConnected  = false
          self.lastError    = reason.map { "Disconnected: \($0)" }
        }
      }

      sock.on(clientEvent: .error) { [weak self] data, _ in
        guard let self else { return }
        Task { @MainActor in
          self.isConnecting = false
          self.isConnected  = false
          self.lastError    = "Socket error: \(data)"
        }
      }

      // --- Presence: handle multiple event names & numeric types ---
      let presenceHandler: NormalCallback = { [weak self] data, _ in
        guard let self else { return }
        guard let obj = data.first as? [String: Any] else { return }

        // count can be Int / NSNumber / Double
        let count: Int = {
          if let v = obj["count"] as? Int { return v }
          if let v = obj["count"] as? NSNumber { return v.intValue }
          if let v = obj["count"] as? Double { return Int(v) }
          // also accept "participantCount"
          if let v = obj["participantCount"] as? Int { return v }
          if let v = obj["participantCount"] as? NSNumber { return v.intValue }
          if let v = obj["participantCount"] as? Double { return Int(v) }
          return 0
        }()

        // remainingMs can be Int / NSNumber / Double
        let remainingMs: Int = {
          if let v = obj["remainingMs"] as? Int      { return v }
          if let v = obj["remainingMs"] as? NSNumber { return v.intValue }
          if let v = obj["remainingMs"] as? Double   { return Int(v) }
          // accept "ttlSeconds" fallback if your server sends seconds
          if let secs = obj["ttlSeconds"] as? Int    { return secs * 1000 }
          if let secs = obj["ttlSeconds"] as? Double { return Int(secs * 1000) }
          return 0
        }()

        Task { @MainActor in
          self.updatePresence(count: count, remainingMs: max(0, remainingMs))
        }
      }

      // Listen to all common names (use the one your server actually emits)
      sock.on("presenceUpdate",    callback: presenceHandler)
      sock.on("presence",          callback: presenceHandler)
      sock.on("presence:snapshot", callback: presenceHandler)

      // --- Messages ---
      sock.on("newMessage") { [weak self] data, _ in
        guard let self else { return }
        guard
          let obj  = data.first as? [String: Any],
          let from = obj["from"] as? [String: Any],
          let senderName = from["name"] as? String,
          let type = obj["type"] as? String
        else { return }

        var content  = obj["content"] as? String
        var imageUrl = obj["imageUrl"] as? String

        if type == "image", imageUrl == nil {
          // 1) Try embedded binary (various shapes)
          var bin: Data? = nil
          if let any = obj["imageData"] {
            bin = coerceToData(any)
          }

          // 2) Or as a second event argument (Socket.IO attachments)
          if bin == nil, data.count >= 2 {
            bin = coerceToData(data[1])
          }

          // 3) If we found bytes, write a temp file and point AsyncImage to file:// URL
          if let bin {
            let imageName      = (obj["imageName"] as? String) ?? "image"
            let mimeFromServer = obj["imageType"] as? String
            let finalMime      = bestMimeType(imageName: imageName, fallback: mimeFromServer)

            if let localURL = writeTempFile(data: bin, suggestedName: imageName, mime: finalMime) {
              imageUrl = localURL.absoluteString
            } else {
              content = (content ?? "") + "\n⚠️ Failed to materialize incoming image."
            }
          }
        }

        // Guard rails
        if type == "text" {
          let trimmed = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
        } else if type == "image" {
          guard let u = imageUrl, !u.isEmpty else { return }
        }

        let msg = ReceivedMessage(type: type, content: content, imageUrl: imageUrl, senderName: senderName)
        Task { @MainActor in self.onIncomingMessage?(msg) }
      }


      sock.on("sessionEnded") { [weak self] _, _ in
        let msg = ReceivedMessage(type: "text", content: "— Session ended —", imageUrl: nil, senderName: "System")
        Task { @MainActor in self?.onIncomingMessage?(msg) }
      }

      self.manager = mgr
      self.socket  = sock
    }

  /// Start the connection with an auth token sent in the handshake.
  func connect(token: String) {
    guard let socket else { return }
    // Reset state and start the connection process.
    // The handlers in `configure()` will manage the isConnecting/isConnected state.
    lastError = nil
    isConnecting = true
    socket.connect(withPayload: ["token": token])
  }

  func sendMessage(_ text: String) {
    guard let socket, isConnected else { return }
    // Send as a structured object
    let payload: [String: Any] = ["type": "text", "content": text]
    socket.emit("sendMessage", payload)
  }

  func disconnect() {
    socket?.disconnect()
    presenceTimer?.invalidate()
  }

  private func updatePresence(count: Int, remainingMs: Int) {
    presenceTimer?.invalidate()
    self.presence = Presence(count: count, remainingMs: remainingMs)

    guard remainingMs > 0 else { return }

    self.presenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
      guard let self = self else {
        timer.invalidate()
        return
      }

      Task { @MainActor in
        let newRemainingMs = self.presence.remainingMs - 1000
        if newRemainingMs > 0 {
          self.presence = Presence(count: self.presence.count, remainingMs: newRemainingMs)
        } else {
          self.presence = Presence(count: self.presence.count, remainingMs: 0)
          timer.invalidate()
        }
      }
    }
  }
}

extension ChatGatewaySocket {
  /// Send an image file at URL (e.g., your screenshot) with optional caption.
  func sendImage(at url: URL, caption: String? = nil) {
    guard let socket, isConnected else { return }
    guard let data = try? Data(contentsOf: url) else { return }

    // Guess MIME from extension; fallback to png if unknown
    let ext = url.pathExtension.lowercased()
    let mime: String = {
      switch ext {
      case "jpg", "jpeg": return "image/jpeg"
      case "png":         return "image/png"
      case "gif":         return "image/gif"
      case "webp":        return "image/webp"
      default:            return "image/png"
      }
    }()

    let meta: [String: Any] = [
      "name": url.lastPathComponent,
      "type": mime,
      "size": data.count
    ]

    // Socket.IO: emit(meta, binary, ack)
    socket.emit("sendImage", meta, data) {
      // optional: inspect ack array if you returned anything else
    }

    // If you want to also send a caption as a text message, you can do it here:
    if let c = caption, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let payload: [String: Any] = ["type": "text", "content": c]
      socket.emit("sendMessage", payload)
    }
  }

  /// Send image from raw Data (when you already have it in memory).
  func sendImageData(_ data: Data, filename: String = "image.png", mime: String = "image/png", caption: String? = nil) {
    guard let socket, isConnected else { return }
    let meta: [String: Any] = ["name": filename, "type": mime, "size": data.count]
    socket.emit("sendImage", meta, data)

    if let c = caption, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let payload: [String: Any] = ["type": "text", "content": c]
      socket.emit("sendMessage", payload)
    }
  }
}
