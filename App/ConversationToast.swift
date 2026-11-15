import AppKit
import SwiftUI

struct ConversationToast: View {
    @Environment(\.synthPalette) private var palette
    let alert: ConversationAlert
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title).font(.headline)
                    Text(alert.chatTitle)
                        .font(.callout)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(width: 280)
            .foregroundStyle(palette.foreground)
            .background(palette.surface, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the conversation")
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

struct AttentionDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.synthPalette) private var palette
    let title: String

    var body: some View {
        Group {
            if reduceMotion {
                dot
            } else {
                dot.phaseAnimator([false, true]) { content, pulse in
                    content.scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0.65 : 1)
                } animation: { _ in .easeInOut(duration: 0.85) }
            }
        }
        .frame(width: 11, height: 11)
        .accessibilityLabel(title)
    }

    private var dot: some View {
        Circle().fill(palette.accent).frame(width: 7, height: 7)
    }
}

struct ConversationWindowReader: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowView {
        WindowView(onAttach: onAttach)
    }

    func updateNSView(_ view: WindowView, context: Context) {
        view.onAttach = onAttach
    }

    final class WindowView: NSView {
        var onAttach: (NSWindow) -> Void

        init(onAttach: @escaping (NSWindow) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { [weak self] in
                if let self, let window { onAttach(window) }
            }
        }
    }
}
