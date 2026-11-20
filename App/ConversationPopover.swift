import SwiftUI

struct ConversationDropdown<Trigger: View, Content: View>: View {
    @Binding var isPresented: Bool
    var width: CGFloat = 220
    var arrowEdge: Edge = .top
    @ViewBuilder let label: Trigger
    @ViewBuilder let content: Content

    var body: some View {
        Button { isPresented.toggle() } label: {
            label
        }
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            ConversationPopover(width: width) { content }
        }
    }
}

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

struct ConversationPopoverChoice: View {
    let title: String
    let selected: Bool

    var body: some View {
        HStack {
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ConversationPopoverChoices<Content: View>: View {
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        if count > 8 {
            ScrollView { rows }
                .frame(height: 280)
        } else {
            rows
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 3) { content }
            .buttonStyle(ConversationPopoverRowStyle())
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
