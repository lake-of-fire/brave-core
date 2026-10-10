import Foundation

public enum WebMediaScriptError: Error, LocalizedError {
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing bundled web media script resource: \(name)"
        }
    }
}

public struct WebMediaScriptConfiguration: Hashable, Sendable {
    public let messageHandlerName: String
    public let securityToken: String
    public let tagAttributeName: String
    public let sendMessageTimeoutName: String
    public let longPressFunctionName: String
    public let processDocumentLoadFunctionName: String
    public let currentTimeFunctionName: String
    public let stopPlaybackFunctionName: String
    public let telemetryAttachedName: String
    public let telemetryHeartbeatName: String

    public init(
        messageHandlerName: String,
        securityToken: String = UUID().uuidString,
        namespaceToken: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.messageHandlerName = messageHandlerName
        self.securityToken = securityToken
        self.tagAttributeName = "tagId_\(namespaceToken)"
        self.sendMessageTimeoutName = "smt_\(namespaceToken)"
        self.longPressFunctionName = "webMediaLongPressed_\(namespaceToken)"
        self.processDocumentLoadFunctionName = "webMediaProcessDocumentLoad_\(namespaceToken)"
        self.currentTimeFunctionName = "mediaCurrentTimeFromTag_\(namespaceToken)"
        self.stopPlaybackFunctionName = "stopMediaPlayback_\(namespaceToken)"
        self.telemetryAttachedName = "webMediaTelemetryAttached_\(namespaceToken)"
        self.telemetryHeartbeatName = "webMediaTelemetryHeartbeat_\(namespaceToken)"
    }
}

public struct WebMediaBuiltScriptSet: Sendable {
    public let configuration: WebMediaScriptConfiguration
    public let firefoxShimSource: String
    public let mediaSourceOverrideSource: String
    public let detectorSource: String

    public var processDocumentLoadJavaScript: String {
        "window.__firefox__.\(configuration.processDocumentLoadFunctionName)()"
    }
}

public enum WebMediaScriptEngine {
    public static func makeScriptSet(
        configuration: WebMediaScriptConfiguration
    ) throws -> WebMediaBuiltScriptSet {
        let firefoxShimSource = try loadResource(named: "__firefox__")
        let swizzler = try loadResource(named: "WebMediaSwizzlerScript")
        let detector = try loadResource(named: "WebMediaDetectorScript")

        let detectorSource = secureScript(
            handlerNamesMap: [
                "$<message_handler>": configuration.messageHandlerName,
                "$<tagUUID>": configuration.tagAttributeName,
                "$<sendMessageTimeout>": configuration.sendMessageTimeoutName,
                "$<webMediaLongPressed>": configuration.longPressFunctionName,
                "$<webMediaProcessDocumentLoad>": configuration.processDocumentLoadFunctionName,
                "$<mediaCurrentTimeFromTag>": configuration.currentTimeFunctionName,
                "$<stopMediaPlayback>": configuration.stopPlaybackFunctionName,
                "$<telemetryAttached>": configuration.telemetryAttachedName,
                "$<telemetryHeartbeat>": configuration.telemetryHeartbeatName,
            ],
            securityToken: configuration.securityToken,
            script: detector
        )

        let mediaSourceOverrideSource = secureScript(
            handlerNamesMap: [:],
            securityToken: "",
            script: swizzler
        )

        return WebMediaBuiltScriptSet(
            configuration: configuration,
            firefoxShimSource: firefoxShimSource,
            mediaSourceOverrideSource: mediaSourceOverrideSource,
            detectorSource: detectorSource
        )
    }

    public static func secureScript(
        handlerNamesMap: [String: String],
        securityToken: String,
        script: String
    ) -> String {
        guard !script.isEmpty else {
            return script
        }

        let substituted = handlerNamesMap.reduce(script) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }

        let messageHandlers: String = {
            guard !handlerNamesMap.isEmpty else {
                return ""
            }
            let handlers = handlerNamesMap.values.map { "'\($0)'" }.joined(separator: ", ")
            return """
            [\(handlers)].forEach((handlerName) => {
              if (handlerName && handlerName.length > 0 && window.webkit?.messageHandlers?.[handlerName]) {
                Object.freeze(window.webkit.messageHandlers[handlerName]);
                Object.freeze(window.webkit.messageHandlers[handlerName].postMessage);
              }
            });
            """
        }()

        return """
        (function() {
          const SECURITY_TOKEN = '\(securityToken)';

          \(messageHandlers)

          \(substituted)
        })();
        """
    }

    private static func loadResource(named name: String) throws -> String {
        let url =
            Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "UserScripts")
            ?? Bundle.module.url(forResource: name, withExtension: "js")
        guard let url,
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw WebMediaScriptError.missingResource(name)
        }
        return source
    }
}
