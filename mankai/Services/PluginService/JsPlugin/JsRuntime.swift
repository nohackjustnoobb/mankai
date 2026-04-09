//
//  JsRuntime.swift
//  mankai
//
//  Created by Travis XU on 23/6/2025.
//

import Foundation
import OpenCC
import WebKit

enum Method: String {
    case log
    case fetch
    case setConfig
    case s2t
    case t2s
    case getValue
    case setValue
    case removeValue
}

class JsRuntime: NSObject {
    static let shared = JsRuntime()

    private lazy var jsLog: String = loadScript("log")
    private lazy var jsFetch: String = loadScript("fetch")
    private lazy var jsOpenCC: String = loadScript("opencc")
    private lazy var jsStorage: String = loadScript("storage")

    private lazy var s2tConverter: OpenCC.ChineseConverter? = try? OpenCC.ChineseConverter(
        options: .traditionalize
    )
    private lazy var t2sConverter: OpenCC.ChineseConverter? = try? OpenCC.ChineseConverter(
        options: .simplify
    )

    private func loadScript(_ name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            if let content = try? String(contentsOf: url) {
                return content
            }
        }

        Logger.jsRuntime.warning("Failed to load script: \(name).js")
        return ""
    }

    private var webview: WKWebView?

    @MainActor
    private func initWebview() async {
        Logger.jsRuntime.debug("Initializing WebView")
        if webview == nil {
            webview = WKWebView(frame: .zero)
            webview?.configuration.userContentController.addScriptMessageHandler(
                self, contentWorld: .defaultClient, name: "DEFAULT_BRIDGE"
            )
        }
    }

    /// Executes JavaScript in the hidden WKWebView using async/await
    /// - Parameter js: The JavaScript code to execute
    /// - Returns: The result of the JavaScript execution
    @MainActor
    func execute(_ js: String, from: String? = nil, plugin: JsPlugin? = nil) async throws
        -> Any?
    {
        Logger.jsRuntime.debug("Executing JS (from: \(from ?? plugin?.id ?? "unknown"))")
        await initWebview()

        guard let webview else {
            Logger.jsRuntime.error("WebView not initialized")
            throw NSError(
                domain: "JsRuntime", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "webViewNotInitialized")]
            )
        }

        // Inject functions
        let injectedJs = inject(js, from: from, plugin: plugin)

        return try await webview.callAsyncJavaScript(injectedJs, contentWorld: .defaultClient)
    }

    private func inject(_ js: String, from: String? = nil, plugin: JsPlugin? = nil) -> String {
        var injectedJs = jsLog + jsFetch + jsOpenCC

        if let plugin = plugin {
            // inject getConfigs
            let configValuesArray = plugin.configValues.map { configValue in
                [
                    "key": configValue.key,
                    "value": configValue.value,
                ]
            }

            let configValuesJson: String
            do {
                let jsonData = try JSONSerialization.data(
                    withJSONObject: configValuesArray, options: []
                )
                configValuesJson = String(data: jsonData, encoding: .utf8) ?? "[]"
            } catch {
                configValuesJson = "[]"
            }

            let getConfigs = """
            function getConfigs() {
                return \(configValuesJson);
            }
            """

            injectedJs += getConfigs

            // inject getValue and setValue
            injectedJs += jsStorage
            injectedJs += """
            const getValue = (key) => _getValue(key, "\(plugin.id)");
            const setValue = (key, value) => _setValue(key, value, "\(plugin.id)");
            const removeValue = (key) => _removeValue(key, "\(plugin.id)");
            """
        }

        var from = plugin?.id ?? from
        from = from == nil ? "undefined" : "\"\(from!)\""

        // Override console.log
        injectedJs += "console.log = (...m) => _log(m.join(' '), \(from!));"

        injectedJs += js
        return injectedJs
    }
}

