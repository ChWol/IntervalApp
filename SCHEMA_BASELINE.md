# SwiftData Schema Baseline

This repository state is the first tester-release persistence baseline. No earlier build has been distributed and no existing installation needs to be upgraded into this schema.

The baseline contains these SwiftData models:

- `TaskItem`: identity, text, completion state, creation/completion/deletion timestamps, interval, order, optional habit link, update timestamp, and sync timestamp.
- `HabitItem`: identity, text, frequency, streak, completion/postponement/deletion timestamps, order, update timestamp, and sync timestamp.
- `ScratchpadList`: list identity, title, owner, order, creation/deletion/update timestamps, and sync timestamp.
- `ScratchpadItem`: item and list identity, text, completion state, order, creation/completion/deletion/update timestamps, and sync timestamp.

Before any future tester or production release changes these models:

1. Preserve a store created by this baseline build as a test fixture.
2. Add an explicit migration path if automatic lightweight migration is insufficient.
3. Open the fixture with the new build and verify tasks, habits, links, completed/deleted records, and scratchpad data.
4. Run the full testbench before distributing the update.

