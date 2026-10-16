import Foundation
import Testing
@testable import JoinCore

struct LocationFormatterTests {
    /// A list row's location: "Street, number · District or city", or "Place · District or city" for a place with
    /// its address. Most rows are real address formats (several added from review findings).
    @Test(arguments: [
        // A street address on one line.
        ("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España", "C. de Ruiz de Alarcón, 23 · Retiro"),
        ("Glorieta de Bilbao, 7, 28004 Madrid, Spain", "Glorieta de Bilbao, 7 · Madrid"),
        ("1 Infinite Loop, Cupertino, CA 95014, United States", "1 Infinite Loop · Cupertino"),
        ("Calle Mayor, s/n, Valdemoro", "Calle Mayor, s/n · Valdemoro"),
        ("Café Comercial, Madrid", "Café Comercial · Madrid"),
        ("Conference Room A", "Conference Room A"),
        ("  Room 4  ", "Room 4"),
        ("Calle Mayor, 28013", "Calle Mayor"),
        ("Unter den Linden 77, 10117 Berlin, Germany", "Unter den Linden 77 · Berlin"),
        ("Damrak 1, 1012 LG Amsterdam, Netherlands", "Damrak 1 · Amsterdam"),
        (", ,", ", ,"),
        // Google Calendar stores a place picked from its suggestions as "Place, street, [number,] [district,]
        // postcode city, country".
        ("Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España", "Museo del Prado · Retiro"),
        ("Blue Bottle Coffee, 66 Mint St, San Francisco, CA 94103, USA", "Blue Bottle Coffee · San Francisco"),
        ("WeWork, 20-22 Wenlock Road, London N1 7GU, UK", "WeWork · London"),
        ("Estación de Atocha, Plaza del Emperador Carlos V, s/n, Arganzuela, 28045 Madrid", "Estación de Atocha · Arganzuela"),
        ("Blue Bottle Coffee, 1 W 42nd St, New York, NY 10036, USA", "Blue Bottle Coffee · New York"),
        ("Microsoft Building 92, 15010 NE 36th St, Redmond, WA 98052, USA", "Microsoft Building 92 · Redmond"),
        ("Hotel Adlon Kempinski, Unter den Linden 77, 10117 Berlin, Germany", "Hotel Adlon Kempinski · Berlin"),
        // A postcode and a town of several words isn't a street.
        ("Ciudad Grupo Santander, Av. de Cantabria, s/n, 28660 Boadilla del Monte, Madrid, España", "Ciudad Grupo Santander · Boadilla del Monte"),
        ("1 Hotel Brooklyn Bridge, 60 Furman St, Brooklyn, NY 11201, USA", "1 Hotel Brooklyn Bridge · Brooklyn"),
        // Nor is a region and its postcode: the word before a trailing number needs a lowercase letter.
        ("Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia", "Sydney Opera House · Bennelong Point"),
        // A street address on several lines.
        ("1 Microsoft Way\nRedmond, WA 98052\nUnited States", "1 Microsoft Way · Redmond"),
        ("1 Infinite Loop\nCupertino CA 95014\nUnited States", "1 Infinite Loop · Cupertino"),
        ("C. de Ruiz de Alarcón, 23\n28014 Madrid, España", "C. de Ruiz de Alarcón, 23 · Madrid"),
        // A place picked from Maps: its name over its address.
        ("Café Comercial\nGlorieta de Bilbao, 7, 28004 Madrid, Spain", "Café Comercial · Madrid"),
        ("Apple Park\nOne Apple Park Way", "Apple Park"),
        ("Apple Park\nOne Apple Park Way, Cupertino, CA 95014, United States", "Apple Park · Cupertino"),
        ("Apple Park\n1 Apple Park Way, Cupertino, CA 95014, United States", "Apple Park · Cupertino"),
        ("Plaza Mayor\n28012 Madrid\nSpain", "Plaza Mayor · Madrid"),
    ])
    func shortLocation(_ location: String, expected: String) {
        #expect(LocationFormatter.shortLocation(location) == expected)
    }

