import SwiftUI
import os
import UIKit
import WebKit

public struct WebView: UIViewRepresentable {
    public enum NavigationEvent {
        case started(URL?)
        case finished(URL?)
        case decided(url: URL, policy: WKNavigationActionPolicy)
        case externalNavigation(URL)
    }

    public enum NavigationErrorContext {
        case provisionalNavigation(URL?)
        case committedNavigation(URL?)
    }

    public struct NavigationFailure {
        public let error: Error
        public let context: NavigationErrorContext

        public init(error: Error, context: NavigationErrorContext) {
            self.error = error
            self.context = context
        }
    }

    public typealias UIViewType = WKWebView
    private static let consoleBridgeHandlerName = "consoleBridge"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "playday", category: "WebView")

    // Inputs/Outputs
    public let url: URL
    @Binding public var isLoading: Bool
    @Binding public var pageTitle: String?
    @Binding public var reloadTrigger: Int

    // Callbacks / Injectables
    public var onDecidePolicy: ((URL) -> WKNavigationActionPolicy)?
    public var onError: ((Error) -> Void)?
    public var onNavigationEvent: ((NavigationEvent) -> Void)?
    public var onNavigationFailure: ((NavigationFailure) -> Void)?
    public var configurationProvider: (() -> WKWebViewConfiguration)?
    public var requestBuilder: ((URL) -> URLRequest)?

    public var enablePullToRefresh: Bool = false
    public var enableConsoleBridge: Bool = false

    public init(
        url: URL,
        isLoading: Binding<Bool> = .constant(false),
        pageTitle: Binding<String?> = .constant(nil),
        reloadTrigger: Binding<Int> = .constant(0),
        onDecidePolicy: ((URL) -> WKNavigationActionPolicy)? = nil,
        onError: ((Error) -> Void)? = nil,
        onNavigationEvent: ((NavigationEvent) -> Void)? = nil,
        onNavigationFailure: ((NavigationFailure) -> Void)? = nil,
        configurationProvider: (() -> WKWebViewConfiguration)? = nil,
        requestBuilder: ((URL) -> URLRequest)? = nil,
        enablePullToRefresh: Bool = false,
        enableConsoleBridge: Bool = false
    ) {
        self.url = url
        self._isLoading = isLoading
        self._pageTitle = pageTitle
        self._reloadTrigger = reloadTrigger
        self.onDecidePolicy = onDecidePolicy
        self.onError = onError
        self.onNavigationEvent = onNavigationEvent
        self.onNavigationFailure = onNavigationFailure
        self.configurationProvider = configurationProvider
        self.requestBuilder = requestBuilder
        self.enablePullToRefresh = enablePullToRefresh
        self.enableConsoleBridge = enableConsoleBridge
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = configurationProvider?() ?? defaultConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        context.coordinator.lastReloadTrigger = reloadTrigger

        // Pull to refresh
        if enablePullToRefresh {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefreshControl(_:)), for: .valueChanged)
            webView.scrollView.refreshControl = refreshControl
            context.coordinator.refreshControl = refreshControl
        }

        // Initial load
        load(url: url, in: webView, coordinator: context.coordinator)
        return webView
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        let target = url.absoluteString
        let reloadRequested = context.coordinator.lastReloadTrigger != reloadTrigger

        if reloadRequested {
            context.coordinator.lastReloadTrigger = reloadTrigger
            load(url: url, in: uiView, coordinator: context.coordinator)
            return
        }

        if context.coordinator.isDisplayingOrNavigating(to: target, in: uiView) {
            return
        }

        load(url: url, in: uiView, coordinator: context.coordinator)
    }

    private func load(url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.pendingURLString = url.absoluteString
        let request = requestBuilder?(url) ?? URLRequest(url: url)
        webView.load(request)
    }

    private func defaultConfiguration(coordinator: Coordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        } else {
            config.requiresUserActionForMediaPlayback = false
        }

        if enableConsoleBridge {
            // Console bridge script (main frame only)
            let js = """
            (function() {
                function serialize(value) {
                    if (typeof value === 'string') { return value; }
                    try { return JSON.stringify(value); } catch (_) { return String(value); }
                }

                function send(level, args) {
                    try {
                        var message = Array.prototype.slice.call(args).map(serialize).join(' ');
                        var meta = { level: level, url: document.location.href, stack: (new Error()).stack || '' };
                        window.webkit.messageHandlers.consoleBridge.postMessage({ message: message, meta: meta });
                    } catch (bridgeError) {
                        try {
                            var fallback = console.warn || console.log;
                            if (fallback) {
                                fallback.call(console, '[consoleBridge]', bridgeError && bridgeError.message ? bridgeError.message : String(bridgeError));
                            }
                        } catch (_) {}
                    }
                }

                function wrap(level) {
                    var original = console[level];
                    console[level] = function() {
                        send(level, arguments);
                        if (original) { try { original.apply(console, arguments); } catch (_) {} }
                    };
                }

                ['log', 'warn', 'error'].forEach(wrap);

                window.addEventListener('error', function(event) {
                    send('error', [event.message, event.filename, event.lineno + ':' + event.colno]);
                });

                window.addEventListener('unhandledrejection', function(event) {
                    var reason = event.reason && event.reason.message ? event.reason.message : String(event.reason);
                    send('error', ['Unhandled promise rejection', reason]);
                });
            })();
            """
            let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(userScript)
            config.userContentController.add(WeakScriptMessageHandler(delegate: coordinator), name: Self.consoleBridgeHandlerName)
        }

        return config
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private static let transientErrorCodes: Set<URLError.Code> = [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed
        ]

        private let maxAutomaticRetryCount = 1
        var parent: WebView
        var refreshControl: UIRefreshControl?
        var lastReloadTrigger: Int = 0
        var pendingURLString: String?
        private weak var webView: WKWebView?
        private var estimatedProgressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var retryCounts: [String: Int] = [:]

        init(parent: WebView) {
            self.parent = parent
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            estimatedProgressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.isLoading = webView.estimatedProgress < 1.0
                }
            }
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.pageTitle = webView.title
                }
            }
        }

        func detach(from webView: WKWebView) {
            refreshControl?.endRefreshing()
            refreshControl = nil
            pendingURLString = nil
            estimatedProgressObservation?.invalidate()
            estimatedProgressObservation = nil
            titleObservation?.invalidate()
            titleObservation = nil
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.scrollView.refreshControl = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebView.consoleBridgeHandlerName)
            self.webView = nil
        }

        func isDisplayingOrNavigating(to targetURLString: String, in webView: WKWebView) -> Bool {
            if pendingURLString == targetURLString {
                return true
            }

            return webView.url?.absoluteString == targetURLString
        }

        // Navigation delegate
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onNavigationEvent?(.started(webView.url))
            DispatchQueue.main.async { self.parent.isLoading = true }
        }
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pendingURLString = nil
            if let loadedURL = webView.url?.absoluteString {
                retryCounts[loadedURL] = 0
            }
            parent.onNavigationEvent?(.finished(webView.url))
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.pageTitle = webView.title
                self.endRefreshingIfNeeded()
            }
        }
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(error, context: .committedNavigation(webView.url), webView: webView)
        }
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(error, context: .provisionalNavigation(webView.url), webView: webView)
        }
        private func handleError(_ error: Error, context: NavigationErrorContext, webView: WKWebView) {
            pendingURLString = nil
            let nsError = error as NSError
            let domain = nsError.domain
            let code = nsError.code
            let failing = webView.url?.absoluteString ?? "unknown"

            if scheduleRetryIfNeeded(for: nsError, failingURLString: failing, webView: webView) {
                WebView.logger.notice("Retrying navigation after transient error for \(failing, privacy: .public)")
                return
            }

            WebView.logger.error("Navigation error domain=\(domain, privacy: .public) code=\(code) url=\(failing, privacy: .public) description=\(nsError.localizedDescription, privacy: .public)")
            parent.onNavigationFailure?(NavigationFailure(error: error, context: context))
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.endRefreshingIfNeeded()
            }
            parent.onError?(error)
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if let policy = parent.onDecidePolicy?(url) {
                parent.onNavigationEvent?(.decided(url: url, policy: policy))
                if policy == .cancel, navigationAction.navigationType == .linkActivated {
                    parent.onNavigationEvent?(.externalNavigation(url))
                }
                // If consumer cancels, they may choose to open externally.
                decisionHandler(policy)
            } else {
                parent.onNavigationEvent?(.decided(url: url, policy: .allow))
                decisionHandler(.allow)
            }
        }

        // JS console bridge
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "consoleBridge",
                  let body = message.body as? [String: Any],
                  let text = body["message"] as? String,
                  let meta = body["meta"] as? [String: Any],
                  let level = meta["level"] as? String else { return }
            let url = meta["url"] as? String ?? "unknown"
            let stack = meta["stack"] as? String ?? ""
            WebView.logger.log(level: logLevel(for: level), "[JS] \(text, privacy: .public) url=\(url, privacy: .public) stack=\(stack, privacy: .public)")
        }

        // Pull to refresh
        @objc func handleRefreshControl(_ sender: UIRefreshControl) {
            guard let webView else {
                sender.endRefreshing()
                return
            }

            if webView.isLoading {
                webView.stopLoading()
            }

            if !sender.isRefreshing {
                sender.beginRefreshing()
            }

            webView.reload()
        }

        public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            presentDialog(
                in: webView,
                title: webView.title,
                message: message,
                actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }],
                fallback: completionHandler
            )
        }

        public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            presentDialog(
                in: webView,
                title: webView.title,
                message: message,
                actions: [
                    UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(false) },
                    UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }
                ],
                fallback: { completionHandler(false) }
            )
        }

        public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let presenter = topPresenter(for: webView) else {
                completionHandler(defaultText)
                return
            }

            let alert = UIAlertController(title: webView.title, message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }

        deinit {
            if let webView {
                detach(from: webView)
            }
        }

        private func endRefreshingIfNeeded() {
            if let refreshControl, refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
        }

        private func scheduleRetryIfNeeded(for error: NSError, failingURLString: String, webView: WKWebView) -> Bool {
            guard error.domain == NSURLErrorDomain else {
                return false
            }

            let code = URLError.Code(rawValue: error.code)
            guard Self.transientErrorCodes.contains(code) else {
                return false
            }

            let attempts = retryCounts[failingURLString, default: 0]
            guard attempts < maxAutomaticRetryCount else {
                return false
            }

            retryCounts[failingURLString] = attempts + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.parent.isLoading = true
                webView.reload()
            }
            return true
        }

        private func logLevel(for level: String) -> OSLogType {
            switch level.lowercased() {
            case "warn":
                return .default
            case "error":
                return .error
            default:
                return .info
            }
        }

        private func presentDialog(in webView: WKWebView, title: String?, message: String, actions: [UIAlertAction], fallback: @escaping () -> Void) {
            guard let presenter = topPresenter(for: webView) else {
                fallback()
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach(alert.addAction)
            presenter.present(alert, animated: true)
        }

        private func topPresenter(for webView: WKWebView) -> UIViewController? {
            if let root = webView.window?.rootViewController {
                return topMostViewController(from: root)
            }

            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)

            return topMostViewController(from: keyWindow?.rootViewController)
        }

        private func topMostViewController(from controller: UIViewController?) -> UIViewController? {
            if let navigationController = controller as? UINavigationController {
                return topMostViewController(from: navigationController.visibleViewController)
            }

            if let tabBarController = controller as? UITabBarController {
                return topMostViewController(from: tabBarController.selectedViewController)
            }

            if let presentedViewController = controller?.presentedViewController {
                return topMostViewController(from: presentedViewController)
            }

            return controller
        }
    }

    public static func clearMemoryCache() {
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {
            logger.notice("Cleared WKWebView memory cache after memory warning")
        }
    }

    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var delegate: WKScriptMessageHandler?

        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }
}
