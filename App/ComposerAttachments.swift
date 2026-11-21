import AppKit
import ImageIO
import SynthClient
import SynthProtocol
import UniformTypeIdentifiers

extension ConversationModel {
    var composerDraft: ComposerDraft { sessionID.flatMap { drafts[$0] } ?? .init() }
    var isImportingAttachments: Bool { sessionID.map { importingAttachments[$0, default: 0] > 0 } == true }

    func attach(_ items: [ComposerAttachment], in session: String) {
        guard openedSessions[session] != nil else { return }
        drafts[session, default: .init()].attachments.append(contentsOf: items)
    }

    func attachText(_ text: String, label: String, in session: String) {
        guard text.utf8.count <= AttachmentImporter.textLimit else {
            reportDraftError(ComposerError.fileTooLarge, in: session)
            return
        }
        let lines = text.utf8.lazy.filter { $0 == 10 }.count + 1
        let unit = lines == 1 ? "line" : "lines"
        attach([.init(name: "\(label) (\(lines) \(unit))", body: .text(text))], in: session)
    }

    func attachTerminalContext(_ text: String) {
        if let sessionID { attachText(text, label: "Terminal context", in: sessionID) }
    }

    func removeAttachment(_ id: UUID) {
        guard let sessionID else { return }
        drafts[sessionID]?.attachments.removeAll { $0.id == id }
    }

    func restoreFailedDraft() {
        guard let sessionID, let failed = failedDrafts[sessionID]?.popLast() else { return }
        if !composerDraft.isEmpty {
            failedDrafts[sessionID, default: []].insert(composerDraft, at: 0)
        }
        drafts[sessionID] = failed
    }

    func reportDraftError(_ error: any Error, in session: String) {
        guard openedSessions[session] != nil else { return }
        failures[session] = error.localizedDescription
        if sessionID == session { self.error = error.localizedDescription }
    }

    func send(in expectedSession: String? = nil) async {
        guard canSend, let client, let sessionID, expectedSession == nil || expectedSession == sessionID else { return }
        let submitted = composerDraft
        if submitted.markdown.hasPrefix("/"),
           submitted.markdown.trimmingCharacters(in: .whitespacesAndNewlines) == "/compact",
           !submitted.attachments.isEmpty {
            reportDraftError(ComposerError.compactWithAttachments, in: sessionID)
            return
        }
        do {
            try validateReferences(in: submitted)
        } catch {
            reportDraftError(error, in: sessionID)
            return
        }
        drafts[sessionID] = .init()
        failures.removeValue(forKey: sessionID)
        error = nil
        submissions[sessionID, default: 0] += 1
        defer {
            submissions[sessionID, default: 1] -= 1
            if submissions[sessionID] == 0 {
                submissions.removeValue(forKey: sessionID)
                stopping.remove(sessionID)
            }
        }
        do {
            _ = try await client.prompt(submitted.content, in: sessionID)
        } catch {
            if drafts[sessionID, default: .init()].isEmpty {
                drafts[sessionID] = submitted
            } else {
                failedDrafts[sessionID, default: []].append(submitted)
            }
            reportDraftError(error, in: sessionID)
        }
        await refresh(from: client)
        if let opened = openedSessions[sessionID] {
            await loadGroup(opened.folder, refresh: true)
        }
    }

    func compact() async {
        guard canConfigure, let sessionID, let client else { return }
        do { try await client.compact(in: sessionID) } catch { reportDraftError(error, in: sessionID) }
    }

    func importAttachments(in session: String, using load: @escaping @Sendable () throws -> [ComposerAttachment]) {
        importingAttachments[session, default: 0] += 1
        Task {
            defer {
                importingAttachments[session, default: 1] -= 1
                if importingAttachments[session] == 0 { importingAttachments.removeValue(forKey: session) }
            }
            do {
                let items = try await Task.detached(priority: .userInitiated, operation: load).value
                attach(items, in: session)
            } catch { reportDraftError(error, in: session) }
        }
    }

    func importFiles(_ urls: [URL], in session: String) {
        importAttachments(in: session) { try urls.map(AttachmentImporter.file) }
    }

    func chooseAttachments() {
        guard let sessionID else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose text files or images to attach"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.importFiles(panel.urls, in: sessionID)
        }
    }

    func referenceURL(_ path: String) throws -> URL {
        guard let root = state?.status?.root else { throw ComposerError.missingReference(path) }
        let directory = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath()
        let file = directory.appending(path: path).resolvingSymlinksInPath()
        let prefix = directory.path == "/" ? "/" : directory.path + "/"
        guard file.path.hasPrefix(prefix), FileManager.default.fileExists(atPath: file.path) else {
            throw ComposerError.missingReference(path)
        }
        return file
    }

    func validateReferences(in draft: ComposerDraft) throws {
        for path in Set(FileReference.selectedPaths(in: draft.markdown)) {
            let file = try referenceURL(path)
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw ComposerError.unsupportedFile }
            let maxBytes = FileReference.isImagePath(path) ? AttachmentImporter.imageLimit : 256 * 1024
            guard (values.fileSize ?? 0) <= maxBytes else {
                throw ComposerError.linkedFileTooLarge(path: path, limit: maxBytes)
            }
        }
    }
}

enum AttachmentImporter {
    static let imageLimit = 10 * 1024 * 1024
    static let textLimit = 1024 * 1024

    static func file(_ url: URL) throws -> ComposerAttachment {
        let fileURL = url.resolvingSymlinksInPath()
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard values.isRegularFile == true else { throw ComposerError.unsupportedFile }
        guard (values.fileSize ?? 0) <= imageLimit else { throw ComposerError.fileTooLarge }
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        let data = try file.read(upToCount: imageLimit + 1) ?? Data()
        if values.contentType?.conforms(to: .image) == true || CGImageSourceCreateWithData(data as CFData, nil) != nil {
            return try image(data, name: url.lastPathComponent)
        }
        guard data.count <= textLimit else { throw ComposerError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
              values.contentType?.conforms(to: .pdf) != true else { throw ComposerError.unsupportedFile }
        return .init(name: url.lastPathComponent, body: .text(text))
    }

    static func image(_ data: Data, name: String) throws -> ComposerAttachment {
        guard data.count <= imageLimit else { throw ComposerError.fileTooLarge }
        guard let source = imageSource(data), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ComposerError.invalidImage
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw ComposerError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ComposerError.invalidImage }
        guard png.length <= imageLimit else { throw ComposerError.fileTooLarge }
        return .init(name: name, body: .image(png as Data))
    }

    static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = imageSource(data) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary)
    }

    private static func imageSource(_ data: Data) -> CGImageSource? {
        guard data.count <= imageLimit,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000_000 / height else { return nil }
        return source
    }
}
