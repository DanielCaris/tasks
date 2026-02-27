import SwiftUI
import WebKit
import AppKit

/// Vista que renderiza HTML enriquecido con soporte para imágenes de Jira (carga autenticada).
struct RichHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: String
    let jiraEmail: String?
    let jiraToken: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let email = jiraEmail, let token = jiraToken, !token.isEmpty {
            let handler = JiraImageURLSchemeHandler(baseURL: baseURL, email: email, apiToken: token)
            config.setURLSchemeHandler(handler, forURLScheme: "jira-image")
        }
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>\(html)</body>
        </html>
        """
        let base = URL(string: baseURL) ?? URL(string: "https://example.atlassian.net")!
        webView.loadHTMLString(fullHTML, baseURL: base)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               (url.scheme == "http" || url.scheme == "https") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// Resuelve URLs jira-image://id cargando el attachment con autenticación.
private final class JiraImageURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let baseURL: String
    private let email: String
    private let apiToken: String

    init(baseURL: String, email: String, apiToken: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.email = email
        self.apiToken = apiToken
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "jira-image" else {
            urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"]))
            return
        }
        let mediaId = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !mediaId.isEmpty else {
            urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "ID de media vacío"]))
            return
        }
        let contentURL = "\(baseURL)/rest/api/3/attachment/content/\(mediaId)"
        guard let downloadURL = URL(string: contentURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"]))
            return
        }
        var request = URLRequest(url: downloadURL)
        let credentials = "\(email):\(apiToken)"
        if let data = credentials.data(using: .utf8) {
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"]))
                return
            }
            let mimeType = response.mimeType ?? "image/png"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
