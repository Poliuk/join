import Testing
@testable import JoinCore

struct OutOfOfficeDetectorTests {
    let keywords = OutOfOfficeDetector.defaultKeywords

    @Test func googleTitlesInSeveralLanguages() {
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "Out of office", keywords: keywords))
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "Fuera de la oficina", keywords: keywords))
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "Absent du bureau", keywords: keywords))
    }

    @Test func shortTokensMustStandAlone() {
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "Sick/Medical (OOO)", keywords: keywords))
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "PTO - beach", keywords: keywords))
        #expect(!OutOfOfficeDetector.isOutOfOffice(title: "Photo review", keywords: keywords))
        #expect(!OutOfOfficeDetector.isOutOfOffice(title: "Zooom party", keywords: keywords))
    }

    @Test func regularMeetingsAreNotFlagged() {
        #expect(!OutOfOfficeDetector.isOutOfOffice(title: "Ana/Luis: Product Planning", keywords: keywords))
        #expect(!OutOfOfficeDetector.isOutOfOffice(title: "Quarterly Roadmap Review", keywords: keywords))
    }

    @Test func customKeywords() {
        #expect(OutOfOfficeDetector.isOutOfOffice(title: "Vacaciones en Asturias", keywords: ["vacaciones"]))
        #expect(!OutOfOfficeDetector.isOutOfOffice(title: "Out of office", keywords: []))
    }
}
