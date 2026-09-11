# IntervalApp Robustness and Data Safety Plan

## Scope

This work hardens the existing app for tester release. It must not introduce new product features or change intended user-facing behavior except where required to prevent data loss, corruption, unauthorized access, or failed synchronization.

Do not weaken or remove existing tests. Every production change must be validated with the repository testbench:

```bash
./scripts/run-tests.sh
```

The existing safeguards include per-record sync timestamps, tombstones, protection against incomplete remote snapshots, soft deletion, sign-out push protection, habit-link tests, migration tests, and data-loss tests. This plan extends those safeguards into a release gate.

## 1. Non-negotiable data invariants

- [x] A task is never permanently removed without an explicit permanent-delete action. Automatic launch-time hard deletion has been removed; manual clear and permanent-delete actions remain explicit.
- [x] Completing a task never removes it from storage.
- [x] Completed and deleted records retain their text, IDs, timestamps, interval, order, and habit relationship.
- [x] Dragging a task or habit never overwrites another task.
- [x] A habit-generated task never replaces an existing task.
- [x] Unselected migration tasks remain in their original interval.
- [x] A local change is never discarded because synchronization failed.
- [x] A remote snapshot that is incomplete or malformed cannot delete local data.
- [x] Logging out cannot destroy unsynced local data.
- [ ] One account can never read or modify another account's data. Client isolation is covered; server RLS verification remains.
- [x] Any local save operation that cannot be completed preserves pending context changes and exposes a recoverable error.

Local section status: complete. The account-isolation invariant remains an external server verification gate in section 8 and is intentionally not marked complete from client tests alone.

## 2. Persistence and crash-safety tests

Add deterministic tests that simulate:

- [x] Real on-disk reopen tests simulate termination after creation, editing, completion, soft-deletion, restore, and committed drag-and-drop.
- [x] Termination immediately before save retains the last committed version; every tested post-save lifecycle state survives a new container.
- [x] Save failures are reported while pending changes remain available for retry.
- [x] A corrupted or unreadable SwiftData store enters a blocked recovery screen using an in-memory container; the original store remains untouched and the empty fallback cannot sync over remote data.
- [x] Storage-full save errors follow the recoverable failure path, report the condition, and retain pending context work for retry.
- [x] App backgrounding flushes active task, habit, list-title, and scratchpad drafts, retries pending storage changes, and schedules sync only after the local save succeeds.
- [x] Relaunch after committed create, completion, soft-delete, restore, and mixed-record operations is covered with a real on-disk store reopen test.
- [ ] Schema migration from older versions, including stores containing habits, links, deleted items, and incomplete tasks.
- [x] Duplicate IDs are deterministically collapsed by newest update; empty IDs and unambiguous relationships are repaired; blank drafts are preserved locally; malformed remote dates trigger republishing; invalid intervals are restored to a visible day bucket.
- [x] Model-container open failure is handled without exposing an empty working app, with deterministic primary/fallback bootstrap tests.

For every case, verify that the last known local state remains present and no record disappears silently.

Relevant files:

- `IntervalApp/TaskHousekeeping.swift`
- `IntervalApp/IntervalModel.swift`
- `IntervalAppTests/DataLossPreventionTests.swift`

## 3. Task lifecycle matrix

Test every combination of:

- Create, edit, complete, undo, move to bin, restore, and permanently delete.
- Active, completed, binned, habit-linked, imported, and link-backed tasks.
- 1 hour, 1 day, 1 week, 1 month, and 1 year.
- Single-line, multiline, empty, long, Unicode, emoji, and URL-backed text.
- Rapid repeated taps and repeated save actions.
- Completion while a remote update arrives.
- Deletion while synchronization is active.
- Restore after the original task changed on another device.

Verify that completed and binned rows retain all original data and that automatic cleanup never removes records prematurely.

## 4. Drag-and-drop safety

Add deterministic tests for:

