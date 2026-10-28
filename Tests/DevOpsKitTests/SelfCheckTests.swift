import XCTest
@testable import DevOpsKit

final class SelfCheckTests: XCTestCase {
    func testSelfChecksPass() {
        let failures = SelfCheck.run()
        XCTAssertTrue(failures.isEmpty, "SelfCheck failures:\n" + failures.joined(separator: "\n"))
    }
}
