import SwiftUI

struct SynthPalette {
    let background: Color
    let surface: Color
    let alternateSurface: Color
    let foreground: Color
    let muted: Color
    let accent: Color
    let success: Color
    let danger: Color
    let border: Color
    let diffAddedBackground: Color
    let diffAddedForeground: Color
    let diffRemovedBackground: Color
    let diffRemovedForeground: Color
}

struct SynthTheme: Identifiable {
    let id: String
    let name: String
    let colorScheme: ColorScheme
    let palette: SynthPalette

    static func resolve(_ id: String) -> SynthTheme {
        all.first { $0.id == id } ?? defaultTheme
    }

    // IDs and palettes come from synth/src/tui/themes.zig.
    static let defaultTheme = SynthTheme(
        id: "synth", name: "Synth", colorScheme: .dark,
        palette: SynthPalette(
            background: .init(rgb: 0x1C1E25), surface: .init(rgb: 0x22242C), alternateSurface: .init(rgb: 0x3A332E),
            foreground: .init(rgb: 0xE7E5DD), muted: .init(rgb: 0x8B8E99), accent: .init(rgb: 0xE8A33D),
            success: .init(rgb: 0x5FC9A8), danger: .init(rgb: 0xE2695B), border: .init(rgb: 0x34363F),
            diffAddedBackground: .init(rgb: 0x212829), diffAddedForeground: .init(rgb: 0x6FA88C),
            diffRemovedBackground: .init(rgb: 0x2B2326), diffRemovedForeground: .init(rgb: 0xC77B72)
        )
    )

