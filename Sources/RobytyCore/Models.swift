import Foundation

public enum BoardCoding {
    public static let stayDays = CodingUserInfoKey(rawValue: "robyty.stayDays")!
}

public struct Item: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var createdAt: Date
    public var doneAt: Date?
    public var nights: Int
    public var note: String?
    public var context: String?

    public var isOpen: Bool { doneAt == nil }

    public func canKeep(stayDays: Int) -> Bool {
        isOpen && nights < max(stayDays - 1, 0)
    }

    enum CodingKeys: String, CodingKey {
        case id, text
        case createdAt = "created_at"
        case doneAt = "done_at"
        case nights, carried, note, context
    }

    public init(
        id: String,
        text: String,
        createdAt: Date,
        doneAt: Date? = nil,
        nights: Int = 0,
        note: String? = nil,
        context: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.nights = max(nights, 0)
        self.note = note
        self.context = context
    }

    public static func make(_ text: String, now: Date = Date()) -> Item {
        Item(
            id: String(UUID().uuidString.prefix(8)).lowercased(),
            text: text,
            createdAt: now,
            doneAt: nil,
            nights: 0,
            note: nil,
            context: nil
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        nights = max(try c.decodeIfPresent(Int.self, forKey: .nights) ?? 0, 0)
        let rawNote = try c.decodeIfPresent(String.self, forKey: .note)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        note = (rawNote?.isEmpty == false) ? rawNote : nil
        let rawContext = try c.decodeIfPresent(String.self, forKey: .context)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        context = (rawContext?.isEmpty == false) ? rawContext : nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encode(nights, forKey: .nights)
        let stay = encoder.userInfo[BoardCoding.stayDays] as? Int ?? BoardState.defaultStayDays
        try c.encode(nights >= max(stay - 1, 0), forKey: .carried)
        if let note, !note.isEmpty {
            try c.encode(note, forKey: .note)
        }
        if let context, !context.isEmpty {
            try c.encode(context, forKey: .context)
        }
    }
}

public struct BoardState: Codable, Equatable, Sendable {
    public static let minStayDays = 1
    public static let maxStayDays = 10
    public static let defaultStayDays = 5

    public var version: Int
    public var date: String
    public var stayDays: Int
    public var skipWeekends: Bool
    public var items: [Item]
    public var pending: [Item]
    public var dismissed: [Item]

    public var open: [Item] { items.filter(\.isOpen) }
    public var done: [Item] { items.filter { !$0.isOpen } }
    public var openCount: Int { open.count }

    enum CodingKeys: String, CodingKey {
        case version, date, items, pending, dismissed
        case openCount = "open_count"
        case stayDays = "stay_days"
        case skipWeekends = "skip_weekends"
    }

    public init(
        version: Int = 1,
        date: String,
        stayDays: Int = BoardState.defaultStayDays,
        skipWeekends: Bool = true,
        items: [Item] = [],
        pending: [Item] = [],
        dismissed: [Item] = []
    ) {
        self.version = version
        self.date = date
        self.stayDays = BoardState.clampStayDays(stayDays)
        self.skipWeekends = skipWeekends
        self.items = items
        self.pending = pending
        self.dismissed = dismissed
    }

    public static func clampStayDays(_ n: Int) -> Int {
        min(max(n, minStayDays), maxStayDays)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        date = try c.decode(String.self, forKey: .date)
        stayDays = BoardState.clampStayDays(
            try c.decodeIfPresent(Int.self, forKey: .stayDays) ?? BoardState.defaultStayDays
        )
        // Missing key means the file predates this setting. Default to the new
        // general behavior (every day counts) rather than the old hardcoded skip.
        skipWeekends = try c.decodeIfPresent(Bool.self, forKey: .skipWeekends) ?? false
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        pending = try c.decodeIfPresent([Item].self, forKey: .pending) ?? []
        dismissed = try c.decodeIfPresent([Item].self, forKey: .dismissed) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(date, forKey: .date)
        try c.encode(stayDays, forKey: .stayDays)
        try c.encode(skipWeekends, forKey: .skipWeekends)
        try c.encode(openCount, forKey: .openCount)
        try c.encode(items, forKey: .items)
        try c.encode(pending, forKey: .pending)
        try c.encode(dismissed, forKey: .dismissed)
    }
}

public struct DayArchive: Codable, Sendable {
    public var date: String
    public var closedAt: Date
    public var closeKind: String
    public var completed: [Item]
    public var carried: [Item]
    public var dropped: [Item]

    enum CodingKeys: String, CodingKey {
        case date
        case closedAt = "closed_at"
        case closeKind = "close_kind"
        case completed, carried, dropped
    }

    public init(
        date: String,
        closedAt: Date,
        closeKind: String,
        completed: [Item] = [],
        carried: [Item] = [],
        dropped: [Item] = []
    ) {
        self.date = date
        self.closedAt = closedAt
        self.closeKind = closeKind
        self.completed = completed
        self.carried = carried
        self.dropped = dropped
    }
}

