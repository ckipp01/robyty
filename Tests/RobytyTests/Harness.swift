import Foundation
import RobytyCore

enum Fixtures {
    static let thursday = "2026-08-20"
    static let friday = "2026-08-21"
    static let saturday = "2026-08-22"
    static let sunday = "2026-08-23"
    static let monday = "2026-08-24"
    static let tuesday = "2026-08-25"
    static let wednesday = "2026-08-26"
    static let thisFriday = "2026-08-28"
    static let nextMonday = "2026-08-31"

    /// Noon Europe/Amsterdam on a yyyy-MM-dd stamp.
    static func noon(_ stamp: String) -> Date {
        guard let day = BoardDate.date(from: stamp),
              let noon = BoardDate.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
        else {
            fatalError("bad fixture stamp \(stamp)")
        }
        return noon
    }
}

@MainActor
final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

enum Codec {
    static func encoder(stayDays: Int = BoardState.defaultStayDays) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        encoder.userInfo[BoardCoding.stayDays] = stayDays
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
enum Harness {
    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("robyty-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func writeLive(_ state: BoardState, root: URL) throws {
        let url = root.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Codec.encoder(stayDays: state.stayDays).encode(state).write(to: url)
    }

    static func writeArchive(_ archive: DayArchive, root: URL) throws {
        let dir = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Codec.encoder(stayDays: BoardState.defaultStayDays).encode(archive).write(to: dir.appendingPathComponent("\(archive.date).json"))
    }

    static func readLive(root: URL) throws -> BoardState {
        let url = root.appendingPathComponent("state.json")
        return try Codec.decoder().decode(BoardState.self, from: Data(contentsOf: url))
    }

    static func readArchive(root: URL, date: String) throws -> DayArchive {
        let url = root.appendingPathComponent("archive/\(date).json")
        return try Codec.decoder().decode(DayArchive.self, from: Data(contentsOf: url))
    }

    static func open(root: URL, clock: TestClock) -> Store {
        Store(root: root, now: { clock.date })
    }

    static func fresh(clock: TestClock, skipWeekends: Bool = true) throws -> (Store, URL) {
        let root = try makeRoot()
        let store = open(root: root, clock: clock)
        if store.skipWeekends != skipWeekends {
            store.setSkipWeekends(skipWeekends)
        }
        return (store, root)
    }

    static func lastDay(_ text: String, now: Date, stayDays: Int) -> Item {
        var item = Item.make(text, now: now)
        item.nights = max(stayDays - 1, 0)
        return item
    }

    @discardableResult
    static func add(_ store: Store, _ text: String) -> String {
        store.draft = text
        store.addDraft()
        return store.state.items.last!.id
    }
}
