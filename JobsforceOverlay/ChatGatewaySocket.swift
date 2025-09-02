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
      case .local: return URL(string: "http://localhost:8081")!
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
      .path(path),
      .reconnects(true),
      .reconnectAttempts(-1),      // never give up
      .reconnectWait(2),
      .reconnectWaitMax(10),
      .randomizationFactor(0.5),
      .forceWebsockets(true)       // WebSocket only (no long-polling)
    ]
    let mgr = SocketManager(socketURL: env.baseURL, config: cfg)
    let sock = mgr.defaultSocket

    // Core lifecycle
    sock.on(clientEvent: .connect) { [weak self] _, _ in
      guard let self else { return }
      self.isConnecting = false
      self.isConnected = true
      self.lastError = nil
      // Immediately join the room (no payload)
      sock.emit("join")
    }

    sock.on(clientEvent: .disconnect) { [weak self] data, _ in
      guard let self else { return }
      self.isConnecting = false
      self.isConnected = false
      if let reason = data.first as? String, reason.isEmpty == false {
        self.lastError = "Disconnected: \(reason)"
      }
    }

    sock.on(clientEvent: .error) { [weak self] data, _ in
      guard let self else { return }
      self.isConnecting = false
      self.isConnected = false
      self.lastError = "Socket error: \(data)"
    }

    sock.on(clientEvent: .ping) { _, _ in /* keep-alive */ }

    // Server events
    sock.on("presenceUpdate") { [weak self] data, _ in
      guard let self, let obj = data.first as? [String: Any] else { return }
      let count = (obj["count"] as? Int) ?? 0
      let remaining = (obj["remainingMs"] as? Int) ?? 0
      self.presence = Presence(count: count, remainingMs: remaining)
    }

    sock.on("newMessage") { [weak self] data, _ in
      guard let self,
            let obj = data.first as? [String: Any],
            let text = (obj["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            text.isEmpty == false else { return }
      self.onIncomingMessage?(text)
    }

    sock.on("sessionEnded") { [weak self] _, _ in
      self?.onIncomingMessage?("— Session ended —")
    }

    self.manager = mgr
    self.socket = sock
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

  func disconnect() { socket?.disconnect() }
}
