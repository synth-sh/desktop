import AppKit
import Sparkle
import SwiftUI
import UserNotifications

@main
struct SynthApp: App {
    @NSApplicationDelegateAdaptor(SynthAppDelegate.self) private var delegate
    @AppStorage("themeID") private var themeID = SynthTheme.defaultTheme.id

    private var theme: SynthTheme { SynthTheme.resolve(themeID) }

    var body: some Scene {
        Window("Synth", id: "conversation") {
            ConversationView(model: delegate.model)
                .frame(minWidth: 640, minHeight: 500)
                .containerBackground(theme.palette.background, for: .window)
                .environment(\.synthPalette, theme.palette)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.palette.accent)
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Synth") { AboutPanel.show() }
                if let updater = delegate.updaterController?.updater {
                    CheckForUpdatesButton(updater: updater)
                } else {
                    Button("Check for Updates…") {}.disabled(true)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Conversation", systemImage: "square.and.pencil") {
                    Task { await delegate.model.open() }
                }
                .keyboardShortcut("n")
                .disabled(!delegate.model.canSwitch)

                Button("Open Project…", systemImage: "folder") {
                    delegate.model.chooseProject()
                }
                .keyboardShortcut("o")
                .disabled(!delegate.model.canSwitch)
            }
        }
        Settings {
            SettingsView(theme: $themeID, model: delegate.model)
        }
    }
}

private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @State private var canCheckForUpdates = false

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!canCheckForUpdates)
            .onReceive(updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])) {
                canCheckForUpdates = $0
            }
    }
}

@MainActor
final class SynthAppDelegate: NSObject, NSApplicationDelegate {
    let model = ConversationModel()
    let updaterController: SPUStandardUpdaterController? = {
        // Builds without update configuration should not start Sparkle.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()
    private var terminating = false
    private var terminalFocusMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminalFocusMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: WorkspaceTerminalView.releaseFocusOnOutsideClick
        )
        let notifications = model.notifications
        UNUserNotificationCenter.current().delegate = notifications
        notifications.openConversation = { [weak model] identifier, folder in
            Task { await model?.openFromNotification(identifier, folder: folder) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let terminalFocusMonitor { NSEvent.removeMonitor(terminalFocusMonitor) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            if model.anyBusy {
                let confirmation = NSAlert()
                confirmation.messageText = "Quit Synth?"
                confirmation.informativeText =
                    "Quitting will stop active work unless another client is attached."
                confirmation.addButton(withTitle: "Keep Working")
                confirmation.addButton(withTitle: "Quit Synth")
                guard confirmation.runModal() == .alertSecondButtonReturn else {
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
