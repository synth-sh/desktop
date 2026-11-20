import SwiftUI

struct ActivityDisclosure<Content: View, Trailing: View>: View {
    @Environment(\.synthPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var icon: String?
    var tint: Color?
    var detail: String?
    var muted = false
    var expansion: Binding<Bool>?
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing
    @State private var expanded = false

    private var isExpanded: Bool { expansion?.wrappedValue ?? expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if let expansion { expansion.wrappedValue.toggle() } else { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon)
                            .frame(width: 14)
                            .foregroundStyle(tint ?? palette.muted)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(muted ? palette.muted : palette.foreground)
                    Spacer(minLength: 4)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(palette.muted)
                    }
                    trailing.fixedSize()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                .font(.callout)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                content.padding(.leading, icon == nil ? 4 : 21).padding(.bottom, 4)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
    }
}

extension ActivityDisclosure where Trailing == EmptyView {
    init(
        title: String, icon: String? = nil, tint: Color? = nil, detail: String? = nil, muted: Bool = false,
        expansion: Binding<Bool>? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, icon: icon, tint: tint, detail: detail, muted: muted, expansion: expansion,
                  content: content, trailing: { EmptyView() })
    }
}

struct ActivityDuration: View {
    @Environment(\.synthPalette) private var palette
    let milliseconds: UInt64

    var body: some View {
        let seconds = milliseconds / 1_000
        let label: String = if milliseconds < 1_000 {
            "\(milliseconds) ms"
        } else if seconds < 60 {
            "\(seconds)s"
        } else {
            "\(seconds / 60)m \(seconds % 60)s"
        }
        Text(label)
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.muted)
            .accessibilityLabel("Duration")
            .accessibilityValue(label)
    }
}

struct RunningDuration: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            ActivityDuration(milliseconds: UInt64(max(0, context.date.timeIntervalSince(start)) * 1_000))
        }
    }
}

struct ExpandableActivityBody: View {
    @Environment(\.synthPalette) private var palette
    let preview: String
    let load: ActivityBodyLoader?
    @State private var full: String?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: full ?? preview)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let error { Text(error).foregroundStyle(palette.danger) }
            if let load, full == nil {
                Button(loading ? "Loading…" : "Load Full Text") {
                    Task {
                        loading = true
                        defer { loading = false }
                        error = nil
                        do { full = try await load() } catch {
                            if !Task.isCancelled { self.error = error.localizedDescription }
                        }
                    }
                }
                .disabled(loading)
            }
        }
    }
}
