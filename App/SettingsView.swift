import SwiftUI
import UserNotifications

enum SettingsPage: Hashable { case modelsAndMCP, appearance, browser, notifications }

struct SettingsView: View {
    @Binding var theme: String
    @Bindable var model: ConversationModel

    var body: some View {
        TabView(selection: $model.settingsPage) {
            Tab("Models & MCP", systemImage: "slider.horizontal.3", value: .modelsAndMCP) {
                EngineSettings(model: model)
            }
            Tab("Appearance", systemImage: "paintpalette", value: .appearance) {
                AppearanceSettings(selection: $theme)
            }
            Tab("Browser", systemImage: "globe", value: .browser) {
                BrowserSettings()
            }
            Tab("Notifications", systemImage: "bell", value: .notifications) {
                NotificationSettings(notifications: model.notifications)
            }
        }
        .frame(width: model.settingsPage == .modelsAndMCP ? 660 : 536, height: settingsHeight)
    }

    private var settingsHeight: CGFloat {
        switch model.settingsPage {
        case .modelsAndMCP: 465
        case .appearance: 390
        case .browser: 180
        case .notifications: 340
        }
    }
}

private struct BrowserSettings: View {
    @AppStorage(BrowserPreference.enabled) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable the built-in browser", isOn: $enabled)
            } footer: {
                Text("Turning this off removes the Browser tab and its tools. Restart Synth to apply the change.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationSettings: View {
    let notifications: ConversationNotifications
    @AppStorage(NotificationPreference.toasts) private var toasts = true
    @AppStorage(NotificationPreference.system) private var system = true
    @AppStorage(NotificationPreference.input) private var input = true
    @AppStorage(NotificationPreference.outcomes) private var outcomes = true
    @AppStorage(NotificationPreference.sound) private var sound = NotificationSound.both

    var body: some View {
        Form {
            Section("Delivery") {
                Toggle("In-app toasts", isOn: $toasts)
                Toggle("macOS notifications", isOn: $system)
                if system {
                    LabeledContent("macOS permission") {
                        permission
                    }
                }
                Picker("Play sounds", selection: $sound) {
                    ForEach(NotificationSound.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Section {
                Toggle("Permission requests and questions", isOn: $input)
                Toggle("Turn outcomes and engine errors", isOn: $outcomes)
            } header: {
                Text("Alert Events")
            } footer: {
                Text("Sidebar dots mark unseen activity.")
            }
        }
        .formStyle(.grouped)
        .task { await notifications.refreshSystemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refreshSystemStatus() }
        }
    }

    @ViewBuilder
    private var permission: some View {
        switch notifications.systemStatus {
        case .notDetermined:
            VStack(alignment: .trailing) {
                Button("Enable macOS Notifications") { Task { await notifications.authorize() } }
                if let error = notifications.authorizationError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        case .denied:
            Text("Denied in System Settings").foregroundStyle(.secondary)
        case .authorized, .provisional:
            Text("Allowed").foregroundStyle(.secondary)
        case nil:
            ProgressView().controlSize(.small)
        default:
            Text("Unavailable").foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceSettings: View {
    @Binding var selection: String
    @AppStorage(WorkspaceTerminalPreference.useThemeBackground) private var useThemeBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a theme for the conversation window.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                ForEach(SynthTheme.all) { theme in
                    let selected = SynthTheme.resolve(selection).id == theme.id
                    Button {
                        selection = theme.id
                    } label: {
                        VStack(spacing: 5) {
                            ThemeSwatch(palette: theme.palette)
                                .overlay(alignment: .topTrailing) {
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.palette.background, theme.palette.foreground)
                                            .padding(5)
                                    }
                                }
                            Text(theme.name).font(.callout)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Divider()
            Toggle("Match terminal background to app theme", isOn: $useThemeBackground)
                .toggleStyle(.switch)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ThemeSwatch: View {
    let palette: SynthPalette

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                bar(palette.accent, width: 15)
                bar(palette.muted, width: 10)
            }
            .frame(width: 28, height: 54)
            .background(palette.surface)

            VStack(alignment: .leading, spacing: 5) {
                bar(palette.foreground, width: 27)
                bar(palette.muted, width: 19)
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(palette.border))
                    .frame(height: 11)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(palette.background)
        }
        .frame(height: 54)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .accessibilityHidden(true)
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: 3)
    }
}
