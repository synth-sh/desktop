import AppKit
import Observation
import SynthClient
import UserNotifications

enum NotificationSound: String, CaseIterable {
    case both, inApp, macOS, off

    var title: String {
        switch self {
        case .both: "Both"
        case .inApp: "In app"
        case .macOS: "macOS only"
        case .off: "Off"
        }
    }

    var playsInApp: Bool { self == .both || self == .inApp }
    var playsInMacOS: Bool { self == .both || self == .macOS }
}

enum NotificationPreference {
    static let toasts = "notificationToasts"
    static let system = "notificationSystem"
    static let input = "notificationInput"
    static let outcomes = "notificationOutcomes"
    static let sound = "notificationSound"

    static func enabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static var soundLocation: NotificationSound {
        UserDefaults.standard.string(forKey: sound).flatMap(NotificationSound.init(rawValue:)) ?? .both
    }
}

struct ConversationAlert: Identifiable {
    let id = UUID().uuidString
    let event: SynthClient.AttentionEvent
    let chatTitle: String
    let folder: URL?

    var sessionID: String { event.sessionID }

    var title: String {
        switch event.kind {
        case .permission: "Permission needed"
        case .question: "Question needs an answer"
        case .turnCompleted: "Turn completed"
        case .turnCancelled: "Turn cancelled"
        case .turnFailed: "Turn failed"
        case .turnHalted: "Turn stopped at an engine limit"
        case .sessionStopped: "Synth engine stopped"
        case .inputResolved: ""
        }
    }

    var isEnabled: Bool {
        NotificationPreference.enabled(
            event.kind.requestID == nil ? NotificationPreference.outcomes : NotificationPreference.input
        )
    }
}

@MainActor
@Observable
final class ConversationNotifications: NSObject, UNUserNotificationCenterDelegate {
    private(set) var unseen: [String: ConversationAlert] = [:]
    private(set) var toast: ConversationAlert?
    private(set) var systemStatus: UNAuthorizationStatus?
    private(set) var authorizationError: String?
    private var expiration: Task<Void, Never>?
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var openConversation: ((String, URL?) -> Void)?
    @ObservationIgnored var showWindow: (() -> Void)?
    private var selectedSession: String?
    private var pendingSystem: Set<String> = []

    private var center: UNUserNotificationCenter { .current() }
    private var isConversationActive: Bool {
        NSApp.isActive && window?.isKeyWindow == true &&
            window?.isVisible == true && window?.isMiniaturized == false
    }

    func select(_ sessionID: String?) {
        selectedSession = sessionID
        focusChanged()
    }

    func focusChanged() {
        if !isConversationActive, toast != nil { toast = nil }
        if isConversationActive, let selectedSession { acknowledge(selectedSession) }
    }

    func receive(_ event: SynthClient.AttentionEvent, title: String?, folder: URL?) {
        if case .inputResolved(let request) = event.kind {
            if unseen[event.sessionID]?.event.kind.requestID == request { acknowledge(event.sessionID) }
            return
        }
        acknowledge(event.sessionID)
        guard !isConversationActive || selectedSession != event.sessionID else { return }
        let alert = ConversationAlert(event: event, chatTitle: title ?? "Untitled conversation", folder: folder)
        unseen[event.sessionID] = alert
        guard alert.isEnabled else { return }
        if isConversationActive {
            showToast(alert)
        } else if NotificationPreference.enabled(NotificationPreference.system) {
            Task { await deliver(alert) }
        }
    }

    func acknowledge(_ sessionID: String) {
        guard let alert = unseen[sessionID] else { return }
        unseen.removeValue(forKey: sessionID)
        if toast?.id == alert.id { toast = nil }
        if pendingSystem.remove(alert.id) != nil { removeSystemAlert(alert.id) }
    }

    private func showToast(_ alert: ConversationAlert) {
        guard NotificationPreference.enabled(NotificationPreference.toasts) else { return }
        toast = alert
        if NotificationPreference.soundLocation.playsInApp { NSSound.beep() }
        expiration?.cancel()
        expiration = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            self?.toast = nil
        }
    }

    func open(_ sessionID: String, folder: URL?) {
        NSApp.activate()
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            showWindow?()
        }
        openConversation?(sessionID, folder)
    }

    func refreshSystemStatus() async {
        systemStatus = await center.notificationSettings().authorizationStatus
    }

    func authorize() async {
        authorizationError = nil
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorizationError = error.localizedDescription
        }
        await refreshSystemStatus()
    }

    private func isCurrent(_ alert: ConversationAlert) -> Bool {
        unseen[alert.sessionID]?.id == alert.id && (!isConversationActive || selectedSession != alert.sessionID)
    }

    private func deliver(_ alert: ConversationAlert) async {
        let settings = await center.notificationSettings()
        guard isCurrent(alert), alert.isEnabled,
              NotificationPreference.enabled(NotificationPreference.system) else { return }
        if isConversationActive {
            showToast(alert)
            return
        }
        let authorization = settings.authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = "Open Synth to view the conversation."
        content.userInfo["sessionID"] = alert.sessionID
        content.userInfo["folder"] = alert.folder?.path
        if NotificationPreference.soundLocation.playsInMacOS { content.sound = .default }
        pendingSystem.insert(alert.id)
        do {
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
        } catch {
            pendingSystem.remove(alert.id)
        }
        if !isCurrent(alert) { removeSystemAlert(alert.id) }
    }

    private func removeSystemAlert(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        let id = request.identifier
        guard let sessionID = request.content.userInfo["sessionID"] as? String else { return [] }
        return await MainActor.run {
            guard let alert = unseen[sessionID], alert.id == id, isCurrent(alert), alert.isEnabled else {
                return []
            }
            if isConversationActive {
                pendingSystem.remove(id)
                showToast(alert)
                return []
            }
            guard NotificationPreference.enabled(NotificationPreference.system) else { return [] }
            return NotificationPreference.soundLocation.playsInMacOS
                ? [.banner, .list, .sound] : [.banner, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let sessionID = response.notification.request.content.userInfo["sessionID"] as? String else { return }
        let folder = (response.notification.request.content.userInfo["folder"] as? String)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        await open(sessionID, folder: folder)
    }
}

extension ConversationModel {
    func openFromNotification(_ identifier: String, folder: URL?) async {
        await restore()
        while isOpening && !isShuttingDown {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard canSwitch else { return }
        if sessionID != identifier {
            let known = openedSessions[identifier]
            let group = groups.first { $0.sessions.contains { $0.id == identifier } }
            let stored = group?.sessions.first { $0.id == identifier }
            await open(in: known?.folder ?? group?.folder ?? folder, stored: stored, identifier: identifier)
        }
    }
}
