import SwiftUI
import WebKit

struct BrowserWorkspaceView: View {
    let tab: BrowserTab
    @State private var address = ""
    @FocusState private var editingAddress: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = tab.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Divider()
            }
            BrowserWebView(webView: tab.webView)
                .overlay {
                    if tab.url == nil && !tab.isLoading {
                        ContentUnavailableView(
                            "Open a Page", systemImage: "globe",
                            description: Text("Enter an address or ask Synth to open one.")
                        )
                        .background(.background)
                    }
                }
        }
        .onChange(of: tab.url, initial: true) {
            if !editingAddress { address = tab.url?.absoluteString ?? "" }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Go Back", systemImage: "chevron.left", action: tab.goBack)
                .disabled(!tab.canGoBack)
                .help("Go Back")
            Button("Go Forward", systemImage: "chevron.right", action: tab.goForward)
                .disabled(!tab.canGoForward)
                .help("Go Forward")
            if tab.isLoading {
                Button("Stop Loading", systemImage: "xmark", action: tab.stop)
                    .help("Stop Loading")
            } else {
                Button("Reload Page", systemImage: "arrow.clockwise", action: tab.reload)
                    .disabled(tab.url == nil)
                    .help("Reload Page")
            }
            TextField("Enter an address", text: $address)
                .focused($editingAddress)
                .onSubmit {
                    editingAddress = false
                    tab.openAddress(address)
                }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
