import OSLog
import JoinCore

/// Where the notification coordinator shows and closes Join!'s notification cards (`NotificationCard`), the
/// seam the card windows go behind. A card is one per meeting; showing a meeting's card again replaces it.
protocol NotificationPresenter: AnyObject {
    /// The meetings whose cards are up or waiting for a slot.
    var shownMeetingIDs: [Meeting.ID] { get }
    /// Shows `card`, with the user's alert sound when `playsSound`.
    func show(_ card: NotificationCard, playsSound: Bool)
    /// Closes these meetings' cards, wherever they are.
    func close(_ meetingIDs: [Meeting.ID])
}

/// Keeps track of the cards it's asked for and logs them, without drawing anything: the stand-in until the
/// card windows replace it.
final class LoggingNotificationPresenter: NotificationPresenter {
    private(set) var shownMeetingIDs: [Meeting.ID] = []

    func show(_ card: NotificationCard, playsSound: Bool) {
        shownMeetingIDs.removeAll { $0 == card.id }
        shownMeetingIDs.append(card.id)
        // Ids carry the event's identifier, so they stay private.
        Logger.notifications.notice("Would show the card for \(card.id, privacy: .private), sound \(playsSound, privacy: .public)")
    }

    func close(_ meetingIDs: [Meeting.ID]) {
        guard !meetingIDs.isEmpty else { return }
        shownMeetingIDs.removeAll(where: meetingIDs.contains)
        Logger.notifications.notice("Would close the cards for \(meetingIDs, privacy: .private)")
    }
}
