import Foundation
import Testing
@testable import JoinCore

struct DismissedEventsTests {
    typealias F = MenuBarFixtures

    /// A daily standup at 9:00, one series, like EventKit's: every occurrence shares the event identifier.
    static func standup(_ day: Int, _ hour: Int = 9, minutes: Double = 15) -> Meeting {
        let start = F.date(day, hour)
        return Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: start), title: "Standup",
                       start: start, end: start.addingTimeInterval(minutes * 60), seriesID: "standup")
    }

    static let monday = standup(5)
    static let tuesday = standup(6)
    static let wednesday = standup(7)
    static let thursday = standup(8)
    static let friday = standup(9)
    /// Every standup from Monday 5 to Friday 16 October.
    static let standups = (5...16).map { standup($0) }

    private var monday: Meeting { Self.monday }
    private var tuesday: Meeting { Self.tuesday }
    private var wednesday: Meeting { Self.wednesday }
    private var thursday: Meeting { Self.thursday }
    private var friday: Meeting { Self.friday }
    private var standups: [Meeting] { Self.standups }

    /// The days of `meetings` (the standups by default) that are dismissed.
    private func dismissedDays(_ dismissed: DismissedEvents, _ meetings: [Meeting] = Self.standups) -> [Int] {
        meetings.filter(dismissed.isDismissed).map { F.calendar.component(.day, from: $0.start) }
    }

    // MARK: One occurrence

    /// Dismiss and restore one occurrence. An event that doesn't repeat has no series, so All Future Events
    /// is This Event, both ways.
    @Test(arguments: DismissScope.allCases)
    func dismissAndRestoreAOneOffEvent(scope: DismissScope) {
        #expect(!F.workshop.isRepeating)
        let none = DismissedEvents()
        #expect(none.isEmpty)
        #expect(!none.isDismissed(F.workshop))

        let dismissed = none.dismissing(F.workshop, scope: scope)
        #expect(!dismissed.isEmpty)
        #expect(dismissed.isDismissed(F.workshop))
        #expect(!dismissed.isDismissed(F.planning))
        #expect(dismissed.occurrences == [F.workshop.id: .init(start: F.workshop.start, end: F.workshop.end)], "kept until the occurrence ends")
        #expect(dismissed.dismissing(F.workshop, scope: scope) == dismissed, "dismissing twice changes nothing")

        let both = dismissed.dismissing(F.planning, scope: scope)
        #expect(Set(both.occurrences.keys) == [F.workshop.id, F.planning.id])
        #expect(both.restoring(F.planning, scope: scope) == dismissed)
        #expect(dismissed.restoring(F.workshop, scope: scope) == none)
        #expect(dismissed.restoring(F.planning, scope: scope) == dismissed, "restoring what isn't dismissed changes nothing")
    }

    // This Event on a repeating event: only that occurrence. Each occurrence has its own id, and so does an
    // occurrence moved to another start.
    @Test func thisEventDismissesOnlyThatOccurrence() {
        #expect(monday.isRepeating)
        let dismissed = DismissedEvents().dismissing(monday)
        #expect(dismissedDays(dismissed) == [5])
        #expect(dismissed.seriesRules.isEmpty)
        #expect(dismissed.occurrences[monday.id] == .init(start: monday.start, end: monday.end, seriesID: "standup"))
        #expect(!dismissed.isDismissed(Self.standup(5, 10)), "moved to 10:00, it's a new occurrence")
        #expect(dismissed.restoring(monday) == DismissedEvents())
    }

    // MARK: All future events

    @Test func allFutureEventsDismissesThisOccurrenceAndEveryLaterOne() {
        let dismissed = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        #expect(dismissed.seriesRules == ["standup": [.init(from: wednesday.start)]])
        #expect(dismissed.occurrences.isEmpty)
        #expect(dismissedDays(dismissed) == Array(7...16), "Monday and Tuesday aren't, everything from Wednesday is")
        #expect(dismissed.isDismissed(Self.standup(30)), "beyond the 7-day window, and not fetched yet")
        #expect(dismissed.isDismissed(Self.standup(8, 11)), "an occurrence moved on its own is still in the series")
        #expect(!dismissed.isDismissed(Self.standup(7, 8)), "moved before the occurrence the rule started from")

        // Only that series: another one, and an event with the same identifier that doesn't repeat, aren't.
        var other = Self.standup(9)
        other.seriesID = "retro"
        #expect(!dismissed.isDismissed(other))
        var oneOff = Self.standup(9)
        oneOff.seriesID = nil
        #expect(!dismissed.isDismissed(oneOff))

        #expect(dismissed.dismissing(friday, scope: .allFutureEvents) == dismissed, "Friday's already covered")
        #expect(dismissed.dismissing(wednesday, scope: .allFutureEvents) == dismissed, "twice changes nothing")
    }

    /// Entries of the series from where All Future Events is chosen on become the rule's: dismissed ones are
    /// covered, restored ones dismissed again. Earlier entries and other events stay.
    struct Absorbing: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let stored: DismissedEvents
        let from: Meeting
        let rules: [DismissedEvents.SeriesRule]
        let occurrenceIDs: Set<String>
        let exceptionIDs: Set<String>
        let days: [Int]
    }

    static let absorbing: [Absorbing] = [
        Absorbing(
            testDescription: "later single entries are covered",
            stored: DismissedEvents().dismissing(monday).dismissing(thursday).dismissing(F.workshop),
            from: wednesday,
            rules: [.init(from: wednesday.start)],
            occurrenceIDs: [monday.id, F.workshop.id],
            exceptionIDs: [],
            days: [5] + Array(7...16)
        ),
        Absorbing(
            testDescription: "from before a rule, the rule's start moves back",
            stored: DismissedEvents().dismissing(thursday, scope: .allFutureEvents).restoring(friday).dismissing(tuesday),
            from: monday,
            rules: [.init(from: monday.start)],
            occurrenceIDs: [],
            exceptionIDs: [],
            days: Array(5...16)
        ),
        Absorbing(
            testDescription: "from inside a rule, later exceptions are dismissed again",
            stored: DismissedEvents().dismissing(monday, scope: .allFutureEvents).restoring(tuesday).restoring(thursday),
            from: wednesday,
            rules: [.init(from: monday.start)],
            occurrenceIDs: [],
            exceptionIDs: [tuesday.id],
            days: [5] + Array(7...16)
        ),
    ]

    @Test(arguments: absorbing)
    func allFutureEventsAbsorbsEntriesFromItsStart(_ row: Absorbing) {
        let dismissed = row.stored.dismissing(row.from, scope: .allFutureEvents)
        #expect(dismissed.seriesRules == ["standup": row.rules])
        #expect(Set(dismissed.occurrences.keys) == row.occurrenceIDs)
        #expect(Set(dismissed.exceptions.keys) == row.exceptionIDs)
        #expect(dismissedDays(dismissed) == row.days)
    }

    // This Event inside a rule's range: Dismiss changes nothing, since it's already dismissed, unless it had
    // been restored on its own; Restore makes an exception for it, which goes at the occurrence's end like a
    // dismissed one, and the rest of the series stays dismissed.
    @Test func thisEventInsideASeriesRule() {
        let rule = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        #expect(rule.dismissing(thursday) == rule)

        let restored = rule.restoring(thursday)
        #expect(restored.exceptions == [thursday.id: .init(start: thursday.start, end: thursday.end, seriesID: "standup")])
        #expect(restored.seriesRules == rule.seriesRules)
        #expect(dismissedDays(restored) == [7] + Array(9...16))
        #expect(restored.restoring(thursday) == restored, "twice changes nothing")
        #expect(restored.dismissing(thursday) == rule, "dismissed again, the rule covers it")

        #expect(rule.restoring(tuesday) == rule, "Tuesday wasn't dismissed")
        #expect(Set(rule.dismissing(tuesday).occurrences.keys) == [tuesday.id], "before the rule, it's an occurrence of its own")
    }

    // MARK: Restoring

    // Restore asks This Event or All Future Events only on an occurrence dismissed with its series: one
    // dismissed on its own, repeating or not, restores at once (the user's ask, 2026-10-15).
    @Test func dismissedBySeries() {
        let alone = DismissedEvents().dismissing(wednesday)
        #expect(alone.isDismissed(wednesday))
        #expect(!alone.isDismissedBySeries(wednesday))

        let rule = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        #expect(standups.filter(rule.isDismissedBySeries).map(\.id) == standups.filter(rule.isDismissed).map(\.id))
        #expect(!rule.isDismissedBySeries(tuesday), "before the rule")

        let excepted = rule.restoring(thursday)
        #expect(!excepted.isDismissedBySeries(thursday), "restored on its own")
        #expect(excepted.dismissing(thursday).isDismissedBySeries(thursday), "dismissed again, the rule covers it")

        let bounded = rule.restoring(friday, scope: .allFutureEvents)
        #expect(bounded.isDismissedBySeries(thursday))
        #expect(!bounded.isDismissedBySeries(friday), "past the rule's end")
        #expect(!bounded.dismissing(friday).isDismissedBySeries(friday), "Friday dismissed on its own")
    }

    // Restore All Future Events from the occurrence the rule started on: the rule goes, and with it any
    // occurrence of the series dismissed one by one from there on and every exception.
    @Test func restoreAllFutureEventsFromTheRulesStart() {
        let stored = DismissedEvents()
            .dismissing(wednesday, scope: .allFutureEvents)
            .restoring(friday)
            .dismissing(F.workshop)
        let restored = stored.restoring(wednesday, scope: .allFutureEvents)
        #expect(restored.seriesRules.isEmpty)
        #expect(restored.exceptions.isEmpty)
        #expect(restored == DismissedEvents().dismissing(F.workshop))
        #expect(dismissedDays(restored) == [])

        // From before the rule's start too, and single entries of the series come back with it.
        let singles = DismissedEvents().dismissing(tuesday).dismissing(thursday, scope: .allFutureEvents)
        #expect(singles.restoring(tuesday, scope: .allFutureEvents) == DismissedEvents())
        #expect(singles.restoring(monday, scope: .allFutureEvents) == DismissedEvents())
    }

    // Restore All Future Events from a later occurrence: the rule stops there. Earlier occurrences still
    // listed and dismissed stay dismissed, one restored on its own stays restored, and later ones come back,
    // however they were dismissed.
    @Test func restoreAllFutureEventsFromALaterOccurrenceBoundsTheRule() {
        let stored = DismissedEvents()
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(tuesday)
            .restoring(friday)
        let restored = stored.restoring(thursday, scope: .allFutureEvents)
        #expect(restored.seriesRules == ["standup": [.init(from: monday.start, until: thursday.start)]])
        #expect(Set(restored.exceptions.keys) == [tuesday.id], "Friday's exception has no rule left to except it from")
        #expect(dismissedDays(restored) == [5, 7])
        #expect(!restored.isDismissed(Self.standup(30)))
        #expect(restored.isDismissed(Self.standup(8, 8)), "moved to 8:00, it starts before the occurrence restored from")
        #expect(restored.restoring(friday, scope: .allFutureEvents) == restored, "nothing left to restore after Thursday")

        // A single entry after a bounded rule comes back with a restore further back.
        let single = restored.dismissing(Self.standup(12))
        #expect(single.restoring(friday, scope: .allFutureEvents) == restored)
    }

    // All Future Events again, after Restore All Future Events bounded the rule: a second rule from that
    // occurrence on, so the occurrences between the two stay as they are; from inside or right at the end of
    // the first rule, it runs on with no end.
    @Test func allFutureEventsAfterABoundedRestore() {
        let bounded = DismissedEvents()
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(wednesday, scope: .allFutureEvents)
        #expect(dismissedDays(bounded) == [5, 6])

        let twoRules = bounded.dismissing(friday, scope: .allFutureEvents)
        #expect(twoRules.seriesRules == ["standup": [.init(from: monday.start, until: wednesday.start), .init(from: friday.start)]])
        #expect(dismissedDays(twoRules) == [5, 6] + Array(9...16))

        let joined = twoRules.dismissing(wednesday, scope: .allFutureEvents)
        #expect(joined.seriesRules == ["standup": [.init(from: monday.start)]])
        #expect(dismissedDays(joined) == Array(5...16))
        #expect(bounded.dismissing(tuesday, scope: .allFutureEvents) == joined, "from inside the bounded rule")

        let restoredFromTuesday = twoRules.restoring(tuesday, scope: .allFutureEvents)
        #expect(restoredFromTuesday.seriesRules == ["standup": [.init(from: monday.start, until: tuesday.start)]])
        #expect(dismissedDays(restoredFromTuesday) == [5])
    }

    // MARK: Other series

    /// A daily retro at 3:00 PM, a series of its own.
    static func retro(_ day: Int) -> Meeting {
        let start = F.date(day, 15)
        return Meeting(id: Meeting.occurrenceID(eventIdentifier: "retro", start: start), title: "Retro",
                       start: start, end: start.addingTimeInterval(45 * 60), seriesID: "retro")
    }

    /// A daily one-on-one at 11:00 AM, another series.
    static func oneOnOne(_ day: Int) -> Meeting {
        let start = F.date(day, 11)
        return Meeting(id: Meeting.occurrenceID(eventIdentifier: "one", start: start), title: "1:1",
                       start: start, end: start.addingTimeInterval(30 * 60), seriesID: "one")
    }

    /// Dismiss or Restore All Future Events on the standup from Wednesday leaves every other series as it was:
    /// the retro's rule and its exception, and a one-on-one dismissed on its own, all later than Wednesday.
    @Test(arguments: [false, true])
    func allFutureEventsLeavesOtherSeriesAlone(restores: Bool) {
        let stored = DismissedEvents()
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(thursday)
            .dismissing(Self.retro(6), scope: .allFutureEvents)
            .restoring(Self.retro(9))
            .dismissing(Self.oneOnOne(10))
        let retros = (5...16).map(Self.retro)
        let oneOnOnes = (5...16).map(Self.oneOnOne)
        #expect(dismissedDays(stored, retros) == [6, 7, 8] + Array(10...16))
        #expect(dismissedDays(stored, oneOnOnes) == [10])

        let changed = restores
            ? stored.restoring(wednesday, scope: .allFutureEvents)
            : stored.dismissing(wednesday, scope: .allFutureEvents)
        #expect(changed.seriesRules["retro"] == stored.seriesRules["retro"])
        #expect(dismissedDays(changed, retros) == dismissedDays(stored, retros))
        #expect(dismissedDays(changed, oneOnOnes) == [10])
    }

    // MARK: Pruning

    /// Lunch (1:00 to 2:00 PM) and the Workshop (3:00 to 7:30 PM) dismissed, pruned at a time against the
    /// meetings fetched then: an occurrence goes at its end. One missing from the fetch (its calendar
    /// unchecked, a fetch that failed) is kept until its stored end.
    @Test(arguments: [
        ("both still on or to come", F.date(6, 13, 30), [F.lunch, F.workshop], [F.lunch.id, F.workshop.id]),
        ("lunch over at 2:00 PM", F.date(6, 14), [F.lunch, F.workshop], [F.workshop.id]),
        ("both over", F.date(6, 19, 30), [F.lunch, F.workshop], []),
        ("the Workshop missing from the fetch", F.date(6, 16), [], [F.workshop.id]),
        ("missing, a minute before its stored end", F.date(6, 19, 29), [F.lunch], [F.workshop.id]),
        ("missing, at its stored end", F.date(6, 19, 30), [], []),
        ("missing, the next day", F.date(7, 9), [F.lunch], []),
    ] as [(String, Date, [Meeting], Set<String>)])
    func pruningKeepsAnOccurrenceUntilItsEnd(_ name: String, now: Date, meetings: [Meeting], kept: Set<String>) {
        let dismissed = DismissedEvents().dismissing(F.lunch).dismissing(F.workshop)
        #expect(Set(dismissed.pruned(at: now, meetings: meetings).occurrences.keys) == kept)
    }

    /// The Workshop, dismissed while it ran until 7:30 PM, then moved to end later or earlier: it stays
    /// dismissed until its new end rather than its old one, and keeps that end if it then goes missing.
    @Test(arguments: [
        ("extended to 8:30 PM", F.date(6, 20, 30)),
        ("shortened to 5:00 PM", F.date(6, 17)),
    ])
    func pruningFollowsTheEventsCurrentEnd(_ name: String, newEnd: Date) {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        var moved = F.workshop
        moved.end = newEnd
        let stillOn = newEnd.addingTimeInterval(-15 * 60)

        #expect(dismissed.pruned(at: stillOn, meetings: [moved]).isDismissed(F.workshop))
        let updated = dismissed.pruned(at: F.date(6, 16), meetings: [moved])
        #expect(updated.occurrences[F.workshop.id]?.end == newEnd, "the stored end follows the event")
        #expect(updated.pruned(at: stillOn, meetings: []) == updated, "and is kept if the event then goes missing")
        #expect(dismissed.pruned(at: newEnd, meetings: [moved]).isEmpty, "over at its new end")
    }

    /// A fetch with the same occurrence twice, in either order, doesn't crash, and the copy that ends later
    /// decides when the dismissal goes.
    @Test(arguments: [false, true])
    func pruningAFetchWithAnOccurrenceTwice(longerFirst: Bool) {
        var longer = F.workshop
        longer.end = F.date(6, 20, 30)
        let meetings = longerFirst ? [longer, F.workshop] : [F.workshop, longer]
        let dismissed = DismissedEvents().dismissing(F.workshop)
        #expect(dismissed.pruned(at: F.date(6, 19, 45), meetings: meetings).occurrences[F.workshop.id]?.end == longer.end)
    }

    // A rule with no end covers occurrences not in the calendar yet, so it never expires, whatever is fetched.
    @Test func pruningKeepsASeriesRuleWithNoEnd() {
        let rule = DismissedEvents().dismissing(monday, scope: .allFutureEvents)
        #expect(rule.pruned(at: F.date(5, 12), meetings: standups) == rule)
        #expect(rule.pruned(at: F.date(30, 12), meetings: []) == rule)
    }

    // An exception goes at its occurrence's end, following the event as it is now, like a dismissed occurrence;
    // the rule stays.
    @Test func pruningDropsExceptionsAtTheirEnd() {
        let restored = DismissedEvents().dismissing(monday, scope: .allFutureEvents).restoring(wednesday)
        #expect(restored.pruned(at: F.date(7, 9, 10), meetings: standups) == restored)
        let over = restored.pruned(at: F.date(7, 9, 15), meetings: standups)
        #expect(over.exceptions.isEmpty)
        #expect(over.seriesRules == restored.seriesRules)
        #expect(restored.pruned(at: F.date(7, 9, 20), meetings: [Self.standup(7, minutes: 30)]).exceptions[wednesday.id]?.end
                    == F.date(7, 9, 30), "extended to 9:30, it stays restored until then")
    }

    // A rule bounded by Restore All Future Events only covers occurrences that start before the bound: it goes
    // once that start has passed and none of them is still running.
    @Test func pruningDropsABoundedRuleOnceItsOccurrencesAreOver() {
        let bounded = DismissedEvents()
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(tuesday)
            .restoring(wednesday, scope: .allFutureEvents)
        #expect(bounded.pruned(at: F.date(6, 12), meetings: standups) == bounded.pruned(at: F.date(6, 12), meetings: []))
        #expect(bounded.pruned(at: F.date(6, 12), meetings: standups).seriesRules == bounded.seriesRules, "before the bound")
        #expect(bounded.pruned(at: F.date(7, 9), meetings: standups).isEmpty, "the rule goes with its exception")

        // Tuesday's standup runs past Wednesday 9:00 this time.
        let long = Self.standup(6, minutes: 25 * 60)
        let running = bounded.restoring(long).dismissing(long)
        #expect(running.pruned(at: F.date(7, 9, 30), meetings: [long]).seriesRules == bounded.seriesRules, "still running")
        #expect(running.pruned(at: F.date(7, 10), meetings: [long]).isEmpty)
    }

    // MARK: Fixture runs

    // What a fixture run starts with (`AppModel`): the occurrences dismissed one by one, a repeating event's
    // included, without the series rules or the exceptions that only matter inside them.
    @Test func withoutSeriesRules() {
        let alone = DismissedEvents().dismissing(F.workshop).dismissing(monday)
        let stored = alone.dismissing(tuesday, scope: .allFutureEvents).restoring(wednesday)
        #expect(!stored.seriesRules.isEmpty)
        #expect(!stored.exceptions.isEmpty)
        #expect(stored.withoutSeriesRules == alone)
        #expect(dismissedDays(stored.withoutSeriesRules) == [5])
    }

    // MARK: Saved format

    @Test func jsonRoundTrip() throws {
        let dismissed = DismissedEvents()
            .dismissing(F.workshop)
            .dismissing(F.review)
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(wednesday)
            .restoring(friday, scope: .allFutureEvents)
            .dismissing(Self.standup(12), scope: .allFutureEvents)
        let data = try JSONEncoder().encode(dismissed)
        #expect(try JSONDecoder().decode(DismissedEvents.self, from: data) == dismissed)

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["occurrences", "seriesRules", "exceptions"])
        let occurrences = try #require(object["occurrences"] as? [String: Any])
        #expect(Set(occurrences.keys) == [F.workshop.id, F.review.id])
        let seriesRules = try #require(object["seriesRules"] as? [String: [Any]])
        #expect(seriesRules["standup"]?.count == 2)
        let exceptions = try #require(object["exceptions"] as? [String: Any])
        #expect(Set(exceptions.keys) == [wednesday.id])
    }

    // 1.2.0 saved a plain object of occurrence id → end: each entry reads as an occurrence dismissed on its own,
    // with no start or series. Once its event is fetched it gets them, so a series choice covers it like any
    // other.
    @Test func entriesSavedBy120ReadAndJoinSeriesChoices() throws {
        let data = try JSONEncoder().encode([thursday.id: thursday.end, F.workshop.id: F.workshop.end])
        let old = try JSONDecoder().decode(DismissedEvents.self, from: data)
        #expect(old.occurrences == [thursday.id: .init(end: thursday.end), F.workshop.id: .init(end: F.workshop.end)])
        #expect(old.isDismissed(thursday))
        #expect(old.isDismissed(F.workshop))
        #expect(!old.isDismissed(F.planning))
        #expect(old.restoring(thursday).restoring(F.workshop) == DismissedEvents())
        #expect(old.pruned(at: F.date(5, 8), meetings: []) == old, "kept as it is while its event isn't fetched")

        let completed = old.pruned(at: F.date(5, 8), meetings: standups + [F.workshop])
        #expect(completed == DismissedEvents().dismissing(thursday).dismissing(F.workshop))
        #expect(completed.dismissing(monday, scope: .allFutureEvents)
                    == DismissedEvents().dismissing(F.workshop).dismissing(monday, scope: .allFutureEvents))
        #expect(completed.restoring(monday, scope: .allFutureEvents) == DismissedEvents().dismissing(F.workshop))

        #expect(try JSONDecoder().decode(DismissedEvents.self, from: Data("{}".utf8)).isEmpty)
    }

    /// Neither shape, or the new one with a part missing or of the wrong kind.
    @Test(arguments: [
        #"["val"]"#,
        #"{"val": "tonight"}"#,
        #"{"val": null}"#,
        #"{"occurrences": {}}"#,
        #"{"occurrences": {}, "seriesRules": {}, "exceptions": []}"#,
        #"{"occurrences": {"val": {"start": 0}}, "seriesRules": {}, "exceptions": {}}"#,
    ])
    func unreadableJSONDoesNotDecode(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(DismissedEvents.self, from: Data(json.utf8))
        }
    }
}
