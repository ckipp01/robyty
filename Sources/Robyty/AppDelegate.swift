import AppKit
import Carbon
import RobytyCore
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let robytyBecameKey = Notification.Name("robytyBecameKey")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var retained: AppDelegate?

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var store: Store!
    private let hotKey = HotKey()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var midnightTimer: Timer?
    private var hosting: NSHostingController<BoardView>!
    private var reclaimKeyFromStatus = false
    private var showGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        store = Store()
        store.onChange = { [weak self] in
            self?.refreshIcon()
            self?.resizePanel()
            if self?.store.escapeLocked == true {
                self?.focusWhyField()
            }
        }

        let rootView = BoardView(store: store)
        hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]

        panel = BoardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Робити"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // We hide ourselves. hidesOnDeactivate plus a status-item click
        // dismisses the panel in the same gesture that opened it.
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(srgbRed: 31 / 255, green: 31 / 255, blue: 40 / 255, alpha: 1)
        panel.delegate = self
        panel.contentViewController = hosting
        panel.minSize = NSSize(width: 328, height: 140)
        hosting.view.appearance = NSAppearance(named: .darkAqua)
        installMainMenu()

        let extraName = "RobytyExtra"
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(extraName)")
        // Same scale as WiFi/Focus on this machine (~180-300). Small numbers
        // sit on the right with system extras. Default placement walks left
        // into the notch and Control Center then hides the item.
        UserDefaults.standard.set(200.0, forKey: "NSStatusItem Preferred Position \(extraName)")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = extraName
        statusItem.behavior = []
        if let button = statusItem.button {
            button.imageScaling = .scaleProportionallyDown
            button.refusesFirstResponder = true
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            Log.app.error("status item button is nil")
        }
        refreshIcon()
        statusItem.isVisible = true
        if let frame = statusItem.button?.window?.frame {
            Log.app.notice("status frame x=\(Int(frame.origin.x)) w=\(Int(frame.width))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.rehomeStatusItemIfInNotch(extraName: extraName)
        }

        hotKey.onPress = { [weak self] in self?.togglePanel() }
        hotKey.register(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey))

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        scheduleMidnight()
        Log.app.notice("launch")
        showPanel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Dock / Command-Tab. A status-item click also activates us; that
        // path owns the toggle, so skip showing again if the mouse is on
        // the ring. Still take key: the click often activates us too late
        // for the first focus pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.mouseOverStatusItem() {
                Log.app.debug("becomeActive on ring, panel=\(self.panel.isVisible)")
                if self.panel.isVisible {
                    self.stealKeyAndFocusDraft()
                }
                return
            }
            Log.app.info("becomeActive → show")
            self.showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NotificationCenter.default.post(name: .robytyBecameKey, object: nil)
        focusDraftField()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard reclaimKeyFromStatus, panel.isVisible else { return }
        reclaimKeyFromStatus = false
        DispatchQueue.main.async { [weak self] in
            self?.stealKeyAndFocusDraft()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.mouseOverStatusItem() {
                Log.app.debug("resignActive on ring, panel=\(self.panel.isVisible)")
                if self.panel.isVisible {
                    self.stealKeyAfterMouseUp(generation: self.showGeneration)
                }
                return
            }
            if NSApp.isActive {
                Log.app.debug("resignActive skipped, still active")
                return
            }
            Log.app.info("resignActive → hide")
            self.hidePanel()
        }
    }

    @objc private func didWake() {
        store.rolloverIfNeeded()
        refreshIcon()
        scheduleMidnight()
    }

    @objc private func statusClicked() {
        let right = NSApp.currentEvent?.type == .rightMouseUp
        Log.app.info("status click right=\(right) visible=\(self.panel.isVisible)")
        if right {
            showMenu()
            return
        }
        togglePanel(fromStatusItem: true)
    }

    @objc private func togglePanel() {
        togglePanel(fromStatusItem: false)
    }

    private func togglePanel(fromStatusItem: Bool) {
        if panel.isVisible {
            Log.app.info("toggle → hide")
            hidePanel()
            return
        }
        Log.app.info("toggle → show")
        showPanel(fromStatusItem: fromStatusItem)
    }

    @objc private func openFromMenu() {
        showPanel()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showPanel(fromStatusItem: Bool = false) {
        Log.app.info("show panel")
        store.rolloverIfNeeded()
        refreshIcon()
        resizePanel()
        placePanelTopRight()
        panel.orderFrontRegardless()
        startKeyMonitor()
        startClickMonitor()
        showGeneration += 1
        let generation = showGeneration
        reclaimKeyFromStatus = fromStatusItem
        stealKeyAndFocusDraft()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            self.stealKeyAndFocusDraft()
        }
        if fromStatusItem {
            stealKeyAfterMouseUp(generation: generation)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { [weak self] _, error in
                if let error {
                    Log.app.error("activate via open: \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    guard let self, self.showGeneration == generation else { return }
                    self.stealKeyAndFocusDraft()
                }
            }
        }
    }

    private func hidePanel() {
        Log.app.info("hide panel")
        reclaimKeyFromStatus = false
        showGeneration += 1
        panel.orderOut(nil)
        stopKeyMonitor()
        stopClickMonitor()
    }

    private func stealKeyAfterMouseUp(generation: Int) {
        guard showGeneration == generation, panel.isVisible else { return }
        if NSEvent.pressedMouseButtons != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.stealKeyAfterMouseUp(generation: generation)
            }
            return
        }
        stealKeyAndFocusDraft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            self.stealKeyAndFocusDraft()
        }
    }

    private func stealActivation() {
        NSApp.activate()
    }

    private func stealKeyAndFocusDraft() {
        guard panel.isVisible else { return }
        stealActivation()
        if let statusWindow = statusItem.button?.window, statusWindow.isKeyWindow {
            statusWindow.resignKey()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        NotificationCenter.default.post(name: .robytyBecameKey, object: nil)
        focusDraftField()
        let responder = String(describing: panel.firstResponder)
        Log.app.info("steal key active=\(NSApp.isActive) key=\(self.panel.isKeyWindow) first=\(responder, privacy: .public)")
    }

    private func focusDraftField() {
        guard !store.isClosing, !store.isSettings, !store.escapeLocked else { return }
        if !panel.isKeyWindow { panel.makeKey() }
        guard let field = findField(in: hosting.view, preferring: ["robyty.add"], placeholders: ["add"]) else {
            Log.app.debug("draft field not found")
            return
        }
        panel.makeFirstResponder(field)
    }

    private func focusWhyField() {
        guard store.escapeLocked, !store.isClosing else { return }
        if !panel.isKeyWindow { panel.makeKey() }
        guard let field = findField(in: hosting.view, preferring: ["robyty.why"], placeholders: ["why? (optional)"]) else {
            return
        }
        panel.makeFirstResponder(field)
    }

    private func findField(in view: NSView, preferring ids: [String], placeholders: [String]) -> NSTextField? {
        var match: NSTextField?
        func walk(_ v: NSView) {
            if match != nil { return }
            if let field = v as? NSTextField, field.isEditable {
                let id = field.identifier?.rawValue ?? ""
                let ax = field.accessibilityIdentifier()
                let placeholder = field.placeholderString
                    ?? (field.cell as? NSTextFieldCell)?.placeholderString
                    ?? ""
                if ids.contains(id) || ids.contains(ax) || placeholders.contains(placeholder) {
                    match = field
                    return
                }
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(view)
        return match
    }

    private func placePanelTopRight() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let pad: CGFloat = 16
        let x = visible.maxX - size.width - pad
        let y = visible.maxY - size.height - pad
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Робити",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Робити", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.store.escapeLocked == true || self?.store.isClosing == true {
                    return event
                }
                Task { @MainActor in
                    self?.hidePanel()
                }
                return nil
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func startClickMonitor() {
        stopClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.mouseOverStatusItem() { return }
                if self.panel.frame.contains(NSEvent.mouseLocation) { return }
                Log.app.info("outside click → hide")
                self.hidePanel()
            }
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func resizePanel() {
        hosting.view.layoutSubtreeIfNeeded()
        var size = hosting.view.fittingSize
        if size.width < 328 { size.width = 328 }
        if size.height < 140 { size.height = 140 }
        // Room for the hidden titlebar / close button.
        size.height += 28
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
        if panel.isVisible {
            placePanelTopRight()
        }
    }

    private func mouseOverStatusItem() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func rehomeStatusItemIfInNotch(extraName: String) {
        statusItem.isVisible = true
        guard let window = statusItem.button?.window else { return }
        let x = window.frame.midX
        let screenWidth = window.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1512
        let notchMin = screenWidth * 0.36
        let notchMax = screenWidth * 0.64
        Log.app.notice("status rehome check x=\(Int(x)) screen=\(Int(screenWidth))")
        guard x >= notchMin, x <= notchMax else { return }
        Log.app.notice("status item in notch, pinning right")
        UserDefaults.standard.set(80.0, forKey: "NSStatusItem Preferred Position \(extraName)")
        statusItem.isVisible = false
        statusItem.isVisible = true
        if let frame = statusItem.button?.window?.frame {
            Log.app.notice("status frame after pin x=\(Int(frame.origin.x))")
        }
    }

    private func refreshIcon() {
        guard let button = statusItem.button else {
            Log.app.error("refreshIcon skipped, no button")
            return
        }
        let n = store.openItems.count
        button.image = MenuMark.image()
        button.imagePosition = n == 0 ? .imageOnly : .imageLeading
        button.title = n == 0 ? "" : "\(n)"
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = n == 0 ? "Робити" : "Робити · \(n) open"
        statusItem.isVisible = true
    }

    private func scheduleMidnight() {
        midnightTimer?.invalidate()
        guard let next = BoardDate.calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) else { return }
        midnightTimer = Timer.scheduledTimer(withTimeInterval: max(next.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.store.rolloverIfNeeded()
                self?.refreshIcon()
                self?.scheduleMidnight()
            }
        }
        midnightTimer?.tolerance = 2
    }
}

private final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
