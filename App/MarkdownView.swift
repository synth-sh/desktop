import AppKit
import MarkdownEngine
import SwiftUI

struct MarkdownView: View {
    @Environment(\.synthPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let identifier: String
    var openReference: ((URL) -> Void)?

    var body: some View {
        NativeTextViewWrapper(
            text: .constant(text),
            configuration: MarkdownPresentation.configuration(palette, colorScheme: colorScheme, fitsContent: true),
            fontSize: NSFont.systemFontSize, documentId: identifier, isEditable: false,
            interaction: .init(openURL: { url in
                if url.scheme == "synth-file" {
                    openReference?(url)
                } else {
                    MarkdownPresentation.openExternal(url)
                }
                return true
            })
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StreamingMarkdown: View {
    let text: String
    let identifier: String
    @State private var rendered = ""
    @State private var pendingText = ""
    @State private var renderUpdate: Task<Void, Never>?

    var body: some View {
        MarkdownView(text: rendered, identifier: identifier)
            .onChange(of: text, initial: true) { scheduleRender() }
            .onDisappear {
                renderUpdate?.cancel()
                renderUpdate = nil
            }
    }

    private func scheduleRender() {
        pendingText = text
        if rendered.isEmpty {
            rendered = pendingText
            return
        }
        guard renderUpdate == nil else { return }
        renderUpdate = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            rendered = pendingText
            renderUpdate = nil
        }
    }
}
