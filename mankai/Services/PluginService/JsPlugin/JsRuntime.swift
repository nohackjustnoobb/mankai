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

final class JsRuntime: NSObject {
    static let shared = JsRuntime()

    static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let literal = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return literal
    }

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
            throw MankaiErrorCode.pluginJavascriptWebViewNotInitialized.makeError()
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
                const getValue = (key) => _getValue(key, \(Self.javascriptStringLiteral(plugin.id)));
                const setValue = (key, value) => _setValue(key, value, \(Self.javascriptStringLiteral(plugin.id)));
                const removeValue = (key) => _removeValue(key, \(Self.javascriptStringLiteral(plugin.id)));
                """
        }

        var from = plugin?.id ?? from
        from = from.map(Self.javascriptStringLiteral) ?? "undefined"

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
            throw MankaiErrorCode.pluginJavascriptMissingUrlParameter.makeError()
        }

        guard let requestURL = URL(string: url) else {
            throw MankaiErrorCode.pluginJavascriptInvalidUrl.makeError()
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
            throw MankaiErrorCode.pluginJavascriptInvalidResponseType.makeError()
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
        guard let body = message.body as? [String: Any] else {
            let error = "Invalid message body"
            Logger.jsRuntime.error(error)
            return (nil, error)
        }

        guard let methodStr = body["method"] as? String,
            let method = Method(rawValue: methodStr)
        else {
            let error = "Invalid or missing method"
            Logger.jsRuntime.error(error)
            return (nil, error)
        }

        Logger.jsRuntime.debug("Received message from JS: \(methodStr)")

        let start = Date()
        defer {
            Logger.jsRuntime.debug(
                "\(methodStr) process time: \(Date().timeIntervalSince(start) * 1000)ms"
            )
        }

        guard let params = body["params"] as? [String: Any] else {
            let error = "Invalid or missing params for method: \(methodStr)"
            Logger.jsRuntime.error(error)
            return (nil, error)
        }

        switch method {
        case .log:
            guard let from = params["from"] as? String,
                let logMessage = params["message"] as? String
            else {
                let error = "Invalid or missing log parameters"
                Logger.jsRuntime.error(error)
                return (nil, error)
            }
            Logger.jsRuntime.info("[\(from)] \(logMessage)")
        case .fetch:
            do {
                let resp = try await handleFetch(params)

                return (resp, nil)
            } catch {
                Logger.jsRuntime.error("Fetch failed", error: error)
                return (nil, "Fetch failed")
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
                return (nil, "Missing plugin ID")
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, "Database not available")
            }

            do {
                try await dbPool.write { db in
                    let kvPair = JsRuntimeKvPairModel(pluginId: pluginId, key: key, value: value)
                    try kvPair.save(db)
                }
            } catch {
                Logger.jsRuntime.error("Failed to save value", error: error)
                return (nil, "Failed to save value")
            }
        case .getValue:
            let key = params["key"] as? String ?? ""
            let from = params["from"] as? String

            guard let pluginId = from else {
                Logger.jsRuntime.error("Missing pluginId")
                return (nil, "Missing plugin ID")
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, "Database not available")
            }

            do {
                let kvPair = try await dbPool.read { db in
                    try JsRuntimeKvPairModel.fetchOne(db, key: ["pluginId": pluginId, "key": key])
                }
                return (kvPair?.value, nil)
            } catch {
                Logger.jsRuntime.error("Failed to fetch value", error: error)
                return (nil, "Failed to fetch value")
            }
        case .removeValue:
            let key = params["key"] as? String ?? ""
            let from = params["from"] as? String

            guard let pluginId = from else {
                Logger.jsRuntime.error("Missing pluginId")
                return (nil, "Missing plugin ID")
            }

            guard let dbPool = DbService.shared.appDb else {
                Logger.jsRuntime.error("Database not available")
                return (nil, "Database not available")
            }

            do {
                let deleted = try await dbPool.write { db in
                    try JsRuntimeKvPairModel.deleteOne(db, key: ["pluginId": pluginId, "key": key])
                }

                return (deleted, nil)
            } catch {
                Logger.jsRuntime.error("Failed to remove value", error: error)
                return (nil, "Failed to remove value")
            }
        default:
            let error = "Unexpected method: \(methodStr)"
            Logger.jsRuntime.warning(error)
            return (nil, error)
        }

        return (nil, nil)
    }
}
