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

    func testLinksWithoutAScheme() {
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("meet.google.com/abc-defg-hij"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("zoom.us/j/123456789"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("example.com"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Room 4.2"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("C. de Ruiz de Alarcón, 23"))
    }

    func testPhoneNumbers() {
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Tel: +34 600 123 456"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("+1 646-558-8656,,123456789#"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("tel:+34600123456"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Phone: (415) 555-0132"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("28013"), "too short for a phone number")
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Calle Mayor, 28013"))
    }

    func testServiceNamesOnlyCountOnTheirOwn() {
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Teams"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace(" meet "))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("Chime"))
        XCTAssertFalse(LocationFormatter.isPhysicalPlace("GoToMeeting"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Teams Room 3"))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Meeting Room 2"))
    }

    func testHybridLocationsKeepThePlace() {
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Sala Retiro; Microsoft Teams Meeting"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Sala Retiro\nmeet.google.com/abc-defg-hij"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; Sala Retiro; Tel: +34 600 123 456"), "Sala Retiro")
        XCTAssertEqual(LocationFormatter.physicalPlace(in: " Café Comercial\nGlorieta de Bilbao, 7 "), "Café Comercial\nGlorieta de Bilbao, 7")
        XCTAssertNil(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; https://teams.microsoft.com/l/meetup-join/abc"))
        XCTAssertNil(LocationFormatter.physicalPlace(in: nil))
        XCTAssertTrue(LocationFormatter.isPhysicalPlace("Sala Retiro; Microsoft Teams Meeting"))
    }

    func testInPersonNeedsAPlaceAndNoJoinLink() {
        let place = "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"
        XCTAssertTrue(LocationFormatter.isInPerson(Meeting(id: "a", title: "A", start: .distantPast, end: .distantFuture, location: place)))
        XCTAssertFalse(LocationFormatter.isInPerson(Meeting(
            id: "b", title: "B", start: .distantPast, end: .distantFuture, location: place,
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )))
        XCTAssertFalse(LocationFormatter.isInPerson(Meeting(id: "c", title: "C", start: .distantPast, end: .distantFuture)))
        XCTAssertFalse(LocationFormatter.isInPerson(Meeting(
            id: "d", title: "D", start: .distantPast, end: .distantFuture, location: "meet.google.com/abc-defg-hij"
        )))
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
