# IntervalAppTests

Regression suite for sync, migrations, habit↔hour linking, and task lifecycle.

Coding agents should treat a failing test here as the source of truth for intended
behaviour. Prefer extending these tests over guessing from UI code.

## Run

From the repo root:

```bash
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'platform=macOS' -derivedDataPath .build \
  test -only-testing:IntervalAppTests
```


Or:

```bash
./scripts/run-tests.sh
```

## Layout

| File | Covers |
| --- | --- |
| `SyncBehaviourTests` | Two-device push/pull, deletes, recycle bin, habit_id column |
| `MergePolicyTests` / `ServerClockTests` / `SyncTimestampTests` / `TombstoneLedgerTests` | Pure sync primitives |
| `HabitTaskLinkTests` | Hour migration habit selection + tick mirroring |
| `MigrationScheduleTests` | Calendar rollover → which modal is due |
| `MigrationManagerTests` | Day tasks + habits into the hour list |
| `TaskHousekeepingTests` | Soft delete, restore, expiry, permanent delete |
| `SyncHarness` / `TestSupport` | In-memory store + fake Supabase |

## Conventions

- No network. `SupabaseSyncManager.shared` stays unauthenticated in tests.
- No wall clock. Use `TestTime.now` (or an offset from it).
- SwiftData only via `TestStore` (in-memory).
- Production rules live in pure helpers (`SyncCore`, `HabitTaskLink`,
  `MigrationSchedule`, `TaskHousekeeping`) so agents can unit-test them without
  launching the app.
