import Foundation
import Observation
import UserNotifications

public enum BoardTab {
    case today
    case tomorrow
    case overview
}

@MainActor
@Observable
public final class Store {
    public private(set) var state: BoardState
    public var draft: String = ""
    public var isClosing = false
    public var tab: BoardTab = .today
    public var choices: [String: CloseChoice] = [:]
    public var dropNotes: [String: String] = [:]
    public var lastDropped: [Item] = []
    public var escapeLocked = false
    public var isSettings = false
    public var overview = OverviewStats()
    public var onChange: (() -> Void)?
    /// Fired when `setRoot` moves the board, so the app shell can re-point
    /// its file watcher at the new folder.
    public var onRootChange: (() -> Void)?

    public var openItems: [Item] { state.open }
    public var doneItems: [Item] { state.done }
    public var pendingItems: [Item] { state.pending }
    public var canFinishClose: Bool {
        isClosing && !openItems.isEmpty && openItems.allSatisfy { choices[$0.id] != nil }
    }

    /// Keep-all shortcut. Hidden once every row has a choice (finish is the way out).
    public var canKeepAll: Bool {
        isClosing && !canFinishClose && openItems.contains { canKeep($0) }
    }

    public var stayDays: Int { state.stayDays }
    public var skipWeekends: Bool { state.skipWeekends }

    public func canKeep(_ item: Item) -> Bool {
        item.canKeep(stayDays: state.stayDays)
    }

    public func isLastDay(_ item: Item) -> Bool {
        item.isOpen && !canKeep(item)
    }

    public var dayUnit: String { state.skipWeekends ? "weekday" : "day" }
    public var nightUnit: String { state.skipWeekends ? "weeknight" : "night" }

    public var closeHint: String {
        if state.stayDays <= 1 {
            return "no keep. leftovers drop the next \(dayUnit). drop can take a why."
        }
        if state.stayDays == 2 {
            return "one extra \(nightUnit). last day drops. drop can take a why."
        }
        return "leftovers stay \(state.stayDays) \(dayUnit)s. last day drops. drop can take a why."
    }

    public var visibleOpen: [Item] {
        switch tab {
        case .today: state.open
        case .tomorrow: state.pending.filter(\.isOpen)
        case .overview: []
        }
    }

    public var visibleDone: [Item] {
        switch tab {
        case .today: state.done
        case .tomorrow: state.pending.filter { !$0.isOpen }
        case .overview: []
        }
    }

    public var visibleIsEmpty: Bool { visibleOpen.isEmpty && visibleDone.isEmpty }

