import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

enum MarkdownPresentation {
    private static let lightCode = HighlightJSBridge(autoSwitchAppearance: false)
    private static let darkCode = HighlightJSBridge(
        lightTheme: .githubDark, autoSwitchAppearance: false,
        lightBackground: NSColor(calibratedWhite: 0.13, alpha: 1)
    )

    static func configuration(
        _ palette: SynthPalette, colorScheme: ColorScheme, fitsContent: Bool = false
    ) -> MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration()
        configuration.theme.bodyText = NSColor(palette.foreground)
        configuration.theme.mutedText = NSColor(palette.muted)
        configuration.theme.disabledText = NSColor(palette.muted)
        configuration.theme.headingMarker = NSColor(palette.muted)
        configuration.theme.link = NSColor(palette.accent)
        configuration.theme.incompleteLink = NSColor(palette.muted)
        configuration.theme.strikethroughColor = NSColor(palette.muted)
        configuration.overscroll = .init(percent: 0, maxPoints: 0, minPoints: 0)
        configuration.textInsets = .init(horizontal: 4, vertical: 4)
        configuration.heightBehavior = fitsContent ? .fitsContent : .scrolls
        configuration.extensions = [StrikethroughExtension()]
        configuration.services = MarkdownEditorServices(syntaxHighlighter: colorScheme == .dark ? darkCode : lightCode)
        return configuration
    }

    static func openExternal(_ url: URL) {
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    }
}
