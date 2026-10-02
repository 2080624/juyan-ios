//
//  WebShellViewController.swift
//  网页壳：WKWebView 装网页 + 和网页打交道的小桥。
//
//  网页那边（App.tsx）会往 window.webkit.messageHandlers.jy 发一条
//    { type: "auth", uid, name, token }
//  我们收到就存下来，配合 deviceToken 上报到服务端 —— 服务端才知道
//  「这个账号要推到哪台设备」。
//
import UIKit
import WebKit

final class WebShellViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {

    /// 主地址 + 备用地址，第一个打不开自动换下一个
    private let hosts = [
        "https://jysl.pw/",
        "https://xn--czry41hlbaz17d.icu/",
        "http://jysl.pw/",
    ]
    private var hostIndex = 0
    private var webView: WKWebView!
    private var loadingTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        conf.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = WKUserContentController()
        ucc.add(self, name: "jy")
        conf.userContentController = ucc

        webView = WKWebView(frame: view.bounds, configuration: conf)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        // 键盘弹出时页面别被顶飞
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)

        NotificationCenter.default.addObserver(self, selector: #selector(openConv(_:)),
                                               name: .jyOpenConv, object: nil)
        loadHost(0)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        loadingTimer?.invalidate()
    }

    // MARK: - 加载

    private func loadHost(_ index: Int) {
        hostIndex = min(max(index, 0), hosts.count - 1)
        guard let url = URL(string: hosts[hostIndex]) else { return }
        print("[jy] load", url.absoluteString)
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
        startWatchdog()
    }

    /// 25 秒还没加载完就换下一个地址（机场 wifi 很烂的时候很有用）
    private func startWatchdog() {
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.webView.isLoading {
                print("[jy] 超时，换下一个地址")
                self.loadHost(self.hostIndex + 1)
            }
        }
    }

    // MARK: - 点推送通知进来

    @objc private func openConv(_ note: Notification) {
        let conv = (note.userInfo?["conv"] as? String) ?? ""
        guard !conv.isEmpty else { return }
        // 网页那边认 ?c=<会话id>，直接在聊天窗口打开它
        openConversation(conv)
    }

    /// 打开指定会话：已经进过网页就用 JS 换地址，重载后前端会自动落到那个聊天
    func openConversation(_ convId: String) {
        let path = "/?c=\(convId)"
        if let base = URL(string: hosts[hostIndex]), let url = URL(string: path, relativeTo: base) {
            print("[jy] open conv", url.absoluteString)
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - 网页递过来的消息

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "jy", let body = message.body as? [String: Any] else { return }
        guard (body["type"] as? String) == "auth" else { return }
        AppDelegate.authUID = (body["uid"] as? String) ?? ""
        AppDelegate.authToken = (body["token"] as? String) ?? ""
        PushRegistrar.reportIfReady()

        // 会话名字顺便记一下，通知里能写「谁发来的」
        if let name = body["name"] as? String, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "jy_last_name")
        }
    }

    // MARK: - 导航

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingTimer?.invalidate()
        injectHelper()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingTimer?.invalidate()
        retryOnce()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingTimer?.invalidate()
        retryOnce()
    }

    private var retried = false
    private func retryOnce() {
        if retried { return }
        retried = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            self.loadHost(self.hostIndex + 1)
        }
    }

    /// 注入一个小工具对象：网页里可以 window.JyNative.postMessage("...") 递消息
    /// （走的是跟 messageHandlers.jy 同一套逻辑，两代写法都留着）
    private func injectHelper() {
        let js = """
        (function () {
          if (window.JyNative) return;
          window.JyNative = {
            postMessage: function (s) {
              try { window.webkit.messageHandlers.jy.postMessage(JSON.parse(s)); } catch (e) {}
            },
            openConv: function (id) {
              try { window.webkit.messageHandlers.jy.postMessage({ type: 'open', conv: String(id) }); } catch (e) {}
            }
          };
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - 新窗口 / 相册 / 麦克风

    @available(iOS 14.0, *)
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 网页里 target=_blank 的链接，别开新窗口，直接用当前窗口打开
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // 语音 / 视频通话要放行麦克风、摄像头
        decisionHandler(.grant)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
