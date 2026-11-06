import SwiftUI

@main
struct HalfBrowserApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Browser") {
                Button("Reload") { appState.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Home") { appState.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Back") { appState.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { appState.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

/// Global app state bridging SwiftUI and the CEF browser.
final class AppState: ObservableObject {
    @Published var currentURL: String = ""
    @Published var pageTitle: String = "Half-Browser"
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var showHome: Bool = true
    @Published var themeMode: ThemeMode = .system
    @Published var accentHue: Float = 210.0

    /// Weak reference to the browser controller for commands.
    weak var browserController: BrowserControlling?

    func navigate(to url: String) {
        guard !url.isEmpty else { return }
        showHome = false
        currentURL = url
        browserController?.loadURL(url)
    }

    func reload() { browserController?.reload() }
    func goBack() { browserController?.goBack() }
    func goForward() { browserController?.goForward() }
    func goHome() {
        showHome = true
        currentURL = ""
    }
}

enum ThemeMode: String, CaseIterable {
    case system, light, dark
}

/// Abstraction over the browser engine (CEF today, anything else later).
protocol BrowserControlling: AnyObject {
    func loadURL(_ url: String)
    func reload()
    func goBack()
    func goForward()
}
