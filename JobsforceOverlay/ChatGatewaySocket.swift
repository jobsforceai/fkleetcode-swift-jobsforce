import Foundation
import SocketIO
import Combine

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

  struct Presence: Equatable { let count: Int; let remainingMs: Int }

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var presence = Presence(count: 0, remainingMs: 0)
    @Published var isConnecting = false

  // Hook the UI in: whenever a server message arrives, call this.
  var onIncomingMessage: ((String) -> Void)?

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
          let text = (obj["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty
        else { return }
        // UI callback; keep on main actor to match your @MainActor class
        Task { @MainActor in self.onIncomingMessage?(text) }
      }

      sock.on("sessionEnded") { [weak self] _, _ in
        Task { @MainActor in self?.onIncomingMessage?("— Session ended —") }
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
    socket.emit("sendMessage", ["message": text])
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
