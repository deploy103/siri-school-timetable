#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "네이티브 테스트에는 Mac의 Xcode와 iPhone Simulator가 필요합니다." >&2
  exit 1
fi

for tool in xcodegen xcodebuild xcrun python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool 명령이 없습니다. ios/README.md의 Mac 준비 조건을 확인해 주세요." >&2
    exit 1
  fi
done
if [[ "$(xcodegen --version)" != "Version: 2.46.0" ]]; then
  echo "이 프로젝트의 기준 버전인 XcodeGen 2.46.0을 사용해 주세요." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys
devices = [device for group in json.load(sys.stdin)["devices"].values() for device in group]
requested = os.environ.get("SIMULATOR_UDID")
device = next((device for device in devices if device["name"].startswith("iPhone")
    and (not requested or device["udid"] == requested)), None)
if device is None:
    sys.exit("사용 가능한 iPhone Simulator가 없습니다. Xcode에서 iOS runtime을 설치하거나 SIMULATOR_UDID를 확인해 주세요.")
print(device["udid"])
')

xcodegen generate --spec "$root/ios/project.yml" --project "$root/ios"
mkdir -p "$root/ios/build"
run=$(mktemp -d "$root/ios/build/local-test.XXXXXX")
echo "Simulator: $device_id"
echo "결과 폴더: $run"

set +e
xcodebuild -project "$root/ios/SchoolToday.xcodeproj" -scheme SchoolToday \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -destination-timeout 120 -derivedDataPath "$run/DerivedData" \
  -resultBundlePath "$run/SchoolToday.xcresult" CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "$run/xcodebuild.log"
status=${PIPESTATUS[0]}
set -e
if [[ -d "$run/SchoolToday.xcresult" ]]; then
  xcrun xcresulttool export attachments --path "$run/SchoolToday.xcresult" \
    --output-path "$run/screenshots" || echo "화면 내보내기에 실패했습니다. xcresult를 Xcode에서 열어 주세요." >&2
fi
echo "빌드·테스트 로그와 xcresult: $run"
exit "$status"
