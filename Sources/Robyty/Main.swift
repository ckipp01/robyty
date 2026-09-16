import AppKit

@main
enum RobytyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
