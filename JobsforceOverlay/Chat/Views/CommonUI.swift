import SwiftUI

struct ShortcutHint: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            KeyBadge(shortcut)
        }
    }
}

struct KeyBadge: View {
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

struct HintPill: View {
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

struct SegmentedTwoButton: View {
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

struct LockScreenView: View {
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