    public var progressDone: Int { visibleDone.count }
    public var progressTotal: Int { visibleOpen.count + visibleDone.count }
    public var progressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return Double(progressDone) / Double(progressTotal)
    }
    public var progressLabel: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    public var headerLabel: String {
        if isSettings { return "stay length" }
        let today = BoardDate.boardStamp(now(), skipWeekends: state.skipWeekends)
        switch tab {
        case .today:
            return BoardDate.weekdayLabel(today)
        case .tomorrow:
            return BoardDate.weekdayLabel(BoardDate.nextWeekdayStamp(after: today, skipWeekends: state.skipWeekends))
        case .overview:
            return overview.vsLastLabel
        }
    }

    public func showToday() {
        tab = .today
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        escapeLocked = false
        relayout()
    }

    public func showTomorrow() {
        tab = .tomorrow
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        escapeLocked = false
        relayout()
    }

    public func showOverview() {
        tab = .overview
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        escapeLocked = false
        refreshOverview()
        relayout()
    }

    public func showSettings() {
        isSettings = true
        isClosing = false
        choices = [:]
        dropNotes = [:]
        escapeLocked = false
        relayout()
    }

    public func setStayDays(_ n: Int) {
        let next = BoardState.clampStayDays(n)
        guard next != state.stayDays else { return }
        state.stayDays = next
        persist()
        relayout()
    }

    public func setSkipWeekends(_ value: Bool) {
        guard value != state.skipWeekends else { return }
        state.skipWeekends = value
        persist()
        rolloverIfNeeded()
        relayout()
    }

    private var liveURL: URL
    private var archiveDir: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let now: () -> Date
    private let defaults: UserDefaults

    public init(root: URL? = nil, now: @escaping () -> Date = { Date() }, defaults: UserDefaults = .standard) {
        self.now = now
        self.defaults = defaults
        let resolved = root ?? Store.defaultRoot(defaults: defaults)
        liveURL = resolved.appendingPathComponent("state.json")
        archiveDir = resolved.appendingPathComponent("archive")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        state = BoardState(date: BoardDate.boardStamp(now(), skipWeekends: false), skipWeekends: false)
        try? FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        load()
        applyLoadedState()
    }

    private func applyLoadedState() {
        markInheritedCarry()
        rolloverIfNeeded()
        refreshOverview()
    }

    public func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        rolloverIfNeeded()
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        escapeLocked = false
        if tab == .tomorrow {
            state.pending.append(.make(text, now: now()))
        } else {
            state.items.append(.make(text, now: now()))
        }
        draft = ""
        persist()
    }

    public func complete(_ id: String, note: String = "") {
        guard var item = item(id) else { return }
        guard item.isOpen else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.doneAt = now()
        item.note = trimmed.isEmpty ? nil : trimmed
        write(item)
        persist()
    }

    public func reopen(_ id: String) {
        guard var item = item(id) else { return }
        guard !item.isOpen else { return }
        item.doneAt = nil
        item.note = nil
        write(item)
        persist()
    }

    public func relayout() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    public func dismiss(_ id: String, note: String = "") {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if tab == .tomorrow {
            guard let i = state.pending.firstIndex(where: { $0.id == id }) else { return }
            var item = state.pending.remove(at: i)
            item.note = trimmed.isEmpty ? nil : trimmed
            state.dismissed.append(item)
        } else {
            guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
            var item = state.items.remove(at: i)
            item.note = trimmed.isEmpty ? nil : trimmed
            state.dismissed.append(item)
            choices[id] = nil
            dropNotes[id] = nil
            if isClosing, openItems.isEmpty {
                commitClose(kind: CloseKind.manual)
                return
            }
        }
        persist()
    }

    public func remove(_ id: String) {
        dismiss(id, note: "")
    }

    public func rename(_ id: String, to raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            remove(id)
            return
        }
        if tab == .tomorrow {
            guard let i = state.pending.firstIndex(where: { $0.id == id }) else { return }
            state.pending[i].text = text
        } else {
            guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[i].text = text
        }
        persist()
    }

    public func setContext(_ id: String, to raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = text.isEmpty ? nil : text
        if tab == .tomorrow {
            guard let i = state.pending.firstIndex(where: { $0.id == id }) else { return }
            state.pending[i].context = value
        } else {
            guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[i].context = value
        }
        persist()
    }

    public func beginClose() {
        rolloverIfNeeded()
        if openItems.isEmpty {
            commitClose(kind: CloseKind.manual)
            return
        }
        isClosing = true
        choices = [:]
        dropNotes = [:]
        for item in openItems where isLastDay(item) {
            choices[item.id] = .drop
        }
        relayout()
    }

    public func cancelClose() {
        isClosing = false
        choices = [:]
        dropNotes = [:]
        relayout()
    }

    public func choose(id: String, _ choice: CloseChoice) {
        guard isClosing else { return }
        if choice == .keep, let item = openItems.first(where: { $0.id == id }), !canKeep(item) {
            return
        }
        if choices[id] == choice {
            return
        }
        choices[id] = choice
        if choice == .keep { dropNotes[id] = nil }
        relayout()
    }

    public func finishClose() {
        guard canFinishClose else { return }
        commitClose(kind: CloseKind.manual)
    }

    public func dropRest() {
        guard isClosing else { return }
        for item in openItems where choices[item.id] == nil {
            choices[item.id] = .drop
        }
        commitClose(kind: CloseKind.manual)
    }

    public func keepAll() {
        guard isClosing else { return }
        for item in openItems {
            choices[item.id] = canKeep(item) ? .keep : .drop
        }
        commitClose(kind: CloseKind.manual)
    }

    @discardableResult
    public func rolloverIfNeeded() -> [Item] {
        let today = BoardDate.boardStamp(now(), skipWeekends: state.skipWeekends)
        if state.skipWeekends,
           BoardDate.isWeekend(stamp: state.date),
           let dated = BoardDate.date(from: state.date) {
            let snapped = BoardDate.boardStamp(dated, skipWeekends: state.skipWeekends)
            if snapped != state.date {
                state.date = snapped
                persist()
            }
        }
        if state.date > today {
            let parked = state.items.map { item -> Item in
                var copy = item
                copy.doneAt = nil
                return copy
            }
            state.pending.append(contentsOf: parked)
            state.items = []
            state.date = today
            persist()
            return []
        }
        guard state.date < today else { return [] }
        var dropped: [Item] = []
        while state.date < BoardDate.boardStamp(now(), skipWeekends: state.skipWeekends) {
            dropped.append(contentsOf: applyOneNight())
        }
        lastDropped = dropped
        tab = .today
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        persist()
        if !dropped.isEmpty {
            notifyExpired(dropped)
        }
        return dropped
    }

    private func applyOneNight() -> [Item] {
        var autoCarry: [Item] = []
        var dropped: [Item] = []
        for item in state.open {
            if canKeep(item) {
                var next = item
                next.doneAt = nil
                next.nights += 1
                autoCarry.append(next)
            } else {
                dropped.append(item)
            }
        }
        writeArchive(
            date: state.date,
            kind: CloseKind.expired,
            completed: state.done,
            carried: autoCarry,
            dropped: state.dismissed + dropped
        )
        let nextDate = BoardDate.nextWeekdayStamp(after: state.date, skipWeekends: state.skipWeekends)
        let incoming = state.pending.filter(\.isOpen) + autoCarry
        state = BoardState(
            date: nextDate,
            stayDays: state.stayDays,
            skipWeekends: state.skipWeekends,
            items: incoming
        )
        return dropped
    }

    private func commitClose(kind: String) {
        let today = BoardDate.boardStamp(now(), skipWeekends: state.skipWeekends)
        let completed = state.done
        var carried: [Item] = []
        var dropped: [Item] = []
        for item in state.open {
            switch choices[item.id] ?? .drop {
            case .keep:
                var next = item
                next.doneAt = nil
                next.nights += 1
                carried.append(next)
            case .drop:
                dropped.append(withNote(item))
            }
        }
        dropped.append(contentsOf: state.dismissed)
        writeArchive(
            date: state.date,
            kind: kind,
            completed: completed,
            carried: carried,
            dropped: dropped
        )
        lastDropped = dropped
        var pending = state.pending
        pending.append(contentsOf: carried)
        state = BoardState(
            date: today,
            stayDays: state.stayDays,
            skipWeekends: state.skipWeekends,
            items: [],
            pending: pending
        )
        tab = .today
        isClosing = false
        isSettings = false
        choices = [:]
        dropNotes = [:]
        persist()
    }

    private func withNote(_ item: Item) -> Item {
        var copy = item
        let raw = dropNotes[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copy.note = raw.isEmpty ? nil : raw
        return copy
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: liveURL.path) else {
            persist()
            return
        }
        do {
            let data = try Data(contentsOf: liveURL)
            state = try decoder.decode(BoardState.self, from: data)
        } catch {
            Log.store.error("failed to read live state: \(error.localizedDescription, privacy: .public)")
            state = BoardState(date: BoardDate.boardStamp(now(), skipWeekends: false), skipWeekends: false)
        }
    }

    /// Picks up edits made to `state.json` by another process while Robyty is
    /// running (e.g. an external tool with the board folder open). No-op if
    /// the file is unreadable, unchanged, or a close is in progress — closing
    /// keys `choices`/`dropNotes` by item id, and swapping `state` out from
    /// under it could strand those choices against items that no longer
    /// match.
    public func reloadFromDiskIfChanged() {
        guard !isClosing else { return }
        guard FileManager.default.fileExists(atPath: liveURL.path) else { return }
        guard let data = try? Data(contentsOf: liveURL) else { return }
        guard let decoded = try? decoder.decode(BoardState.self, from: data) else {
            Log.store.error("failed to parse externally-changed live state")
            return
        }
        guard decoded != state else { return }
        Log.store.notice("reloaded externally-changed live state")
        state = decoded
        applyLoadedState()
        onChange?()
    }

    private func markInheritedCarry() {
        let today = state.date
        var changed = false
        for i in state.items.indices {
            let created = BoardDate.stamp(state.items[i].createdAt)
            let elapsed = BoardDate.weekdaySteps(from: created, to: today, skipWeekends: state.skipWeekends)
            if elapsed > state.items[i].nights {
                state.items[i].nights = elapsed
                changed = true
            }
        }
        if changed { persist() }
    }

    private func item(_ id: String) -> Item? {
        if tab == .tomorrow {
            return state.pending.first(where: { $0.id == id })
        }
        return state.items.first(where: { $0.id == id })
    }

    private func write(_ item: Item) {
        if tab == .tomorrow {
            guard let i = state.pending.firstIndex(where: { $0.id == item.id }) else { return }
            state.pending[i] = item
        } else {
            guard let i = state.items.firstIndex(where: { $0.id == item.id }) else { return }
            state.items[i] = item
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: liveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            encoder.userInfo[BoardCoding.stayDays] = state.stayDays
            let data = try encoder.encode(state)
            try data.write(to: liveURL, options: .atomic)
            refreshOverview()
            onChange?()
        } catch {
            Log.store.error("failed to write live state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeArchive(
        date: String,
        kind: String,
        completed: [Item],
        carried: [Item],
        dropped: [Item]
    ) {
        if completed.isEmpty, carried.isEmpty, dropped.isEmpty { return }
        let archive = DayArchive(
            date: date,
            closedAt: now(),
            closeKind: kind,
            completed: completed,
            carried: carried,
            dropped: dropped
        )
        let url = archiveDir.appendingPathComponent("\(date).json")
        do {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            encoder.userInfo[BoardCoding.stayDays] = state.stayDays
            let data = try encoder.encode(archive)
            try data.write(to: url, options: .atomic)
            refreshOverview()
        } catch {
            Log.store.error("failed to write archive: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshOverview() {
        var byDay = completedFromArchives()
        let liveIds = Set(state.done.map(\.id))
        let archivedIds = archivedCompletedIds(on: state.date)
        byDay[state.date, default: 0] += liveIds.subtracting(archivedIds).count

        let todayStamp = BoardDate.boardStamp(now(), skipWeekends: state.skipWeekends)
        guard let todayDate = BoardDate.date(from: todayStamp),
              let thisMonday = BoardDate.monday(of: todayStamp)
        else {
            overview = OverviewStats()
            return
        }
        let lastMonday = BoardDate.addWeeks(-1, to: thisMonday)
        let thisEnd = min(todayDate, BoardDate.weekEnd(ofMonday: thisMonday, skipWeekends: state.skipWeekends))
        let lastEnd = BoardDate.weekEnd(ofMonday: lastMonday, skipWeekends: state.skipWeekends)

        func total(from start: Date, to end: Date) -> Int {
            var n = 0
            var day = start
            while day <= end {
                if !state.skipWeekends || !BoardDate.isWeekend(day) {
                    n += byDay[BoardDate.stamp(day)] ?? 0
                }
                day = BoardDate.addDays(1, to: day)
            }
            return n
        }

        var stats = OverviewStats()
        stats.thisWeek = total(from: thisMonday, to: thisEnd)
        stats.lastWeek = total(from: lastMonday, to: lastEnd)

        let startStamp = byDay.keys.sorted().first
        stats.startedOn = startStamp
        if let startStamp, let startMonday = BoardDate.monday(of: startStamp) {
            var weeks = 0
            var completed = 0
            var monday = startMonday
            while monday <= thisMonday {
                let end = min(BoardDate.weekEnd(ofMonday: monday, skipWeekends: state.skipWeekends), todayDate)
                completed += total(from: monday, to: end)
                weeks += 1
                monday = BoardDate.addWeeks(1, to: monday)
            }
            stats.weekCount = weeks
            stats.weeklyAverage = weeks > 0 ? Double(completed) / Double(weeks) : 0
        }
        overview = stats
    }

    private func completedFromArchives() -> [String: Int] {
        var map: [String: Int] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: archiveDir,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let archive = try? decoder.decode(DayArchive.self, from: data)
            else { continue }
            if state.skipWeekends, BoardDate.isWeekend(stamp: archive.date) { continue }
            map[archive.date] = archive.completed.count
        }
        return map
    }

    private func archivedCompletedIds(on date: String) -> Set<String> {
        let url = archiveDir.appendingPathComponent("\(date).json")
        guard let data = try? Data(contentsOf: url),
              let archive = try? decoder.decode(DayArchive.self, from: data)
        else { return [] }
        return Set(archive.completed.map(\.id))
    }

    private func notifyExpired(_ items: [Item]) {
        guard Bundle.main.bundleIdentifier == "com.chriskipp.robyty" else { return }
        let content = UNMutableNotificationContent()
        content.title = "Робити"
        let n = items.count
        content.body = n == 1
            ? "1 item expired overnight."
            : "\(n) items expired overnight."
        let req = UNNotificationRequest(
            identifier: "robyty.expired.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    static let rootOverrideKey = "RobytyRootOverride"

    public static func defaultRoot(defaults: UserDefaults = .standard) -> URL {
        if let env = ProcessInfo.processInfo.environment["ROBYTY_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let saved = defaults.string(forKey: rootOverrideKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Robyty", isDirectory: true)
    }

    /// The folder currently holding `state.json` and `archive/`.
    public var rootPath: String { liveURL.deletingLastPathComponent().path }

    /// Set by `changeRoot` when a move fails; cleared on the next attempt.
    public var rootChangeError: String?

    /// Set by `changeRoot` on success; cleared on the next attempt.
    public var rootChangeConfirmed = false

    /// Moves the live board and archive to `newRoot` and remembers the choice
    /// for future launches. No-op if `newRoot` is already the current root.
    public func setRoot(to newRoot: URL) throws {
        let target = newRoot.standardizedFileURL
        let current = liveURL.deletingLastPathComponent().standardizedFileURL
        guard target != current else { return }

        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let newLiveURL = target.appendingPathComponent("state.json")
        let newArchiveDir = target.appendingPathComponent("archive")

        if FileManager.default.fileExists(atPath: liveURL.path) {
            if FileManager.default.fileExists(atPath: newLiveURL.path) {
                try FileManager.default.removeItem(at: newLiveURL)
            }
            try FileManager.default.moveItem(at: liveURL, to: newLiveURL)
        }

        try FileManager.default.createDirectory(at: newArchiveDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: archiveDir.path) {
            for entry in try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil) {
                let dest = newArchiveDir.appendingPathComponent(entry.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: entry, to: dest)
            }
            try? FileManager.default.removeItem(at: archiveDir)
        }

        liveURL = newLiveURL
        archiveDir = newArchiveDir
        defaults.set(target.path, forKey: Store.rootOverrideKey)
        onRootChange?()
    }

    /// UI entry point: takes a raw path from a text field, expands `~`, and
    /// reports the outcome via `rootChangeError` / `rootChangeConfirmed`
    /// instead of throwing.
    public func changeRoot(to path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = (trimmed as NSString).expandingTildeInPath
        do {
            try setRoot(to: URL(fileURLWithPath: expanded, isDirectory: true))
            rootChangeError = nil
            rootChangeConfirmed = true
        } catch {
            rootChangeConfirmed = false
            rootChangeError = error.localizedDescription
        }
    }
}
