import Foundation
import RobytyCore

@MainActor
enum ReloadTests {
    static func run() {
        T.test("reloadPicksUpExternalDoneMarkAndNote") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock)
            let id = Harness.add(store, "write docs")
            try T.ok(store.state.items[0].isOpen)

            var external = store.state
            external.items[0].doneAt = Fixtures.noon(Fixtures.monday)
            external.items[0].note = "done externally"
            try Harness.writeLive(external, root: root)

            store.reloadFromDiskIfChanged()
            try T.ok(!store.state.items[0].isOpen)
            try T.eq(store.state.items[0].note, "done externally")
            try T.eq(store.state.items[0].id, id)
        }

        T.test("reloadIsNoopWhenFileUnchanged") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, _) = try Harness.fresh(clock: clock)
            Harness.add(store, "steady item")
            let before = store.state
            store.reloadFromDiskIfChanged()
            try T.eq(store.state, before)
        }

        T.test("reloadSkippedWhileClosing") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock)
            Harness.add(store, "mid close")
            store.beginClose()
            try T.ok(store.isClosing)

            var external = store.state
            external.items[0].text = "changed under close"
            try Harness.writeLive(external, root: root)

            store.reloadFromDiskIfChanged()
            try T.eq(store.state.items[0].text, "mid close")
        }

        T.test("reloadIgnoresUnreadableExternalWrite") {
            let clock = TestClock(Fixtures.noon(Fixtures.monday))
            let (store, root) = try Harness.fresh(clock: clock)
            Harness.add(store, "untouched")
            let before = store.state
            try Data("not json".utf8).write(to: root.appendingPathComponent("state.json"))
            store.reloadFromDiskIfChanged()
            try T.eq(store.state, before)
        }
    }
}
