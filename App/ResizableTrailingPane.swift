import SwiftUI

struct ResizableTrailingPane<Main: View, Pane: View>: View {
    @Environment(\.synthPalette) private var palette
    @Binding var savedWidth: Double
    let isPresented: Bool
    let defaultWidth: CGFloat
    let minimumWidth: CGFloat
    let minimumMainWidth: CGFloat
    let dividerLabel: String
    var overlaysMain = false
    @ViewBuilder let main: Main
    @ViewBuilder let pane: Pane
    @GestureState private var dragOffset: CGFloat = 0
    @State private var hovering = false

    private let handleWidth: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.width - handleWidth)
            let range = limits(available: available)
            let preferred = savedWidth > 0 ? CGFloat(savedWidth) : defaultWidth
            let baseWidth = clamp(preferred, to: range)
            let width = clamp(baseWidth - dragOffset, to: range)
            let isDocked = isPresented && !overlaysMain
            let mainWidth = isDocked ? available - width : geometry.size.width
            HStack(spacing: 0) {
                main.frame(width: mainWidth).frame(maxHeight: .infinity).clipped()
                if isDocked { trailing(width: width, base: baseWidth, limits: range) }
            }
            .overlay(alignment: .trailing) {
                if isPresented && overlaysMain {
                    trailing(width: width, base: baseWidth, limits: range)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: -3)
                }
            }
        }
    }

    private func limits(available: CGFloat) -> ClosedRange<CGFloat> {
        let mainReserve = min(minimumMainWidth, available * 0.55)
        let maxWidth = available - mainReserve
        return min(minimumWidth, maxWidth)...maxWidth
    }

    private func clamp(_ width: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }

    private func trailing(width: CGFloat, base: CGFloat, limits: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 0) {
            divider(width: width, base: base, limits: limits)
            pane.frame(width: width).frame(maxHeight: .infinity)
        }
    }

    private func divider(width: CGFloat, base: CGFloat, limits: ClosedRange<CGFloat>) -> some View {
        let highlighted = hovering || dragOffset != 0
        return Rectangle()
            .fill(highlighted ? palette.accent : palette.border)
            .frame(width: highlighted ? 2 : 1)
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($dragOffset) { value, offset, _ in offset = value.translation.width }
                .onEnded { value in savedWidth = Double(clamp(base - value.translation.width, to: limits)) })
            .accessibilityElement()
            .accessibilityLabel(dividerLabel)
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: savedWidth = Double(clamp(width + 20, to: limits))
                case .decrement: savedWidth = Double(clamp(width - 20, to: limits))
                @unknown default: break
                }
            }
    }
}
