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
- [x] Account isolation is enforced in the client and live server configuration: RLS is enabled, ownership policies use `auth.uid()`, anonymous grants are removed, authenticated grants are least-privilege, and shared-list ownership is immutable. A real two-account exercise remains a release drill.
- [x] Any local save operation that cannot be completed preserves pending context changes and exposes a recoverable error.

Local safeguards and the live server configuration audit are complete. End-to-end release drills remain in section 13.

## Open findings from live release testing

- [ ] Reconcile ordering after independent edits on multiple devices so the same account presents a deterministic order everywhere.
- [ ] Decide which Settings values are account-level and synchronize those values across devices; keep device-only preferences explicitly local.
- [ ] Replace the failed-logout message with a clear localized explanation that unsaved changes are safe on this device but must sync after reconnecting before logout can complete. Add translations for all ten supported languages.
- [ ] Make habit postponement reliable on iPhone, with an accessible long-press interaction where appropriate.
- [ ] Persist and synchronize habit postponement consistently between iPhone and Mac.
- [ ] Localize every sign-in button and related authentication action on the login screen.
- [ ] Restyle the login language picker in the app's neutral minimalist palette instead of the default blue accent.
- [ ] Localize the registration screen's account-creation title and register action in all ten languages.
- [ ] Make the import preview display the complete task set consistently before confirmation.
- [ ] Make import-preview task dragging visibly respond and commit the intended ordering/move.
- [ ] Require a deliberate typed confirmation token derived from the account identity before account deletion.
- [ ] Add a concise confirmation dialog before removing a collaborator from a shared list.
- [ ] Add a concise confirmation dialog before leaving a shared list.

## 2. Persistence and crash-safety tests

Add deterministic tests that simulate:

- [x] Real on-disk reopen tests simulate termination after creation, editing, completion, soft-deletion, restore, and committed drag-and-drop.
- [x] Termination immediately before save retains the last committed version; every tested post-save lifecycle state survives a new container.
- [x] Save failures are reported while pending changes remain available for retry.
- [x] A corrupted or unreadable SwiftData store enters a blocked recovery screen using an in-memory container; the original store remains untouched and the empty fallback cannot sync over remote data.
- [x] Storage-full save errors follow the recoverable failure path, report the condition, and retain pending context work for retry.
- [x] App backgrounding flushes active task, habit, list-title, and scratchpad drafts, retries pending storage changes, and schedules sync only after the local save succeeds.
- [x] Relaunch after committed create, completion, soft-delete, restore, and mixed-record operations is covered with a real on-disk store reopen test.
- [x] Historical schema migration is not applicable to the first tester release because no prior build or user installation exists. `SCHEMA_BASELINE.md` records the current store as the mandatory fixture baseline for every future schema-changing release.
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

- [x] Offline creation, editing, completion, deletion, restoration, and reordering converge after reconnection without record loss.
- [x] Network failures before/during requests and ambiguous failures after acceptance leave rows dirty; malformed response decoding aborts the snapshot.
- [x] HTTP 401, 403, 408, 409, 429, and 500 plus malformed bodies preserve local pending rows.
- [x] Token refresh rejection during push cannot mark the row synchronized.
- [x] Partial batch success marks only the accepted 200-row chunk and safely retries the remainder.
- [x] Duplicate server rows deterministically converge to the newest timestamped version regardless of response order.
- [x] Missing columns degrade safely without clearing locally known habit links.
- [x] Missing or malformed timestamps retain/republish local data.
- [x] Pagination is verified with 1,001 rows across three 500-row pages.
- [x] Empty terminal pages complete pagination safely; any page with unreadable rows and snapshots that hit the pagination safety cap are rejected rather than merged as complete.
- [x] A server deletion cannot prune a pending local edit.
- [x] A tombstone prevents an old in-flight remote snapshot from resurrecting a local deletion.
- [x] Concurrent same-record edits converge by timestamp without stale overwrite.
- [x] Concurrent different-record edits converge without record loss.
- [x] Conflicting reorders from two devices converge to the latest complete ordering without losing rows.
- [x] Habit completion racing against linked task completion is reconciled by newest timestamp without double-counting streaks.
- [x] Synchronization recovery after several failed attempts preserves pending rows and marks them synced only after a confirmed retry.
- [x] Exponential backoff resets after success and does not clear pending changes.
- [x] Save failures before push or after a remote merge fail the sync cycle, preserve pending context changes, and prevent uncommitted local state from being uploaded.
- [x] A page/response failure returns no snapshot, so no partially retrieved response is merged.
- [x] Task, habit, list, and scratchpad snapshots must all complete before a pull is reported successful; optional-table failures cannot produce a false green sync state.
- [x] A complete RLS-filtered snapshot removes a revoked collaborator's cached shared list and items immediately; owned rows retain the two-snapshot anti-data-loss guard.

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

- [x] Logout with no local changes.
- [x] Logout with unsynced edits and a working network confirms upload before purge.
- [x] Logout with unsynced edits and a failed network retains session and local rows.
- [x] Logout while a push is active refuses to purge until it settles.
- [x] Logout while a pull is active refuses to purge until it settles.
- Closing the app during logout.
- [x] Reauthentication into the same account preserves unsynced local rows.
- [x] A different-account auth response is rejected until the current account safely logs out, preventing destructive or visible cache crossover.
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

Account deletion safety: the previous per-table-delete-then-logout sequence could re-upload local rows during logout and did not remove the auth account. It now calls one authenticated transactional `delete_interval_account` RPC and purges local rows/session credentials only after server confirmation. Failure preserves the authenticated session and every local record. The required SQL migration is tracked in `supabase/delete_interval_account.sql` and still requires deployment verification in section 8.

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

The live audit confirmed RLS on all five user-data tables. Default broad grants were corrected using `supabase/harden_data_api_grants.sql`: `anon` now has no table grants and `authenticated` has only `SELECT`, `INSERT`, `UPDATE`, and `DELETE`. The verified `protect_scratchpad_list_owner` trigger prevents collaborators from changing list ownership. A two-account exercise still validates these controls end to end before wider distribution.

- [x] The consolidated read-only release audit passes all seven checks: five-table RLS, zero anonymous grants, exact authenticated CRUD grants, all ten policies, ownership protection, and the protected account-deletion RPC.

## 9. Export, import, and recovery

Implementation safeguards now completed:

- [x] Export first saves pending edits and fails closed if any table cannot be read; it cannot silently create an incomplete backup.
- [x] Import establishes a committed recovery point, rolls back a failed batch, does not start sync on failure, and keeps the import screen open with a recovery message.

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

- [x] The existing automated testbench passes with zero failures.
- [x] Automated persistence, sync, authentication, account-isolation, and drag-safety tests pass.
- [ ] A real two-device offline/online test passes.
- [ ] A live failed-logout test confirms that local data remains available.
- [ ] A fresh-install login test passes.
- [ ] A backup restore drill passes.
- [ ] Supabase row-level security is verified with two real accounts.
- [ ] macOS, iPhone, and Watch installations succeed on release builds.
- [ ] A TestFlight update over an existing installation preserves all data.
- [x] The corrected transactional account-deletion RPC is deployed.
- [ ] Account deletion is smoke-tested with a disposable account only, never the primary account.
- [ ] No critical or high-severity issue remains open after the live drills.
- [x] An emergency backup and recovery procedure is documented in `RELEASE_RECOVERY_RUNBOOK.md`.

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
