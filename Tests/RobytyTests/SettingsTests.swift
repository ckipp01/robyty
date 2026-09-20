import Foundation
import RobytyCore

@MainActor
enum SettingsTests {
    static func run() {
        T.test("freshBoardDefaultsToFiveWeekdays") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, _) = try Harness.fresh(clock: clock)
            try T.eq(store.stayDays, 5)
            try T.ok(!store.isSettings)
            store.showSettings()
            try T.ok(store.isSettings)
            try T.eq(store.headerLabel, "stay length")
            store.showToday()
            try T.ok(!store.isSettings)
        }

        T.test("freshBoardDefaultsToNotSkippingWeekends") {
            let clock = TestClock(Fixtures.noon(Fixtures.saturday))
            let root = try Harness.makeRoot()
            let store = Harness.open(root: root, clock: clock)
            try T.ok(!store.skipWeekends)
            try T.eq(store.state.date, Fixtures.saturday)
        }

        T.test("setSkipWeekendsTogglesAndPersists") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock, skipWeekends: false)
            try T.ok(!store.skipWeekends)
            store.setSkipWeekends(true)
            try T.ok(store.skipWeekends)
            let live = try Harness.readLive(root: root)
            try T.ok(live.skipWeekends)

            let reopened = Harness.open(root: root, clock: clock)
            try T.ok(reopened.skipWeekends)
        }

        T.test("setStayDaysClampsAndPersists") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock)
            store.setStayDays(0)
            try T.eq(store.stayDays, 1)
            store.setStayDays(99)
            try T.eq(store.stayDays, 10)
            store.setStayDays(3)
            try T.eq(store.stayDays, 3)
            let live = try Harness.readLive(root: root)
            try T.eq(live.stayDays, 3)

            let reopened = Harness.open(root: root, clock: clock)
            try T.eq(reopened.stayDays, 3)
        }

        T.test("stayDaysOneDropsNextWeekday") {
            let clock = TestClock(Fixtures.noon(Fixtures.friday))
            let (store, root) = try Harness.fresh(clock: clock)
            store.setStayDays(1)
            Harness.add(store, "today only")
            try T.ok(!store.canKeep(store.state.items[0]))
            store.beginClose()
            try T.ok(store.canFinishClose)
            try T.ok(!store.canKeepAll)

            let monday = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.monday)))
            try T.ok(monday.state.items.isEmpty)
            try T.eq(monday.lastDropped.map(\.text), ["today only"])
        }

        T.test("stayDaysFiveSurvivesFourNightsThenDrops") {
            let root = try Harness.makeRoot()
            let item = Item.make("week item", now: Fixtures.noon(Fixtures.monday))
            try Harness.writeLive(
                BoardState(date: Fixtures.monday, stayDays: 5, items: [item]),
                root: root
            )

            let friday = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.thisFriday)))
            try T.eq(friday.state.date, Fixtures.thisFriday)
            try T.eq(friday.state.items.count, 1)
            try T.eq(friday.state.items[0].nights, 4)
            try T.ok(friday.isLastDay(friday.state.items[0]))
            try T.ok(!friday.canKeep(friday.state.items[0]))

            let next = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.nextMonday)))
            try T.eq(next.state.date, Fixtures.nextMonday)
            try T.ok(next.state.items.isEmpty)
            try T.eq(next.lastDropped.map(\.text), ["week item"])
        }

        T.test("raisingStayDaysLetsOldLastDayBeKept") {
            let root = try Harness.makeRoot()
            let item = Harness.lastDay("was last day", now: Fixtures.noon(Fixtures.thursday), stayDays: 2)
            try Harness.writeLive(
                BoardState(date: Fixtures.friday, stayDays: 2, items: [item]),
                root: root
            )
            let store = Harness.open(root: root, clock: TestClock(Fixtures.noon(Fixtures.friday)))
            try T.ok(!store.canKeep(store.state.items[0]))
            store.setStayDays(5)
            try T.ok(store.canKeep(store.state.items[0]))
            store.beginClose()
            store.choose(id: item.id, .keep)
            store.finishClose()
            try T.eq(store.state.pending.map(\.text), ["was last day"])
            try T.eq(store.state.pending[0].nights, 2)
        }

        T.test("changeRootMovesLiveStateAndArchive") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, oldRoot) = try Harness.fresh(clock: clock)
            Harness.add(store, "moving item")
            try Harness.writeArchive(
                DayArchive(date: Fixtures.friday, closedAt: Fixtures.noon(Fixtures.friday), closeKind: "manual"),
                root: oldRoot
            )

            let newRoot = try Harness.makeRoot().appendingPathComponent("nested", isDirectory: true)
            store.changeRoot(to: newRoot.path)

            try T.ok(store.rootChangeError == nil)
            try T.eq(store.rootPath, newRoot.standardizedFileURL.path)
            try T.ok(!FileManager.default.fileExists(atPath: oldRoot.appendingPathComponent("state.json").path))

            let moved = try Harness.readLive(root: newRoot)
            try T.eq(moved.items.map(\.text), ["moving item"])
            let movedArchive = try Harness.readArchive(root: newRoot, date: Fixtures.friday)
            try T.eq(movedArchive.date, Fixtures.friday)

            let reopened = Harness.open(root: newRoot, clock: clock)
            try T.eq(reopened.state.items.map(\.text), ["moving item"])
        }

        T.test("changeRootPersistsForFutureDefaultRootLookups") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let suiteName = "robyty-test-\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let root = try Harness.makeRoot()
            let store = Store(root: root, now: { clock.date }, defaults: testDefaults)
            let newRoot = try Harness.makeRoot()

            store.changeRoot(to: newRoot.path)
            try T.ok(store.rootChangeError == nil)
            try T.eq(Store.defaultRoot(defaults: testDefaults), newRoot.standardizedFileURL)
        }

        T.test("changeRootToSameLocationIsNoop") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock)
            Harness.add(store, "stays put")
            store.changeRoot(to: root.path)
            try T.ok(store.rootChangeError == nil)
            try T.eq(store.state.items.map(\.text), ["stays put"])
        }

        T.test("changeRootToBlockedPathReportsErrorAndKeepsOldState") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, oldRoot) = try Harness.fresh(clock: clock)
            Harness.add(store, "stuck here")

            let blocker = try Harness.makeRoot().appendingPathComponent("blocker")
            try Data().write(to: blocker)

            store.changeRoot(to: blocker.path)
            try T.ok(store.rootChangeError != nil)
            try T.eq(store.rootPath, oldRoot.standardizedFileURL.path)
            let stillThere = try Harness.readLive(root: oldRoot)
            try T.eq(stillThere.items.map(\.text), ["stuck here"])
        }

        T.test("encodedCarriedIsLastDayUnderCurrentStay") {
            var item = Item.make("open", now: Fixtures.noon(Fixtures.friday))
            item.nights = 1
            let data = try Codec.encoder(stayDays: 5).encode(item)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try T.ok(obj["carried"] as? Bool == false)
            try T.ok(obj["nights"] as? Int == 1)

            let last = try Codec.encoder(stayDays: 2).encode(item)
            let lastObj = try JSONSerialization.jsonObject(with: last) as! [String: Any]
            try T.ok(lastObj["carried"] as? Bool == true)
        }
    }
}
