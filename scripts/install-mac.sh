#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-/tmp/dd_iv_mac}"
APP_PATH="${APP_PATH:-/Applications/IntervalApp.app}"
BUILT_APP="${BUILD_DIR}/Build/Products/Debug/IntervalApp.app"

if [[ "${1:-}" == "--from" ]]; then
  BUILT_APP="${2:?Usage: install-mac.sh --from /path/to/IntervalApp.app}"
else
  echo "==> Building IntervalApp (macOS)..."
  xcodebuild -scheme IntervalApp \
    -destination "platform=macOS" \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "❌ Build succeeded without producing ${BUILT_APP}" >&2
  exit 1
fi

BUILT_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${BUILT_APP}/Contents/Info.plist")
if [[ "${BUILT_BUNDLE_ID}" != "chw.IntervalApp" ]]; then
  echo "❌ Refusing to install unexpected bundle ID: ${BUILT_BUNDLE_ID}" >&2
  exit 1
fi

# A build with CODE_SIGNING_ALLOWED=NO has only a linker signature whose
# identifier is the executable name. Seal the app bundle with its real bundle
# identifier so macOS can associate notifications with its bundled icon.
if ! /usr/bin/codesign --verify --strict "${BUILT_APP}" >/dev/null 2>&1; then
  /usr/bin/codesign --force --sign - --identifier "${BUILT_BUNDLE_ID}" "${BUILT_APP}"
fi

echo "==> Replacing ${APP_PATH} with the freshly built app..."
APP_PARENT="$(dirname "${APP_PATH}")"
STAGING_APP="${APP_PARENT}/.IntervalApp.installing.app"
BACKUP_APP="${APP_PARENT}/.IntervalApp.previous.app"
rm -rf "${STAGING_APP}" "${BACKUP_APP}"
ditto "${BUILT_APP}" "${STAGING_APP}"

# Keep the old bundle available until the new copy is in place; restore it if
# the final rename fails. App data lives outside the .app bundle.
if [[ -e "${APP_PATH}" ]]; then
  mv "${APP_PATH}" "${BACKUP_APP}"
fi
if ! mv "${STAGING_APP}" "${APP_PATH}"; then
  if [[ -e "${BACKUP_APP}" ]]; then mv "${BACKUP_APP}" "${APP_PATH}"; fi
  exit 1
fi
rm -rf "${BACKUP_APP}"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

echo "==> Removing duplicate Xcode build registrations..."
"${LSREGISTER}" -u -R "${BUILT_APP}" >/dev/null 2>&1 || true
unregister_duplicate_builds() {
  local candidate bundle_id

  # Check only known build output paths. Recursively walking all of DerivedData
  # after every Xcode build scans gigabytes of unrelated compiler/index data.
  for candidate in \
    "${PROJECT_DIR}"/.build*/Build/Products/*/IntervalApp.app \
    "${HOME}/Library/Developer/Xcode/DerivedData"/*/Build/Products/*/IntervalApp.app; do
    [[ -d "${candidate}" ]] || continue
    [[ "${candidate}" == "${APP_PATH}" ]] && continue
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null || true)
    if [[ "${bundle_id}" == "${BUILT_BUNDLE_ID}" ]]; then
      "${LSREGISTER}" -u -R "${candidate}" >/dev/null 2>&1 || true
    fi
  done
}
unregister_duplicate_builds

echo "==> Registering the installed app with LaunchServices..."
"${LSREGISTER}" -f -R -trusted "${APP_PATH}"

echo "✅ Successfully installed ${BUILT_BUNDLE_ID} at ${APP_PATH}."
