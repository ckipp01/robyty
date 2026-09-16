import Foundation
import RobytyCore

@MainActor
enum StoreTests {
    static func run() {
        T.test("addCompleteReopenAndDismiss") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)

            store.draft = "Ping Bernardo"
            store.addDraft()
            try T.eq(store.state.items.count, 1)
            try T.eq(store.state.date, Fixtures.friday)
            let id = store.state.items[0].id
            try T.eq(BoardDate.stamp(store.state.items[0].createdAt), Fixtures.friday)
            try T.eq(store.progressFraction, 0)
            try T.eq(store.progressLabel, "0%")

            store.complete(id, note: "shipped")
            try T.ok(store.state.items[0].doneAt != nil)
            try T.eq(store.state.items[0].note, "shipped")
            try T.eq(store.progressFraction, 1)
            try T.eq(store.progressLabel, "100%")

            store.reopen(id)
            try T.ok(store.state.items[0].isOpen)
            try T.ok(store.state.items[0].note == nil)

            store.dismiss(id, note: "Harman took this")
            try T.ok(store.state.items.isEmpty)
            try T.eq(store.state.dismissed.count, 1)
            try T.eq(store.state.dismissed[0].note, "Harman took this")
        }

        T.test("completeWithoutNoteLeavesNoteNil") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            store.draft = "tiny"
            store.addDraft()
            store.complete(store.state.items[0].id, note: "  ")
            try T.ok(store.state.items[0].note == nil)
            try T.ok(store.state.items[0].doneAt != nil)
        }

        T.test("setContextAndRename") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            store.draft = "Ping Bernardo"
            store.addDraft()
            let id = store.state.items[0].id

            store.setContext(id, to: "Bernie: One Tap")
            try T.eq(store.state.items[0].context, "Bernie: One Tap")
            store.setContext(id, to: "  ")
            try T.ok(store.state.items[0].context == nil)

            store.rename(id, to: "Ping Bernie")
            try T.eq(store.state.items[0].text, "Ping Bernie")
            store.rename(id, to: "")
            try T.ok(store.state.items.isEmpty)
            try T.eq(store.state.dismissed.count, 1)
        }

        T.test("tomorrowAddGoesToPending") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            store.showTomorrow()
            store.draft = "Monday standup"
            store.addDraft()
            try T.ok(store.state.items.isEmpty)
            try T.eq(store.state.pending.count, 1)
            try T.eq(store.headerLabel, "monday 24 aug")
            try T.eq(store.visibleOpen.count, 1)
        }

        T.test("progressIgnoresOverviewTab") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            store.draft = "a"
            store.addDraft()
            store.showOverview()
            try T.eq(store.progressTotal, 0)
            try T.ok(store.visibleIsEmpty)
            try T.eq(store.headerLabel, store.overview.vsLastLabel)
        }

        T.test("fridayHeaderStaysFridayOnWeekendClock") {
            let clock = TestClock(Fixtures.noon(Fixtures.saturday))
            let (store, _) = try Harness.fresh(clock: clock)
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.headerLabel, "friday 21 aug")
            store.showTomorrow()
            try T.eq(store.headerLabel, "monday 24 aug")
        }

        T.test("skipCloseOnFridaySurvivesWeekendThenCarriesMonday") {
            let root = try Harness.makeRoot()
            let item = Item.make("once", now: Fixtures.noon(Fixtures.friday))
            try Harness.writeLive(BoardState(date: Fixtures.friday, items: [item]), root: root)

            let saturday = TestClock(Fixtures.noon(Fixtures.saturday))
            var store = Harness.open(root: root, clock: saturday)
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.state.items.count, 1)
            try T.ok(store.state.items[0].nights == 0)

            store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.sunday)))
            try T.eq(store.state.date, Fixtures.friday)
            try T.ok(store.state.items[0].nights == 0)

            store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(store.state.date, Fixtures.monday)
            try T.eq(store.state.items.count, 1)
            try T.eq(store.state.items[0].nights, 1)
            try T.eq(store.state.items[0].text, "once")
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.closeKind, CloseKind.expired)
            try T.eq(archive.carried.count, 1)
            try T.ok(archive.dropped.isEmpty)
        }

        T.test("skipCloseOnFridayCountsSaturdayNightWhenNotSkippingWeekends") {
            let root = try Harness.makeRoot()
            let item = Item.make("once", now: Fixtures.noon(Fixtures.friday))
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, skipWeekends: false, items: [item]),
                root: root
            )

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.saturday)))
            try T.eq(store.state.date, Fixtures.saturday)
            try T.eq(store.state.items.count, 1)
            try T.eq(store.state.items[0].nights, 1)
        }

        T.test("overviewCountsWeekendArchivesWhenNotSkippingWeekends") {
            let root = try Harness.makeRoot()
            let saturdayDone = [Item.make("sat", now: Fixtures.noon(Fixtures.saturday))]
            try Harness.writeArchive(
                DayArchive(
                    date: Fixtures.saturday,
                    closedAt: Fixtures.noon(Fixtures.saturday),
                    closeKind: CloseKind.manual,
                    completed: saturdayDone
                ),
                root: root
            )
            try Harness.writeLive(
                BoardState(date: Fixtures.sunday, skipWeekends: false),
                root: root
            )

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.sunday)))
            try T.eq(store.overview.thisWeek, 1)
        }

        T.test("lastDayFridayExpiresMonday") {
            let root = try Harness.makeRoot()
            let item = Harness.lastDay("drop me", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [item]),
                root: root
            )

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(store.state.date, Fixtures.monday)
            try T.ok(store.state.items.isEmpty)
            try T.eq(store.lastDropped.map(\.text), ["drop me"])
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.closeKind, CloseKind.expired)
            try T.eq(archive.dropped.map(\.text), ["drop me"])
            try T.ok(archive.carried.isEmpty)
        }

        T.test("thursdayToFridayIsOneNight") {
            let root = try Harness.makeRoot()
            let item = Item.make("carry once", now: Fixtures.noon(Fixtures.thursday))
            try Harness.writeLive(BoardState(date: Fixtures.thursday, items: [item]), root: root)

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.state.items.count, 1)
            try T.eq(store.state.items[0].nights, 1)
        }

        T.test("weekendLiveDateSnapsToFriday") {
            let root = try Harness.makeRoot()
            let item = Item.make("still friday", now: Fixtures.noon(Fixtures.friday))
            try Harness.writeLive(BoardState(date: Fixtures.saturday, items: [item]), root: root)

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.saturday)))
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.state.items.count, 1)
            let live = try Harness.readLive(root: root)
            try T.eq(live.date, Fixtures.friday)
        }

        T.test("closeKeepParksForTomorrow") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            store.draft = "park"
            store.addDraft()
            let id = store.state.items[0].id
            store.beginClose()
            store.choose(id: id, .keep)
            store.finishClose()

            try T.ok(store.state.items.isEmpty)
            try T.eq(store.state.pending.count, 1)
            try T.eq(store.state.pending[0].nights, 1)
            try T.eq(store.state.date, Fixtures.friday)
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.closeKind, CloseKind.manual)
            try T.eq(archive.carried.map(\.text), ["park"])
        }

        T.test("closeDropWritesNote") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            store.draft = "skip"
            store.addDraft()
            let id = store.state.items[0].id
            store.beginClose()
            store.choose(id: id, .drop)
            store.dropNotes[id] = "not this week"
            store.finishClose()

            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.dropped.count, 1)
            try T.eq(archive.dropped[0].note, "not this week")
            try T.ok(store.state.pending.isEmpty)
        }

        T.test("cannotKeepOnLastDay") {
            let root = try Harness.makeRoot()
            let item = Harness.lastDay("second night", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [item]),
                root: root
            )
            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))

            store.beginClose()
            try T.eq(store.choices[item.id], Optional(CloseChoice.drop))
            store.choose(id: item.id, .keep)
            try T.eq(store.choices[item.id], Optional(CloseChoice.drop))
        }

        T.test("contextSurvivesFridayToMondayCarry") {
            let root = try Harness.makeRoot()
            var item = Item.make("Ping Bernardo", now: Fixtures.noon(Fixtures.friday))
            item.context = "Bernie: One Tap"
            try Harness.writeLive(BoardState(date: Fixtures.friday, items: [item]), root: root)

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(store.state.items[0].context, "Bernie: One Tap")
            try T.eq(store.state.items[0].nights, 1)
        }

        T.test("markInheritedCarryWhenCreatedEarlierThanBoardDate") {
            let root = try Harness.makeRoot()
            let item = Item.make("from thursday", now: Fixtures.noon(Fixtures.thursday))
            try Harness.writeLive(BoardState(date: Fixtures.friday, items: [item]), root: root)

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.state.items[0].nights, 1)
        }

        T.test("pendingBecomesTodayAfterSkipClose") {
            let root = try Harness.makeRoot()
            let today = Item.make("today leftover", now: Fixtures.noon(Fixtures.friday))
            let parked = Item.make("already monday", now: Fixtures.noon(Fixtures.friday))
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, items: [today], pending: [parked]),
                root: root
            )

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(store.state.date, Fixtures.monday)
            try T.eq(Set(store.state.items.map(\.text)), Set(["today leftover", "already monday"]))
            try T.eq(store.state.items.first { $0.text == "today leftover" }?.nights, Optional(1))
            try T.eq(store.state.items.first { $0.text == "already monday" }?.nights, Optional(0))
            try T.ok(store.state.pending.isEmpty)
        }

        T.test("overviewSkipsWeekendArchives") {
            let root = try Harness.makeRoot()
            let fridayDone = (1...3).map { Item.make("fri \($0)", now: Fixtures.noon(Fixtures.friday)) }
            let saturdayDone = (1...50).map { Item.make("sat \($0)", now: Fixtures.noon(Fixtures.saturday)) }
            let mondayDone = [Item.make("mon", now: Fixtures.noon(Fixtures.monday))]
            try Harness.writeArchive(
                DayArchive(
                    date: Fixtures.friday,
                    closedAt: Fixtures.noon(Fixtures.friday),
                    closeKind: CloseKind.manual,
                    completed: fridayDone
                ),
                root: root
            )
            try Harness.writeArchive(
                DayArchive(
                    date: Fixtures.saturday,
                    closedAt: Fixtures.noon(Fixtures.saturday),
                    closeKind: CloseKind.manual,
                    completed: saturdayDone
                ),
                root: root
            )
            try Harness.writeArchive(
                DayArchive(
                    date: Fixtures.monday,
                    closedAt: Fixtures.noon(Fixtures.monday),
                    closeKind: CloseKind.manual,
                    completed: mondayDone
                ),
                root: root
            )
            try Harness.writeLive(BoardState(date: Fixtures.tuesday), root: root)

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.tuesday)))
            try T.eq(store.overview.lastWeek, 3)
            try T.eq(store.overview.thisWeek, 1)
            try T.eq(store.overview.weekCount, 2)
            try T.eq(store.overview.weeklyAverage, 2)
            try T.eq(store.overview.vsLastLabel, "-2 vs last week")
        }

        T.test("overviewAddsLiveDoneNotAlreadyArchived") {
            let root = try Harness.makeRoot()
            var liveDone = Item.make("done today", now: Fixtures.noon(Fixtures.tuesday))
            liveDone.doneAt = Fixtures.noon(Fixtures.tuesday)
            try Harness.writeLive(
                BoardState(date: Fixtures.tuesday, items: [liveDone]),
                root: root
            )

            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.tuesday)))
            try T.eq(store.overview.thisWeek, 1)
        }

        T.test("emptyDraftDoesNotAdd") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            store.draft = "   "
            store.addDraft()
            try T.ok(store.state.items.isEmpty)
        }
    }
}
