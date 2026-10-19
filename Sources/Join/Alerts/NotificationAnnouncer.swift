import AppKit
import AVFoundation

/// Tells VoiceOver users about a notification card as it appears ("Join!: Design review starts in 5 minutes."):
/// the card's window never takes the keyboard, so VoiceOver's focus doesn't go to it and nothing would be read.
/// It posts a high-priority announcement for the app, and, while VoiceOver is on and another app is active, speaks
/// it too (`speaksWhileInactive`).
final class NotificationAnnouncer {
    /// Whether the text is also spoken, through speech synthesis with VoiceOver's voice and rate, while VoiceOver is
    /// on and Join! isn't the active app. An announcement from an app that isn't active may not be read: Chromium
    /// found it silent on macOS 10.14, and nothing confirms it either way on macOS 26 or 27. If a check with
    /// VoiceOver on and another app frontmost hears the card twice, the announcement does reach VoiceOver: set
    /// this false.
    static let speaksWhileInactive = true

    /// Kept while it speaks: a synthesizer that goes away stops mid-sentence.
    private var synthesizer: AVSpeechSynthesizer?

    func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        guard Self.speaksWhileInactive, NSWorkspace.shared.isVoiceOverEnabled, !NSApp.isActive else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        let synthesizer = synthesizer ?? AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        self.synthesizer = synthesizer
    }
}
