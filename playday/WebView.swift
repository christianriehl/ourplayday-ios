import SwiftUI
import WebKit

public struct WebView: UIViewRepresentable {
    public typealias UIViewType = WKWebView
    private static let consoleBridgeHandlerName = "consoleBridge"

    // Inputs/Outputs
    public let url: URL
    @Binding public var isLoading: Bool
    @Binding public var pageTitle: String?
    @Binding public var reloadTrigger: Int

    // Callbacks / Injectables
    public var onDecidePolicy: ((URL) -> WKNavigationActionPolicy)?
    public var onError: ((Error) -> Void)?
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
                function wrap(level) {
                    var original = console[level];
                    console[level] = function() {
                        try {
                            var msg = Array.prototype.slice.call(arguments).map(String).join(' ');
                            var meta = { level: level, url: document.location.href, stack: (new Error()).stack || '' };
                            window.webkit.messageHandlers.consoleBridge.postMessage({ message: msg, meta: meta });
                        } catch (e) {}
                        if (original) { try { original.apply(console, arguments); } catch (e) {} }
                    };
                }
                ['log','warn','error'].forEach(wrap);
            })();
            """
            let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(userScript)
            config.userContentController.add(WeakScriptMessageHandler(delegate: coordinator), name: Self.consoleBridgeHandlerName)
        }

        return config
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        var refreshControl: UIRefreshControl?
        var lastReloadTrigger: Int = 0
        var pendingURLString: String?
        private weak var webView: WKWebView?
        private var estimatedProgressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?

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
            DispatchQueue.main.async { self.parent.isLoading = true }
        }
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pendingURLString = nil
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.pageTitle = webView.title
                if let rc = self.refreshControl, rc.isRefreshing { rc.endRefreshing() }
            }
        }
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(error, webView: webView)
        }
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(error, webView: webView)
        }
        private func handleError(_ error: Error, webView: WKWebView) {
            pendingURLString = nil
            let nsError = error as NSError
            let domain = nsError.domain
            let code = nsError.code
            let failing = webView.url?.absoluteString ?? "unknown"
            NSLog("WebView navigation error: domain=\(domain), code=\(code), url=\(failing), description=\(nsError.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
                if let rc = self.refreshControl, rc.isRefreshing { rc.endRefreshing() }
            }
            parent.onError?(error)
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if let policy = parent.onDecidePolicy?(url) {
                // If consumer cancels, they may choose to open externally.
                decisionHandler(policy)
            } else {
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
            NSLog("[JS] \(level.uppercased()) - \(text)\nURL: \(url)\nStack: \(stack)")
        }

        // Pull to refresh
        @objc func handleRefreshControl(_ sender: UIRefreshControl) {
            sender.beginRefreshing()
            if let webView = sender.superview as? WKWebView {
                webView.reload()
            } else {
                sender.endRefreshing()
            }
        }

        deinit {
            if let webView {
                detach(from: webView)
            }
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