    static let all = [
        defaultTheme,
        SynthTheme(
            id: "tokyonight", name: "Tokyo Night", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x1A1B26), surface: .init(rgb: 0x1E2030), alternateSurface: .init(rgb: 0x222436),
                foreground: .init(rgb: 0xC8D3F5), muted: .init(rgb: 0x9AA5CE), accent: .init(rgb: 0x82AAFF),
                success: .init(rgb: 0xC3E88D), danger: .init(rgb: 0xFF757F), border: .init(rgb: 0x3B4261),
                diffAddedBackground: .init(rgb: 0x20303B), diffAddedForeground: .init(rgb: 0xC8D3F5),
                diffRemovedBackground: .init(rgb: 0x37222C), diffRemovedForeground: .init(rgb: 0xC8D3F5)
            )
        ),
        SynthTheme(
            id: "catppuccin", name: "Catppuccin", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x1E1E2E), surface: .init(rgb: 0x181825), alternateSurface: .init(rgb: 0x11111B),
                foreground: .init(rgb: 0xCDD6F4), muted: .init(rgb: 0xA6ADC8), accent: .init(rgb: 0x89B4FA),
                success: .init(rgb: 0xA6E3A1), danger: .init(rgb: 0xF38BA8), border: .init(rgb: 0x45475A),
                diffAddedBackground: .init(rgb: 0x24312B), diffAddedForeground: .init(rgb: 0xCDD6F4),
                diffRemovedBackground: .init(rgb: 0x3C2A32), diffRemovedForeground: .init(rgb: 0xCDD6F4)
            )
        ),
        SynthTheme(
            id: "gruvbox", name: "Gruvbox", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x282828), surface: .init(rgb: 0x3C3836), alternateSurface: .init(rgb: 0x504945),
                foreground: .init(rgb: 0xEBDBB2), muted: .init(rgb: 0xB4A692), accent: .init(rgb: 0x83A598),
                success: .init(rgb: 0xB8BB26), danger: .init(rgb: 0xFB4934), border: .init(rgb: 0x504945),
                diffAddedBackground: .init(rgb: 0x32302F), diffAddedForeground: .init(rgb: 0xEBDBB2),
                diffRemovedBackground: .init(rgb: 0x322929), diffRemovedForeground: .init(rgb: 0xEBDBB2)
            )
        ),
        SynthTheme(
            id: "nord", name: "Nord", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x2E3440), surface: .init(rgb: 0x3B4252), alternateSurface: .init(rgb: 0x434C5E),
                foreground: .init(rgb: 0xECEFF4), muted: .init(rgb: 0xB6BCCB), accent: .init(rgb: 0x88C0D0),
                success: .init(rgb: 0xA3BE8C), danger: .init(rgb: 0xBF616A), border: .init(rgb: 0x434C5E),
                diffAddedBackground: .init(rgb: 0x414A4C), diffAddedForeground: .init(rgb: 0xECEFF4),
                diffRemovedBackground: .init(rgb: 0x453B47), diffRemovedForeground: .init(rgb: 0xECEFF4)
            )
        ),
        SynthTheme(
            id: "rose-pine", name: "Rosé Pine", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x191724), surface: .init(rgb: 0x1F1D2E), alternateSurface: .init(rgb: 0x26233A),
                foreground: .init(rgb: 0xE0DEF4), muted: .init(rgb: 0x988BA2), accent: .init(rgb: 0x9CCFD8),
                success: .init(rgb: 0x31748F), danger: .init(rgb: 0xEB6F92), border: .init(rgb: 0x403D52),
                diffAddedBackground: .init(rgb: 0x1F2D3A), diffAddedForeground: .init(rgb: 0xE0DEF4),
                diffRemovedBackground: .init(rgb: 0x3A1F2D), diffRemovedForeground: .init(rgb: 0xE0DEF4)
            )
        ),
        SynthTheme(
            id: "one-dark", name: "One Dark", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x282C34), surface: .init(rgb: 0x21252B), alternateSurface: .init(rgb: 0x353B45),
                foreground: .init(rgb: 0xABB2BF), muted: .init(rgb: 0x9AA3B3), accent: .init(rgb: 0x61AFEF),
                success: .init(rgb: 0x98C379), danger: .init(rgb: 0xE06C75), border: .init(rgb: 0x3E4451),
                diffAddedBackground: .init(rgb: 0x2C382B), diffAddedForeground: .init(rgb: 0xABB2BF),
                diffRemovedBackground: .init(rgb: 0x3A2D2F), diffRemovedForeground: .init(rgb: 0xABB2BF)
            )
        ),
        SynthTheme(
            id: "everforest", name: "Everforest", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x2D353B), surface: .init(rgb: 0x333C43), alternateSurface: .init(rgb: 0x343F44),
                foreground: .init(rgb: 0xD3C6AA), muted: .init(rgb: 0xA8B1A3), accent: .init(rgb: 0xA7C080),
                success: .init(rgb: 0xA7C080), danger: .init(rgb: 0xE67E80), border: .init(rgb: 0x4F585E),
                diffAddedBackground: .init(rgb: 0x20303B), diffAddedForeground: .init(rgb: 0xD3C6AA),
                diffRemovedBackground: .init(rgb: 0x37222C), diffRemovedForeground: .init(rgb: 0xD3C6AA)
            )
        ),
        SynthTheme(
            id: "dracula", name: "Dracula", colorScheme: .dark,
            palette: SynthPalette(
                background: .init(rgb: 0x282A36), surface: .init(rgb: 0x21222C), alternateSurface: .init(rgb: 0x44475A),
                foreground: .init(rgb: 0xF8F8F2), muted: .init(rgb: 0xA1A8C8), accent: .init(rgb: 0xBD93F9),
                success: .init(rgb: 0x50FA7B), danger: .init(rgb: 0xFF5555), border: .init(rgb: 0x44475A),
                diffAddedBackground: .init(rgb: 0x1A3A1A), diffAddedForeground: .init(rgb: 0xF8F8F2),
                diffRemovedBackground: .init(rgb: 0x3A1A1A), diffRemovedForeground: .init(rgb: 0xF8F8F2)
            )
        ),
        SynthTheme(
            id: "github-light", name: "GitHub Light", colorScheme: .light,
            palette: SynthPalette(
                background: .init(rgb: 0xFFFFFF), surface: .init(rgb: 0xF6F8FA), alternateSurface: .init(rgb: 0xF0F3F6),
                foreground: .init(rgb: 0x24292F), muted: .init(rgb: 0x424B53), accent: .init(rgb: 0x0969DA),
                success: .init(rgb: 0x1A7F37), danger: .init(rgb: 0xCF222E), border: .init(rgb: 0xD0D7DE),
                diffAddedBackground: .init(rgb: 0xDAFBE1), diffAddedForeground: .init(rgb: 0x24292F),
                diffRemovedBackground: .init(rgb: 0xFFEBE9), diffRemovedForeground: .init(rgb: 0x24292F)
            )
        ),
        SynthTheme(
            id: "solarized-light", name: "Solarized Light", colorScheme: .light,
            palette: SynthPalette(
                background: .init(rgb: 0xFDF6E3), surface: .init(rgb: 0xEEE8D5), alternateSurface: .init(rgb: 0xEEE8D5),
                // Solarized's terminal text colors are too faint on the desktop's raised surfaces.
                foreground: .init(rgb: 0x40545A), muted: .init(rgb: 0x4D6269), accent: .init(rgb: 0x0969A2),
                success: .init(rgb: 0x859900), danger: .init(rgb: 0xB5252B), border: .init(rgb: 0xD8D0BD),
                diffAddedBackground: .init(rgb: 0xEAE7BF), diffAddedForeground: .init(rgb: 0x4D6269),
                diffRemovedBackground: .init(rgb: 0xF8D7C6), diffRemovedForeground: .init(rgb: 0x4D6269)
            )
        )
    ]
}

extension EnvironmentValues {
    @Entry var synthPalette = SynthTheme.defaultTheme.palette
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

struct SynthProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.synthPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isEnabled ? palette.background : palette.muted)
            .modifier(SynthButtonBackground(
                idle: isEnabled ? palette.accent : palette.border,
                hovered: palette.accent.opacity(0.9),
                pressed: palette.accent.opacity(0.78),
                isPressed: configuration.isPressed
            ))
    }
}

struct SynthButtonBackground: ViewModifier {
    let idle: Color
    let hovered: Color
    let pressed: Color
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var fill: Color {
        guard isEnabled else { return idle }
        if isPressed { return pressed }
        return isHovered ? hovered : idle
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = inside
                }
            }
    }
}
