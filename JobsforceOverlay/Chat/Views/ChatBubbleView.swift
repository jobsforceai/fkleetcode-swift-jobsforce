import SwiftUI

struct ChatBubbleView: View {
    let item: ChatBubble
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            if !item.isAI { Spacer(minLength: 40) }
            
            VStack(alignment: item.isAI ? .leading : .trailing, spacing: 4) {
                Text(item.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                if item.type == "code" {
                    codeBubble
                } else if item.type == "image" {
                    imageBubble
                } else {
                    textBubble
                }
            }
            .frame(maxWidth: 540, alignment: item.isAI ? .leading : .trailing)
            
            if item.isAI { Spacer(minLength: 40) }
        }
    }

    private var imageBubble: some View {
        AsyncImage(url: item.imageUrl) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(12)
        } placeholder: {
            ProgressView()
                .progressViewStyle(.circular)
                .padding()
        }
        .frame(maxWidth: 300)
    }

    private var textBubble: some View {
        Text(item.text ?? "")
            .foregroundStyle(item.isAI ? Color.primary : Color.white)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isAI
                          ? (colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                          : Color.blue
                    )
            )
    }

    private var codeBubble: some View {
        Text(item.text ?? "")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        colorScheme == .light
                        ? Color.black.opacity(0.08)
                        : Color.white.opacity(0.10)
                    )
            )
    }
}
