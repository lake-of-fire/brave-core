import Foundation
import BraveAdblockCore

public struct AdblockContentRules: Sendable, Equatable {
    public let rulesJSON: String
    public let truncated: Bool

    public init(rulesJSON: String, truncated: Bool) {
        self.rulesJSON = rulesJSON
        self.truncated = truncated
    }
}

public enum BraveAdblock {
    public static func contentBlockerRules(fromFilterSet filterSet: String) throws -> AdblockContentRules {
        let result = try AdblockEngine.contentBlockerRules(fromFilterSet: filterSet)
        return AdblockContentRules(rulesJSON: result.rulesJSON, truncated: result.truncated)
    }
}
