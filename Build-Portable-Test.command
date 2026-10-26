#!/bin/zsh
# Build "NeAntik Unlimited" — a portable, no-install test build of the
# NeAntik incognito-profile browser for Apple Silicon Macs (macOS 14+).
#
# What it does:
#   1. Builds the patched manager (unlimited profiles) from this checkout.
#   2. Downloads the official signed 0.9.0 Chromium runtime (180 MB).
#   3. Assembles NeAntik-Unlimited.app and ad-hoc signs it.
#   4. Leaves the app in ./dist — unzip nothing, install nothing:
#      just double-click the app (right-click → Open on first launch).
#
# Requirements: Apple Silicon Mac, macOS 14+, Xcode (full, any recent
# version) — the script checks and tells you what is missing.

set -euo pipefail
umask 077

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RUNTIME_URL="https://github.com/AffPapa/neantik/releases/download/v0.9.0/NeAntik-0.9.0-arm64-notarized.zip"
RUNTIME_SHA="87337e18d7d0e93f14c5ca3d30dfe07b42edb929aa6510c5c015275b50f40b47"
WORK="$(mktemp -d /private/tmp/neantik-unlimited-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "== NeAntik Unlimited — portable test build =="
echo

# --- Preflight -------------------------------------------------------------
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "✗ هذا الجهاز Intel — التطبيق يعمل على Apple Silicon فقط." >&2
  exit 1
fi
MACVER="$(sw_vers -productVersion)"
if [[ "$(python3 -c 'print(1 if tuple(map(int,"'"$MACVER"'".split("."))[:2] >= (14,0) else 0)')" != "1" ]]; then
  echo "✗ macOS $MACVER — التطبيق يحتاج macOS 14 أو أحدث." >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1 || \
   ! DEVELOPER_DIR="$(xcode-select -p 2>/dev/null)" \
     DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --show-sdk-path >/dev/null 2>&1 || \
   [[ "$(xcode-select -p 2>/dev/null)" != *Xcode.app* ]]; then
  echo "✗ Xcode الكامل غير مثبّت. ثبّته من App Store ثم:" >&2
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
echo "✓ Apple Silicon، macOS $MACVER، Xcode جاهز"
echo

# --- 1. Build the patched manager -------------------------------------------
echo "[1/4] أبني مدير البروفايلات المعدّل (unlimited)…"
swift build -c release --arch arm64 --disable-sandbox \
  --scratch-path .build/unlimited --product NeAntik
BIN="$(swift build -c release --arch arm64 --disable-sandbox \
  --scratch-path .build/unlimited --show-bin-path)/NeAntik"
[[ -x "$BIN" ]] || { echo "✗ لم يُنتج البناء الملف التنفيذي." >&2; exit 1; }
echo "✓ $BIN"

# --- 2. Fetch the official runtime -------------------------------------------
echo "[2/4] أنزّل runtime Chromium الرسمي (180 ميجا، مرة واحدة)…"
curl -fL --progress-bar -o "$WORK/runtime.zip" "$RUNTIME_URL"
ACTUAL_SHA="$(shasum -a 256 "$WORK/runtime.zip" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$RUNTIME_SHA" ]]; then
  echo "✗ فشل التحقق من بصمة runtime." >&2
  echo "  expected: $RUNTIME_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi
echo "✓ تحققت بصمة runtime."

# --- 3. Assemble the portable app -------------------------------------------
echo "[3/4] أجمّع NeAntik-Unlimited.app…"
mkdir "$WORK/x"
unzip -q "$WORK/runtime.zip" -d "$WORK/x"
APP="$WORK/x/NeAntik.app"
cp "$BIN" "$APP/Contents/MacOS/NeAntik"
# app.neantik.desktop.dev is the code-recognized isolated environment:
# separate Application Support dir + own Keychain service, so the test
# build never touches a real NeAntik installation on the same Mac.
plutil -replace CFBundleIdentifier -string app.neantik.desktop.dev \
  "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "NeAntik Unlimited" \
  "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "NeAntik Unlimited" \
  "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "0.9.0-unlimited" \
  "$APP/Contents/Info.plist"
# Keep localized display name consistent too.
if [[ -f "$APP/Contents/Resources/ru.lproj/InfoPlist.strings" ]]; then
  plutil -replace CFBundleDisplayName -string "NeAntik Unlimited" \
    "$APP/Contents/Resources/ru.lproj/InfoPlist.strings" 2>/dev/null || true
  plutil -replace CFBundleName -string "NeAntik Unlimited" \
    "$APP/Contents/Resources/ru.lproj/InfoPlist.strings" 2>/dev/null || true
fi
# Ad-hoc re-sign: nested browser runtime first, helpers, then the bundle.
# (Matches the official Dev fast path: deep-sign the runtime, plain-sign
# the outer app; no entitlements — the official ones are team-bound.)
codesign --force --deep -s - "$APP/Contents/Resources/NeAntik Browser.app" 2>/dev/null || true
find "$APP/Contents/Helpers" -type f -perm +111 \
  -exec codesign --force -s - {} \; 2>/dev/null || true
codesign --force -s - "$APP"
codesign --verify --deep --strict "$APP" || {
  echo "✗ فشل التحقق من التوقيع ad-hoc." >&2; exit 1; }

# --- 4. Deliver ---------------------------------------------------------------
echo "[4/4] أنسخ النتيجة إلى dist/…"
mkdir -p "$PROJECT_DIR/dist"
rm -rf "$PROJECT_DIR/dist/NeAntik-Unlimited.app"
cp -R "$APP" "$PROJECT_DIR/dist/NeAntik-Unlimited.app"
shasum -a 256 "$PROJECT_DIR/dist/NeAntik-Unlimited.app/Contents/MacOS/NeAntik" \
  > "$PROJECT_DIR/dist/NeAntik-Unlimited.sha256"

echo
echo "PASS: التطبيق المحمول جاهز — لا تثبيت."
echo "    $PROJECT_DIR/dist/NeAntik-Unlimited.app"
echo
echo "للتشغيل: انقر مرتين؛ وفي أول مرة: زر يمين ← فتح (Open) بسبب التوقيع ad-hoc."
(( SHOULD_OPEN := 1 ))
if [[ "${1:-}" != "--no-open" ]]; then
  open "$PROJECT_DIR/dist/NeAntik-Unlimited.app" 2>/dev/null || true
fi