    /// Whether a location is a place to travel to, so the panel offers Directions: not a link (with or without a
    /// scheme), a phone number, or a video service. Service keywords match whole words only, and a service name
    /// alone is a call while "Teams Room 3" is a room.
    @Test(arguments: [
        ("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España", true),
        ("Conference Room A", true),
        (nil, false),
        ("   ", false),
        ("https://zoom.us/j/123456", false),
        ("www.example.com/room", false),
        ("Zoom", false),
        ("Microsoft Teams Meeting", false),
        ("Google Meet", false),
        ("Online", false),
        ("Zoomarine, Algarve", true),
        // Links without a scheme.
        ("meet.google.com/abc-defg-hij", false),
        ("teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0", false),
        ("zoom.us/j/123456789", false),
        ("example.com", false),
        ("Room 4.2", true),
        // Phone numbers: seven digits or more.
        ("Tel: +34 600 123 456", false),
        ("+1 646-558-8656,,123456789#", false),
        ("tel:+34600123456", false),
        ("Phone: (415) 555-0132", false),
        ("28013", true),
        ("Calle Mayor, 28013", true),
        // Service names only count on their own.
        ("Teams", false),
        (" meet ", false),
        ("Chime", false),
        ("GoToMeeting", false),
        ("Teams Room 3", true),
        ("Meeting Room 2", true),
    ] as [(String?, Bool)])
    func isPhysicalPlace(_ location: String?, expected: Bool) {
        #expect((LocationFormatter.physicalPlace(in: location) != nil) == expected)
    }

    /// A hybrid location keeps its place segments and drops the links, phones and services; nothing removed gives
    /// back the trimmed original.
    @Test(arguments: [
        ("Sala Retiro; Microsoft Teams Meeting", "Sala Retiro"),
        ("Sala Retiro\nmeet.google.com/abc-defg-hij", "Sala Retiro"),
        ("Microsoft Teams Meeting; Sala Retiro; Tel: +34 600 123 456", "Sala Retiro"),
        (" Café Comercial\nGlorieta de Bilbao, 7 ", "Café Comercial\nGlorieta de Bilbao, 7"),
        ("Microsoft Teams Meeting; https://teams.microsoft.com/l/meetup-join/abc", nil),
    ] as [(String, String?)])
    func hybridLocationsKeepThePlace(_ location: String, expected: String?) {
        #expect(LocationFormatter.physicalPlace(in: location) == expected)
    }

    /// The full-screen alert's location line, which the notification's body repeats: the lines on one, joined
    /// with ", ", trimmed; nothing for a blank location or one that is only the join link again. A link that
    /// isn't the join link stays, as the alert has always shown it.
    @Test(arguments: [
        ("Conference Room A", nil, "Conference Room A"),
        (" Café Comercial \n\n Glorieta de Bilbao, 7 ", nil, "Café Comercial, Glorieta de Bilbao, 7"),
        ("https://meet.google.com/abc-defg-hij", "https://meet.google.com/abc-defg-hij", nil),
        ("https://zoom.us/j/123", "https://meet.google.com/abc-defg-hij", "https://zoom.us/j/123"),
        (" \n ", nil, nil),
        (nil, nil, nil),
    ] as [(String?, String?, String?)])
    func alertLocation(_ location: String?, joinURL: String?, expected: String?) {
        #expect(LocationFormatter.alertLocation(location, joinURL: joinURL.flatMap(URL.init(string:))) == expected)
    }

    /// Apple Maps directions: lines joined with ", ", "&" and "+" encoded, and nothing for a blank location.
    @Test(arguments: [
        ("C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España",
         "https://maps.apple.com/?daddr=C.%20de%20Ruiz%20de%20Alarc%C3%B3n%2C%2023%2C%20Retiro%2C%2028014%20Madrid%2C%20Espa%C3%B1a"),
        ("Café Comercial\nGlorieta de Bilbao, 7", "https://maps.apple.com/?daddr=Caf%C3%A9%20Comercial%2C%20Glorieta%20de%20Bilbao%2C%207"),
        ("A & B+C", "https://maps.apple.com/?daddr=A%20%26%20B%2BC"),
        (" \n ", nil),
    ] as [(String, String?)])
    func directionsURL(_ location: String, expected: String?) {
        #expect(LocationFormatter.directionsURL(to: location)?.absoluteString == expected)
    }
}
