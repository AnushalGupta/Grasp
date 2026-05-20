import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var state: BrowserState
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // 1. Add Compiled Adblocking Rules
        if state.adblockEnabled {
            if let ruleList = AdBlockerManager.shared.activeRuleList {
                configuration.userContentController.add(ruleList)
                print("[WebView] Loaded Active Adblocker Rules into web configuration.")
            }
        }
        
        // 2. Add Media Grabber Message Handler
        configuration.userContentController.add(context.coordinator, name: "mediaGrabber")
        
        // 3. Inject Client-side JavaScript
        let script = WKUserScript(
            source: MediaGrabberScript.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(script)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Custom configurations
        webView.customUserAgent = DownloadManager.shared.userAgent
        
        // Save weak reference to webView in coordinator for notification triggers
        context.coordinator.webView = webView
        
        // Track page progress
        context.coordinator.setupProgressObserver(for: webView)
        
        // Load initial tab request
        if let url = tab.url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If the URL in State was updated outside the WebView (e.g. from the URL Bar)
        if let tabUrl = tab.url, uiView.url != tabUrl {
            let request = URLRequest(url: tabUrl)
            uiView.load(request)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?
        private var progressObserver: NSKeyValueObservation?
        
        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            
            // Subscribe to web page movement triggers
            NotificationCenter.default.addObserver(self, selector: #selector(handleWebBack), name: Notification.Name("GraspWebBack"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleWebForward), name: Notification.Name("GraspWebForward"), object: nil)
        }
        
        func setupProgressObserver(for webView: WKWebView) {
            progressObserver = webView.observe(\\WKWebView.estimatedProgress, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.tab.estimatedProgress = webView.estimatedProgress
                }
            }
        }
        
        @objc func handleWebBack() {
            DispatchQueue.main.async { [weak self] in
                if let wv = self?.webView, wv.canGoBack {
                    wv.goBack()
                }
            }
        }
        
        @objc func handleWebForward() {
            DispatchQueue.main.async { [weak self] in
                if let wv = self?.webView, wv.canGoForward {
                    wv.goForward()
                }
            }
        }
        
        // MARK: - Navigation Delegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.tab.isLoading = true
                self.parent.tab.canGoBack = webView.canGoBack
                self.parent.tab.canGoForward = webView.canGoForward
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.tab.isLoading = false
                self.parent.tab.title = webView.title ?? webView.url?.host ?? "Grasp Browser"
                self.parent.tab.url = webView.url
                self.parent.tab.canGoBack = webView.canGoBack
                self.parent.tab.canGoForward = webView.canGoForward
                
                if let urlString = webView.url?.absoluteString {
                    self.parent.state.addHistory(url: urlString)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.tab.isLoading = false
            }
        }
        
        // MARK: - Script Message Handler (Intercepting Javascript Events)
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mediaGrabber" else { return }
            guard let dict = message.body as? [String: Any] else { return }
            
            guard let urlStr = dict["url"] as? String, let url = URL(string: urlStr) else { return }
            let title = dict["title"] as? String ?? "Grabbed Stream"
            let type = dict["type"] as? String ?? "video/mp4"
            let action = dict["action"] as? String ?? ""
            
            print("[WebView Message] Intercepted stream payload: \\(urlStr), Action: \\(action)")
            
            // Add to captured media list in global state
            parent.state.addCapturedMedia(url: url, title: title, type: type)
            
            // If the user long pressed/right clicked, display immediate prompt
            if action == "long_press" || action == "context_menu" {
                DispatchQueue.main.async {
                    // Trigger dynamic download trigger in ContentView via notification
                    NotificationCenter.default.post(
                        name: Notification.Name("GraspShowDownloadPrompt"),
                        object: nil,
                        userInfo: ["url": url, "title": title, "type": type]
                    )
                }
            }
        }
        
        deinit {
            progressObserver?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
