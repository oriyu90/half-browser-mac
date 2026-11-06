import SwiftUI

/// SwiftUI host for the CEF browser view.
///
/// The CEF engine itself lives in the Objective-C++ `cefapp` process. Until the
/// two processes are merged, this view presents the browser surface placeholder
/// and keeps the address bar / toolbar state in sync.
struct BrowserView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(appState.pageTitle)
                    .font(.headline)
                Text(appState.currentURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
