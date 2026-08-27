# IntervalApp Testbench

Comprehensive regression & data integrity test suite for IntervalApp.

> **CRITICAL RULE FOR ALL CODING AGENTS**:
> Before and after modifying any code or implementing any new features in IntervalApp, you MUST run this test suite using `./scripts/run-tests.sh` or `xcodebuild test`.
> **ALL tests must pass (0 failures). Never delete or disable tests.**

---

## Running the Test Suite

```bash
./scripts/run-tests.sh
```

Or via `xcodebuild`:

```bash
xcodebuild -scheme IntervalApp -destination "platform=macOS" -derivedDataPath .build test
```

---

## Test Suites & Coverage

| Test File | Critical Invariants & Behaviors Tested |
| :--- | :--- |
| **`DataLossPreventionTests`** | **CRITICAL**: Verifies that unselected tasks in migrations are NEVER deleted or moved to bin; habit tasks never pollute bottom Completed/Bin archives; soft deletes and restores maintain 100% data integrity; habit weekday changes trigger sync timestamps. |
| **`HabitDragAndDropTests`** | Dragging a habit chip into the 1-Hour Focus list (at top, bottom, or specific index) inserts a linked `TaskItem` and adjusts orders; dropping into other sections (1 Day, 1 Week, etc.) is strictly rejected; prevents duplicate active habit tasks. |
| **`HabitTaskLinkTests`** | Postponed habits filtered out of hourly transitions; ticking hour task ticks linked habit and updates streak; unticking mirrors in reverse; ticking habit ticks all its active hour tasks; soft-deleting linked tasks. |
| **`MigrationManagerTests`** | Task and habit transfers during hourly transitions; remote marker synchronization automatically dismissing active transition dialogs on other devices; skipping transitions. |
| **`MigrationScheduleTests`** | Presentation rules across all interval transitions (Year->Year, Day->Hour, Week->Day, Month->Week, Year->Month). |
| **`TaskHousekeepingTests`** | Soft delete (`moveToBin`), restore (`restore`), permanent delete (`deletePermanently`), 30-day retention window (`expired`), and habit exclusions. |
| **`ScratchpadTests`** | Scratchpad list and item CRUD, completing items, soft-deleting items and cascading list deletes. |
| **`UIInteractionsAndButtonsTests`** | "Clear All" completed, "Empty Bin", habit postpone button toggle, German and international localization keys. |
| **`SyncBehaviourTests`** | Multi-device push/pull simulation, conflict resolution, tombstone ledger confirmation, offline edits surviving. |
| **`MergePolicyTests`** / **`SyncTimestampTests`** / **`ServerClockTests`** / **`TombstoneLedgerTests`** | Timestamp parsing, server clock skew adjustment, last-write-wins merge resolution. |

---

## Rules & Conventions

1. **Zero Network Dependence**: `SupabaseSyncManager` stays unauthenticated or uses `FakeSupabase`.
2. **Zero Wall-Clock Dependence**: Tests use deterministic `TestTime.now` or date offsets.
3. **In-Memory SwiftData**: All SwiftData interactions run against `TestStore` (in-memory `ModelContainer`).
4. **Data Loss Invariant**: No code change is allowed to merge if it causes any unselected, active, or linked data to be deleted or lost.