- [x] Reordering within every interval.
- [x] Moving tasks between every allowed interval.
- [x] Drag cancellation leaves the model and persistent context unchanged.
- [x] Committed task drops clamp safely to first, middle, and last positions; header and bottom delegates use the same commit path.
- [x] Dropping outside a valid target only resets the proposed drag and cannot autosave a move.
- [x] Repeated identical drops are idempotent and do not advance timestamps.
- [x] Starting a second drag replaces only transient drag state and cannot mutate either task.
- [x] A drop recomputes ordering from current SwiftData rows, preserving records that arrived during the drag.
- [x] Dragging a habit into 1 hour when existing tasks are present.
- [x] Attempting to drag a habit into forbidden intervals.
- [x] Dropping the same habit twice.
- [x] Dropping a habit while its generated task already exists.
- [x] Only rows whose interval/order changes receive a new `updatedAt`; unrelated rows retain their timestamp.
- [x] Committed and cancelled drag tests preserve every unaffected task's text, ID, completion state, habit ID, and order.

Cover both macOS mouse dragging and iPhone long-press dragging.

Relevant files:

- `IntervalApp/TaskRowView.swift`
- `IntervalApp/TaskListView.swift`
- `IntervalApp/HabitsBarView.swift`
- `IntervalAppTests/HabitDragAndDropTests.swift`

## 5. Habit-link integrity

Verify that:

- Completing a habit completes only its linked hour task.
- Undoing a habit completion restores only its linked task.
- Completing a linked task updates only its linked habit.
- The relationship survives export, import, synchronization, logout, login, and migration.
- Two habits with identical visible text remain distinct.
- Deleted or completed habit tasks cannot be accidentally regenerated.
- Repeated hourly migrations do not create duplicate generated tasks.
- A linked task cannot silently become an unrelated task.
- Watch, iPhone, and Mac completion produce identical stored data.
- A linked task cannot appear in the wrong completed or recently deleted section.

Relevant file:

- `IntervalApp/HabitTaskLink.swift`

## 6. Synchronization and conflict testing

Expand the fake Supabase coverage for:

- Offline creation, editing, completion, deletion, restoration, and reordering.
- Network loss before a request, during a request, after server acceptance, and during response decoding.
- HTTP 401, 403, 408, 409, 429, 500, and malformed response bodies.
- Token refresh failure during a push.
- Partial batch success.
- Duplicate server rows.
- Missing columns.
- Missing or malformed timestamps.
- More than 500 rows and more than 1,000 rows.
- Empty pages and incomplete pages.
- Server deletion while a local edit is pending.
- Local deletion while an old remote snapshot is in flight.
- Concurrent edits to the same record on two devices.
- Concurrent edits to different records.
- Conflicting reorders from two devices.
- Habit completion racing against linked task completion.
- Synchronization recovery after several failed attempts.
- Backoff recovery without permanently stranding pending changes.
- Save failure while merging remote records.
- Pull failure after part of a remote response has been processed.

Verify that newer local edits are never overwritten by stale device state and that deletes never resurrect records.

Relevant files:

- `IntervalApp/SupabaseSyncManager.swift`
- `IntervalApp/SyncCore.swift`
- `IntervalAppTests/SyncBehaviourTests.swift`
- `IntervalAppTests/SyncTimestampTests.swift`
- `IntervalAppTests/ServerClockTests.swift`
- `IntervalAppTests/TombstoneLedgerTests.swift`

## 7. Logout, login, and account switching

Test:

- Logout with no local changes.
- Logout with unsynced edits and a working network.
- Logout with unsynced edits and a failed network.
- Logout while a push is active.
- Logout while a pull is active.
- Closing the app during logout.
- Logging back into the same account.
- Logging into a different account on the same device.
- Logout, reinstall, and login again.
- Expired access token with a valid refresh token.
- Expired access and refresh tokens.
- Invalid credentials.
- Password reset and recovery-link interruption.
- Repeated login and logout.
- Account switching while a sync loop is running.

Verify that:

- Failed logout preserves local unsynced data.
- Successful logout does not leave the previous account visible.
- Account B never sees account A's local rows.
- The next login performs a safe account-specific pull.
- Pending work is either confirmed remotely or remains available locally for recovery.
- UI state cannot accidentally display stale data from the previous account.

Relevant file:

- `IntervalApp/SupabaseSyncManager.swift`

## 8. Server-side account security

Verify the Supabase database independently of the client:

- Row-level security is enabled on every user-owned table.
- Every select, insert, update, and delete policy checks the authenticated user ID.
- Shared lists allow only intended owner and member actions.
- A member cannot modify another user's private tasks or habits.
- A removed collaborator immediately loses access.
- Invitations cannot be accepted by the wrong account.
- Client-supplied IDs cannot bypass ownership checks.
- The publishable client key cannot access data without valid policies.
- No service-role key exists in the app bundle or repository.
- Authentication endpoints have rate limiting and abuse protection.
- Password reset links expire and cannot be reused.
- Tokens are not written to logs, analytics, crash reports, or exported data.

