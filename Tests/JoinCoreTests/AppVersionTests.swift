import XCTest
@testable import JoinCore

final class AppVersionTests: XCTestCase {
    func testParsesWithOrWithoutTheTagPrefix() {
        XCTAssertEqual(AppVersion("1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(AppVersion("0.0.0"), AppVersion(major: 0, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion("v10.20.300"), AppVersion(major: 10, minor: 20, patch: 300))
    }

    func testRejectsAnythingElse() {
        let invalid = [
            "", "v", "1", "v1.2", "1.2.3.4", "1.2.3-beta", "1.2.3+build", " 1.2.3", "1.2.3 ", "01.2.3", "1.02.3",
            "1.2.03", "1.-2.3", "+1.2.3", "1..3", "1.2.", ".1.2", "V1.2.3", "vv1.2.3", "1.2.x", "١.٢.٣",
            "99999999999999999999.0.0",
        ]
        for string in invalid {
            XCTAssertNil(AppVersion(string), "\"\(string)\"")
        }
    }

    func testOrdersByMajorThenMinorThenPatch() {
        let ordered = ["0.9.9", "1.0.0", "1.0.1", "1.0.10", "1.1.0", "1.10.0", "2.0.0"].compactMap(AppVersion.init)
        XCTAssertEqual(ordered.count, 7)
        XCTAssertEqual(ordered.shuffled().sorted(), ordered)
        XCTAssertLessThan(AppVersion(major: 1, minor: 0, patch: 9), AppVersion(major: 1, minor: 1, patch: 0))
        XCTAssertFalse(AppVersion(major: 1, minor: 1, patch: 0) < AppVersion(major: 1, minor: 1, patch: 0))
        XCTAssertEqual(AppVersion("v1.1.0"), AppVersion("1.1.0"))
    }

    func testDescriptionAndTag() {
        let version = AppVersion(major: 1, minor: 10, patch: 0)
        XCTAssertEqual(version.description, "1.10.0")
        XCTAssertEqual("\(version)", "1.10.0")
        XCTAssertEqual(version.tag, "v1.10.0")
        XCTAssertEqual(AppVersion(version.tag), version)
    }
}
