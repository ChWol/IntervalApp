# IntervalApp Coding Agent Rules & Behavioral Directives

## 1. MANDATORY Testbench Verification Rule
Before finishing any coding task or declaring work complete, you **MUST** run the automated testbench:
```bash
./scripts/run-tests.sh
```
**ALL 126+ tests must pass with 0 errors and 0 failures.**

---

## 2. STRICT Anti-Reward-Hacking Policy
- **NEVER delete, comment out, weaken, or modify existing test assertions** in `IntervalAppTests/` to make failing tests pass.
- If a test fails after your changes, **you MUST iterate on your production code implementation** until the test passes naturally.
- The tests in `IntervalAppTests/` represent the ground truth of user-expected behavior, data safety, and sync integrity. Modifying tests without explicit user instructions is strictly prohibited.

---

## 3. Data Integrity & Safety Invariants (Zero-Tolerance for Data Loss)
1. **Migration & Transition Invariant**:
   - In any interval transition (e.g. 1 Day → 1 Hour, 1 Week → 1 Day, etc.), unselected tasks **MUST remain safely in their source interval** and **must NEVER be deleted, binned, or completed**.
2. **Habit Task Isolation**:
   - Tasks generated from habits (`task.habitId != nil`) must NEVER appear in the bottom "Completed" or "Recently Deleted" sections. Ticking them updates the habit streak and marks the task done without polluting archives.
3. **Selective Drag & Drop**:
   - Dragging habit chips is **only allowed into 1 Hour**. Dropping into 1 Day, 1 Week, 1 Month, or 1 Year is strictly forbidden.
   - Drag-and-drop operations must **only update `updatedAt` on the dragged/modified items**, never on all records in the database.
4. **Offline & Sign-Out Safety**:
   - Sign-out must only purge the local database if a remote push succeeded or if unauthenticated. Never wipe unsynced local data if network push fails.
5. **No SwiftData Crashes on Async Sync**:
   - Always check `!model.isDeleted` before mutating `syncedAt` on models after an `await` network call.
6. **Habit Postpone Invariant**:
   - Postponed habits for today (`isPostponedToday == true`) must be filtered out of `selectableHabits` and never trigger or appear in hourly transition dialogues.

---

## 4. Platform & UI Behavior Guidelines
- **macOS Menu Bar**: Shows only active 1-Hour tasks, no completed tasks, no default auto-focus on text input, on-hover input styling, no Quit button.
- **German Localization**: "Recently Deleted" is "KÜRZLICH GELÖSCHT", "Empty Bin" is "Papierkorb leeren", "Habits" is "GEWOHNHEITEN".
- **Tab Key Navigation**: Focus advances in strict order: 1 Hour $\to$ 1 Day $\to$ 1 Week $\to$ 1 Month $\to$ 1 Year $\to$ Scratchpad.
