# Робити tests

Logic lives in `RobytyCore` (`Models.swift`, `Store.swift`). The menu-bar app
target is not loaded. Tests never write to the live data dir. Each case uses a
temp root plus an injected clock.

This Mac uses Command Line Tools, not Xcode. `swift test` cannot load Swift
Testing here (`lib_TestingInterop` is missing). The suite is a SwiftPM
executable instead.

## Run (agents: start here)

From the repo root:

```bash
./scripts/test.sh
```

From anywhere in the repo:

```bash
swift run RobytyTestRunner
```

Pass. Fail. No third state. Exit 0 means the suite passed. Non-zero means stop
and fix before installing the app. Output is one `ok` / `FAIL` line per case,
then `N passed, N failed, N run`.

Filter by substring of the test name:

```bash
./scripts/test.sh --filter skipClose
./scripts/test.sh --filter BoardDate
swift run RobytyTestRunner -- --filter overview
```

Same filter via env: `ROBYTY_TEST_FILTER=carry ./scripts/test.sh`

Do not run `swift test` for Robyty. Do not pass `--filter` without `--` when
using `swift run` directly; `swift run RobytyTestRunner -- --filter NAME`.

`./scripts/build.sh` does **not** run this suite. Run tests first, then
build if you changed `RobytyCore`.

## Clock and calendar

`Store` takes `now: () -> Date`. Tests mutate a `TestClock` and reopen the store
when the day changes (init already runs `rolloverIfNeeded`).

All stamps are **Europe/Amsterdam**. Fixtures (noon local):

| Stamp | Weekday |
| :-- | :-- |
| 2026-08-20 | Thursday |
| 2026-08-21 | Friday |
| 2026-08-22 | Saturday |
| 2026-08-23 | Sunday |
| 2026-08-24 | Monday |
| 2026-08-25 | Tuesday |

With **skip weekends** on, Friday → Monday is one weeknight and Saturday/Sunday
do not consume a night; `BoardDate.boardStamp` on Sat/Sun snaps to Friday. This
was the only behavior before `skip_weekends` existed; `Harness.fresh` still
defaults to it (`skipWeekends: true`) so the pre-existing weekday-carry tests
below read the same as ever. A real fresh board (no `state.json` yet) now
defaults `skip_weekends` to `false` — every day, including weekends, is a
board day — pass `skipWeekends: false` to `Harness.fresh` to test that mode.

## Covered

- `BoardDate`: weekend vs weekday, board stamp, next weekday (Fri → Mon), labels;
  `skipWeekends: false` variants keep Saturday/Sunday as ordinary board days
- Item / `BoardState` JSON: missing `note` / `context` / `dismissed` / `skip_weekends`,
  blank strings become nil, encode omits empty optionals, derived `open_count`;
  missing `nights` defaults to 0 — `carried` is write-only (derived from
  `nights` + `stay_days` for readers) and never read back, no legacy migration
- Add, complete (optional note), reopen (clears note), dismiss, rename, context
- Tomorrow tab writes `pending`; Friday tomorrow header is Monday (skip weekends on)
- Skip-close Friday leftover survives Sat/Sun, auto-carries Monday (`nights` +1)
  when skip weekends is on; counts Saturday as a night when it is off
- Last-day leftover (at `stay_days`) expires next weekday
- Stay length setting (default 5 days, clamp 1 to 10); raising it lets an old last-day be kept
- `skip_weekends` setting (default off, i.e. every day counts); toggling persists
  and re-runs rollover immediately
- Board folder setting: moves `state.json` and `archive/` to a new root, persists
  the choice for future `defaultRoot()` lookups, no-ops on the same path, and
  reports an error (leaving the old location untouched) when the target can't
  be created
- Reload from disk: picks up an externally-written done mark/note by id,
  no-ops when the file is unchanged, skips while a close is in progress, and
  ignores an unparsable external write instead of clearing live state
- Thursday → Friday is one night
- Weekend live `date` snaps to Friday (skip weekends on)
- Close keep parks in `pending`; close drop writes `note`
- Close flow: finish stays offered once every row is chosen; reclicking keep/drop
  does not unstick a choice; Friday mixed keep/drop/carried then Monday pickup;
  drop rest, keep all, cancel, tab abandon, empty close, dismiss-during-close
- Last-day leftovers cannot be kept
- Context survives Friday → Monday carry
- Overview counts Mon–Fri only when skip weekends is on; counts every archived
  day, including Saturday/Sunday, when it is off
- Progress fraction on today/tomorrow (overview has none)

## Not covered (do not add UI tests here)

- SwiftUI focus (`escapeLocked`, why-field steal, draft steal)
- Status item, panel, Dock / Command-Tab activation
- Hotkey, notifications, LaunchAgent, `Robyty.app` install

Those need a running app. Core tests will not catch them.

## Layout

```
robyty/
  Package.swift        RobytyCore + Robyty + RobytyTestRunner
  Sources/RobytyCore/  Models, Store, Log
  Sources/Robyty/      AppKit / SwiftUI
  Tests/RobytyTests/   runner (not XCTest)
```
