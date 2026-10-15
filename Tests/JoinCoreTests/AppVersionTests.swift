import Testing
@testable import JoinCore

struct AppVersionTests {
    /// "1.2.3" or "v1.2.3", read as its tag, "v1.2.3", which spells out major, minor and patch; nil for
    /// anything else, one row per kind.
    @Test(arguments: [
        ("1.2.3", "v1.2.3"),
        ("v1.2.3", "v1.2.3"),
        ("0.0.0", "v0.0.0"),
        ("v10.20.300", "v10.20.300"),
        ("", nil),
        ("v1.2", nil),
        ("1.2.3.4", nil),
        ("1.2.3-beta", nil),
        ("1.2.3+build", nil),
        (" 1.2.3", nil),
        ("01.2.3", nil),
        ("+1.2.3", nil),
        ("1..3", nil),
        ("V1.2.3", nil),
        ("vv1.2.3", nil),
        ("١.٢.٣", nil),
        ("99999999999999999999.0.0", nil),
    ] as [(String, String?)])
    func parse(_ string: String, tag: String?) {
        #expect(AppVersion(string)?.tag == tag)
    }

    /// By number, not as text: 1.10.0 is newer than 1.9.0, which decides whether a release is offered.
    @Test func ordersByMajorThenMinorThenPatch() {
        let ordered = ["0.9.9", "1.0.0", "1.0.1", "1.0.10", "1.1.0", "1.9.0", "1.10.0", "2.0.0"].compactMap(AppVersion.init)
        #expect(ordered.count == 8)
        let scrambled = [ordered[6], ordered[3], ordered[7], ordered[0], ordered[5], ordered[2], ordered[4], ordered[1]]
        #expect(scrambled.sorted() == ordered)
        #expect(!(AppVersion(major: 1, minor: 1, patch: 0) < AppVersion(major: 1, minor: 1, patch: 0)))
    }
}
