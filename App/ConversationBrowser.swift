import SynthClient
import SynthProtocol

extension ConversationModel {
    var currentBrowser: BrowserTab? {
        sessionID.flatMap { browserTabs[$0] }
    }

    var browserHandler: SynthClient.BrowserHandler? {
        guard browserEnabled else { return nil }
        return { [weak self] request in
            guard let self, !self.isShuttingDown, self.openedSessions[request.sessionId] != nil else {
                return .init("This chat's browser is unavailable.", isError: true)
            }
            if request.operation == .navigate, BrowserTab.httpURL(request.arguments.url) != nil {
                return await self.openBrowser(in: request.sessionId).run(request)
            }
            guard let tab = self.browserTabs[request.sessionId] else {
                return .init("Open an HTTP or HTTPS URL with browser_navigate first.", isError: true)
            }
            return await tab.run(request)
        }
    }

    private func openBrowser(in sessionID: String) -> BrowserTab {
        if let tab = browserTabs[sessionID] { return tab }
        let tab = BrowserTab()
        browserTabs[sessionID] = tab
        return tab
    }

    func selectBrowser() {
        guard browserEnabled, let sessionID else { return }
        openBrowser(in: sessionID).isSelected = true
    }

    func closeBrowser(in sessionID: String) {
        browserTabs.removeValue(forKey: sessionID)?.close()
    }

    func closeBrowsers() {
        for tab in browserTabs.values { tab.close() }
        browserTabs.removeAll()
    }
}
