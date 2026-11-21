import Observation
import SynthProtocol
import WebKit

enum BrowserPreference {
    static let enabled = "workspaceBrowserEnabled"
}

@MainActor
@Observable
final class BrowserTab: NSObject, WKNavigationDelegate {
    let id = UUID()
    let webView: WKWebView
    var isSelected = true
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var error: String?
    @ObservationIgnored private var navigation: WKNavigation?
    @ObservationIgnored private let contentWorld = WKContentWorld.world(name: "Synth Browser")
    @ObservationIgnored private var closed = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func httpURL(_ address: String?) -> URL? {
        guard let address, let url = URL(string: address),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func openAddress(_ text: String) {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultURL = URL(string: "https://" + address)
        let loopback = ["localhost", "127.0.0.1", "[::1]"].contains(defaultURL?.host()?.lowercased() ?? "")
        let input = address.contains("://") ? address : (loopback ? "http://" : "https://") + address
        guard let target = Self.httpURL(input) else {
            error = "Enter a valid HTTP or HTTPS address."
            return
        }
        open(target)
    }

    func goBack() { started(webView.goBack()) }
    func goForward() { started(webView.goForward()) }
    func reload() { started(webView.reload()) }

    func stop() {
        webView.stopLoading()
        navigation = nil
        isLoading = false
        error = "Navigation stopped."
    }

    func close() {
        closed = true
        stop()
        webView.navigationDelegate = nil
    }

    func run(_ request: Synth.BrowserRequest) async -> Synth.BrowserResult {
        do {
            try Task.checkCancellation()
            if request.operation == .navigate { return try await navigate(request.arguments.url) }
            try await waitForPage()
            guard url != nil else { throw Failure.message("Open a page with browser_navigate first.") }
            return try await interact(request)
        } catch {
            return .init(error.localizedDescription, isError: true)
        }
    }

    private func navigate(_ address: String?) async throws -> Synth.BrowserResult {
        guard let target = Self.httpURL(address) else { throw Failure.message("Enter an absolute HTTP or HTTPS URL.") }
        open(target)
        let startedNavigation = navigation
        do {
            try await waitForPage()
        } catch {
            if navigation != nil, navigation === startedNavigation { stop() }
            throw error
        }
        guard let url else { throw Failure.message("The page did not open.") }
        return .init("Opened \(url.absoluteString). Use browser_snapshot to inspect it.")
    }

    private func interact(_ request: Synth.BrowserRequest) async throws -> Synth.BrowserResult {
        let arguments: [String: Any] = [
            "operation": request.operation.rawValue,
            "ref": request.arguments.ref ?? "",
            "text": request.arguments.text ?? "",
            "direction": request.arguments.direction ?? ""
        ]
        let result = try await webView.callAsyncJavaScript(
            BrowserPageScript.source, arguments: arguments, in: nil, contentWorld: contentWorld
        )
        try Task.checkCancellation()
        guard !closed, let result = result as? [String: Any], let content = result["content"] as? String else {
            throw Failure.message("The page changed before the browser could finish. Take a new snapshot.")
        }
        if request.operation == .click, result["isError"] as? Bool != true {
            try await Task.sleep(for: .milliseconds(120))
            try await waitForPage()
        }
        return .init(content, isError: result["isError"] as? Bool ?? false)
    }

    private func open(_ url: URL) {
        started(webView.load(URLRequest(url: url, timeoutInterval: 25)))
    }

    private func started(_ load: WKNavigation?) {
        guard let load else { return }
        navigation = load
        error = nil
        isLoading = true
    }

    private func waitForPage() async throws {
        let deadline = ContinuousClock.now + .seconds(27)
        while isLoading {
            guard ContinuousClock.now < deadline else { throw Failure.message("The page took too long to load.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        if closed { throw Failure.message("The browser tab was closed.") }
        if let error { throw Failure.message(error) }
    }

    private func syncPage() {
        url = webView.url.flatMap { Self.httpURL($0.absoluteString) }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let address = action.request.url else { return .cancel }
        if action.shouldPerformDownload { return .cancel }
        if action.targetFrame?.isMainFrame == false,
           ["about", "blob", "data"].contains(address.scheme?.lowercased() ?? "") { return .allow }
        guard Self.httpURL(address.absoluteString) != nil else { return .cancel }
        if action.targetFrame == nil {
            started(webView.load(action.request))
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        started(navigation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncPage()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(navigation, error: error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(navigation, error: error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        navigation = nil
        isLoading = false
        error = "The page stopped responding. Reload it to continue."
    }

    private func finish(_ load: WKNavigation?, error: String? = nil) {
        guard load === navigation else { return }
        navigation = nil
        isLoading = false
        self.error = error
        syncPage()
    }

    private enum Failure: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): text
            }
        }
    }
}
