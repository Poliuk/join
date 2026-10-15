import Testing
@testable import JoinCore

struct OutOfOfficeDetectorTests {
    static let defaults = OutOfOfficeDetector.defaultKeywords

    /// Google titles out-of-office events in the account's language. Short tokens must stand alone ("Photo review"
    /// isn't PTO), the user's keywords replace the defaults, and blank ones are skipped: Preferences stores them as
    /// typed, and a blank one would match titles like "Ana/Luis: Product Planning", which would lose their alert.
    @Test(arguments: [
        ("Out of office", defaults, true),
        ("Fuera de la oficina", defaults, true),
        ("Absent du bureau", defaults, true),
        ("Sick/Medical (OOO)", defaults, true),
        ("PTO - beach", defaults, true),
        ("Photo review", defaults, false),
        ("Zooom party", defaults, false),
        ("Ana/Luis: Product Planning", defaults, false),
        ("Quarterly Roadmap Review", defaults, false),
        ("Vacaciones en Asturias", ["vacaciones"], true),
        ("Out of office", [], false),
        ("Ana/Luis: Product Planning", ["", "  ", "\n"], false),
        ("Vacaciones en Asturias", [" ", "vacaciones"], true),
    ] as [(String, [String], Bool)])
    func isOutOfOffice(_ title: String, keywords: [String], expected: Bool) {
        #expect(OutOfOfficeDetector.isOutOfOffice(title: title, keywords: keywords) == expected)
    }
}
