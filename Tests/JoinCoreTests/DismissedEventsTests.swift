import Foundation
import Testing
@testable import JoinCore

struct DismissedEventsTests {
    typealias F = MenuBarFixtures

    /// A daily standup at 9:00, one series, like EventKit's: every occurrence shares the event identifier.
    private func standup(_ day: Int, _ hour: Int = 9, minutes: Double = 15) -> Meeting {
        let start = F.date(day, hour)
        return Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: start), title: "Standup",
                       start: start, end: start.addingTimeInterval(minutes * 60), seriesID: "standup")
    }

    private var monday: Meeting { standup(5) }
    private var tuesday: Meeting { standup(6) }
    private var wednesday: Meeting { standup(7) }
    private var thursday: Meeting { standup(8) }
    private var friday: Meeting { standup(9) }
    /// Every standup from Monday 5 to Friday 16 October.
    private var standups: [Meeting] { (5...16).map { standup($0) } }

    private func dismissedDays(_ dismissed: DismissedEvents, _ meetings: [Meeting]? = nil) -> [Int] {
        (meetings ?? standups).filter(dismissed.isDismissed).map { F.calendar.component(.day, from: $0.start) }
    }

    // MARK: One occurrence

    @Test func dismissAndRestore() {
        let none = DismissedEvents()
        #expect(none.isEmpty)
        #expect(!none.isDismissed(F.workshop))

        let dismissed = none.dismissing(F.workshop)
        #expect(!dismissed.isEmpty)
        #expect(dismissed.isDismissed(F.workshop))
        #expect(!dismissed.isDismissed(F.planning))
        #expect(dismissed.occurrences == [F.workshop.id: .init(start: F.workshop.start, end: F.workshop.end)], "kept until the occurrence ends")
        #expect(dismissed.seriesRules.isEmpty)
        #expect(dismissed.exceptions.isEmpty)
        #expect(dismissed.dismissing(F.workshop) == dismissed, "dismissing twice changes nothing")

        let both = dismissed.dismissing(F.planning)
        #expect(Set(both.occurrences.keys) == [F.workshop.id, F.planning.id])
        #expect(both.restoring(F.planning) == dismissed)
        #expect(dismissed.restoring(F.workshop) == none)
        #expect(dismissed.restoring(F.planning) == dismissed, "restoring what isn't dismissed changes nothing")
    }

    // An event that doesn't repeat has no series: All Future Events is This Event, both ways.
    @Test func allFutureEventsOfAOneOffEventIsThisEvent() {
        #expect(!F.workshop.isRepeating)
        #expect(DismissedEvents().dismissing(F.workshop, scope: .allFutureEvents) == DismissedEvents().dismissing(F.workshop))
        let dismissed = DismissedEvents().dismissing(F.workshop).dismissing(F.planning)
        #expect(dismissed.restoring(F.workshop, scope: .allFutureEvents) == dismissed.restoring(F.workshop))
    }

    // This Event on a repeating event: only that occurrence. Each occurrence has its own id, and so does an
    // occurrence moved to another start.
    @Test func thisEventDismissesOnlyThatOccurrence() {
        #expect(monday.isRepeating)
        let dismissed = DismissedEvents().dismissing(monday)
        #expect(dismissedDays(dismissed) == [5])
        #expect(dismissed.seriesRules.isEmpty)
        #expect(dismissed.occurrences[monday.id] == .init(start: monday.start, end: monday.end, seriesID: "standup"))
        #expect(!dismissed.isDismissed(standup(5, 10)), "moved to 10:00, it's a new occurrence")
        #expect(dismissed.restoring(monday) == DismissedEvents())
    }

    // MARK: All future events

    @Test func allFutureEventsDismissesThisOccurrenceAndEveryLaterOne() {
        let dismissed = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        #expect(dismissed.seriesRules == ["standup": [.init(from: wednesday.start)]])
        #expect(dismissed.occurrences.isEmpty)
        #expect(dismissedDays(dismissed) == Array(7...16), "Monday and Tuesday aren't, everything from Wednesday is")
        #expect(dismissed.isDismissed(standup(30)), "beyond the 7-day window, and not fetched yet")
        #expect(dismissed.isDismissed(standup(8, 11)), "an occurrence moved on its own is still in the series")
        #expect(!dismissed.isDismissed(standup(7, 8)), "moved before the occurrence the rule started from")

        // Only that series: another one, and an event with the same identifier that doesn't repeat, aren't.
        var other = standup(9)
        other.seriesID = "retro"
        #expect(!dismissed.isDismissed(other))
        var oneOff = standup(9)
        oneOff.seriesID = nil
        #expect(!dismissed.isDismissed(oneOff))

        #expect(dismissed.dismissing(friday, scope: .allFutureEvents) == dismissed, "Friday's already covered")
        #expect(dismissed.dismissing(wednesday, scope: .allFutureEvents) == dismissed, "twice changes nothing")
    }

    // Occurrences dismissed one by one from there on are covered by the rule, so their entries go; earlier ones
    // and other events stay.
    @Test func allFutureEventsReplacesLaterSingleEntriesOfTheSeries() {
        let singles = DismissedEvents().dismissing(monday).dismissing(thursday).dismissing(F.workshop)
        let dismissed = singles.dismissing(wednesday, scope: .allFutureEvents)
        #expect(Set(dismissed.occurrences.keys) == [monday.id, F.workshop.id])
        #expect(dismissedDays(dismissed) == [5] + Array(7...16))
        #expect(dismissed.isDismissed(F.workshop))
    }

    // Dismiss This Event inside a rule's range: already dismissed, so nothing changes, unless it had been
    // restored on its own, when the rule covers it again.
    @Test func thisEventInsideASeriesRule() {
        let rule = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        #expect(rule.dismissing(thursday) == rule)

        let restored = rule.restoring(thursday)
        #expect(!restored.isDismissed(thursday))
        #expect(restored.dismissing(thursday) == rule)
        #expect(rule.dismissing(tuesday) != rule, "before the rule, it's an occurrence of its own")
        #expect(rule.dismissing(tuesday).occurrences.keys.first == tuesday.id)
    }

    // All Future Events from an earlier occurrence than a rule's start moves the start back, and occurrences
    // restored on their own from there on are dismissed again.
    @Test func allFutureEventsFromEarlierMovesTheRuleBack() {
        let stored = DismissedEvents()
            .dismissing(thursday, scope: .allFutureEvents)
            .restoring(friday)
            .dismissing(tuesday)
        #expect(stored.exceptions.keys.first == friday.id)
        #expect(dismissedDays(stored) == [6, 8] + Array(10...16))

        let moved = stored.dismissing(monday, scope: .allFutureEvents)
        #expect(moved.seriesRules == ["standup": [.init(from: monday.start)]])
        #expect(moved.exceptions.isEmpty, "Friday is dismissed again")
        #expect(moved.occurrences.isEmpty, "Tuesday's entry is covered")
        #expect(moved == DismissedEvents().dismissing(monday, scope: .allFutureEvents))
        #expect(dismissedDays(moved) == Array(5...16))
    }

    // From a later occurrence inside the rule: the rule stays, and occurrences restored on their own from there
    // on are dismissed again, while an earlier restored one stays restored.
    @Test func allFutureEventsFromInsideARuleDismissesLaterExceptionsAgain() {
        let stored = DismissedEvents()
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(tuesday)
            .restoring(thursday)
        #expect(dismissedDays(stored) == [5, 7] + Array(9...16))

        let again = stored.dismissing(wednesday, scope: .allFutureEvents)
        #expect(again.seriesRules == stored.seriesRules)
        #expect(Set(again.exceptions.keys) == [tuesday.id])
        #expect(dismissedDays(again) == [5] + Array(7...16))
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

    // Restore This Event inside a rule: an exception for that occurrence, the rest stays dismissed. It goes at
    // the occurrence's end, like a dismissed one.
    @Test func restoreThisEventInsideASeriesRule() {
        let rule = DismissedEvents().dismissing(wednesday, scope: .allFutureEvents)
        let restored = rule.restoring(thursday)
        #expect(restored.exceptions == [thursday.id: .init(start: thursday.start, end: thursday.end, seriesID: "standup")])
        #expect(restored.seriesRules == rule.seriesRules)
        #expect(dismissedDays(restored) == [7] + Array(9...16))
        #expect(restored.restoring(thursday) == restored, "twice changes nothing")
        #expect(rule.restoring(tuesday) == rule, "Tuesday wasn't dismissed")
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
        #expect(!restored.isDismissed(standup(30)))
        #expect(restored.isDismissed(standup(8, 8)), "moved to 8:00, it starts before the occurrence restored from")
        #expect(restored.restoring(friday, scope: .allFutureEvents) == restored, "nothing left to restore after Thursday")

        // A single entry after a bounded rule comes back with a restore further back.
        let single = restored.dismissing(standup(12))
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

    // MARK: Pruning

    @Test func pruningDropsEventsThatHaveEnded() {
        let dismissed = DismissedEvents().dismissing(F.lunch).dismissing(F.workshop)
        #expect(dismissed.pruned(at: F.date(6, 13, 30), meetings: [F.lunch, F.workshop]) == dismissed, "both still on or to come")
        #expect(Set(dismissed.pruned(at: F.date(6, 14), meetings: [F.lunch, F.workshop]).occurrences.keys) == [F.workshop.id], "lunch ended at 2:00 PM")
        #expect(dismissed.pruned(at: F.date(6, 19, 30), meetings: [F.lunch, F.workshop]).isEmpty)
        #expect(DismissedEvents().pruned(at: F.date(6, 12), meetings: F.week).isEmpty)
    }

    // An event missing from the meetings (its calendar unchecked, a fetch that failed) is kept until its stored end.
    @Test func pruningKeepsAnUnknownEventUntilItsStoredEnd() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        #expect(dismissed.pruned(at: F.date(6, 16), meetings: []) == dismissed)
        #expect(dismissed.pruned(at: F.date(6, 19, 29), meetings: [F.lunch]) == dismissed)
        #expect(dismissed.pruned(at: F.date(6, 19, 30), meetings: []).isEmpty)
        #expect(dismissed.pruned(at: F.date(7, 9), meetings: [F.lunch]).isEmpty)
    }

    // Workshop, dismissed while it ran until 7:30 PM, now runs until 8:30 PM: it stays dismissed to the new end
    // rather than coming back at 7:30.
    @Test func pruningFollowsAnEventExtendedAfterItWasDismissed() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        var extended = F.workshop
        extended.end = F.date(6, 20, 30)

        let atOldEnd = dismissed.pruned(at: F.date(6, 19, 45), meetings: [extended])
        #expect(atOldEnd.isDismissed(F.workshop))
        #expect(atOldEnd.occurrences[F.workshop.id]?.end == extended.end, "the stored end follows the event")

        let earlier = dismissed.pruned(at: F.date(6, 16), meetings: [extended])
        #expect(earlier.occurrences[F.workshop.id]?.end == extended.end, "updated before the old end too")
        #expect(earlier.pruned(at: F.date(6, 19, 45), meetings: []) == earlier, "and kept if it then goes missing")

        #expect(atOldEnd.pruned(at: F.date(6, 20, 30), meetings: [extended]).isEmpty)
    }

    @Test func pruningFollowsAnEventShortenedAfterItWasDismissed() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        var shortened = F.workshop
        shortened.end = F.date(6, 17)
        #expect(dismissed.pruned(at: F.date(6, 16), meetings: [shortened]).occurrences[F.workshop.id]?.end == shortened.end)
        #expect(dismissed.pruned(at: F.date(6, 17, 30), meetings: [shortened]).isEmpty, "over at its new end")
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
        #expect(restored.pruned(at: F.date(7, 9, 20), meetings: [standup(7, minutes: 30)]).exceptions[wednesday.id]?.end
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
        let long = standup(6, minutes: 25 * 60)
        let running = bounded.restoring(long).dismissing(long)
        #expect(running.pruned(at: F.date(7, 9, 30), meetings: [long]).seriesRules == bounded.seriesRules, "still running")
        #expect(running.pruned(at: F.date(7, 10), meetings: [long]).isEmpty)
    }

    // Entries saved by 1.2.0 have no start or series. Once their event is fetched they get them, so a series
    // choice covers them like any other.
    @Test func pruningCompletesEntriesSavedBy120() throws {
        let old = try JSONDecoder().decode(DismissedEvents.self, from: JSONEncoder().encode([thursday.id: thursday.end]))
        #expect(old.occurrences == [thursday.id: .init(end: thursday.end)])
        #expect(old.isDismissed(thursday))

        let completed = old.pruned(at: F.date(5, 8), meetings: standups)
        #expect(completed == DismissedEvents().dismissing(thursday))
        #expect(completed.dismissing(monday, scope: .allFutureEvents) == DismissedEvents().dismissing(monday, scope: .allFutureEvents))
        #expect(completed.restoring(monday, scope: .allFutureEvents) == DismissedEvents())
        #expect(old.pruned(at: F.date(5, 8), meetings: []) == old, "kept as it is while its event isn't fetched")
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
        #expect(DismissedEvents().dismissing(F.workshop).withoutSeriesRules == DismissedEvents().dismissing(F.workshop),
                "nothing to drop")
        #expect(DismissedEvents().withoutSeriesRules == DismissedEvents())
    }

    // MARK: Saved format

    @Test func jsonRoundTrip() throws {
        let dismissed = DismissedEvents()
            .dismissing(F.workshop)
            .dismissing(F.review)
            .dismissing(monday, scope: .allFutureEvents)
            .restoring(wednesday)
            .restoring(friday, scope: .allFutureEvents)
            .dismissing(standup(12), scope: .allFutureEvents)
        let data = try JSONEncoder().encode(dismissed)
        #expect(try JSONDecoder().decode(DismissedEvents.self, from: data) == dismissed)
        #expect(try JSONDecoder().decode(DismissedEvents.self, from: JSONEncoder().encode(DismissedEvents())) == DismissedEvents())

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["occurrences", "seriesRules", "exceptions"])
        let occurrences = try #require(object["occurrences"] as? [String: Any])
        #expect(Set(occurrences.keys) == [F.workshop.id, F.review.id])
        let seriesRules = try #require(object["seriesRules"] as? [String: [Any]])
        #expect(seriesRules["standup"]?.count == 2)
        let exceptions = try #require(object["exceptions"] as? [String: Any])
        #expect(Set(exceptions.keys) == [wednesday.id])
    }

    // 1.2.0 saved a plain object of occurrence id → end: each entry reads as an occurrence dismissed on its own.
    @Test func jsonSavedBy120StillReads() throws {
        let data = try JSONEncoder().encode([F.workshop.id: F.workshop.end, F.review.id: F.review.end])
        let decoded = try JSONDecoder().decode(DismissedEvents.self, from: data)
        #expect(decoded.occurrences == [F.workshop.id: .init(end: F.workshop.end), F.review.id: .init(end: F.review.end)])
        #expect(decoded.seriesRules.isEmpty)
        #expect(decoded.exceptions.isEmpty)
        #expect(decoded.isDismissed(F.workshop))
        #expect(decoded.isDismissed(F.review))
        #expect(!decoded.isDismissed(F.planning))
        #expect(decoded.restoring(F.workshop).restoring(F.review) == DismissedEvents())
        #expect(decoded.pruned(at: F.date(6, 12), meetings: [F.workshop, F.review])
                    == DismissedEvents().dismissing(F.workshop).dismissing(F.review))
        #expect(try JSONDecoder().decode(DismissedEvents.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test func unreadableJSONDoesNotDecode() {
        for json in [#"not json"#, #"["val"]"#, #"{"val": "tonight"}"#, #"{"val": null}"#, #"3"#,
                     #"{"occurrences": {}}"#, #"{"occurrences": {}, "seriesRules": {}, "exceptions": []}"#,
                     #"{"occurrences": {"val": {"start": 0}}, "seriesRules": {}, "exceptions": {}}"#] {
            #expect(throws: (any Error).self, "\(json)") {
                try JSONDecoder().decode(DismissedEvents.self, from: Data(json.utf8))
            }
        }
    }
}
