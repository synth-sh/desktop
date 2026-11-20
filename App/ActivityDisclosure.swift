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
        VStack(alignment: .leading, spacing: 0) {
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
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isExpanded)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                .font(.callout)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            DisclosureReveal(expanded: isExpanded, reduceMotion: reduceMotion) {
                content.padding(.leading, icon == nil ? 4 : 21).padding(.vertical, 4)
            }
        }
    }
}

private struct DisclosureReveal<Content: View>: View {
    let expanded: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: Content
    @State private var mounted: Bool
    @State private var fraction: CGFloat
    @State private var revision = 0

    init(expanded: Bool, reduceMotion: Bool, @ViewBuilder content: () -> Content) {
        self.expanded = expanded
        self.reduceMotion = reduceMotion
        self.content = content()
        _mounted = State(initialValue: expanded)
        _fraction = State(initialValue: expanded ? 1 : 0)
    }

    var body: some View {
        DisclosureHeight(fraction: fraction) {
            if mounted { content }
        }
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .onChange(of: expanded) { updateHeight() }
    }

    private func updateHeight() {
        revision += 1
        let current = revision
        if reduceMotion {
            mounted = expanded
            fraction = expanded ? 1 : 0
            return
        }
        if expanded { mounted = true }
        withAnimation(.easeOut(duration: expanded ? 0.17 : 0.13)) {
            fraction = expanded ? 1 : 0
        } completion: {
            if revision == current, !expanded { mounted = false }
        }
    }
}

private struct DisclosureHeight: Layout {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: measured.width, height: measured.height * min(max(fraction, 0), 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
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
