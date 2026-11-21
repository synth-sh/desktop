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
        var theme = TerminalTheme.default
        theme.light = theme.light.selectionBackground("245DAE").selectionForeground("FFFFFF")
        theme.dark = theme.dark.selectionBackground("82B5FF").selectionForeground("101828")

        if useThemeBackground, let color = NSColor(palette.background).usingColorSpace(.sRGB) {
            let components = [color.redComponent, color.greenComponent, color.blueComponent]
                .map { Int(($0 * 255).rounded()) }
            let hex = String(format: "%02X%02X%02X", components[0], components[1], components[2])
            theme.light = theme.light.background(hex)
            theme.dark = theme.dark.background(hex)
        }
        return theme
    }
}

final class WorkspaceTerminalView: AppTerminalView {
    var addContext: ((String) -> Void)?
    private var previousSelection: TerminalSelectionRegion?
    private var selectionMenuTask: Task<Void, Never>?
    private var selectionActions: NSView?

    override func mouseDown(with event: NSEvent) {
        dismissSelectionActions()
        previousSelection = selectionRegion
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard let selection = selectionRegion, selection != previousSelection else { return }
        let point = convert(event.locationInWindow, from: nil)
        // A third click may extend a word selection to the whole line.
        let delay = event.clickCount == 2 ? Duration.seconds(NSEvent.doubleClickInterval) : .zero
        selectionMenuTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, window?.firstResponder === self, selectionRegion == selection else {
                return
            }
            showSelectionActions(at: point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        dismissSelectionActions()
        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        dismissSelectionActions()
        super.scrollWheel(with: event)
    }

    override func setSurfaceVisible(_ visible: Bool) {
        if !visible { dismissSelectionActions() }
        super.setSurfaceVisible(visible)
    }

    override func keyDown(with event: NSEvent) {
        let dismissOnly = selectionActions != nil && event.charactersIgnoringModifiers == "\u{1B}"
        dismissSelectionActions()
        if !dismissOnly { super.keyDown(with: event) }
    }

    override func selectionContextMenu() -> NSMenu {
        let menu = super.selectionContextMenu()
        if addContext != nil, let text = selectedText {
            let item = menu.insertItem(withTitle: "Add to Chat", action: #selector(attachSelection),
                                       keyEquivalent: "", at: 0)
            item.target = self
            item.representedObject = text
        }
        return menu
    }

    private var selectedText: String? {
        guard let text = (delegate as? TerminalViewState)?.surface?.readSelection(), !text.isEmpty else { return nil }
        return text
    }

    private func showSelectionActions(at point: NSPoint) {
        guard let text = selectedText else { return }
        let actions = NSHostingView(rootView: HStack(spacing: 10) {
            Button("Add to Chat", systemImage: "text.badge.plus") { [weak self] in
                self?.dismissSelectionActions()
                self?.addContext?(text)
            }
            Button("Copy", systemImage: "document.on.document") { [weak self] in
                self?.copy(nil)
                self?.dismissSelectionActions()
            }
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .fixedSize())
        let size = actions.fittingSize
        let verticalOrigin = isFlipped ? point.y + 6 : point.y - size.height - 6
        actions.frame = NSRect(
            x: min(max(0, point.x), max(0, bounds.width - size.width)),
            y: min(max(0, verticalOrigin), max(0, bounds.height - size.height)),
            width: size.width, height: size.height
        )
        selectionActions = actions
        addSubview(actions)
    }

    private func dismissSelectionActions() {
        selectionMenuTask?.cancel()
        selectionActions?.removeFromSuperview()
        selectionActions = nil
    }

    @objc private func attachSelection(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String { addContext?(text) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "q" { return false }
        return super.performKeyEquivalent(with: event)
    }

    static func releaseFocusOnOutsideClick(_ event: NSEvent) -> NSEvent? {
        if let window = event.window, let terminal = window.firstResponder as? WorkspaceTerminalView,
           !terminal.bounds.contains(terminal.convert(event.locationInWindow, from: nil)) {
            terminal.dismissSelectionActions()
            window.makeFirstResponder(nil)
        }
        return event
    }
}
