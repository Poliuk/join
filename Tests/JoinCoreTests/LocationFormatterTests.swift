import XCTest
@testable import JoinCore

final class LocationFormatterTests: XCTestCase {
    func testShortLocation() {
        XCTAssertEqual(LocationFormatter.shortLocation("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"), "C. de Ruiz de Alarcón, 23 · Retiro")
        XCTAssertEqual(LocationFormatter.shortLocation("Glorieta de Bilbao, 7, 28004 Madrid, Spain"), "Glorieta de Bilbao, 7 · Madrid")
        XCTAssertEqual(LocationFormatter.shortLocation("1 Infinite Loop, Cupertino, CA 95014, United States"), "1 Infinite Loop · Cupertino")
        XCTAssertEqual(LocationFormatter.shortLocation("Calle Mayor, s/n, Valdemoro"), "Calle Mayor, s/n · Valdemoro")
        XCTAssertEqual(LocationFormatter.shortLocation("Café Comercial, Madrid"), "Café Comercial · Madrid")
        XCTAssertEqual(LocationFormatter.shortLocation("Conference Room A"), "Conference Room A")
        XCTAssertEqual(LocationFormatter.shortLocation("  Room 4  "), "Room 4")
        XCTAssertEqual(LocationFormatter.shortLocation("Calle Mayor, 28013"), "Calle Mayor")
    }

    func testShortLocationOfAPlacePickedFromMaps() {
        XCTAssertEqual(
            LocationFormatter.shortLocation("Café Comercial\nGlorieta de Bilbao, 7, 28004 Madrid, Spain"),
            "Café Comercial · Madrid"
        )
        XCTAssertEqual(LocationFormatter.shortLocation("Apple Park\nOne Apple Park Way"), "Apple Park")
    }

    func testPhysicalPlaces() {
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Conference Room A"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace(nil))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("   "))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("https://zoom.us/j/123456"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("www.example.com/room"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Zoom"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Microsoft Teams Meeting"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Google Meet"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Online"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Zoomarine, Algarve"), "keywords match whole words only")
    }

    func testInPersonNeedsAPlaceAndNoJoinLink() {
        let place = "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"
        XCTAssertTrue(LocationFormatter.isInPerson(Meeting(id: "a", title: "A", start: .distantPast, end: .distantFuture, location: place)))
        XCTAssertFalse(LocationFormatter.isInPerson(Meeting(
            id: "b", title: "B", start: .distantPast, end: .distantFuture, location: place,
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )))
        XCTAssertFalse(LocationFormatter.isInPerson(Meeting(id: "c", title: "C", start: .distantPast, end: .distantFuture)))
    }

    func testDirectionsURL() {
        XCTAssertEqual(
            LocationFormatter.directionsURL(to: "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España")?.absoluteString,
            "https://maps.apple.com/?daddr=C.%20de%20Ruiz%20de%20Alarc%C3%B3n%2C%2023%2C%20Retiro%2C%2028014%20Madrid%2C%20Espa%C3%B1a"
        )
        XCTAssertEqual(
            LocationFormatter.directionsURL(to: "Café Comercial\nGlorieta de Bilbao, 7")?.absoluteString,
            "https://maps.apple.com/?daddr=Caf%C3%A9%20Comercial%2C%20Glorieta%20de%20Bilbao%2C%207"
        )
        XCTAssertEqual(LocationFormatter.directionsURL(to: "A & B+C")?.absoluteString, "https://maps.apple.com/?daddr=A%20%26%20B%2BC")
        XCTAssertNil(LocationFormatter.directionsURL(to: " \n "))
    }
}