extension JsRuntime: WKScriptMessageHandlerWithReply {
    private func handleFetch(_ params: [String: Any]) async throws -> [String: Any] {
        let url = params["url"] as? String ?? "unknown"
        Logger.jsRuntime.debug("Handling fetch request: \(url)")

        guard let url = params["url"] as? String else {
            throw NSError(
                domain: "JsRuntime", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "missingUrlParameter")]
            )
        }

        guard let requestURL = URL(string: url) else {
            throw NSError(
                domain: "JsRuntime", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidUrl")]
            )
        }

        var request = URLRequest(url: requestURL)

        let method = params["method"] as? String ?? "GET"
        request.httpMethod = method

        if let headers = params["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let body = params["body"] as? String {
            request.httpBody = body.data(using: .utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "JsRuntime", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidResponseType")]
            )
        }

        let responseTextBase64 = data.base64EncodedString()

        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                responseHeaders[keyString] = valueString
            }
        }

        return [
            "ok": httpResponse.statusCode >= 200 && httpResponse.statusCode < 300,
            "status": httpResponse.statusCode,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            "headers": responseHeaders,
            "data": responseTextBase64,
            "url": httpResponse.url?.absoluteString ?? url,
        ]
    }

    func userContentController(
        _: WKUserContentController, didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let body = message.body as! [String: Any]
        let methodStr = body["method"] as? String ?? "unknown"
        Logger.jsRuntime.debug("Received message from JS: \(methodStr)")

        let start = Date()
        defer {
            Logger.jsRuntime.debug(
                "\(methodStr) process time: \(Date().timeIntervalSince(start) * 1000)ms"
            )
        }

        let method = Method(rawValue: body["method"] as! String)
        let params = body["params"] as! [String: Any]

        switch method {
        case .log:
            let from = params["from"] as! String
            let message = params["message"] as! String
            Logger.jsRuntime.info("[\(from)] \(message)")
        case .fetch:
            do {
                let resp = try await handleFetch(params)

                return (resp, nil)
            } catch {
                Logger.jsRuntime.error("Fetch failed", error: error)
                return (nil, error.localizedDescription)
            }
        case .s2t:
            let text = params["text"] as? String ?? ""
            guard let converter = s2tConverter else {
                return (text, "Failed to initialize OpenCC s2t")
            }
            let result = converter.convert(text)
            return (result, nil)
        case .t2s:
            let text = params["text"] as? String ?? ""
            guard let converter = t2sConverter else {
                return (text, "Failed to initialize OpenCC t2s")
            }
            let result = converter.convert(text)
            return (result, nil)
        case .setValue:
            let key = params["key"] as? String ?? ""
            let value = params["value"] as? String ?? ""
            let from = params["from"] as? String

            guard let pluginId = from else {
                Logger.jsRuntime.error("Missing pluginId")
                return (nil, String(localized: "missingPluginId"))
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, String(localized: "databaseNotAvailable"))
            }

            do {
                try await dbPool.write { db in
                    let kvPair = JsRuntimeKvPairModel(pluginId: pluginId, key: key, value: value)
                    try kvPair.save(db)
                }
            } catch {
                Logger.jsRuntime.error("Failed to save value", error: error)
                return (nil, error.localizedDescription)
            }
        case .getValue:
            let key = params["key"] as? String ?? ""
            let from = params["from"] as? String

            guard let pluginId = from else {
                Logger.jsRuntime.error("Missing pluginId")
                return (nil, String(localized: "missingPluginId"))
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, String(localized: "databaseNotAvailable"))
            }

            do {
                let kvPair = try await dbPool.read { db in
                    try JsRuntimeKvPairModel.fetchOne(db, key: ["pluginId": pluginId, "key": key])
                }
                return (kvPair?.value, nil)
            } catch {
                Logger.jsRuntime.error("Failed to fetch value", error: error)
                return (nil, error.localizedDescription)
            }
        case .removeValue:
            let key = params["key"] as? String ?? ""
            let from = params["from"] as? String

            guard let pluginId = from else {
                Logger.jsRuntime.error("Missing pluginId")
                return (nil, String(localized: "missingPluginId"))
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, String(localized: "databaseNotAvailable"))
            }

            do {
                let deleted = try await dbPool.write { db in
                    try JsRuntimeKvPairModel.deleteOne(db, key: ["pluginId": pluginId, "key": key])
                }

                return (deleted, nil)
            } catch {
                Logger.jsRuntime.error("Failed to remove value", error: error)
                return (nil, error.localizedDescription)
            }
        default:
            Logger.jsRuntime.warning("Unexpected Method: \(methodStr)")
            fatalError("Unexpected Method")
        }

        return (nil, nil)
    }
}
