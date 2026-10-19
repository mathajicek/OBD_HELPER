#!/usr/bin/env bash
# Updates OBD Pulse and installs it on an iPhone connected to this Mac.
#
# First run:  TEAM=<your Apple team id> ./tool/install_ios.sh
#   (Xcode › Settings › Accounts › your Apple ID shows the team id; a free
#   "Personal Team" works, the app then runs for 7 days.)
# Later runs: ./tool/install_ios.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIGNING=ios/Flutter/Signing.xcconfig
PBX=ios/Runner.xcodeproj/project.pbxproj

# A team picked earlier in Xcode lives in the project file; keep it locally
# and drop the edit so pulling updates does not conflict.
if ! git diff --quiet -- "$PBX"; then
  OLD_TEAM=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$PBX" | awk '{print $3}' || true)
  [ -n "${OLD_TEAM:-}" ] && [ -z "${TEAM:-}" ] && TEAM=$OLD_TEAM
  git checkout -- "$PBX"
fi
[ -n "${TEAM:-}" ] && echo "DEVELOPMENT_TEAM = $TEAM" > "$SIGNING"
if [ ! -f "$SIGNING" ]; then
  echo "Chybí podpisový tým. Spusťte: TEAM=<team id> ./tool/install_ios.sh" >&2
  exit 1
fi

git pull --ff-only
flutter pub get

DEVICE=$(flutter devices --machine | python3 -c '
import json, sys
ds = [d for d in json.load(sys.stdin) if d.get("targetPlatform") == "ios" and not d.get("emulator")]
print(ds[0]["id"] if ds else "")
')
if [ -z "$DEVICE" ]; then
  echo "iPhone nenalezen: připojte ho kabelem, odemkněte a potvrďte Důvěřovat tomuto počítači." >&2
  exit 1
fi

flutter run --release -d "$DEVICE" --no-resident
echo "Hotovo. Při prvním spuštění povolte vývojáře v Nastavení › Obecné › VPN a správa zařízení."
