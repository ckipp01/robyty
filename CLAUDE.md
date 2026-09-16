# Working on Робити

## Test discipline

- **New feature → new test.** Add a case in `Tests/RobytyTests` that exercises
  it. If it's a `Store`/`BoardState`/`BoardDate` behavior, it belongs in
  `RobytyCore` and needs coverage there — the UI (`Sources/Robyty`) has none.
- **Bug fix → regression test.** Before touching the fix, write a test that
  reproduces the bug (fails on `main`), then fix it and confirm the test now
  passes. Don't fix without a test that would have caught it.
- **Changed default or behavior → check existing tests still mean what they
  say.** Some tests intentionally pin one mode (e.g. `Harness.fresh` defaults
  to `skipWeekends: true` so the legacy weekday-carry tests keep testing that
  path unchanged) — read a test before assuming it's safe to "just update the
  assertion."
- Run `./scripts/test.sh` before *and* after your change. All tests must pass
  — pass/fail, no other state. If you can't get a test green, say so; don't
  weaken the assertion to make it pass.
- Do not run `swift test`. Command Line Tools on this Mac can't load Swift
  Testing (`lib_TestingInterop` missing) — the suite is a SwiftPM executable
  (`RobytyTestRunner`), which `./scripts/test.sh` runs.
- `./scripts/build.sh` does **not** run tests. Test first, then build only if
  you changed `RobytyCore`.
- Filtering: `./scripts/test.sh --filter <substring>`. See `TESTS.md` for the
  full test-writing conventions (fixtures, `Harness`, `TestClock`, what's
  covered vs. explicitly out of scope).

## Where things live

- `Sources/RobytyCore` — all real logic (`Models.swift`, `Store.swift`). This
  is what's testable and what almost every change should touch.
- `Sources/Robyty` — AppKit/SwiftUI shell. Not covered by the test suite;
  changes here need manual verification (run the app, don't just assume).
- `Tests/RobytyTests` — the SwiftPM test runner. `Harness.swift` has the
  fixtures/helpers (`Harness.fresh`, `Harness.writeLive`, `TestClock`,
  `Fixtures` dates) — reuse them instead of hand-rolling setup.

## Other

- Tests use temp dirs (`ROBYTY_ROOT` per test) and never touch
  `~/Library/Application Support/Robyty`. Keep it that way — don't write
  live-data paths from a test.
- If a change affects documented behavior (README.md's Use/Settings/Data
  sections, or `TESTS.md`'s Covered list), update those in the same change,
  not as a follow-up.
- Don't hardcode personal identifiers (bundle IDs, usernames, machine-specific
  paths) in docs meant to be general; the actual `com.chriskipp.robyty` in
  code (`Info.plist`, `scripts/build.sh`, `Log.swift`) is fine to keep as is.
