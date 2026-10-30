#if !canImport(BraveAdblockCore) || targetEnvironment(macCatalyst) || os(macOS)
import Foundation

public struct AdblockContentBlockerRulesResult {
    public let rulesJSON: String
    public let truncated: Bool

    public init(rulesJSON: String, truncated: Bool) {
        self.rulesJSON = rulesJSON
        self.truncated = truncated
    }
}

public struct AdblockMatchResult {
    public let didMatchRule: Bool
    public let didMatchException: Bool

    public init(didMatchRule: Bool, didMatchException: Bool) {
        self.didMatchRule = didMatchRule
        self.didMatchException = didMatchException
    }
}

public final class AdblockEngine {
    public init() {}

    public init(rules: String) throws {
        _ = rules
    }

    public static func setDomainResolver() -> Bool {
        true
    }

    public static func contentBlockerRules(fromFilterSet filterSet: String) throws -> AdblockContentBlockerRulesResult {
        _ = filterSet
        return AdblockContentBlockerRulesResult(rulesJSON: "[]", truncated: false)
    }

    public func matches(
        url: String,
        host: String,
        tabHost: String,
        isThirdParty: Bool,
        resourceType: String
    ) -> AdblockMatchResult {
        _ = url
        _ = host
        _ = tabHost
        _ = isThirdParty
        _ = resourceType
        return AdblockMatchResult(didMatchRule: false, didMatchException: false)
    }
}
#endif
