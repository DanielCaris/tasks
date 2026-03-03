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
    /// Hex del color de texto (ej: "1d1d1f"). Si se pasa, se usa en vez de NSColor.labelColor para coincidir con SwiftUI.
    var labelColorHex: String? = nil
    var onCheckboxToggle: ((Int, Bool) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let email = jiraEmail, let token = jiraToken, !token.isEmpty {
            let handler = JiraImageURLSchemeHandler(baseURL: baseURL, email: email, apiToken: token)
            config.setURLSchemeHandler(handler, forURLScheme: "jira-image")
        }
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.userContentController.add(context.coordinator, name: "checkboxToggled")
        config.userContentController.add(context.coordinator, name: "doubleClick")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.appearance = NSApp.effectiveAppearance
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = colorScheme == .dark || NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        webView.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        let textColor: String
        if let hex = labelColorHex, !hex.isEmpty {
            textColor = hex.hasPrefix("#") ? hex : "#\(hex)"
        } else {
            let labelColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            labelColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            textColor = String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        }
        let linkColor = "#64d2ff"

        context.coordinator.isDark = isDark
        context.coordinator.textColorHex = textColor
        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onDoubleClick = onDoubleClick

        let adfBorder = isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.2)"
        let adfSecondary = isDark ? "rgba(255,255,255,0.65)" : "rgba(0,0,0,0.6)"
        let adfCodeBg = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)"
        let adfInlineCodeBg = isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.08)"
        let adfMentionBg = isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.06)"
        let adfPanelBg = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.04)"

        let fullHTML = """
        <!DOCTYPE html>
        <html lang="es">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta id="dark-mode" content="\(isDark ? "1" : "0")">
        <style>
        :root{--adf-text:\(textColor);--adf-border:\(adfBorder);--adf-secondary:\(adfSecondary);--adf-code-bg:\(adfCodeBg);--adf-inline-code-bg:\(adfInlineCodeBg);--adf-link:\(linkColor);--adf-mention-bg:\(adfMentionBg);--adf-panel-info:\(adfPanelBg);--adf-panel-note:\(adfPanelBg);--adf-panel-success:\(adfPanelBg);--adf-panel-warning:\(adfPanelBg);--adf-panel-error:\(adfPanelBg);--adf-panel-default:\(adfPanelBg);}
        *{color:\(textColor) !important;}
        a{color:\(linkColor) !important;}
        html,body{margin:0;padding:0;background:transparent !important;}
        .adf-content{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:14px;line-height:1.5; color:var(--adf-text);margin:0;padding:0;}
        .adf-content p{margin:0 0 0.15em;}
        .adf-content h1{margin:0.25em 0 0.05em;font-size:1.25em;font-weight:500;}
        .adf-content h2{margin:0.25em 0 0.05em;font-size:1.1em;font-weight:500;}
        .adf-content h3{margin:0.25em 0 0.05em;font-size:1em;font-weight:500;}
        .adf-content h4,.adf-content h5,.adf-content h6{margin:0.25em 0 0.05em;font-size:0.9em;font-weight:500;}
        .adf-content hr{margin:0.2em 0;border:none;border-top:1px solid var(--adf-border);}
        .adf-content blockquote{margin:0.25em 0;padding-left:1em;border-left:4px solid var(--adf-border);color:var(--adf-secondary);}
        .adf-content pre{margin:0.25em 0;padding:12px;background:var(--adf-code-bg);border-radius:6px;overflow-x:auto;font-family:"SF Mono",Monaco,monospace;font-size:13px;color:var(--adf-text);}
        .adf-content ol{margin:0.25em 0;padding-left:1.6em;list-style-type:decimal;list-style-position:outside;}
        .adf-content ul.adf-task-list{margin:0.25em 0;padding-left:0;margin-left:0;list-style:none;}
        .adf-content ul.adf-task-list>li{margin:0.2em 0;display:flex;align-items:flex-start;}
        .adf-content .adf-task-checkbox-wrap{display:inline-flex;align-items:center;min-height:1.5em;}
        .adf-content .adf-task-checkbox{margin:0 8px 0 0;cursor:pointer;}
        .adf-content .adf-task-text{flex:1;line-height:1.5;}
        .adf-content ul.adf-bullet-list{margin:0.25em 0;padding-left:1.4em;list-style-type:disc;list-style-position:outside;}
        .adf-content ul.adf-bullet-list>li,.adf-content ol>li{margin:0.1em 0;}
        .adf-content .adf-inline-code{background:var(--adf-inline-code-bg);padding:2px 4px;border-radius:3px;font-family:monospace;font-size:0.9em;color:var(--adf-text);}
        .adf-content .adf-mention{background:var(--adf-mention-bg);padding:1px 4px;border-radius:3px;color:var(--adf-text);}
        .adf-content .adf-panel{margin:0.25em 0;padding:12px;border-radius:6px;}
        .adf-content .adf-panel-info{background:var(--adf-panel-info);}
        .adf-content .adf-panel-note{background:var(--adf-panel-note);}
        .adf-content .adf-panel-success{background:var(--adf-panel-success);}
        .adf-content .adf-panel-warning{background:var(--adf-panel-warning);}
        .adf-content .adf-panel-error{background:var(--adf-panel-error);}
        .adf-content .adf-panel-default{background:var(--adf-panel-default);}
        .adf-content table{border-collapse:collapse;width:100%;margin:0.25em 0;}
        .adf-content th,.adf-content td{border:1px solid var(--adf-border);padding:8px;}
        .adf-content .adf-media{margin:0.25em 0;}
        .adf-content .adf-media-unavailable{padding:24px;background:var(--adf-code-bg);border-radius:6px;color:var(--adf-secondary);font-size:13px;}
        .adf-content .adf-img{max-width:100%;height:auto;border-radius:4px;}
        .adf-content details{margin:0.25em 0;}
        .adf-content summary{cursor:pointer;font-weight:500;}
        .adf-content .adf-expand-body{margin-top:0.25em;}
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        let base = URL(string: baseURL) ?? URL(string: "https://example.atlassian.net")!
        webView.loadHTMLString(fullHTML, baseURL: base)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCheckboxToggle: onCheckboxToggle, onDoubleClick: onDoubleClick)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var isDark = false
        var textColorHex = "#1d1d1f"
        var onCheckboxToggle: ((Int, Bool) -> Void)?
        var onDoubleClick: (() -> Void)?

        init(onCheckboxToggle: ((Int, Bool) -> Void)? = nil, onDoubleClick: (() -> Void)? = nil) {
            self.onCheckboxToggle = onCheckboxToggle
            self.onDoubleClick = onDoubleClick
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "checkboxToggled",
               let body = message.body as? [String: Any],
               let index = body["index"] as? Int,
               let checked = body["checked"] as? Bool {
                DispatchQueue.main.async { [weak self] in
                    self?.onCheckboxToggle?(index, checked)
                }
            } else if message.name == "doubleClick" {
                DispatchQueue.main.async { [weak self] in
                    self?.onDoubleClick?()
                }
            }
        }

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
            let color = textColorHex
            let script = """
            (function(){
                if(!document.body)return;
                document.body.style.color='\(color)';
                document.body.style.backgroundColor='transparent';
                var all=document.querySelectorAll('*');
                for(var i=0;i<all.length;i++){
                    var el=all[i];
                    if(el.tagName!=='A'){el.style.color='\(color)';}
                }
                var links=document.querySelectorAll('a');
                for(var j=0;j<links.length;j++){links[j].style.color='#64d2ff';}
                var checkboxes=document.querySelectorAll('.adf-task-checkbox');
                for(var k=0;k<checkboxes.length;k++){
                    (function(cb){
                        cb.onclick=function(e){e.stopPropagation();};
                        cb.onchange=function(){
                            var idx=parseInt(this.getAttribute('data-task-index'),10);
                            if(!isNaN(idx)&&window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.checkboxToggled){
                                window.webkit.messageHandlers.checkboxToggled.postMessage({index:idx,checked:this.checked});
                            }
                        };
                    })(checkboxes[k]);
                }
                document.body.ondblclick=function(){
                    if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.doubleClick){
                        window.webkit.messageHandlers.doubleClick.postMessage({});
                    }
                };
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
    private let stoppedTaskIds = NSLock()
    private var stoppedIds = Set<ObjectIdentifier>()

    init(baseURL: String, email: String, apiToken: String) {
        var url = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        self.baseURL = url
        self.email = email
        self.apiToken = apiToken
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        stoppedTaskIds.lock()
        defer { stoppedTaskIds.unlock() }
        return stoppedIds.contains(ObjectIdentifier(task as AnyObject))
    }

    private func markStopped(_ task: WKURLSchemeTask) {
        stoppedTaskIds.lock()
        stoppedIds.insert(ObjectIdentifier(task as AnyObject))
        stoppedTaskIds.unlock()
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
        #if DEBUG
        print("[JiraImage] jira-image://\(mediaId) → intentando attachment/content")
        #endif
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
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if self.isStopped(urlSchemeTask) { return }
            if let error = error {
                if !self.isStopped(urlSchemeTask) { urlSchemeTask.didFailWithError(error) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                if !self.isStopped(urlSchemeTask) { urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida"])) }
                return
            }
            if httpResponse.statusCode == 303, let location = httpResponse.value(forHTTPHeaderField: "Location"), let redirectURL = URL(string: location) {
                #if DEBUG
                print("[JiraImage] jira-image://\(mediaId) → 303 redirect a \(redirectURL.absoluteString)")
                #endif
                var redirectRequest = URLRequest(url: redirectURL)
                if let credData = credentials.data(using: .utf8) {
                    redirectRequest.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
                URLSession.shared.dataTask(with: redirectRequest) { redirectData, redirectResponse, redirectError in
                    if self.isStopped(urlSchemeTask) { return }
                    if let redirectError = redirectError {
                        if !self.isStopped(urlSchemeTask) { urlSchemeTask.didFailWithError(redirectError) }
                        return
                    }
                    guard let redirectData = redirectData,
                          let r = redirectResponse as? HTTPURLResponse,
                          (200...299).contains(r.statusCode) else {
                        if !self.isStopped(urlSchemeTask) { urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"])) }
                        return
                    }
                    if self.isStopped(urlSchemeTask) { return }
                    let mimeType = r.mimeType ?? "image/png"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: redirectData.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(redirectData)
                    urlSchemeTask.didFinish()
                }.resume()
            } else if (200...299).contains(httpResponse.statusCode), let data = data {
                #if DEBUG
                print("[JiraImage] jira-image://\(mediaId) → OK (\(data.count) bytes)")
                #endif
                if self.isStopped(urlSchemeTask) { return }
                let mimeType = httpResponse.mimeType ?? "image/png"
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } else {
                #if DEBUG
                print("[JiraImage] jira-image://\(mediaId) → error status=\(httpResponse.statusCode)")
                #endif
                if !self.isStopped(urlSchemeTask) { urlSchemeTask.didFailWithError(NSError(domain: "JiraImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"])) }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        markStopped(urlSchemeTask)
    }
}
