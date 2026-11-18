import Foundation

public enum FileReference {
    private static let prefix = "synth-file://project/"
    private static let safeURLCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
    private static let punctuation = CharacterSet(charactersIn: ",;:)]}!?\"'")
    private static let links = try? NSRegularExpression(pattern:
        #"\[@(?:\\.|[^\]\\\r\n])*\]\(synth-file://project/([^\s)]+)\)"#
    )
    private static let mentions = try? NSRegularExpression(pattern:
        #"(?<![^ \t\r\n(\[{])@(?:"([^"\r\n]+)"|([^ \t\r\n"]+))"#
    )
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    public static func canMention(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("\"") &&
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    public static func markdown(path: String) -> String {
        let label = path.reduce(into: "@") { result, character in
            if "\\[]*_`~".contains(character) { result.append("\\") }
            result.append(character)
        }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: safeURLCharacters) ?? ""
        return "[\(label)](\(prefix)\(encoded))"
    }

    public static func path(url: URL) -> String? {
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        return String(url.absoluteString.dropFirst(prefix.count)).removingPercentEncoding
    }

    public static func selectedPaths(in markdown: String) -> [String] {
        links(in: markdown).map(\.path)
    }

    public static func prompt(_ markdown: String) -> String {
        var result = markdown
        for link in links(in: markdown).reversed() {
            guard let range = Range(link.range, in: result) else { continue }
            let needsQuotes = link.path.contains(where: \.isWhitespace) ||
                link.path.unicodeScalars.last.map(punctuation.contains) == true
            result.replaceSubrange(range, with: needsQuotes ? "@\"\(link.path)\"" : "@\(link.path)")
        }
        return result
    }

    public static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    public static func mentionsImage(in text: String) -> Bool {
        mentions(in: text).contains { isImagePath($0.path) }
    }

    public static func transcript(
        _ text: String, attachedPaths: Set<String>, excluding codeRanges: [NSRange]
    ) -> String {
        var result = text
        for mention in mentions(in: text).reversed() where attachedPaths.contains(mention.path) {
            guard !codeRanges.contains(where: { NSIntersectionRange($0, mention.range).length > 0 }),
                  let range = Range(mention.range, in: result) else { continue }
            result.replaceSubrange(range, with: markdown(path: mention.path))
        }
        return result
    }

    private static func links(in text: String) -> [(range: NSRange, path: String)] {
        guard text.contains(prefix), let links else { return [] }
        let source = text as NSString
        return links.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard let path = source.substring(with: match.range(at: 1)).removingPercentEncoding,
                  canMention(path) else { return nil }
            return (match.range, path)
        }
    }

    private static func mentions(in text: String) -> [(range: NSRange, path: String)] {
        guard text.contains("@"), let mentions else { return [] }
        let source = text as NSString
        return mentions.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let quoted = match.range(at: 1)
            if quoted.location != NSNotFound { return (match.range, source.substring(with: quoted)) }
            let bare = match.range(at: 2)
            let value = source.substring(with: bare)
            let scalars = value.unicodeScalars
            guard let last = scalars.lastIndex(where: { !punctuation.contains($0) }) else { return nil }
            let path = String(scalars[...last])
            return (NSRange(location: match.range.location, length: path.utf16.count + 1), path)
        }
    }
}
