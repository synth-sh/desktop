import Foundation
import SynthProtocol

extension SynthClient {
    func receiveBrowserRequest(_ id: RequestID, envelope: Envelope) async throws {
        guard let browser else {
            try await write(.failure(id, .init(code: -32601, message: "The Synth browser is disabled.")))
            return
        }
        guard let request = try? envelope.parameters(Synth.BrowserRequest.self), browserRequests[id] == nil else {
            try await write(.failure(id, .init(code: -32602, message: "Invalid browser request.")))
            return
        }
        let generation = self.generation
        browserRequests[id] = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let result = await browser(request)
            guard !Task.isCancelled else { return }
            await self?.finishBrowserRequest(id, result: result, generation: generation)
        }
    }

    private func finishBrowserRequest(_ id: RequestID, result: Synth.BrowserResult, generation: UUID) async {
        guard self.generation == generation, browserRequests.removeValue(forKey: id) != nil else { return }
        try? await write(.reply(id, result: result))
    }
}
