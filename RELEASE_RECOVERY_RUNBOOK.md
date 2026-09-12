# Interval Release Recovery Runbook

Use this procedure if a tester reports missing, stale, or unsynchronized data. Do not ask the tester to reinstall, sign out, clear the bin, or delete the account before completing the preservation steps.

## Preserve the recovery copy

1. Ask the tester to stop editing on every other device.
2. Keep the affected device signed in and do not delete the app.
3. In Interval, open **Settings → Data & Import → Export Data (JSON Backup)** and save the JSON file somewhere outside the app.
4. Duplicate that file before attempting any repair. Keep the original unchanged.
5. Record the app version, device/OS version, account email, approximate time of the last correct state, and the exact action that preceded the problem. Never request passwords or session tokens.

If export fails, leave the app installed and signed in. Preserve the device for engineering inspection; the SwiftData store may still contain the recovery copy.

## Diagnose without destroying data

1. Confirm network access and retry synchronization once.
2. Check Supabase service status and the latest database migration state.
3. In Supabase, inspect only the affected authenticated user's rows. Never disable RLS or use a service-role key in a client build.
4. Compare record IDs and `updated_at` timestamps with the exported backup. Do not edit production rows until the backup is secured and the cause is understood.

## Restore

1. Prefer repairing synchronization and allowing the preserved local copy to republish.
2. If a backup restore is required, test the file in a disposable account/build first.
3. Import into the affected account only after confirming the conflict rule and expected row counts.
4. Verify active, completed, binned, habit-linked, and scratchpad records on two devices before closing the incident.

## Escalation and release response

- Stop rollout for any unexplained cross-account visibility, permanent data loss, invalid backup, or repeatable sync corruption.
- Preserve logs and timestamps, but never task text, private URLs, passwords, access tokens, refresh tokens, or full database dumps.
- Ship a fix only with a regression test reproducing the incident and a successful backup/restore drill.
