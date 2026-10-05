import XCTest
@testable import JoinCore

final class AppearanceTests: XCTestCase {
    func testHexRoundTrip() {
        let color = RGBA(hex: "#EF990E")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexString, "#EF990E")
        XCTAssertEqual(RGBA(hex: "ff000080")?.alpha ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(RGBA(red: 1, green: 0, blue: 0, alpha: 0.5).hexString, "#FF000080")
        XCTAssertNil(RGBA(hex: "nope"))
    }

    func testAppearanceRoundTripsThroughJSON() throws {
        var appearance = AlertAppearance.default
        appearance.blurMode = .light
        appearance.backgroundTint = RGBA(hex: "#FBF5DD")
        let data = try JSONEncoder().encode(appearance)
        XCTAssertEqual(try JSONDecoder().decode(AlertAppearance.self, from: data), appearance)
    }
}
