import SwiftUI

struct HostTokenGateView: View {
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
