import SwiftUI

struct ReasoningEffortSlider: View {
    let levels: [String]
    @Binding var selection: String
    let onCommit: () -> Void
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Reasoning effort", value: selection.capitalized)
            if levels.count > 1 {
                Slider(value: position, in: 0...Double(levels.count - 1), step: 1) { active in
                    editing = active
                    if !active { onCommit() }
                }
                .accessibilityLabel("Reasoning effort")
                .accessibilityValue(selection.capitalized)
            }
        }
    }

    private var position: Binding<Double> {
        Binding(get: { Double(levels.firstIndex(of: selection) ?? 0) }, set: { value in
            let level = levels[Int(value.rounded())]
            guard selection != level else { return }
            selection = level
            if !editing { onCommit() }
        })
    }
}
