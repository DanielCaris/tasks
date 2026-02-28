import SwiftUI
import WebKit
import AppKit

/// Vista que renderiza HTML enriquecido con soporte para imágenes de Jira (carga autenticada).
struct RichHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: String
    let jiraEmail: String?
    let jiraToken: String?
    var colorScheme: ColorScheme = .light

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
        webView.appearance = NSApp.effectiveAppearance
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = colorScheme == .dark || NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        context.coordinator.isDark = isDark
        webView.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        let textColor = isDark ? "#ffffff" : "#1d1d1f"
        let linkColor = "#64d2ff"

        let fullHTML = """
        <!DOCTYPE html>
        <html lang="es">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta id="dark-mode" content="\(isDark ? "1" : "0")">
        <style>
        *{color:\(textColor) !important;}
        a{color:\(linkColor) !important;}
        html,body{margin:0;padding:0;background:transparent !important;}
        </style>
        </head>
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
        var isDark = false

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let color = isDark ? "#ffffff" : "#1d1d1f"
            let script = """
            (function(){
                document.body.style.color='\(color)';
                document.body.style.backgroundColor='transparent';
                var all=document.querySelectorAll('*');
                for(var i=0;i<all.length;i++){
                    var el=all[i];
                    if(el.tagName!=='A'){el.style.color='\(color)';}
                }
                var links=document.querySelectorAll('a');
                for(var j=0;j<links.length;j++){links[j].style.color='#64d2ff';}
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

/// Resuelve URLs jira-image://id cargando el attachment con autenticación.
private final class JiraImageURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let baseURL: String
    private let email: String
    private let apiToken: String

    init(baseURL: String, email: String, apiToken: String) {
        var url = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        self.baseURL = url
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
        let contentURL = "\(baseURL)/rest/api/3/attachment/content/\(mediaId)?redirect=false"
        guard let downloadURL = URL(string: contentURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"]))
            return
        }
        var request = URLRequest(url: downloadURL)
        let credentials = "\(email):\(apiToken)"
        if let credData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida"]))
                return
            }
            if httpResponse.statusCode == 303, let location = httpResponse.value(forHTTPHeaderField: "Location"), let redirectURL = URL(string: location) {
                var redirectRequest = URLRequest(url: redirectURL)
                if let credData = credentials.data(using: .utf8) {
                    redirectRequest.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
                URLSession.shared.dataTask(with: redirectRequest) { redirectData, redirectResponse, redirectError in
                    if let redirectError = redirectError {
                        urlSchemeTask.didFailWithError(redirectError)
                        return
                    }
                    guard let redirectData = redirectData,
                          let r = redirectResponse as? HTTPURLResponse,
                          (200...299).contains(r.statusCode) else {
                        urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"]))
                        return
                    }
                    let mimeType = r.mimeType ?? "image/png"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: redirectData.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(redirectData)
                    urlSchemeTask.didFinish()
                }.resume()
            } else if (200...299).contains(httpResponse.statusCode), let data = data {
                let mimeType = httpResponse.mimeType ?? "image/png"
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"]))
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