Access and refresh tokens now use a dedicated, device-only Keychain service. Existing `UserDefaults` tokens migrate once and are removed only after Keychain confirms the secure copy; other non-secret session metadata remains in preferences. Token revocation and server-side session invalidation still require live-backend verification.

## 9. Export, import, and recovery

Run recovery drills for:

- Exporting an account with active, completed, deleted, linked, and URL-backed data.
- Exporting while offline.
- Exporting during synchronization.
- Exporting an empty account.
- Importing a valid backup.
- Importing a backup with unknown fields.
- Importing duplicate IDs.
- Importing malformed JSON.
- Importing partial data.
- Importing into a non-empty account.
- Repeating the same import twice.
- Restoring an account after deleting the local store.

Verify that:

- Import never overwrites existing records without an explicit existing conflict rule.
- Dates, order, completion state, deleted state, habit links, and URLs survive round trips.
- An interrupted export or import leaves the existing store unchanged.
- Corrupt backup data produces a clear error and no partial destructive mutation.
- Exported data contains no authentication tokens or secrets.

## 10. Migration and housekeeping

Test:

- Every interval transition with zero, one, and many tasks.
- Dismissed migration dialogs.
- Partial migration followed by termination.
- Migration while offline.
- Migration while another device edits the same tasks.
- Repeated migration at the same time boundary.
- Daylight-saving-time changes.
- Time-zone changes.
- Manual clock changes.
- Habit rollover at midnight.
- Completed and deleted tasks during rollover.
- Automatic cleanup thresholds.
- Reopening recently deleted items after cleanup attempts.
- Postponed habits.
- Repeated launch and sync around migration boundaries.

Verify that unselected tasks remain in their source interval and that no migration deletes or completes a task unexpectedly.

Relevant files:

- `IntervalApp/MigrationManager.swift`
- `IntervalApp/MigrationSchedule.swift`
- `IntervalApp/TaskHousekeeping.swift`
- `IntervalAppTests/MigrationManagerTests.swift`
- `IntervalAppTests/MigrationScheduleTests.swift`

## 11. Platform matrix

Test:

- macOS app.
- iPhone portrait and landscape.
- iPad if supported.
- Apple Watch.
- iPhone with the Watch app installed and removed.
- Offline Watch usage followed by reconnection.
- Widget installation and removal.
- Live Activity start, update, expiration, and dismissal.
- App update with an existing widget and Live Activity.
- All supported operating-system versions.
- Light mode, dark mode, Dynamic Type, and localization.

For every platform, verify the stored data and synchronization result, not just visual rendering.

## 12. Logging and diagnostics

Add safe operational diagnostics for:

- Last successful pull and push.
- Number of pending local changes.
- Number of pending tombstones.
- Current authentication state.
- Last synchronization failure category.
- Retry count and next retry time.
- Store migration status.
- Export and import result.

Logs must never include:

- Task or habit text.
- Private URLs.
- Passwords.
- Access tokens.
- Refresh tokens.
- Full email addresses where avoidable.
- Private account data.

Diagnostics should help support a failed sync without exposing user content.

## 13. Release gates

Do not distribute to testers until:

- The existing testbench passes with zero failures.
- Persistence, sync, authentication, account-isolation, and drag-safety tests pass.
- A real two-device offline/online test passes.
- A failed-logout test confirms that local data remains available.
- A fresh-install login test passes.
- A backup restore drill passes.
- Supabase row-level security is verified with multiple accounts.
- macOS, iPhone, and Watch installations succeed.
- A TestFlight update over an existing installation preserves all data.
- No critical or high-severity issue remains open.
- An emergency backup and recovery procedure is documented.

## Recommended implementation order

1. Persistence and save guarantees.
2. Synchronization conflict and offline recovery.
3. Logout and account isolation.
4. Drag-and-drop and habit-link safety.
5. Migrations and housekeeping.
6. Export/import recovery.
7. Platform matrix testing.
8. Secure diagnostics.
9. TestFlight rollout with a small internal tester group before wider distribution.

Every fix should include a regression test for the failure it addresses. Keep all work within the existing feature set and preserve the current product behavior.
