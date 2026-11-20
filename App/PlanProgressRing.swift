import SwiftUI
import SynthProtocol

struct PlanProgressRing: View {
    @Environment(\.synthPalette) private var palette
    let plan: [Synth.PlanStep]

    private var finished: Int { plan.filter { $0.status == .done }.count }
    private var running: Int { plan.filter { $0.status == .active }.count }
    private var summary: String { "\(finished) of \(plan.count) steps complete, \(running) in progress" }

    var body: some View {
        Canvas { context, size in
            let midpoint = CGPoint(x: size.width / 2, y: size.height / 2)
            let arc = 360 / Double(plan.count)
            let gap = plan.count > 1 ? min(8, arc * 0.3) / 2 : 0
            for (index, step) in plan.enumerated() {
                let start = -90 + arc * Double(index)
                var path = Path()
                if plan.count == 1 {
                    path.addEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5))
                } else {
                    path.addArc(
                        center: midpoint, radius: size.width / 2 - 1.5,
                        startAngle: .degrees(start + gap), endAngle: .degrees(start + arc - gap), clockwise: false
                    )
                }
                context.stroke(path, with: .color(step.status.planColor(palette)), lineWidth: 2)
            }
        }
        .frame(width: 16, height: 16)
        .help(summary)
        .accessibilityLabel("Plan progress")
        .accessibilityValue(summary)
    }
}

extension Synth.PlanStep.Status {
    func planColor(_ palette: SynthPalette) -> Color {
        switch self {
        case .pending: palette.muted.opacity(0.65)
        case .active: palette.accent == palette.success ? palette.foreground : palette.accent
        case .done: palette.success
        }
    }

    var planLabel: String {
        switch self {
        case .pending: "Pending"
        case .active: "In progress"
        case .done: "Complete"
        }
    }
}
