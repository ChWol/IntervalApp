---
trigger: always_on
---

# Testbench & Data Loss Guard

## Mandate
Whenever modifying the codebase, you MUST:
1. Run `./scripts/run-tests.sh` to execute the full 126+ test testbench.
2. If any test fails, iterate on your implementation in `IntervalApp/` until all tests pass.
3. NEVER delete, comment out, or weaken test assertions in `IntervalAppTests/`.
4. Ensure 0 compilation errors, 0 compilation warnings, and 0 test failures.
