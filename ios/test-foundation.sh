#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "이 검사는 Linux용입니다. Mac에서는 bash ios/test-local.sh로 실제 iOS 검사를 실행하세요." >&2
  exit 1
fi

swiftc="${SWIFTC:-swiftc}"
for tool in "$swiftc" python3 git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool 명령이 없습니다. Swift 컴파일러 경로는 SWIFTC로 지정할 수 있습니다." >&2
    exit 1
  fi
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! git -C "$root" check-ignore -q .amp/in/; then
  echo "먼저 저장소 로컬 info/exclude에 /.amp/in/ 규칙을 추가하세요. 생성 파일은 이 폴더에서만 사용합니다." >&2
  exit 1
fi
mkdir -p "$root/.amp/in"
run=$(mktemp -d "$root/.amp/in/foundation.XXXXXX")
trap 'rm -rf -- "$run"' EXIT

python3 - "$root" "$run" <<'PY'
from pathlib import Path
import re
import sys

root, out = map(Path, sys.argv[1:])
source = (root / 'ios/SchoolTodayTests/SchoolTodayTests.swift').read_text()
teacher_tests = (root / 'ios/SchoolTodayTests/TeacherNotesTests.swift').read_text().replace('import XCTest', '').replace('@testable import SchoolToday', '')
teacher_names = re.findall(r'^    func (test\w+)\(', teacher_tests, re.M)
event_tests = (root / 'ios/SchoolTodayTests/SchoolEventsTests.swift').read_text().replace('import XCTest', '').replace('@testable import SchoolToday', '')
event_names = re.findall(r'^    func (test\w+)\(', event_tests, re.M)
excluded = {'testAppIntentsFailWithSetupGuidanceWhenSchoolIsMissing'}
names = [name for name in re.findall(r'^    func (test\w+)\(', source, re.M) if name not in excluded]
methods = [re.search(r'^    (?:@MainActor\n    )?func ' + name + r'\b.*?^    \}', source, re.M | re.S).group() for name in names]
settings = re.search(r'^    private var settings: SchoolSettings \{.*?^    \}', source, re.M | re.S).group()
transport = source[source.index('private final class ControlledTransport:'):]
app = (root / 'ios/SchoolToday/SchoolTodayApp.swift').read_text()
store = app[app.index('@MainActor\nfinal class SchoolStore:'):app.index('\nstruct RootView:')]
today = (root / 'ios/SchoolToday/TodayView.swift').read_text()
model = today[today.index('enum TodayKind:'):today.index('\nstruct TodayView:')]
shims = '''import Foundation
import FoundationNetworking
import XCTest

// These substitutes do not validate observation, SwiftUI, or real network monitoring.
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
protocol ObservableObject {}
struct NWPath { enum Status { case satisfied }; let status: Status }
final class NWPathMonitor {
    var pathUpdateHandler: ((NWPath) -> Void)?
    func start(queue: DispatchQueue) {}
    func cancel() {}
}
struct WidgetCenter {
    static let shared = WidgetCenter()
    func reloadAllTimelines() {}
}
actor PreparationNotifications {
    static let shared = PreparationNotifications()
    func synchronize(plan: PreparationPlan, selection: String, cache: SchoolWeekCache? = nil, plus: Bool = false, plusUntil: Date? = nil) async -> String? { nil }
}
'''
planner = (root / 'ios/SchoolToday/PlannerStore.swift').read_text().replace('import Combine', '').replace('import WidgetKit', '')
runner = shims + '\n' + store + '\n' + model + '\n' + planner + '\nfinal class FoundationTests: XCTestCase {\n'
runner += settings + '\n\n' + '\n\n'.join(methods) + '\n}\n' + transport + '\n' + teacher_tests + '\n' + event_tests
runner += '\nXCTMain([testCase([\n'
runner += ',\n'.join('    ("' + name + '", ' + ('asyncTest(FoundationTests.' + name + ')' if 'async throws' in method else 'FoundationTests.' + name) + ')' for name, method in zip(names, methods))
runner += '\n]), testCase([\n'
runner += ',\n'.join('    ("' + name + '", TeacherNotesTests.' + name + ')' for name in teacher_names)
runner += '\n]), testCase([\n'
runner += ',\n'.join('    ("' + name + '", asyncTest(SchoolEventsTests.' + name + '))' for name in event_names)
runner += '\n])])\n'
(out / 'main.swift').write_text(runner)
for name in ['SchoolAPI', 'PreviewTransport']:
    original = (root / ('ios/SchoolToday/' + name + '.swift')).read_text()
    (out / (name + '.swift')).write_text('import FoundationNetworking\n' + original)
print(f'Foundation-only: {len(names)} model/API/store tests + {len(teacher_names)} teacher-note tests + {len(event_names)} school-calendar tests; actual Foundation bodies.', flush=True)
print('Observation/network monitor/widget/notification substitutes; no SwiftUI, OS notifications, WidgetKit, iOS SDK, or Siri verification.', flush=True)
print('iOS-only test excluded: ' + ', '.join(sorted(excluded)), flush=True)
PY

"$swiftc" -swift-version 5 -DDEBUG "$root/ios/SchoolToday/Models.swift" "$root/ios/SchoolToday/PlannerModels.swift" \
  "$root/ios/SchoolToday/TeacherNotes.swift" "$root/ios/SchoolToday/SchoolEvents.swift" \
  "$run/SchoolAPI.swift" "$run/PreviewTransport.swift" "$run/main.swift" -o "$run/tests"
"$run/tests"
