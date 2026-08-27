#!/usr/bin/env bash
# ==============================================================================
# IntervalApp Mandatory Testbench & Integrity Runner
# ==============================================================================
# All coding agents MUST execute this script before concluding their task.
# Reward hacking (deleting or disabling tests) is strictly prohibited.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Integrity Check: Verify all required test suites exist
REQUIRED_SUITES=(
  "IntervalAppTests/DataLossPreventionTests.swift"
  "IntervalAppTests/HabitDragAndDropTests.swift"
  "IntervalAppTests/HabitTaskLinkTests.swift"
  "IntervalAppTests/HabitPeriodicResetAndStreakTests.swift"
  "IntervalAppTests/TaskKeyboardAndNavigationTests.swift"
  "IntervalAppTests/CrossPlatformInteractionsTests.swift"
  "IntervalAppTests/TransitionLifecycleAndSelectionTests.swift"
  "IntervalAppTests/MigrationManagerTests.swift"
  "IntervalAppTests/MigrationScheduleTests.swift"
  "IntervalAppTests/TaskHousekeepingTests.swift"
  "IntervalAppTests/ScratchpadTests.swift"
  "IntervalAppTests/UIInteractionsAndButtonsTests.swift"
  "IntervalAppTests/SyncBehaviourTests.swift"
  "IntervalAppTests/MergePolicyTests.swift"
)

for suite in "${REQUIRED_SUITES[@]}"; do
  if [ ! -f "$suite" ]; then
    echo "❌ INTEGRITY ERROR: Required test suite '$suite' is missing!"
    exit 1
  fi
done

# 2. Clear stale test bundles to prevent caching artifacts
rm -rf .build/Build/Products/Debug/IntervalAppTests.xctest

# 3. Run full xcodebuild test suite
echo "🚀 Running IntervalApp Testbench..."
xcodebuild \
  -project IntervalApp.xcodeproj \
  -scheme IntervalApp \
  -destination 'platform=macOS' \
  -derivedDataPath .build \
  test \
  -only-testing:IntervalAppTests \
  "$@"

echo ""
echo "✅ TESTBENCH PASSED: All 126+ regression & data integrity tests succeeded."
