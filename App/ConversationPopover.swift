import SwiftUI

struct ConversationPopoverLabel: View {
    @Environment(\.synthPalette) private var palette
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .foregroundStyle(palette.foreground)
    }
}

struct ConversationPopover<Content: View>: View {
    @Environment(\.synthPalette) private var palette
    var width: CGFloat = 220
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(palette.surface)
        .foregroundStyle(palette.foreground)
    }
}

struct ConversationPopoverRowStyle: ButtonStyle {
    @Environment(\.synthPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .foregroundStyle(color(for: configuration.role))
            .modifier(SynthButtonBackground(
                idle: .clear,
                hovered: palette.alternateSurface.opacity(0.65),
                pressed: palette.alternateSurface,
                isPressed: configuration.isPressed
            ))
    }

    private func color(for role: ButtonRole?) -> Color {
        guard isEnabled else { return palette.muted }
        return role == .destructive ? palette.danger : palette.foreground
    }
}
