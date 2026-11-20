import SwiftUI

struct ResizableEdgePane<Main: View, Pane: View>: View {
    @Environment(\.synthPalette) private var palette
    @Binding var savedSize: Double
    var axis: Axis = .horizontal
    let isPresented: Bool
    let defaultSize: CGFloat
    let minimumSize: CGFloat
    let minimumMainSize: CGFloat
    let dividerLabel: String
    var overlaysMain = false
    var keepsPaneMounted = false
    @ViewBuilder let main: Main
    @ViewBuilder let pane: Pane
    @GestureState private var dragOffset: CGFloat = 0
    @State private var hovering = false

    private let handleSize: CGFloat = 7
    private var horizontal: Bool { axis == .horizontal }

    var body: some View {
        GeometryReader { geometry in
            let total = extent(geometry.size)
            let available = max(0, total - handleSize)
            let range = limits(available: available)
            let preferred = savedSize > 0 ? CGFloat(savedSize) : defaultSize
            let baseSize = clamp(preferred, to: range)
            let size = clamp(baseSize - dragOffset, to: range)
            let mainSize = isPresented && !overlaysMain ? available - size : total

            sized(main, mainSize)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: horizontal ? .trailing : .bottom) {
                    if isPresented || keepsPaneMounted {
                        edgePane(size: size, base: baseSize, limits: range)
                            .opacity(isPresented ? 1 : 0)
                            .allowsHitTesting(isPresented)
                            .disabled(!isPresented)
                            .accessibilityElement(children: .contain)
                            .accessibilityHidden(!isPresented)
                    }
                }
        }
    }

    private func extent(_ size: CGSize) -> CGFloat {
        horizontal ? size.width : size.height
    }

    private func sized(_ content: some View, _ size: CGFloat) -> some View {
        content
            .frame(width: horizontal ? size : nil, height: horizontal ? nil : size)
            .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
    }

    private func limits(available: CGFloat) -> ClosedRange<CGFloat> {
        let mainReserve = min(minimumMainSize, available * 0.55)
        let maximum = available - mainReserve
        return min(minimumSize, maximum)...maximum
    }

    private func clamp(_ size: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(size, range.lowerBound), range.upperBound)
    }

    private func edgePane(size: CGFloat, base: CGFloat, limits: ClosedRange<CGFloat>) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            divider(size: size, base: base, limits: limits)
            sized(pane, size).clipped()
        }
        .shadow(
            color: .black.opacity(overlaysMain ? 0.18 : 0), radius: 8,
            x: horizontal ? -3 : 0, y: horizontal ? 0 : -3
        )
    }

    private func divider(size: CGFloat, base: CGFloat, limits: ClosedRange<CGFloat>) -> some View {
        let highlighted = hovering || dragOffset != 0
        let line = Rectangle().fill(highlighted ? palette.accent : palette.border)
        return sized(sized(line, highlighted ? 2 : 1), handleSize)
            .contentShape(Rectangle())
            .pointerStyle(horizontal ? .columnResize : .rowResize)
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($dragOffset) { value, offset, _ in offset = extent(value.translation) }
                .onEnded { value in
                    savedSize = Double(clamp(base - extent(value.translation), to: limits))
                })
            .accessibilityElement()
            .accessibilityLabel(dividerLabel)
            .accessibilityValue("\(Int(size)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: savedSize = Double(clamp(size + 20, to: limits))
                case .decrement: savedSize = Double(clamp(size - 20, to: limits))
                @unknown default: break
                }
            }
    }
}
