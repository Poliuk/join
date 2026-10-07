import Foundation

/// The rule behind a Settings pop-up of preset minutes and Custom…: **Alert me**, both snooze buttons
/// and the pill's **Appears**. Only Alert me offers **Never**, between the presets and Custom…, and it
/// turns full-screen alerts off while keeping the time. The view remembers whether Custom… was picked;
/// this decides what the pop-up shows and what picking an item or saving a custom value changes.
public struct MinutesChoice: Sendable {
    /// A pop-up item, and its tag. Never and Custom… are cases of their own, so neither can be taken
    /// for a preset, not even 0 (When the event starts), or for each other.
    public enum Item: Hashable, Sendable {
        case preset(Int)
        case never
        case custom
    }

    /// What picking an item changes.
    public struct Pick: Equatable, Sendable {
        /// Whether Custom… is picked afterwards, which shows the custom row.
        public var customPicked: Bool
        /// The minutes to save, or nil to keep the stored ones.
        public var minutes: Int?
        /// Whether Never is chosen afterwards, or nil to leave it as it is.
        public var neverChosen: Bool?

        public init(customPicked: Bool, minutes: Int?, neverChosen: Bool?) {
            self.customPicked = customPicked
            self.minutes = minutes
            self.neverChosen = neverChosen
        }
    }

    public let presets: [Int]
    public let offersNever: Bool

    public init(presets: [Int], offersNever: Bool = false) {
        self.presets = presets
        self.offersNever = offersNever
    }

    /// Whether Custom… is the choice on opening the pane, or after the stored minutes change from
    /// elsewhere (Restore Defaults): when they aren't a preset, such as a lead time of 2 or 10 minutes
    /// from before 1.2.0, unless Never is chosen, which shows whatever time is kept.
    public func opensAsCustom(minutes: Int, neverChosen: Bool) -> Bool {
        !isNever(neverChosen) && !presets.contains(minutes)
    }

    /// Whether the custom row shows: from picking Custom… until another item is picked, even while the
    /// custom value matches a preset, and whenever the pop-up opens as Custom….
    public func showsCustomRow(minutes: Int, neverChosen: Bool, customPicked: Bool) -> Bool {
        customPicked || opensAsCustom(minutes: minutes, neverChosen: neverChosen)
    }

    /// The item the pop-up shows.
    public func selection(minutes: Int, neverChosen: Bool, customPicked: Bool) -> Item {
        if showsCustomRow(minutes: minutes, neverChosen: neverChosen, customPicked: customPicked) { return .custom }
        if isNever(neverChosen) { return .never }
        return .preset(minutes)
    }

    /// A preset saves its minutes and turns Never off. Never keeps the minutes. Custom… turns Never off
    /// too, at once, with the kept minutes in its field: what the pop-up shows is what's in effect.
    public func picking(_ item: Item) -> Pick {
        switch item {
        case .preset(let minutes):
            return Pick(customPicked: false, minutes: minutes, neverChosen: offersNever ? false : nil)
        case .never:
            return Pick(customPicked: false, minutes: nil, neverChosen: offersNever ? true : nil)
        case .custom:
            return Pick(customPicked: true, minutes: nil, neverChosen: offersNever ? false : nil)
        }
    }

    /// Whether Custom… is picked once the stored minutes have changed. Minutes the pop-up saved itself
    /// keep Custom… picked, even when they match a preset, and minutes that aren't a preset pick it. A
    /// change from elsewhere shows the way it would on opening the pane.
    public func customPicked(afterChangeTo minutes: Int, neverChosen: Bool, customPicked: Bool, savedHere: Bool) -> Bool {
        savedHere
            ? customPicked || !presets.contains(minutes)
            : opensAsCustom(minutes: minutes, neverChosen: neverChosen)
    }

    /// A pop-up without Never is never on Never.
    private func isNever(_ neverChosen: Bool) -> Bool {
        offersNever && neverChosen
    }
}
