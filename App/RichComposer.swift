import AppKit
import MarkdownEngine
import SwiftUI
import SynthClient
import UniformTypeIdentifiers

struct RichComposer: View {
    @Environment(\.synthPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: ConversationModel
    @Binding var focused: Bool
    let controller: ComposerController
    @State private var preview: ComposerAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editor
            if model.isImportingAttachments { ProgressView("Preparing attachments…").controlSize(.small) }
            if model.state?.status?.vision == false && model.composerDraft.hasImages {
                Text("This model cannot see images. Choose a vision model or remove the images.")
                    .font(.caption).foregroundStyle(palette.danger)
            }
            if let session = model.sessionID, model.failedDrafts[session]?.isEmpty == false {
                Button("Restore unsent message") { model.restoreFailedDraft() }
                    .help("Keeps your current draft available to restore")
            }
            formattingBar
        }
        .sheet(item: $preview) { AttachmentPreview(attachment: $0) }
        .task(id: controller.fileRequest) {
            if let session = controller.fileRequest { await loadFiles(in: session) }
        }
        .onChange(of: model.sessionID) { preview = nil }
        .onChange(of: model.state?.status?.finished) { controller.refreshFiles() }
    }

    private var formattingBar: some View {
        HStack(spacing: 12) {
            Button("Attach Files", systemImage: "paperclip") { model.chooseAttachments() }
                .labelStyle(.iconOnly).help("Attach files")
            Menu("Format", systemImage: "textformat") {
                ForEach([
                    ("Bold", "bold"), ("Italic", "italic"), ("Link", "link"), ("Heading", "heading"),
                    ("Inline Code", "code"), ("Code Block", "block"), ("Quote", "quote"),
                    ("Bullet List", "list"), ("Numbered List", "numbered")
                ], id: \.1) { label, action in
                    Button(label) { controller.apply(action) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize().help("Format message")
            Spacer()
            Text("⇧↩ New line").font(.caption2).foregroundStyle(palette.muted)
        }
        .buttonStyle(.borderless)
    }

    private var editor: some View {
        let session = model.sessionID ?? "none"
        var configuration = MarkdownPresentation.configuration(palette, colorScheme: colorScheme)
        configuration.services.bus = controller.bus
        return NativeTextViewWrapper(
            text: Binding(
                get: { model.drafts[session]?.markdown ?? "" },
                set: { model.drafts[session, default: .init()].markdown = $0 }
            ),
            configuration: configuration,
            fontSize: NSFont.systemFontSize,
            documentId: session,
            isEditable: model.sessionID != nil,
            isFocused: $focused,
            fileDrop: .init(
                action: { _, _ in .handOff },
                markdown: { _ in nil },
                handOff: { model.importFiles($0, in: session) }
            ),
            interaction: .init(
                key: { _, event in controller.key(event, model: model, session: session) },
                paste: { _, board in paste(board, session: session) },
                selection: { view, inCode in
                    controller.update(view, inCode: inCode, model: model, session: session)
                },
                openURL: { url in
                    if let path = FileReference.path(url: url) {
                        previewFile(path, session: session)
                    } else {
                        MarkdownPresentation.openExternal(url)
                    }
                    return true
                }
            ),
            placeholder: NSAttributedString(
                string: model.busy ? "Steer the conversation" : "Message Synth",
                attributes: [.foregroundColor: NSColor(palette.muted)]
            )
        )
        .frame(height: controller.height)
        .accessibilityLabel("Message")
        .overlay(alignment: .top) {
            if focused && controller.showsCompletions {
                completions
                    .visualEffect { content, geometry in
                        content.offset(y: -geometry.size.height - 8)
                    }
            }
        }
        .zIndex(1)
    }

    private var completions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.fileRequest != nil {
                ProgressView("Finding project files…").controlSize(.small)
            } else if let error = controller.fileError {
                Text(error).foregroundStyle(palette.danger).fixedSize(horizontal: false, vertical: true)
                Button("Retry") { controller.refreshFiles() }
            } else if controller.choices.isEmpty {
                Text("No matching files").foregroundStyle(palette.muted)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(controller.choices.enumerated()), id: \.element.id) { index, choice in
                                completionRow(choice, index: index)
                            }
                        }
                    }
                    .frame(height: min(5, CGFloat(controller.choices.count)) * 42)
                    .onChange(of: controller.selection) { proxy.scrollTo(controller.selection) }
                }
            }
        }
        .font(.callout)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border) }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private func completionRow(_ choice: ComposerController.Choice, index: Int) -> some View {
        Button {
            if let session = model.sessionID { controller.choose(index, model: model, session: session) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(choice.detail).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(index == controller.selection ? palette.alternateSurface : Color.clear)
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityAddTraits(index == controller.selection ? .isSelected : [])
    }

    private func loadFiles(in session: String) async {
        guard let client = model.client else { return }
        do {
            let paths = try await client.files(in: session)
            controller.receiveFiles(paths, model: model, session: session)
        } catch {
            controller.failFiles(error, session: session)
        }
    }

    private func paste(_ board: NSPasteboard, session: String) -> Bool {
        guard model.sessionID == session else { return false }
        let fileURLs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        if let fileURLs, !fileURLs.isEmpty {
            model.importFiles(fileURLs, in: session)
            return true
        }
        if let type = board.types?.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }),
           let data = board.data(forType: type) {
            model.importAttachments(in: session) { [try AttachmentImporter.image(data, name: "Pasted image")] }
            return true
        }
        guard let text = board.string(forType: .string), ComposerDraft.collapsesPaste(text) else { return false }
        guard text.utf8.count <= AttachmentImporter.textLimit else {
            model.reportDraftError(ComposerError.fileTooLarge, in: session)
            return true
        }
        let lines = text.utf8.lazy.filter { $0 == 10 }.count + 1
        model.attach([.init(name: "Pasted text (\(lines) lines)", body: .text(text))], in: session)
        return true
    }

    private func previewFile(_ path: String, session: String) {
        Task {
            do {
                let file = try model.referenceURL(path)
                let item = try await Task.detached { try AttachmentImporter.file(file) }.value
                if model.sessionID == session { preview = item }
            } catch {
                model.reportDraftError(error, in: session)
            }
        }
    }
}

