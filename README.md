# Робити

*Робити* is a rolling daily task board that lives in the macOS menu bar. Add
items, complete them, close the day. Leftovers carry over for a configurable
number of days, then expire. Live state is plain JSON on disk so other tools can
read it directly.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode Command Line Tools is enough — see [Development](#development))

## Install

```bash
git clone <this repo>
cd robyty
./scripts/build.sh
```

Builds `Robyty.app`, installs it to `~/Applications`, and registers a login
LaunchAgent using the bundle identifier from `Info.plist`. Re-run after
pulling code changes.

## Use

- **Open**: Dock icon, the menu-bar ring, Command-Tab, or Control-Option-D.
  Click away or press Escape to hide it.
- **Add**: type, Return.
- **Complete**: click an item's ring (optional why). Click again to reopen.
- **Drop**: hover an item, click × (optional why).
- **Edit**: click the text to rename it. Click the dim context line under an
  item to add a subtitle.
- **Close day**: leftovers that can still stay are kept or dropped; the last
  eligible day can only drop. **drop rest** clears anything left unchosen.
  If you never close, leftovers auto-carry until they hit the stay limit,
  then expire at the next board-day midnight (Europe/Amsterdam).
- **Overview**: this week vs. last week vs. weekly average of completed
  items, from the close archives plus anything completed today.

## Settings

| Setting | Default | Notes |
| :-- | :-- | :-- |
| Stay length | 5 days | Range 1–10. How long a leftover survives before it drops. |
| Skip weekends | off | Off: every day, including Saturday/Sunday, is a board day. On: weekends aren't board days — a Friday leftover carries to Monday instead of Saturday. |
| Board folder | `~/Library/Application Support/Robyty` | Where `state.json` and `archive/` live. Enter a path and Robyty moves the live board and archive there, and remembers the choice for future launches. |

## Data

Lives under `~/Library/Application Support/Robyty/` by default. The Settings
board-folder field is the normal way to change this (it moves the existing
data for you); `ROBYTY_ROOT` is an env-var override for scripts and tests, and
takes precedence over the Settings value when set.

Robyty watches the board folder while running and reloads `state.json` if
something else changes it on disk (e.g. an external tool editing the live
board directly) — useful once you've pointed the board folder somewhere an
external tool can reach. It also re-reads on wake and whenever the panel is
shown, as a fallback. Reload is skipped mid-close (`close day` in progress),
since that flow tracks in-flight choices by item id.

| Path | Role |
| :-- | :-- |
| `state.json` | Live board. Mutable. |
| `archive/YYYY-MM-DD.json` | Close archive. Immutable. Written once when a day is closed or expires. |

Live schema:

```json
{
  "version": 1,
  "date": "2026-08-24",
  "stay_days": 5,
  "skip_weekends": false,
  "open_count": 1,
  "items": [
    {
      "id": "a1b2c3d4",
      "text": "Reply to the vendor about the renewal",
      "created_at": "2026-08-24T09:12:00Z",
      "done_at": null,
      "nights": 0,
      "carried": false,
      "context": "Renewal quote came in high, worth a counter"
    }
  ],
  "pending": [],
  "dismissed": [
    {
      "id": "b2c3d4e5",
      "text": "Follow up on the dashboard redesign",
      "created_at": "2026-08-24T10:00:00Z",
      "done_at": null,
      "nights": 0,
      "carried": false,
      "note": "Someone else already picked this up"
    }
  ]
}
```

- `open_count` is derived. Treat `done_at == null` as still open.
- `nights` is how many extra days an item has already used; last day when
  `nights >= stay_days - 1`. `carried: true` is that last-day flag for readers,
  written for convenience but never read back — `nights` is the only source
  of truth on load.
- `dismissed` is mid-day drops; they join archive `dropped` at close or midnight.
- `note` is an optional why, on done items and on dismissed/dropped items.
- `context` is an optional living subtitle on an item. Never overwrite a
  non-empty `context` or invent a `note`/`context` that wasn't given.
- If `date` is already tomorrow, the day was closed early — read today's
  archive instead.
- Archive `close_kind` is `manual` or `expired`.

## Development

```bash
./scripts/test.sh
```

Tests cover `RobytyCore` only, run against temp dirs, and never touch live
data. The suite is a plain SwiftPM executable, not XCTest — Command Line
Tools can't load Swift Testing here, so `swift test` won't work; use
`./scripts/test.sh` (or `swift run RobytyTestRunner`). See
[TESTS.md](TESTS.md) for filtering and coverage details.

`./scripts/build.sh` does not run the test suite — run tests first, then
build if you changed `RobytyCore`.

## Logs

Unified logging only, under the same subsystem as the bundle identifier
(see `Log.swift`). Nothing is written under this repo.

```bash
log stream --predicate 'subsystem == "<bundle-id>"' --level debug
```

Or Console.app, search `subsystem:<bundle-id>`.
