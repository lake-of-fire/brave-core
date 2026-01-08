import XCTest
import BraveAdblock

final class BraveAdblockTests: XCTestCase {
    func testContentBlockerRulesFromFilterSet() throws {
        let rules = "||example.com^\n@@||example.com/allow^$document"
        let result = try BraveAdblock.contentBlockerRules(fromFilterSet: rules)
        XCTAssertFalse(result.rulesJSON.isEmpty)

        let json = try JSONSerialization.jsonObject(with: Data(result.rulesJSON.utf8))
        XCTAssertNotNil(json)
    }
}
