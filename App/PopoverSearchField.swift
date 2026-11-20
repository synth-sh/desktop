import AppKit
import SwiftUI

struct PopoverSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let label: String
    let autofocus: Bool
    let move: (Int) -> Void
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField(frame: .zero)
        field.autofocus = autofocus
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
    }

    final class SearchField: NSSearchField {
        var autofocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard autofocus, window != nil else { return }
            Task { [weak self] in
                if let self { window?.makeFirstResponder(self) }
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: PopoverSearchField

        init(_ parent: PopoverSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }

        // AppKit's field editor owns these keys while the search field is focused.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            default: return false
            }
            return true
        }
    }
}
