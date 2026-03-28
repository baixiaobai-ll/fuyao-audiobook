import WebKit

/// Loads chapter content from JS-protected novel sites using WKWebView
@MainActor
class ChapterWebLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var pollCount = 0
    private let maxPolls = 20

    func loadContent(from url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.pollCount = 0

            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812), configuration: config)
            wv.navigationDelegate = self
            self.webView = wv
            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.pollForContent() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        Task { @MainActor in self.finish(.failure(error)) }
    }

    // MARK: - Private

    private func pollForContent() {
        pollCount += 1
        if pollCount > maxPolls {
            finish(.failure(NSError(domain: "ChapterWebLoader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "加载超时，请稍后重试"])))
            return
        }

        webView?.evaluateJavaScript("""
            (function(){
                var el = document.getElementById('content');
                if(el && el.innerText && el.innerText.trim().length > 50){
                    return el.innerText.trim();
                }
                return null;
            })()
        """) { [weak self] result, _ in
            guard let self else { return }
            if let text = result as? String, !text.isEmpty {
                self.finish(.success(text))
            } else {
                // Page not ready yet, poll again after 1.5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.pollForContent()
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        webView?.navigationDelegate = nil
        webView = nil
        let c = continuation
        continuation = nil
        switch result {
        case .success(let t): c?.resume(returning: t)
        case .failure(let e): c?.resume(throwing: e)
        }
    }
}