public enum CloseKind {
    public static let manual = "manual"
    public static let expired = "expired"
}

public enum CloseChoice: Equatable {
    case keep
    case drop
}

public enum BoardDate {
    public static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        return cal
    }()

    public static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public static func isWeekend(_ date: Date) -> Bool {
        let day = calendar.component(.weekday, from: date)
        return day == 1 || day == 7
    }

    public static func isWeekend(stamp: String) -> Bool {
        guard let date = date(from: stamp) else { return false }
        return isWeekend(date)
    }

    public static func lastWeekday(onOrBefore date: Date, skipWeekends: Bool = true) -> Date {
        guard skipWeekends else { return date }
        var d = date
        while isWeekend(d) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return d
    }

    public static func nextWeekday(after date: Date, skipWeekends: Bool = true) -> Date {
        let d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        guard skipWeekends else { return d }
        var stepped = d
        while isWeekend(stepped) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: stepped) else { break }
            stepped = next
        }
        return stepped
    }

    public static func boardStamp(_ date: Date = Date(), skipWeekends: Bool = true) -> String {
        stamp(lastWeekday(onOrBefore: date, skipWeekends: skipWeekends))
    }

    public static func nextWeekdayStamp(after stamp: String, skipWeekends: Bool = true) -> String {
        guard let date = date(from: stamp) else { return stamp }
        return self.stamp(nextWeekday(after: date, skipWeekends: skipWeekends))
    }

    /// Day hops from `from` to `to`. With `skipWeekends`, Thursday to Friday is 1 and Friday to Monday is 1;
    /// without it, every calendar day (including Saturday and Sunday) counts as one hop.
    public static func weekdaySteps(from: String, to: String, skipWeekends: Bool = true) -> Int {
        guard from < to else { return 0 }
        var n = 0
        var stamp = from
        while stamp < to {
            let next = nextWeekdayStamp(after: stamp, skipWeekends: skipWeekends)
            if next <= stamp { break }
            n += 1
            stamp = next
            if n > 400 { break }
        }
        return n
    }

    public static func friday(ofMonday monday: Date) -> Date {
        addDays(4, to: monday)
    }

    public static func weekEnd(ofMonday monday: Date, skipWeekends: Bool = true) -> Date {
        skipWeekends ? friday(ofMonday: monday) : addDays(6, to: monday)
    }

    public static func date(from stamp: String) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: stamp)
    }

    public static var iso: Calendar {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    public static func monday(of stamp: String) -> Date? {
        guard let date = date(from: stamp) else { return nil }
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return iso.date(from: parts)
    }

    public static func addDays(_ n: Int, to date: Date) -> Date {
        iso.date(byAdding: .day, value: n, to: date) ?? date
    }

    public static func addWeeks(_ n: Int, to date: Date) -> Date {
        iso.date(byAdding: .weekOfYear, value: n, to: date) ?? date
    }

    public static func shortDay(_ stamp: String) -> String {
        guard let date = date(from: stamp) else { return stamp }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: date).lowercased()
    }

    public static func weekdayLabel(_ stamp: String) -> String {
        guard let date = date(from: stamp) else { return stamp }
        let w = DateFormatter()
        w.calendar = calendar
        w.timeZone = calendar.timeZone
        w.locale = Locale(identifier: "en_GB")
        w.dateFormat = "EEEE d MMM"
        return w.string(from: date).lowercased()
    }
}

public struct OverviewStats: Equatable, Sendable {
    public var thisWeek: Int = 0
    public var lastWeek: Int = 0
    public var weeklyAverage: Double = 0
    public var weekCount: Int = 0
    public var startedOn: String?
    public var thisWeekLabel: String = "this week"
    public var lastWeekLabel: String = "last week"

    public init() {}

    public var averageLabel: String {
        if weekCount == 0 { return "0" }
        if abs(weeklyAverage - weeklyAverage.rounded()) < 0.05 {
            return "\(Int(weeklyAverage.rounded()))"
        }
        return String(format: "%.1f", weeklyAverage)
    }

    public var vsLastLabel: String {
        let d = thisWeek - lastWeek
        if weekCount < 2 { return "first week" }
        if d == 0 { return "even with last week" }
        if d > 0 { return "+\(d) vs last week" }
        return "\(d) vs last week"
    }

    public var sinceLabel: String {
        guard let startedOn else { return "no days closed yet" }
        let weeks = weekCount == 1 ? "1 week" : "\(weekCount) weeks"
        return "since \(BoardDate.shortDay(startedOn)) · \(weeks)"
    }

    public var barMax: Double {
        max(Double(max(thisWeek, lastWeek)), weeklyAverage, 1)
    }
}
