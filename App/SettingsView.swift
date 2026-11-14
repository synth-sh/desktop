import SwiftUI

struct SettingsView: View {
    @Binding var theme: String

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Color.clear
            }
            Tab("Themes", systemImage: "paintpalette") {
                ThemePicker(selection: $theme)
            }
        }
        .frame(width: 536, height: 340)
    }
}

private struct ThemePicker: View {
    @Binding var selection: String

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
