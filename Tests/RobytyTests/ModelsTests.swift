import Foundation
import RobytyCore

@MainActor
enum ModelsTests {
    static func run() {
        T.test("decodeItemMissingNoteAndContext") {
            let json = """
            {
              "id": "abcd1234",
              "text": "Ping Bernardo",
              "created_at": "2026-08-21T10:00:00Z",
              "done_at": null,
              "carried": false
            }
            """
            let item = try Codec.decoder().decode(Item.self, from: Data(json.utf8))
            try T.ok(item.note == nil)
            try T.ok(item.context == nil)
            try T.ok(item.isOpen)
            try T.ok(item.canKeep(stayDays: 5))
            try T.eq(item.nights, 0)
        }

        T.test("decodeItemBlankNoteAndContextBecomeNil") {
            let json = """
            {
              "id": "abcd1234",
              "text": "Ping Bernardo",
              "created_at": "2026-08-21T10:00:00Z",
              "done_at": null,
              "carried": false,
              "note": "  ",
              "context": ""
            }
            """
            let item = try Codec.decoder().decode(Item.self, from: Data(json.utf8))
            try T.ok(item.note == nil)
            try T.ok(item.context == nil)
        }

        T.test("encodeItemOmitsEmptyNoteAndContext") {
            let item = Item.make("Ping Bernardo", now: Fixtures.noon(Fixtures.friday))
            let data = try Codec.encoder().encode(item)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try T.ok(obj["note"] == nil)
            try T.ok(obj["context"] == nil)
            try T.ok(obj["text"] as? String == "Ping Bernardo")
            try T.ok(obj["nights"] as? Int == 0)
            try T.ok(obj["carried"] as? Bool == false)
        }

        T.test("encodeItemKeepsNonEmptyNoteAndContext") {
            var item = Item.make("Ping Bernardo", now: Fixtures.noon(Fixtures.friday))
            item.note = "handed off"
            item.context = "Bernie: One Tap"
            let data = try Codec.encoder().encode(item)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try T.ok(obj["note"] as? String == "handed off")
            try T.ok(obj["context"] as? String == "Bernie: One Tap")
        }

        T.test("decodeBoardStateMissingDismissed") {
            let json = """
            {
              "version": 1,
              "date": "2026-08-21",
              "items": [],
              "pending": []
            }
            """
            let state = try Codec.decoder().decode(BoardState.self, from: Data(json.utf8))
            try T.ok(state.dismissed.isEmpty)
            try T.eq(state.version, 1)
            try T.eq(state.openCount, 0)
        }

        T.test("encodeBoardStateWritesDerivedOpenCount") {
            let item = Item.make("open", now: Fixtures.noon(Fixtures.friday))
            var done = Item.make("done", now: Fixtures.noon(Fixtures.friday))
            done.doneAt = Fixtures.noon(Fixtures.friday)
            let state = BoardState(date: Fixtures.friday, items: [item, done])
            let data = try Codec.encoder().encode(state)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try T.ok(obj["open_count"] as? Int == 1)
            try T.eq(state.openCount, 1)
            try T.eq(state.done.count, 1)
        }

        T.test("decodeItemMissingNightsDefaultsToZero") {
            let json = """
            {
              "id": "abcd1234",
              "text": "leftover",
              "created_at": "2026-08-21T10:00:00Z",
              "done_at": null,
              "carried": true
            }
            """
            let item = try Codec.decoder().decode(Item.self, from: Data(json.utf8))
            try T.eq(item.nights, 0)
            try T.ok(item.canKeep(stayDays: 5))
        }

        T.test("decodeBoardStateMissingStayDaysDefaultsToFive") {
            let json = """
            {
              "version": 1,
              "date": "2026-08-21",
              "items": [],
              "pending": []
            }
            """
            let state = try Codec.decoder().decode(BoardState.self, from: Data(json.utf8))
            try T.eq(state.stayDays, 5)
        }

        T.test("lastDayItemCannotKeep") {
            var item = Item.make("leftover", now: Fixtures.noon(Fixtures.thursday))
            item.nights = 1
            try T.ok(item.isOpen)
            try T.ok(!item.canKeep(stayDays: 2))
            try T.ok(item.canKeep(stayDays: 5))
        }

        T.test("overviewLabels") {
            var first = OverviewStats()
            first.thisWeek = 2
            first.lastWeek = 0
            first.weekCount = 1
            try T.eq(first.vsLastLabel, "first week")
            try T.eq(first.averageLabel, "0")

            var even = OverviewStats()
            even.thisWeek = 4
            even.lastWeek = 4
            even.weekCount = 2
            even.weeklyAverage = 4
            try T.eq(even.vsLastLabel, "even with last week")
            try T.eq(even.averageLabel, "4")

            var up = OverviewStats()
            up.thisWeek = 6
            up.lastWeek = 4
            up.weekCount = 2
            up.weeklyAverage = 3.5
            try T.eq(up.vsLastLabel, "+2 vs last week")
            try T.eq(up.averageLabel, "3.5")
        }
    }
}
