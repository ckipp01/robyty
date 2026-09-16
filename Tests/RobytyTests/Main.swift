import Foundation

@main
@MainActor
enum RobytyTestRunner {
    static func main() {
        T.filter = parseFilter(CommandLine.arguments)
        BoardDateTests.run()
        ModelsTests.run()
        StoreTests.run()
        CloseTests.run()
        SettingsTests.run()
        T.summaryAndExit()
    }

    private static func parseFilter(_ args: [String]) -> String? {
        if let env = ProcessInfo.processInfo.environment["ROBYTY_TEST_FILTER"], !env.isEmpty {
            return env
        }
        var pending = false
        for arg in args.dropFirst() {
            if pending { return arg }
            if arg == "--filter" { pending = true; continue }
            if arg.hasPrefix("--filter=") {
                return String(arg.dropFirst("--filter=".count))
            }
        }
        return nil
    }
}
