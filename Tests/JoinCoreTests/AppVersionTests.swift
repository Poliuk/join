import Testing
@testable import JoinCore

struct AppVersionTests {
    @Test func parsesWithOrWithoutTheTagPrefix() {
        #expect(AppVersion("1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("v1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("0.0.0") == AppVersion(major: 0, minor: 0, patch: 0))
        #expect(AppVersion("v10.20.300") == AppVersion(major: 10, minor: 20, patch: 300))
    }

    @Test func rejectsAnythingElse() {
        let invalid = [
            "", "v", "1", "v1.2", "1.2.3.4", "1.2.3-beta", "1.2.3+build", " 1.2.3", "1.2.3 ", "01.2.3", "1.02.3",
            "1.2.03", "1.-2.3", "+1.2.3", "1..3", "1.2.", ".1.2", "V1.2.3", "vv1.2.3", "1.2.x", "١.٢.٣",
            "99999999999999999999.0.0",
        ]
        for string in invalid {
            #expect(AppVersion(string) == nil, "\"\(string)\"")
        }
    }

    @Test func ordersByMajorThenMinorThenPatch() {
        let ordered = ["0.9.9", "1.0.0", "1.0.1", "1.0.10", "1.1.0", "1.10.0", "2.0.0"].compactMap(AppVersion.init)
        #expect(ordered.count == 7)
        #expect(ordered.shuffled().sorted() == ordered)
        #expect(AppVersion(major: 1, minor: 0, patch: 9) < AppVersion(major: 1, minor: 1, patch: 0))
        #expect(!(AppVersion(major: 1, minor: 1, patch: 0) < AppVersion(major: 1, minor: 1, patch: 0)))
        #expect(AppVersion("v1.1.0") == AppVersion("1.1.0"))
    }

    @Test func descriptionAndTag() {
        let version = AppVersion(major: 1, minor: 10, patch: 0)
        #expect(version.description == "1.10.0")
        #expect("\(version)" == "1.10.0")
        #expect(version.tag == "v1.10.0")
        #expect(AppVersion(version.tag) == version)
    }
}
