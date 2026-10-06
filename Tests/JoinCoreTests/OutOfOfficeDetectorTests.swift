import XCTest
@testable import JoinCore

final class OutOfOfficeDetectorTests: XCTestCase {
    let keywords = OutOfOfficeDetector.defaultKeywords

    func testGoogleTitlesInSeveralLanguages() {
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "Out of office", keywords: keywords))
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "Fuera de la oficina", keywords: keywords))
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "Absent du bureau", keywords: keywords))
    }

    func testShortTokensMustStandAlone() {
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "Sick/Medical (OOO)", keywords: keywords))
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "PTO - beach", keywords: keywords))
        XCTAssertFalse(OutOfOfficeDetector.isOutOfOffice(title: "Photo review", keywords: keywords))
        XCTAssertFalse(OutOfOfficeDetector.isOutOfOffice(title: "Zooom party", keywords: keywords))
    }

    func testRegularMeetingsAreNotFlagged() {
        XCTAssertFalse(OutOfOfficeDetector.isOutOfOffice(title: "Ana/Luis: Product Planning", keywords: keywords))
        XCTAssertFalse(OutOfOfficeDetector.isOutOfOffice(title: "Quarterly Roadmap Review", keywords: keywords))
    }

    func testCustomKeywords() {
        XCTAssertTrue(OutOfOfficeDetector.isOutOfOffice(title: "Vacaciones en Asturias", keywords: ["vacaciones"]))
        XCTAssertFalse(OutOfOfficeDetector.isOutOfOffice(title: "Out of office", keywords: []))
    }
}
