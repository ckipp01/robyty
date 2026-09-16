import RobytyCore
import SwiftUI

private let boardWidth: CGFloat = 328

// Kanagawa (Gogh): same wave palette WezTerm uses.
private let ink = Color(hex: 0xDCD7BA)      // fujiWhite
private let inkMuted = Color(hex: 0x727169) // fujiGray
private let paper = Color(hex: 0x1F1F28)    // sumiInk3
private let paper2 = Color(hex: 0x2A2A37)   // sumiInk4
private let amber = Color(hex: 0xFFA066)    // surimiOrange
private let rust = Color(hex: 0xC34043)     // autumnRed
private let moss = Color(hex: 0x98BB6C)     // springGreen
private let inkDeep = Color(hex: 0x16161D)  // sumiInk0

private extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct BoardView: View {
    @Bindable var store: Store
    @FocusState private var inputFocused: Bool
    @State private var hoveredID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.tab != .overview, !store.isSettings {
                progressStrip
            }
            cap
            if store.isClosing {
                closeBody
            } else if store.isSettings {
                settingsBody
            } else if store.tab == .overview {
                overviewBody
            } else {
                liveBody
            }
        }
        .frame(width: boardWidth)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .tint(amber)
        .onAppear { focusDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .robytyBecameKey)) { _ in
            focusDraft()
        }
        .onChange(of: store.isClosing) { _, closing in
            if !closing, store.tab != .overview { focusDraft() }
        }
        .onChange(of: store.escapeLocked) { _, locked in
            if locked {
                inputFocused = false
            } else if !store.isClosing, !store.isSettings, store.tab != .overview {
                focusDraft()
            }
        }
        .onChange(of: store.tab) { _, tab in
            if tab == .today || tab == .tomorrow { focusDraft() }
            else { inputFocused = false }
        }
        .preferredColorScheme(.dark)
    }

    private func focusDraft() {
        guard store.tab != .overview, !store.isClosing, !store.isSettings, !store.escapeLocked else { return }
        inputFocused = false
        DispatchQueue.main.async { inputFocused = true }
    }

    private func lockEscape(_ locked: Bool) {
        store.escapeLocked = locked
        if locked { inputFocused = false }
    }

    private var cap: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("today") { store.showToday() }
                    .foregroundStyle(store.tab == .today && !store.isSettings && !store.isClosing ? ink : inkMuted)
                Button("tomorrow") { store.showTomorrow() }
                    .foregroundStyle(store.tab == .tomorrow && !store.isSettings ? ink : inkMuted)
                Button("overview") { store.showOverview() }
                    .foregroundStyle(store.tab == .overview && !store.isSettings ? ink : inkMuted)
                Button("settings") { store.showSettings() }
                    .foregroundStyle(store.isSettings ? ink : inkMuted)
                Spacer()
                if store.isClosing {
                    Button("back") { store.cancelClose() }
                        .foregroundStyle(inkMuted)
                } else if store.isSettings {
                    Button("back") { store.showToday() }
                        .foregroundStyle(inkMuted)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 12, weight: .medium))
            HStack {
                Text(store.headerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(inkMuted)
                if store.tab != .overview, !store.isSettings, store.progressTotal > 0 {
                    Spacer()
                    Text(store.progressLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(progressTint)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var progressStrip: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(inkDeep)
                Rectangle()
                    .fill(progressTint)
                    .frame(width: geo.size.width * store.progressFraction)
                    .animation(.easeInOut(duration: 0.28), value: store.progressFraction)
            }
        }
        .frame(height: 3)
        .accessibilityLabel("progress \(store.progressLabel)")
    }

    private var progressTint: Color {
        store.progressTotal > 0 && store.progressFraction >= 1 ? moss : amber
    }

    private var overviewBody: some View {
        let stats = store.overview
        return VStack(alignment: .leading, spacing: 16) {
            Text("completed")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(inkMuted)
            OverviewStat(
                title: stats.thisWeekLabel,
                value: "\(stats.thisWeek)",
                fraction: Double(stats.thisWeek) / stats.barMax,
                tint: amber
            )
            OverviewStat(
                title: stats.lastWeekLabel,
                value: "\(stats.lastWeek)",
                fraction: Double(stats.lastWeek) / stats.barMax,
                tint: inkMuted
            )
            OverviewStat(
                title: "weekly avg",
                value: stats.averageLabel,
                fraction: stats.weeklyAverage / stats.barMax,
                tint: moss
            )
            Text(stats.sinceLabel)
                .font(.system(size: 11))
                .foregroundStyle(inkMuted.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            if store.visibleIsEmpty {
                emptyHint
            } else {
                itemList
            }
            footer
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Text("▸")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(amber)
            TextField("add", text: $store.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .focused($inputFocused)
                .accessibilityIdentifier("robyty.add")
                .onSubmit {
                    store.addDraft()
                    inputFocused = true
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var emptyHint: some View {
        Text(store.tab == .tomorrow ? "nothing for tomorrow" : "nothing on the plate")
            .font(.system(size: 12))
            .foregroundStyle(inkMuted.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleOpen) { item in
                    ItemRow(
                        item: item,
                        hovered: hoveredID == item.id,
                        lastDay: store.isLastDay(item),
                        onComplete: { store.complete(item.id, note: $0) },
                        onReopen: { store.reopen(item.id) },
                        onRename: { store.rename(item.id, to: $0) },
                        onContext: { store.setContext(item.id, to: $0) },
                        onDismiss: { store.dismiss(item.id, note: $0) },
                        onLayout: { store.relayout() },
                        onEscapeLock: lockEscape
                    )
                    .onHover { hoveredID = $0 ? item.id : nil }
                }
                if !store.visibleDone.isEmpty, !store.visibleOpen.isEmpty {
                    Rectangle()
                        .fill(paper2)
                        .frame(height: 1)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                }
                ForEach(store.visibleDone) { item in
                    ItemRow(
                        item: item,
                        hovered: hoveredID == item.id,
                        lastDay: false,
                        onComplete: { store.complete(item.id, note: $0) },
                        onReopen: { store.reopen(item.id) },
                        onRename: { store.rename(item.id, to: $0) },
                        onContext: { store.setContext(item.id, to: $0) },
                        onDismiss: { store.dismiss(item.id, note: $0) },
                        onLayout: { store.relayout() },
                        onEscapeLock: lockEscape
                    )
                    .onHover { hoveredID = $0 ? item.id : nil }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerCount)
                .font(.system(size: 11))
                .foregroundStyle(inkMuted)
            Spacer()
            if store.tab == .today {
                Button(action: store.beginClose) {
                    Text("close day")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.openItems.isEmpty ? inkMuted : amber)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Carry leftovers to tomorrow, or they expire.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var footerCount: String {
        let n = store.visibleOpen.count
        if store.tab == .tomorrow {
            if n == 0 { return store.visibleDone.isEmpty ? "" : "ready for morning" }
            return n == 1 ? "1 for tomorrow" : "\(n) for tomorrow"
        }
        let parked = store.pendingItems.filter(\.isOpen).count
        var parts: [String] = []
        if n == 0 {
            if !store.doneItems.isEmpty { parts.append("all done") }
        } else {
            parts.append(n == 1 ? "1 open" : "\(n) open")
        }
        if parked > 0 {
            parts.append(parked == 1 ? "1 for tomorrow" : "\(parked) for tomorrow")
        }
        return parts.joined(separator: " · ")
    }

    private var closeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.closeHint)
                .font(.system(size: 11))
                .foregroundStyle(inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.openItems) { item in
                        CloseRow(
                            item: item,
                            choice: store.choices[item.id],
                            canKeep: store.canKeep(item),
                            note: Binding(
                                get: { store.dropNotes[item.id] ?? "" },
                                set: { store.dropNotes[item.id] = $0 }
                            ),
                            onKeep: { store.choose(id: item.id, .keep) },
                            onDrop: { store.choose(id: item.id, .drop) },
                            onLayout: { store.relayout() }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 360)

            HStack {
                Button("drop rest") { store.dropRest() }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(rust)
                Spacer()
                if store.canKeepAll {
                    Button("keep all") { store.keepAll() }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(amber)
                }
                Button("finish") { store.finishClose() }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.canFinishClose ? amber : inkMuted)
                    .disabled(!store.canFinishClose)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.skipWeekends
                ? "how many weekdays an item can stay. weekends do not count. friday to monday is one night."
                : "how many days an item can stay. every day counts, including weekends.")
                .font(.system(size: 11))
                .foregroundStyle(inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("-") { store.setStayDays(store.stayDays - 1) }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(store.stayDays > BoardState.minStayDays ? amber : inkMuted)
                    .disabled(store.stayDays <= BoardState.minStayDays)
                Text("\(store.stayDays)")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(ink)
                    .frame(minWidth: 36)
                Text(store.stayDays == 1 ? store.dayUnit : "\(store.dayUnit)s")
                    .font(.system(size: 13))
                    .foregroundStyle(inkMuted)
                Button("+") { store.setStayDays(store.stayDays + 1) }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(store.stayDays < BoardState.maxStayDays ? amber : inkMuted)
                    .disabled(store.stayDays >= BoardState.maxStayDays)
                Spacer()
            }
            .buttonStyle(.plain)
            .focusable(false)
            Text(store.closeHint)
                .font(.system(size: 11))
                .foregroundStyle(inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(paper2)
                .frame(height: 1)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("skip weekends")
                        .font(.system(size: 13))
                        .foregroundStyle(ink)
                    Text(store.skipWeekends
                        ? "on. saturday and sunday are not board days."
                        : "off. every day, including weekends, is a board day.")
                        .font(.system(size: 11))
                        .foregroundStyle(inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.skipWeekends },
                        set: { store.setSkipWeekends($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .focusable(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

private struct ItemRow: View {
    let item: Item
    var hovered: Bool
    var lastDay: Bool
    var onComplete: (String) -> Void
    var onReopen: () -> Void
    var onRename: (String) -> Void
    var onContext: (String) -> Void
    var onDismiss: (String) -> Void
    var onLayout: () -> Void
    var onEscapeLock: (Bool) -> Void

    @State private var editing = false
    @State private var editingContext = false
    @State private var capture: Capture?
    @State private var draft = ""
    @State private var contextDraft = ""
    @State private var dropNote = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var contextFocused: Bool
    @FocusState private var noteFocused: Bool

    private enum Capture {
        case complete
        case dismiss
    }

    var body: some View {
        if capture != nil {
            captureRow
        } else {
            liveRow
        }
    }

    private var liveRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: item.isOpen ? beginComplete : onReopen) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.001))
                    Circle()
                        .strokeBorder(item.isOpen ? inkMuted.opacity(0.85) : Color.clear, lineWidth: 1.25)
                    if !item.isOpen {
                        Circle().fill(inkMuted.opacity(0.28))
                    }
                }
                .frame(width: 13, height: 13)
                .padding(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, -3)
            .help(item.isOpen ? "Complete with an optional why" : "Reopen")

            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(ink)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ItemText(
                        text: item.text,
                        ink: item.isOpen ? ItemInk.body : ItemInk.done,
                        link: item.isOpen ? ItemInk.link : ItemInk.doneLink,
                        done: !item.isOpen,
                        onEdit: beginEdit
                    )
                    if item.isOpen, lastDay {
                        Text("last day")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(amber.opacity(0.85))
                    }
                    if editingContext {
                        TextField("context", text: $contextDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(inkMuted)
                            .focused($contextFocused)
                            .onSubmit { commitContext() }
                            .onExitCommand { cancelContext() }
                    } else if let context = item.context, !context.isEmpty {
                        Text(context)
                            .font(.system(size: 11))
                            .foregroundStyle(inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture { beginContext() }
                    } else if item.isOpen {
                        Text("context")
                            .font(.system(size: 11))
                            .foregroundStyle(inkMuted.opacity(hovered ? 0.7 : 0.4))
                            .onTapGesture { beginContext() }
                    }
                    if !item.isOpen, let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(inkMuted.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if hovered, !editing, !editingContext {
                Button(action: beginDismiss) {
                    Text("×")
                        .font(.system(size: 13))
                        .foregroundStyle(inkMuted)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Drop with an optional why")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .opacity(item.isOpen ? 1 : 0.7)
        .contentShape(Rectangle())
        .onChange(of: fieldFocused) { _, focused in
            if editing, !focused { commit() }
        }
        .onChange(of: contextFocused) { _, focused in
            if editingContext, !focused { commitContext() }
        }
    }

    private var captureRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.system(size: 13.5))
                .foregroundStyle(inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("why? (optional)", text: $dropNote)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .focused($noteFocused)
                .accessibilityIdentifier("robyty.why")
                .onSubmit { confirmCapture() }
                .onExitCommand { cancelCapture() }
            HStack(spacing: 10) {
                Button("cancel") { cancelCapture() }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(inkMuted)
                Button(capture == .dismiss ? "drop" : "done") { confirmCapture() }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(capture == .dismiss ? rust : amber)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            onEscapeLock(true)
            noteFocused = false
            DispatchQueue.main.async {
                noteFocused = true
                onLayout()
                DispatchQueue.main.async { noteFocused = true }
            }
        }
        .onDisappear { onEscapeLock(false) }
    }

    private func beginEdit() {
        draft = item.text
        editing = true
        fieldFocused = true
        onEscapeLock(true)
    }

    private func commit() {
        let text = draft
        editing = false
        fieldFocused = false
        onEscapeLock(false)
        onRename(text)
    }

    private func cancel() {
        editing = false
        fieldFocused = false
        onEscapeLock(false)
        draft = item.text
    }

    private func beginContext() {
        contextDraft = item.context ?? ""
        editingContext = true
        contextFocused = true
        onEscapeLock(true)
        DispatchQueue.main.async { onLayout() }
    }

    private func commitContext() {
        let text = contextDraft
        editingContext = false
        contextFocused = false
        onEscapeLock(false)
        onContext(text)
        DispatchQueue.main.async { onLayout() }
    }

    private func cancelContext() {
        editingContext = false
        contextFocused = false
        onEscapeLock(false)
        contextDraft = item.context ?? ""
        DispatchQueue.main.async { onLayout() }
    }

    private func beginComplete() {
        onEscapeLock(true)
        dropNote = ""
        capture = .complete
    }

    private func beginDismiss() {
        onEscapeLock(true)
        dropNote = ""
        capture = .dismiss
    }

    private func confirmCapture() {
        let note = dropNote
        let kind = capture
        capture = nil
        onEscapeLock(false)
        switch kind {
        case .complete: onComplete(note)
        case .dismiss: onDismiss(note)
        case nil: break
        }
    }

    private func cancelCapture() {
        capture = nil
        dropNote = ""
        onEscapeLock(false)
        DispatchQueue.main.async { onLayout() }
    }
}

private struct CloseRow: View {
    let item: Item
    var choice: CloseChoice?
    var canKeep: Bool
    @Binding var note: String
    var onKeep: () -> Void
    var onDrop: () -> Void
    var onLayout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemText(
                text: item.text,
                ink: ItemInk.body,
                link: ItemInk.link,
                done: false,
                onEdit: {}
            )
            if let context = item.context, !context.isEmpty {
                Text(context)
                    .font(.system(size: 11))
                    .foregroundStyle(inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canKeep {
                HStack(spacing: 8) {
                    ChoiceChip(title: "keep", active: choice == .keep, tint: amber, action: onKeep)
                    ChoiceChip(title: "drop", active: choice == .drop, tint: rust, action: onDrop)
                    Spacer()
                }
            } else {
                Text("last day. drop only.")
                    .font(.system(size: 11))
                    .foregroundStyle(inkMuted)
                HStack(spacing: 8) {
                    ChoiceChip(title: "drop", active: choice == .drop, tint: rust, action: onDrop)
                    Spacer()
                }
            }
            if choice == .drop {
                TextField("why? (optional)", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ink)
                    .onAppear { onLayout() }
            }
        }
        .padding(10)
        .background(paper2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onChange(of: choice) { _, _ in onLayout() }
    }
}

private struct ChoiceChip: View {
    let title: String
    var active: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? paper : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? tint : tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct OverviewStat: View {
    let title: String
    var value: String
    var fraction: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(inkMuted)
                Spacer()
                Text(value)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(inkDeep)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geo.size.width * min(1, fraction)))
                }
            }
            .frame(height: 6)
        }
    }
}
