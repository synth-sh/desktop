import AppKit
import GhosttyTerminal
import SwiftUI

enum WorkspaceTerminalPreference {
    static let useThemeBackground = "terminalUsesThemeBackground"
}

struct WorkspaceTerminalSurface: View {
    @Environment(\.synthPalette) private var palette
    @AppStorage(WorkspaceTerminalPreference.useThemeBackground) private var useThemeBackground = false
    let terminal: TerminalViewState
    let isVisible: Bool

    var body: some View {
        TerminalSurfaceView(context: terminal)
            .onChange(of: appearance, initial: true) { _, theme in
                terminal.controller.setTheme(theme)
            }
            .onChange(of: isVisible, initial: true) {
                terminal.isSurfaceVisible = isVisible
                if !isVisible, let view = terminal.attachedPlatformView, view.window?.firstResponder === view {
                    view.window?.makeFirstResponder(nil)
                }
            }
    }

    private var appearance: TerminalTheme {
        guard useThemeBackground, let color = NSColor(palette.background).usingColorSpace(.sRGB) else {
            return .default
        }
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { Int(($0 * 255).rounded()) }
        let hex = String(format: "%02X%02X%02X", components[0], components[1], components[2])
        let defaults = TerminalTheme.default
        return TerminalTheme(light: defaults.light.background(hex), dark: defaults.dark.background(hex))
    }
}

final class WorkspaceTerminalView: AppTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "q" { return false }
        return super.performKeyEquivalent(with: event)
    }

    static func releaseFocusOnOutsideClick(_ event: NSEvent) -> NSEvent? {
        if let window = event.window, let terminal = window.firstResponder as? WorkspaceTerminalView,
           !terminal.bounds.contains(terminal.convert(event.locationInWindow, from: nil)) {
            window.makeFirstResponder(nil)
        }
        return event
    }
}
