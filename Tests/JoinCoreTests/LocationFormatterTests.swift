import Testing
@testable import JoinCore

struct LocationFormatterTests {
    @Test func shortLocation() {
        #expect(LocationFormatter.shortLocation("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España") == "C. de Ruiz de Alarcón, 23 · Retiro")
        #expect(LocationFormatter.shortLocation("Glorieta de Bilbao, 7, 28004 Madrid, Spain") == "Glorieta de Bilbao, 7 · Madrid")
        #expect(LocationFormatter.shortLocation("1 Infinite Loop, Cupertino, CA 95014, United States") == "1 Infinite Loop · Cupertino")
        #expect(LocationFormatter.shortLocation("Calle Mayor, s/n, Valdemoro") == "Calle Mayor, s/n · Valdemoro")
        #expect(LocationFormatter.shortLocation("Café Comercial, Madrid") == "Café Comercial · Madrid")
        #expect(LocationFormatter.shortLocation("Conference Room A") == "Conference Room A")
        #expect(LocationFormatter.shortLocation("  Room 4  ") == "Room 4")
        #expect(LocationFormatter.shortLocation("Calle Mayor, 28013") == "Calle Mayor")
        #expect(LocationFormatter.shortLocation("Unter den Linden 77, 10117 Berlin, Germany") == "Unter den Linden 77 · Berlin")
        #expect(LocationFormatter.shortLocation("Damrak 1, 1012 LG Amsterdam, Netherlands") == "Damrak 1 · Amsterdam")
        #expect(LocationFormatter.shortLocation(", ,") == ", ,")
    }

