import Foundation
import BraveAdblockCore

public enum AdblockResourceType: String, Sendable, CaseIterable {
    case xmlhttprequest
    case script
    case image
    case document
    case subdocument
}

public final class BraveAdblockEngine {
    private static var didConfigureDomainResolver = false
    private let engine: AdblockEngine

    public init(rules: String) throws {
        Self.configureDomainResolverIfNeeded()
        self.engine = try AdblockEngine(rules: rules)
    }

    public func shouldBlock(
        requestURL: URL,
        sourceURL: URL,
        resourceType: AdblockResourceType,
        isAggressive: Bool
    ) -> Bool {
        guard requestURL.scheme != "data" else {
            return false
        }
        guard let requestHost = requestURL.host, let sourceHost = sourceURL.host else {
            return false
        }

        let isThirdParty = requestHost != sourceHost
        if !isAggressive, !isThirdParty {
            return false
        }

        let result = engine.matches(
            url: requestURL.absoluteString,
            host: requestHost,
            tabHost: sourceHost,
            isThirdParty: isThirdParty,
            resourceType: resourceType.rawValue
        )

        return result.didMatchRule && !result.didMatchException
    }

    private static func configureDomainResolverIfNeeded() {
        guard !didConfigureDomainResolver else { return }
        _ = AdblockEngine.setDomainResolver()
        didConfigureDomainResolver = true
    }
}
