import SwiftUI

struct CheckoutContext: View {
    @Environment(\.synthPalette) private var palette
    let root: String
    let branch: String

    var body: some View {
        HStack(spacing: 12) {
            Label((root as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .help(root)
                .accessibilityLabel("Working directory \(root)")
            if !branch.isEmpty {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                    .help(branch)
                    .accessibilityLabel("Git branch \(branch)")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(palette.muted)
        .frame(maxWidth: 780)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
}