struct ComposerAttachmentStrip: View {
    let model: ConversationModel
    let controller: ComposerController
    @State private var preview: ComposerAttachment?

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(model.composerDraft.attachments) { item in
                    DraftAttachmentChip(
                        item: item, open: { preview = item },
                        insert: { text in
                            if controller.insert(text) { model.removeAttachment(item.id) }
                        },
                        remove: { model.removeAttachment(item.id) }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $preview) { AttachmentPreview(attachment: $0) }
        .id(model.sessionID)
    }
}

private struct DraftAttachmentChip: View {
    @Environment(\.synthPalette) private var palette
    let item: ComposerAttachment
    let open: () -> Void
    let insert: (String) -> Void
    let remove: () -> Void
    @State private var thumbnail: CGImage?
    @State private var hovering = false
    @State private var hoverImage: CGImage?
    @State private var showsPreview = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 2).resizable().scaledToFit().frame(width: 40, height: 32)
                    } else {
                        Image(systemName: item.isImage ? "photo" : "doc.text")
                    }
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .help("Preview \(item.name)")
            if case .text(let text) = item.body {
                Button("Insert", systemImage: "text.insert") { insert(text) }
                    .labelStyle(.iconOnly).buttonStyle(.plain).help("Insert into message")
            }
            Button("Remove \(item.name)", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly).buttonStyle(.plain)
        }
        .font(.caption)
        .padding(8)
        .background(palette.alternateSurface, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .popover(isPresented: $showsPreview, arrowEdge: .top) {
            if let hoverImage {
                Image(decorative: hoverImage, scale: 2).resizable().scaledToFit()
                    .frame(width: 320, height: 240)
                    .padding(8)
                    .accessibilityLabel(item.name)
            }
        }
        .task(id: hovering) {
            showsPreview = false
            guard hovering, case .image(let data) = item.body else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch { return }
            let image = await Task.detached { AttachmentImporter.thumbnail(data, maxPixels: 640) }.value
            guard !Task.isCancelled else { return }
            hoverImage = image
            showsPreview = image != nil
        }
        .task(id: item.id) {
            guard case .image(let data) = item.body else { return }
            thumbnail = await Task.detached { AttachmentImporter.thumbnail(data, maxPixels: 96) }.value
        }
    }
}

struct AttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: ComposerAttachment

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(attachment.name).font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            switch attachment.body {
            case .text(let text):
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .image(let data):
                if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 680, minHeight: 300, idealHeight: 500)
    }
}