    // Google Calendar stores a place picked from its suggestions as "Place, street, [number,] [district,] postcode city, country".
    @Test func shortLocationOfAPlaceWithItsAddress() {
        func short(_ location: String) -> String { LocationFormatter.shortLocation(location) }
        #expect(short("Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España") == "Museo del Prado · Retiro")
        #expect(short("Blue Bottle Coffee, 66 Mint St, San Francisco, CA 94103, USA") == "Blue Bottle Coffee · San Francisco")
        #expect(short("WeWork, 20-22 Wenlock Road, London N1 7GU, UK") == "WeWork · London")
        #expect(short("Estación de Atocha, Plaza del Emperador Carlos V, s/n, Arganzuela, 28045 Madrid") == "Estación de Atocha · Arganzuela")
        #expect(short("Blue Bottle Coffee, 1 W 42nd St, New York, NY 10036, USA") == "Blue Bottle Coffee · New York")
        #expect(short("Microsoft Building 92, 15010 NE 36th St, Redmond, WA 98052, USA") == "Microsoft Building 92 · Redmond")
        #expect(short("Hotel Adlon Kempinski, Unter den Linden 77, 10117 Berlin, Germany") == "Hotel Adlon Kempinski · Berlin")
        #expect(
            short("Ciudad Grupo Santander, Av. de Cantabria, s/n, 28660 Boadilla del Monte, Madrid, España")
                == "Ciudad Grupo Santander · Boadilla del Monte",
            "a postcode and a town of several words isn't a street"
        )
        #expect(short("1 Hotel Brooklyn Bridge, 60 Furman St, Brooklyn, NY 11201, USA") == "1 Hotel Brooklyn Bridge · Brooklyn")
    }

    @Test func shortLocationOfAStreetAddressOnSeveralLines() {
        #expect(LocationFormatter.shortLocation("1 Microsoft Way\nRedmond, WA 98052\nUnited States") == "1 Microsoft Way · Redmond")
        #expect(LocationFormatter.shortLocation("1 Infinite Loop\nCupertino CA 95014\nUnited States") == "1 Infinite Loop · Cupertino")
        #expect(LocationFormatter.shortLocation("1 Infinite Loop\nCupertino, CA 95014, United States") == "1 Infinite Loop · Cupertino")
        #expect(LocationFormatter.shortLocation("C. de Ruiz de Alarcón, 23\n28014 Madrid, España") == "C. de Ruiz de Alarcón, 23 · Madrid")
    }

    @Test func shortLocationOfAPlacePickedFromMaps() {
        #expect(
            LocationFormatter.shortLocation("Café Comercial\nGlorieta de Bilbao, 7, 28004 Madrid, Spain")
                == "Café Comercial · Madrid"
        )
        #expect(LocationFormatter.shortLocation("Apple Park\nOne Apple Park Way") == "Apple Park")
        #expect(LocationFormatter.shortLocation("Apple Park\nOne Apple Park Way, Cupertino, CA 95014, United States") == "Apple Park · Cupertino")
        #expect(LocationFormatter.shortLocation("Apple Park\n1 Apple Park Way, Cupertino, CA 95014, United States") == "Apple Park · Cupertino")
        #expect(LocationFormatter.shortLocation("Plaza Mayor\n28012 Madrid\nSpain") == "Plaza Mayor · Madrid")
    }

    @Test func physicalPlaces() {
        #expect(isPlace("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"))
        #expect(isPlace("Conference Room A"))
        #expect(!isPlace(nil))
        #expect(!isPlace("   "))
        #expect(!isPlace("https://zoom.us/j/123456"))
        #expect(!isPlace("www.example.com/room"))
        #expect(!isPlace("Zoom"))
        #expect(!isPlace("Microsoft Teams Meeting"))
        #expect(!isPlace("Google Meet"))
        #expect(!isPlace("Online"))
        #expect(isPlace("Zoomarine, Algarve"), "keywords match whole words only")
    }

    @Test func linksWithoutAScheme() {
        #expect(!isPlace("meet.google.com/abc-defg-hij"))
        #expect(!isPlace("teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0"))
        #expect(!isPlace("zoom.us/j/123456789"))
        #expect(!isPlace("example.com"))
        #expect(isPlace("Room 4.2"))
        #expect(isPlace("C. de Ruiz de Alarcón, 23"))
    }

    @Test func phoneNumbers() {
        #expect(!isPlace("Tel: +34 600 123 456"))
        #expect(!isPlace("+1 646-558-8656,,123456789#"))
        #expect(!isPlace("tel:+34600123456"))
        #expect(!isPlace("Phone: (415) 555-0132"))
        #expect(isPlace("28013"), "too short for a phone number")
        #expect(isPlace("Calle Mayor, 28013"))
    }

    @Test func serviceNamesOnlyCountOnTheirOwn() {
        #expect(!isPlace("Teams"))
        #expect(!isPlace(" meet "))
        #expect(!isPlace("Chime"))
        #expect(!isPlace("GoToMeeting"))
        #expect(isPlace("Teams Room 3"))
        #expect(isPlace("Meeting Room 2"))
    }

    @Test func hybridLocationsKeepThePlace() {
        #expect(LocationFormatter.physicalPlace(in: "Sala Retiro; Microsoft Teams Meeting") == "Sala Retiro")
        #expect(LocationFormatter.physicalPlace(in: "Sala Retiro\nmeet.google.com/abc-defg-hij") == "Sala Retiro")
        #expect(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; Sala Retiro; Tel: +34 600 123 456") == "Sala Retiro")
        #expect(LocationFormatter.physicalPlace(in: " Café Comercial\nGlorieta de Bilbao, 7 ") == "Café Comercial\nGlorieta de Bilbao, 7")
        #expect(LocationFormatter.physicalPlace(in: "Microsoft Teams Meeting; https://teams.microsoft.com/l/meetup-join/abc") == nil)
    }

    @Test func directionsURL() {
        #expect(
            LocationFormatter.directionsURL(to: "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España")?.absoluteString
                == "https://maps.apple.com/?daddr=C.%20de%20Ruiz%20de%20Alarc%C3%B3n%2C%2023%2C%20Retiro%2C%2028014%20Madrid%2C%20Espa%C3%B1a"
        )
        #expect(
            LocationFormatter.directionsURL(to: "Café Comercial\nGlorieta de Bilbao, 7")?.absoluteString
                == "https://maps.apple.com/?daddr=Caf%C3%A9%20Comercial%2C%20Glorieta%20de%20Bilbao%2C%207"
        )
        #expect(LocationFormatter.directionsURL(to: "A & B+C")?.absoluteString == "https://maps.apple.com/?daddr=A%20%26%20B%2BC")
        #expect(LocationFormatter.directionsURL(to: " \n ") == nil)
    }

    private func isPlace(_ text: String?) -> Bool { LocationFormatter.physicalPlace(in: text) != nil }
}
