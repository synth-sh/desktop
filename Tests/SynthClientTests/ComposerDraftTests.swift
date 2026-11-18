import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test func fileReferenceFormatsRoundTripThroughPromptsAndTranscripts() {
    let path = "docs/é plan [v2]!.md"
    let reference = FileReference.markdown(path: path)
    let prompt = FileReference.prompt("Compare \(reference), @missing.txt. mail@example.com")
    #expect(prompt == "Compare @\"\(path)\", @missing.txt. mail@example.com")
    #expect(FileReference.selectedPaths(in: reference) == [path])
    #expect(FileReference.transcript(prompt, attachedPaths: [path, "example.com"], excluding: []) ==
            "Compare \(reference), @missing.txt. mail@example.com")
    let literal = "`Use @\"\(path)\" literally`"
    #expect(FileReference.transcript(
        literal, attachedPaths: [path], excluding: [NSRange(literal.startIndex..., in: literal)]
    ) == literal)
}

@Test func attachmentOnlyDraftIsSendable() throws {
    let draft = ComposerDraft(attachments: [.init(name: "pasted", body: .text("body"))])
    #expect(!draft.isEmpty)
    let request = ACP.Prompt(sessionID: "chat", content: draft.content)
    let encoded = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(request))
    #expect(encoded["prompt"] == .array([
        .object(["type": .string("text"), "text": .string("")]),
        .object(["type": .string("resource"), "resource": .object(["uri": .string("pasted"), "text": .string("body")])])
    ]))
}

@Test func pasteThresholdsUseUTF8AndLineCount() {
    #expect(ComposerDraft.collapsesPaste("one\r\ntwo\r\nthree\r\nfour"))
    #expect(ComposerDraft.collapsesPaste(String(repeating: "é", count: 200)))
    #expect(!ComposerDraft.collapsesPaste("one\ntwo\nthree"))
}
