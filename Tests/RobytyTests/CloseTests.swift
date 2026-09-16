import Foundation
import RobytyCore

@MainActor
enum CloseTests {
    static func run() {
        T.test("beginCloseWithNoOpenCommitsImmediately") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "done today")
            store.complete(id, note: "shipped")

            store.beginClose()
            try T.ok(!store.isClosing)
            try T.ok(!store.canFinishClose)
            try T.ok(store.state.items.isEmpty)
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.closeKind, CloseKind.manual)
            try T.eq(archive.completed.map(\.text), ["done today"])
            try T.ok(archive.carried.isEmpty)
            try T.ok(archive.dropped.isEmpty)
        }

        T.test("beginCloseEntersClosingUntilEveryRowHasAChoice") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let keepID = Harness.add(store, "keep me")
            let dropID = Harness.add(store, "drop me")

            store.beginClose()
            try T.ok(store.isClosing)
            try T.ok(!store.canFinishClose)
            try T.ok(store.canKeepAll)
            store.finishClose()
            try T.ok(store.isClosing, "finish is a no-op until every row is chosen")
            try T.eq(store.state.items.count, 2)

            store.choose(id: keepID, .keep)
            try T.ok(!store.canFinishClose)
            try T.ok(store.canKeepAll)

            store.choose(id: dropID, .drop)
            try T.ok(store.canFinishClose)
            try T.ok(!store.canKeepAll)
        }

        T.test("finishStaysAvailableAfterReclickingTheSameChoice") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let a = Harness.add(store, "alpha")
            let b = Harness.add(store, "beta")
            store.beginClose()
            store.choose(id: a, .keep)
            store.choose(id: b, .drop)
            try T.ok(store.canFinishClose)

            store.choose(id: a, .keep)
            store.choose(id: b, .drop)
            try T.eq(store.choices[a], Optional(CloseChoice.keep))
            try T.eq(store.choices[b], Optional(CloseChoice.drop))
            try T.ok(store.canFinishClose)
        }

        T.test("switchingKeepAndDropClearsDropNoteOnKeep") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "maybe")
            store.beginClose()
            store.choose(id: id, .drop)
            store.dropNotes[id] = "not this week"
            store.choose(id: id, .keep)
            try T.eq(store.choices[id], Optional(CloseChoice.keep))
            try T.ok(store.dropNotes[id] == nil || store.dropNotes[id]?.isEmpty == true)
        }

        T.test("fridayMixedKeepAndDropThenFinishParksKeepForMonday") {
            let root = try Harness.makeRoot()
            let keep = Item.make("keep to monday", now: Fixtures.noon(Fixtures.friday))
            let drop = Item.make("drop tonight", now: Fixtures.noon(Fixtures.friday))
            let last = Harness.lastDay("already used the night", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            var done = Item.make("shipped", now: Fixtures.noon(Fixtures.friday))
            done.doneAt = Fixtures.noon(Fixtures.friday)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [keep, drop, last, done]),
                root: root
            )
            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))

            store.beginClose()
            try T.eq(store.choices[last.id], Optional(CloseChoice.drop))
            try T.ok(!store.canFinishClose)
            try T.ok(store.canKeepAll)

            store.choose(id: keep.id, .keep)
            store.choose(id: drop.id, .drop)
            store.dropNotes[drop.id] = "Harman took this"
            try T.ok(store.canFinishClose)
            try T.ok(!store.canKeepAll)

            store.choose(id: last.id, .drop)
            try T.ok(store.canFinishClose)

            store.finishClose()
            try T.ok(!store.isClosing)
            try T.ok(store.state.items.isEmpty)
            try T.eq(store.state.date, Fixtures.friday)
            try T.eq(store.state.pending.map(\.text), ["keep to monday"])
            try T.eq(store.state.pending[0].nights, 1)
            try T.eq(store.tab, BoardTab.today)

            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.closeKind, CloseKind.manual)
            try T.eq(archive.completed.map(\.text), ["shipped"])
            try T.eq(archive.carried.map(\.text), ["keep to monday"])
            try T.eq(Set(archive.dropped.map(\.text)), Set(["drop tonight", "already used the night"]))
            try T.eq(archive.dropped.first { $0.text == "drop tonight" }?.note, "Harman took this")

            let monday = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(monday.state.date, Fixtures.monday)
            try T.eq(monday.state.items.map(\.text), ["keep to monday"])
            try T.eq(monday.state.items[0].nights, 1)
            try T.ok(monday.state.pending.isEmpty)
        }

        T.test("carriedOnlyCloseCanFinishImmediately") {
            let root = try Harness.makeRoot()
            let a = Harness.lastDay("old a", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            let b = Harness.lastDay("old b", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [a, b]),
                root: root
            )
            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))

            store.beginClose()
            try T.ok(store.canFinishClose)
            try T.ok(!store.canKeepAll)
            store.choose(id: a.id, .keep)
            try T.eq(store.choices[a.id], Optional(CloseChoice.drop))

            store.finishClose()
            try T.ok(!store.isClosing)
            try T.ok(store.state.pending.isEmpty)
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(Set(archive.dropped.map(\.text)), Set(["old a", "old b"]))
        }

        T.test("finishCloseDoesNothingWhileARowIsUnchosen") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let a = Harness.add(store, "chosen")
            Harness.add(store, "not yet")
            store.beginClose()
            store.choose(id: a, .keep)
            store.finishClose()

            try T.ok(store.isClosing)
            try T.eq(store.state.items.count, 2)
            let files = try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("archive"),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
            try T.ok(files.isEmpty)
        }

        T.test("dropRestFillsUnchosenThenCommits") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let keepID = Harness.add(store, "keep")
            Harness.add(store, "unchosen becomes drop")
            store.beginClose()
            store.choose(id: keepID, .keep)
            store.dropRest()

            try T.ok(!store.isClosing)
            try T.eq(store.state.pending.map(\.text), ["keep"])
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.carried.map(\.text), ["keep"])
            try T.eq(archive.dropped.map(\.text), ["unchosen becomes drop"])
        }

        T.test("keepAllKeepsUncarriedAndDropsCarried") {
            let root = try Harness.makeRoot()
            let fresh = Item.make("new friday", now: Fixtures.noon(Fixtures.friday))
            let old = Harness.lastDay("from thursday", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [fresh, old]),
                root: root
            )
            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))

            store.beginClose()
            try T.ok(store.canKeepAll)
            store.keepAll()

            try T.ok(!store.isClosing)
            try T.eq(store.state.pending.map(\.text), ["new friday"])
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.carried.map(\.text), ["new friday"])
            try T.eq(archive.dropped.map(\.text), ["from thursday"])
        }

        T.test("cancelCloseLeavesItemsAndClearsChoices") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "still here")
            store.beginClose()
            store.choose(id: id, .drop)
            store.cancelClose()

            try T.ok(!store.isClosing)
            try T.ok(store.choices.isEmpty)
            try T.eq(store.state.items.map(\.text), ["still here"])
        }

        T.test("switchingTabAbandonsCloseWithoutCommitting") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "still here")
            store.beginClose()
            store.choose(id: id, .keep)
            store.showTomorrow()

            try T.ok(!store.isClosing)
            try T.ok(store.choices.isEmpty)
            try T.eq(store.state.items.map(\.text), ["still here"])
            let files = try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("archive"),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
            try T.ok(files.isEmpty)
        }

        T.test("closePreservesExistingPendingThenMondayMerges") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            store.showTomorrow()
            store.draft = "already monday"
            store.addDraft()
            store.showToday()
            let keepID = Harness.add(store, "friday leftover")
            store.beginClose()
            store.choose(id: keepID, .keep)
            store.finishClose()

            try T.eq(Set(store.state.pending.map(\.text)), Set(["already monday", "friday leftover"]))
            try T.eq(store.state.pending.first { $0.text == "friday leftover" }?.nights, Optional(1))
            try T.eq(store.state.pending.first { $0.text == "already monday" }?.nights, Optional(0))

            let monday = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.eq(Set(monday.state.items.map(\.text)), Set(["already monday", "friday leftover"]))
        }

        T.test("dismissLastOpenItemDuringCloseCommits") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "gone")
            store.beginClose()
            store.dismiss(id, note: "not this")
            try T.ok(!store.isClosing)
            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.dropped.map(\.text), ["gone"])
            try T.eq(archive.dropped[0].note, "not this")
        }

        T.test("midDayDismissJoinsArchiveDroppedOnFinish") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            let gone = Harness.add(store, "dismissed earlier")
            let keepID = Harness.add(store, "keep")
            store.dismiss(gone, note: "Harman")
            store.beginClose()
            store.choose(id: keepID, .keep)
            store.finishClose()

            let archive = try Harness.readArchive(root: root, date: Fixtures.friday)
            try T.eq(archive.dropped.map(\.text), ["dismissed earlier"])
            try T.eq(archive.dropped[0].note, "Harman")
            try T.eq(archive.carried.map(\.text), ["keep"])
        }

        T.test("chooseIsIgnoredWhenNotClosing") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "open")
            store.choose(id: id, .keep)
            try T.ok(store.choices.isEmpty)
            store.dropRest()
            store.keepAll()
            try T.eq(store.state.items.count, 1)
            try T.ok(!store.isClosing)
        }

        T.test("fridayCloseEmptyTodayShowsParkedOnTomorrow") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, _) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "monday item")
            store.beginClose()
            store.choose(id: id, .keep)
            store.finishClose()

            try T.ok(store.visibleIsEmpty)
            store.showTomorrow()
            try T.eq(store.headerLabel, "monday 24 aug")
            try T.eq(store.visibleOpen.map(\.text), ["monday item"])
        }
    }
}
