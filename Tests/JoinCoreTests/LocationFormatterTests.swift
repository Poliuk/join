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
        XCTAssertEqual(LocationFormatter.shortLocation("Unter den Linden 77, 10117 Berlin, Germany"), "Unter den Linden 77 · Berlin")
        XCTAssertEqual(LocationFormatter.shortLocation("Damrak 1, 1012 LG Amsterdam, Netherlands"), "Damrak 1 · Amsterdam")
        XCTAssertEqual(LocationFormatter.shortLocation(", ,"), ", ,")
    }

    // Google Calendar stores a place picked from its suggestions as "Place, street, [number,] [district,] postcode city, country".
    func testShortLocationOfAPlaceWithItsAddress() {
        func short(_ location: String) -> String { LocationFormatter.shortLocation(location) }
        XCTAssertEqual(short("Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"), "Museo del Prado · Retiro")
        XCTAssertEqual(short("Blue Bottle Coffee, 66 Mint St, San Francisco, CA 94103, USA"), "Blue Bottle Coffee · San Francisco")
        XCTAssertEqual(short("WeWork, 20-22 Wenlock Road, London N1 7GU, UK"), "WeWork · London")
        XCTAssertEqual(short("Estación de Atocha, Plaza del Emperador Carlos V, s/n, Arganzuela, 28045 Madrid"), "Estación de Atocha · Arganzuela")
        XCTAssertEqual(short("Blue Bottle Coffee, 1 W 42nd St, New York, NY 10036, USA"), "Blue Bottle Coffee · New York")
        XCTAssertEqual(short("Microsoft Building 92, 15010 NE 36th St, Redmond, WA 98052, USA"), "Microsoft Building 92 · Redmond")
        XCTAssertEqual(short("Hotel Adlon Kempinski, Unter den Linden 77, 10117 Berlin, Germany"), "Hotel Adlon Kempinski · Berlin")
        XCTAssertEqual(
            short("Ciudad Grupo Santander, Av. de Cantabria, s/n, 28660 Boadilla del Monte, Madrid, España"),
            "Ciudad Grupo Santander · Boadilla del Monte",
            "a postcode and a town of several words isn't a street"
        )
        XCTAssertEqual(short("1 Hotel Brooklyn Bridge, 60 Furman St, Brooklyn, NY 11201, USA"), "1 Hotel Brooklyn Bridge · Brooklyn")
    }

    func testShortLocationOfAStreetAddressOnSeveralLines() {
        XCTAssertEqual(LocationFormatter.shortLocation("1 Microsoft Way\nRedmond, WA 98052\nUnited States"), "1 Microsoft Way · Redmond")
        XCTAssertEqual(LocationFormatter.shortLocation("1 Infinite Loop\nCupertino CA 95014\nUnited States"), "1 Infinite Loop · Cupertino")
        XCTAssertEqual(LocationFormatter.shortLocation("1 Infinite Loop\nCupertino, CA 95014, United States"), "1 Infinite Loop · Cupertino")
        XCTAssertEqual(LocationFormatter.shortLocation("C. de Ruiz de Alarcón, 23\n28014 Madrid, España"), "C. de Ruiz de Alarcón, 23 · Madrid")
    }

    func testShortLocationOfAPlacePickedFromMaps() {
        XCTAssertEqual(
            LocationFormatter.shortLocation("Café Comercial\nGlorieta de Bilbao, 7, 28004 Madrid, Spain"),
            "Café Comercial · Madrid"
        )
        XCTAssertEqual(LocationFormatter.shortLocation("Apple Park\nOne Apple Park Way"), "Apple Park")
        XCTAssertEqual(LocationFormatter.shortLocation("Apple Park\nOne Apple Park Way, Cupertino, CA 95014, United States"), "Apple Park · Cupertino")
        XCTAssertEqual(LocationFormatter.shortLocation("Apple Park\n1 Apple Park Way, Cupertino, CA 95014, United States"), "Apple Park · Cupertino")
        XCTAssertEqual(LocationFormatter.shortLocation("Plaza Mayor\n28012 Madrid\nSpain"), "Plaza Mayor · Madrid")
    }

    func testPhysicalPlaces() {
        XCTAssertTrue(isPlace("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"))
        XCTAssertTrue(isPlace("Conference Room A"))
        XCTAssertFalse(isPlace(nil))
        XCTAssertFalse(isPlace("   "))
        XCTAssertFalse(isPlace("https://zoom.us/j/123456"))
        XCTAssertFalse(isPlace("www.example.com/room"))
        XCTAssertFalse(isPlace("Zoom"))
        XCTAssertFalse(isPlace("Microsoft Teams Meeting"))
        XCTAssertFalse(isPlace("Google Meet"))
        XCTAssertFalse(isPlace("Online"))
        XCTAssertTrue(isPlace("Zoomarine, Algarve"), "keywords match whole words only")
    }

    func testLinksWithoutAScheme() {
        XCTAssertFalse(isPlace("meet.google.com/abc-defg-hij"))
        XCTAssertFalse(isPlace("teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0"))
        XCTAssertFalse(isPlace("zoom.us/j/123456789"))
        XCTAssertFalse(isPlace("example.com"))
        XCTAssertTrue(isPlace("Room 4.2"))
        XCTAssertTrue(isPlace("C. de Ruiz de Alarcón, 23"))
    }

    func testPhoneNumbers() {
        XCTAssertFalse(isPlace("Tel: +34 600 123 456"))
        XCTAssertFalse(isPlace("+1 646-558-8656,,123456789#"))
        XCTAssertFalse(isPlace("tel:+34600123456"))
        XCTAssertFalse(isPlace("Phone: (415) 555-0132"))
        XCTAssertTrue(isPlace("28013"), "too short for a phone number")
        XCTAssertTrue(isPlace("Calle Mayor, 28013"))
    }

    func testServiceNamesOnlyCountOnTheirOwn() {
        XCTAssertFalse(isPlace("Teams"))
        XCTAssertFalse(isPlace(" meet "))
        XCTAssertFalse(isPlace("Chime"))
        XCTAssertFalse(isPlace("GoToMeeting"))
        XCTAssertTrue(isPlace("Teams Room 3"))
        XCTAssertTrue(isPlace("Meeting Room 2"))
    }

    func testHybridLocationsKeepThePlace() {
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Sala Retiro; Microsoft Teams Meeting"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Sala Retiro\nmeet.google.com/abc-defg-hij"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; Sala Retiro; Tel: +34 600 123 456"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: " Café Comercial\nGlorieta de Bilbao, 7 "), "Café Comercial\nGlorieta de Bilbao, 7")
        XCTAssertNil(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; https://teams.microsoft.com/l/meetup-join/abc"))
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

    private func isPlace(_ text: String?) -> Bool { LocationFormatter.physicalPlace(in: text) != nil }
}
