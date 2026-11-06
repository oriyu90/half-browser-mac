import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var addressText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: { appState.goHome() }) {
                    Image(systemName: "house")
                }
                .buttonStyle(.borderless)
                .help("Home (⇧⌘H)")

                Button(action: { appState.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.canGoBack)
                .help("Back (⌘[)")

                Button(action: { appState.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.canGoForward)
                .help("Forward (⌘])")

                Button(action: { appState.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload (⌘R)")

                // Address bar
                TextField("Search or enter URL", text: $addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        appState.navigate(to: normalize(addressText))
                    }
                    .onChange(of: appState.currentURL) { _, newValue in
                        if !newValue.isEmpty {
                            addressText = newValue
                        }
                    }

                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Browser content area
            ZStack {
                if appState.showHome {
                    HomeView()
                } else {
                    BrowserView()
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(appState.pageTitle)
    }

    /// Normalize address-bar input into a URL (mirrors Rust UrlNormalizer behavior).
    private func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.contains(" ") {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            return "https://duckduckgo.com/?q=\(encoded)"
        }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }
}

struct HomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Half-Browser")
                .font(.largeTitle)
            Text("Bookmarks are managed from the Bookmarks menu.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("General").tabItem { Label("General", systemImage: "gear") }
            Text("Appearance").tabItem { Label("Appearance", systemImage: "paintbrush") }
            Text("Security").tabItem { Label("Security", systemImage: "lock") }
            Text("Backup").tabItem { Label("Backup", systemImage: "arrow.up.arrow.down") }
        }
        .frame(width: 500, height: 400)
    }
}