import Foundation

@MainActor
enum T {
    static var filter: String?
    private(set) static var passed = 0
    private(set) static var failed = 0
    private(set) static var ran = 0

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        if let filter, !name.localizedCaseInsensitiveContains(filter) { return }
        ran += 1
        do {
            try body()
            passed += 1
            print("ok   \(name)")
        } catch {
            failed += 1
            print("FAIL \(name)")
            print("     \(error)")
        }
    }

    static func ok(_ cond: Bool, _ message: String = "expected true", file: StaticString = #fileID, line: UInt = #line) throws {
        if !cond { throw Failure(description: "\(file):\(line): \(message)") }
    }

    static func eq<Value: Equatable>(
        _ actual: Value,
        _ expected: Value,
        file: StaticString = #fileID,
        line: UInt = #line
    ) throws {
        if actual != expected {
            throw Failure(description: "\(file):\(line): \(String(describing: actual)) != \(String(describing: expected))")
        }
    }

    static func summaryAndExit() {
        print("\(passed) passed, \(failed) failed, \(ran) run")
        if ran == 0 {
            print("no tests matched filter")
            exit(1)
        }
        if failed > 0 { exit(1) }
    }
}
