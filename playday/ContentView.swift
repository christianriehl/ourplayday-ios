import SwiftUI
import UIKit

struct ContentView: View {
    let incomingURL: URL?

    @State private var isLoading = false
    @State private var pageTitle: String?
    @State private var reloadTrigger = 0
    @State private var currentURL = AppConfiguration.baseURL
    @State private var lastError: ErrorState?

    init(incomingURL: URL? = nil) {
        self.incomingURL = incomingURL
    }

    var body: some View {
        Group {
            if let currentURL {
                ZStack(alignment: .top) {
                    WebView(
                        url: currentURL,
                        isLoading: $isLoading,
                        pageTitle: $pageTitle,
                        reloadTrigger: $reloadTrigger,
                        onNavigationEvent: handleNavigationEvent,
                        onNavigationFailure: handleNavigationFailure,
                        requestBuilder: buildRequest(for:),
                        enablePullToRefresh: true,
                        enableConsoleBridge: true
                    )

                    if isLoading {
                        loadingOverlay
                    }

                    if let lastError {
                        errorOverlay(lastError)
                    }
                }
                .ignoresSafeArea(.all)
                .onOpenURL(perform: updateURL(for:))
                .onChange(of: incomingURL) { _, newValue in
                    if let newValue {
                        updateURL(for: newValue)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    WebView.clearMemoryCache()
                }
            } else {
                configurationErrorView
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text(pageTitle ?? "PlayDay wird geladen")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Seite wird geladen")
    }

    private func errorOverlay(_ error: ErrorState) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(error.title)
                .font(.headline)
            Text(error.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Erneut versuchen", action: retryCurrentPage)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Seite erneut laden")
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    private var configurationErrorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)
            Text("App-Konfiguration fehlt")
                .font(.headline)
            Text("Die Start-URL ist ungültig. Bitte prüfe den Eintrag PLAYDAY_BASE_URL in der Info.plist.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func handleNavigationEvent(_ event: WebView.NavigationEvent) {
        switch event {
        case .started:
            lastError = nil
        default:
            break
        }
    }

    private func handleNavigationFailure(_ failure: WebView.NavigationFailure) {
        lastError = ErrorState(error: failure.error)
    }

    private func retryCurrentPage() {
        lastError = nil
        reloadTrigger += 1
    }

    private func buildRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadRevalidatingCacheData
        return request
    }

    private func updateURL(for incomingURL: URL) {
        currentURL = AppConfiguration.resolvedWebURL(for: incomingURL)
        lastError = nil
        reloadTrigger += 1
    }
}

private extension ContentView {
    struct ErrorState: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        init(error: Error) {
            let nsError = error as NSError

            if nsError.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: nsError.code) {
                case .notConnectedToInternet:
                    title = "Keine Internetverbindung"
                    message = "Sobald wieder eine Verbindung besteht, kannst du die Seite direkt erneut laden."
                case .timedOut:
                    title = "Laden dauert zu lange"
                    message = "Der Request ist in ein Timeout gelaufen. Ein erneuter Versuch hilft oft."
                case .cannotFindHost, .cannotConnectToHost:
                    title = "Server nicht erreichbar"
                    message = "Die App konnte den Server gerade nicht erreichen. Bitte versuche es erneut."
                default:
                    title = "Seite konnte nicht geladen werden"
                    message = nsError.localizedDescription
                }
            } else {
                title = "Seite konnte nicht geladen werden"
                message = nsError.localizedDescription
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
