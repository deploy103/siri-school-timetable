# 오늘의 학교 — 네이티브 iOS 앱

SwiftUI iPhone 앱(iOS 17+)이다. 웹뷰/PWA 래퍼가 아니며 앱 타깃 안에 App Intents와 App Shortcuts Provider를 제공한다. 기존 Next.js 서버는 NEIS 키를 보관하는 백엔드로 재사용한다. NEIS 키와 Apple 계정 암호는 앱에 저장하지 않는다. 구독은 Apple StoreKit 2, 선택적인 개인 기록 동기화는 CloudKit을 사용한다. 별도 회원가입과 광고 SDK는 없다.

## 주간 조회와 등교 준비

- 학교 선택 후 `오늘 / 주간 / 준비`로 바로 이동한다. Siri 설정은 선택 사항이며 오늘 화면과 설정에서 다시 연다.
- 오늘·내일·주간 시간표와 급식은 무료다. 주간 요청은 `/api/timetable/range`, `/api/meal/range`를 사용한다. 두 자료는 동시에 요청하고 먼저 도착한 결과부터 표시해 다른 서비스의 장애를 기다리지 않는다.
- 수업을 누르면 과목이 미리 선택된 준비물 입력을 연다. 한 과목의 자동 연결은 계속 무료이며, 같은 날 중복 수업은 준비물을 중복 생성하지 않는다. 완료 상태는 날짜별로 저장한다.
- 준비물·수행평가·시험·숙제를 날짜와 메모로 직접 등록한다. 준비 탭은 지난 미완료·오늘·앞으로 7일·이후 일정을 모아 보이며 날짜별 준비도 유지한다. 기본 알림은 일정당 한 시점이며, 요청할 때만 권한을 구한다. 완료·삭제하면 예약을 취소한다. 알림 전달 시각과 백그라운드 자료 수집은 보장하지 않는다.
- 주간의 ‘학교 학사일정’은 `/api/calendar/range`에서 받은 NEIS 원문을 개인 평가와 별도로 표시한다. 같은 이름의 행사와 주야/과정 정보도 보존한다. 빈 일정이나 학년 원문 값을 휴일·등교 여부로 해석하지 않는다. 새 서버 경로 배포 전에는 오류·재시도 안내가 표시될 수 있으며 앱 수정이 운영 서버 배포를 뜻하지 않는다.
- 설정의 ‘개인 선생님 메모’는 직접 적은 과목·이름·교실·메모를 학교·학급별로 기기에만 저장한다. 공식 교사 명단이나 공유 자료가 아니며 준비 기록의 JSON 백업·수동 iCloud·학교 설정 공유·위젯에 포함하지 않는다. 연락처 등 민감한 정보 입력은 권하지 않는다.
- 수업을 길게 눌러 해당 날짜·교시의 선택과목과 교실을 수정하거나 누락 수업을 직접 추가한다. 원본을 유지하며 학교 자료로 되돌릴 수 있다. 수정은 앱·위젯·준비물 연결에 적용하며 기존 Siri·읽기·공유는 학교 원본을 사용한다. 자료 누락은 ‘준비물 없음’으로 처리하지 않는다.
- 개인 기록은 Application Support의 별도 JSON에 원자적으로 저장하고 iOS 파일 보호를 적용한다. 읽을 수 없는 원본은 덮어쓰지 않는다. 학교 변경은 기록을 삭제하지 않으며 다른 학급의 기록은 섞어 표시하지 않는다. 무료 JSON 백업·복원과 명시적으로 실행하는 iCloud 동기화를 제공한다.
- 최근 받은 한 주 자료는 학교·학급·서버·실제/예제 모드를 구분해 저장한다. 재조회 실패 때 날짜와 마지막 확인 시각을 유지하며 최신 여부를 안내한다.
- 기본 WidgetKit 확장은 마지막으로 받은 시간표·급식을 App Group에서 읽는다. 별도 Plus 준비 위젯은 사용자가 개인 내용 표시를 직접 켰을 때만 준비물·마감을 읽으며 확인한 구독 만료 시각 뒤에는 숨긴다. 시스템의 갱신 시점을 보장하지 않는다.
- 날짜 헤더·달력·입력·설정·Plus 화면을 밝은 카드와 남색 강조로 통일했다. 달력은 선택 확인 전까지 기존 날짜를 바꾸지 않으며 큰 글자에서는 날짜별 전체 폭 버튼으로 바뀐다. 종 시간을 직접 설정하면 현재·다음 수업을 무료로 표시한다. 실제 학교 종 시간을 추측하지 않는다.
- Plus는 여러 과목 자동 준비, 발표·보고서·실습 마감 단계, 여러 사전 알림, 저녁 요약·아침 재확인, 개인 준비 위젯을 제공한다. 일정·단계의 완료 시 후속 알림을 제외하며 요약 알림은 날짜까지 쉴 수 있다. 알림은 확보한 자료에 근거해 다음 7일만 예약하며 최신 자료의 백그라운드 수집이나 정각 전달을 보장하지 않는다.
- Plus 만료 시 기본 조회·직접 일정·기본 알림·무료 한 과목은 유지한다. 기록은 삭제하지 않고 추가 자동화만 중지한다. 사용할 무료 과목을 직접 고를 수 있고 재구독하면 보존한 연결과 단계를 다시 사용한다. 구매 직전 작성한 준비물은 검증된 구매 성공 후 이어서 저장한다.
- 학교·학급 설정 링크는 개인 준비 기록 없이 공유하며 받는 사람에게 학급 검증·적용 확인을 요구한다. 이전 학교·학기의 과목 규칙은 새 과목명을 직접 지정해 복사한다. 자동으로 이름을 추측해 연결하지 않는다.

### Plus·동기화 운영 준비

- 상품 ID는 `com.deploy103.schooltoday.plus.monthly`, `com.deploy103.schooltoday.plus.yearly`이다. 앱은 실제 StoreKit 상품 가격과 기간만 표시하고 검증된 현재 권한만 사용한다. 취소·승인 대기·구입 복원·환불/회수·만료를 처리하며 로컬 설정으로 권한을 만들지 않는다. 무료 체험 문구는 실제 상품의 introductory offer와 계정 이용 자격을 확인한 경우에만 표시한다.
- `SchoolTodayTests/Plus.storekit`은 **로컬 테스트 전용** 미국 storefront의 월 US$1.90 / 연 US$14.90 예시 카탈로그다. 출시 상품·국내 판매 가격·무료 체험을 등록하는 파일이 아니다. `SchoolToday-LocalStoreKit` scheme의 독립 `StoreKitTestHost`는 실제 `PlusStore.swift`를 그대로 컴파일하되 앱 시작 시 초기화하지 않는다. `SchoolTodayStoreKitTests`가 SKTestSession 설정 뒤 최초 store 접근을 제어한다. 이는 구독 저장소의 계약 검사이지 실제 앱 시작 순서의 검증은 아니다. 기본 `SchoolTodayTests`와 분리하며 실패를 건너뛰지 않는다. 아래 로컬 스크립트와 CI는 두 scheme을 순서대로 실행한다. student-v2의 첫 상품 API 중단/teardown 불명은 보존하며, 별도 [두 번째 PR CI](https://github.com/deploy103/siri-school-timetable/actions/runs/39574550352)의 iOS 18.5 독립 호스트에서는 기존 strict lifecycle **1/1, 23.509초**를 통과했다. 로컬 테스트를 실제 판매 검증으로 사용하면 안 된다.
- 실제 판매에는 Apple Developer 계정의 In-App Purchase 설정, App Store Connect 상품·구독 그룹·판매 가격·계약, 공개 개인정보처리방침 URL과 심사 준비가 필요하다. 소스 구현이나 로컬 StoreKit 테스트는 판매 개시를 뜻하지 않는다. Apple 계정이나 운영 상품을 자동 변경하지 않았다.
- CloudKit container는 `iCloud.com.deploy103.schooltoday`이며 private database의 `SchoolPreparation` / `preparation-v1` 레코드 하나에 최대 256 KiB schema 3 준비 기록을 저장한다. 사용자가 누를 때만 실행한다. 자동 동기화·서버 푸시는 없으며 동기화 권한은 Plus 구매와 별개다. Debug는 Development, Release는 Production entitlement를 사용한다. Apple 계정에서 container·서명 entitlement와 운영 schema를 준비해야 실제 기기에서 사용할 수 있다.
- 양쪽이 바뀌면 한쪽 전체를 직접 선택한다. 계정 변경·원격 기록 삭제·지원하지 않는 형식·동시 변경 시 자동 덮어쓰지 않는다. 복원 직전 기기 원본을 별도 파일로 보존한다. 구매 복원은 Plus 권한만 복원하며 개인 기록은 JSON/iCloud로 별도로 복원한다.
- 준비 기록 schema 1·2는 ID·완료 상태를 유지해 schema 3으로 읽는다. 기존 `preparation-v1.json` 경로는 유지한다. 새 분류·메모가 구형 앱의 재저장으로 사라지지 않도록 새 저장은 schema 3을 사용하며 구형 앱으로 되돌리면 새 archive를 읽지 못한다. JSON 가져오기는 schema 1–3·크기·날짜·관계 검증과 사용자 교체 확인을 거치고, 미리보기 후 기기 기록이 바뀌면 중단한다. CloudKit 운영 데이터 통신·실물 알림·Siri·SpringBoard 위젯은 별도 실제 기기 검증 대상이다.

### 2026-10-21 학생 v1 검증 상태

- 후속 CI 진단 후보는 Xcode 16.4를 명시하고 도구 버전/runtime을 기록한다. `SCHOOL_STOREKIT_DIAGNOSTICS`는 독립 `StoreKitTestHost`에서만 켜 거래 수신·refresh 세대·외부 구매 반환 시 거래 날짜를 남긴다. 앱/위젯은 이 로그를 컴파일하지 않는다. 기존 assertion·10초/20초 대기·50ms poll·session 순서는 그대로이며 추가 StoreKit 조회는 `XCTFail` 뒤에만 한다. 조회/teardown 중 무한 정지를 제한하는 CI step 외부 한도는 5분이다. 조건부 로그를 제거한 앱의 활성 소스·기존 CI 명령/순서 동등 비교, 두 조건의 Swift 문법·YAML·Linux Foundation 40개는 통과했지만 후보의 native 실행은 아직 없다. 로그가 타이밍에 영향을 줄 수 있으며 진단 통과는 원인 규명·제품 수정·기존 실패의 대체가 아니다.
- **최신 필수 CI 실패·병합 보류:** [최종 문서 revision 검사](https://github.com/deploy103/siri-school-timetable/actions/runs/39582443818)는 11:06:50 UTC 실패했다. unsigned Release·웹 211개/브라우저 24개·hosted 41개·UI 19개는 통과했지만 독립 StoreKit 한 case가 64.119초에 실패했다. 월간 구매·자연 만료 뒤 테스트 시계를 realTime으로 바꾸고 외부 연간 구매의 자동 권한 반영을 기존 10초 안에 확인하지 못했다. 오류 기록 2개는 실패 case 하나이며 복원·환불은 미도달이다. 아래 CI2 통과는 이 최신 실패를 대체하지 않는다. 원인은 미확정이며 PR #4는 Draft/미병합, 배포 없음이다.
- 별도 scratch 진단은 listener/refresh/거래 날짜 로그와 실패 확정 뒤 읽기만 추가하고 기존 assertion·10초/20초 대기·시계 전환을 유지했다. Xcode 27.1/iOS 27의 독립 host/test 빌드는 통과했지만 월간 구매 반환을 기다리며 멈춰 11:22:16 UTC 부모 지시로 중단했다. **INTERRUPTED**이며 assertion 실패나 통과가 아니다. 자연 만료·연간 구매·passive wait에는 도달하지 않았고 teardown 완료도 확인하지 못했다. CI의 Xcode 16.4/iOS 18.5와 환경이 달라 원래 실패를 재현·규명한 결과가 아니다. scratch는 제품에 반영하지 않았다. 검증자 보고상 소유 기기는 Shutdown/재사용 제외, 잔여 SDK 작업 0개와 11:22:55 UTC 실제 해제를 확인했으며 후속 예약은 없다.
- 첫 student-v1 snapshot(archive `5264901d…`, 원본 64개 SHA 일치)은 native 빌드 및 hosted unit **38/38**, 기존 날짜/재실행 UI **1/1**, 최대 글자·dark UI **1/1**을 통과했다. 새 평가/메모 UI **1개는 실패**했다. 제목 입력 뒤 키보드가 열린 상태에서 과목란 `isHittable`을 만족하지 못했으며 평가 저장·완료·메모 UI·재실행은 미도달이다. 원인은 앱과 테스트 제스처 중 확정하지 않았다. 기존 결과를 새 기능 전체 통과로 합산하지 않는다.
- student-v2(archive `cbbb37ff…`, 67개 source SHA 일치)는 앱·위젯·unit/UI와 독립 StoreKit host 빌드, hosted unit **41/41** 및 공식 학사일정 UI **1/1(93.268초)**를 통과했다. 공식 일정은 503→재시도·같은 이름의 두 행사·서로 다른 과정/학년 원문·빈 6일의 안내를 검사했다. 평가/메모 UI는 ‘입력 완료’ 탭 뒤에도 제목 포커스와 키보드가 남아 3초 대기에서 **1개 실패(92.399초)**했다. 저장/완료/개인 메모 UI는 미도달이다. 버튼 영역과 실제 터치 영역이 같은지는 아직 확정하지 않았다.
- 독립 StoreKit lifecycle은 첫 상품 API의 XcodeTest/USA `system(unknown)` 뒤 약 7분간 진행이 없어 07:24:12 UTC 중단했다. assertion 실패/카탈로그 복구/구매 검증이 아니라 **미완료**이며 취소 뒤 teardown 완료도 확인하지 못했다. 원본 로그·부분 xcresult·22개 일치 binary 기록과 19개 미검토 PNG를 보존했다.
- student-v3(archive `3f42258a…`, 67개 source 불변)는 완료 버튼의 전체 표시 영역을 label 내부 `contentShape`로 터치 영역에 포함했다. 기존 중앙 탭과 키보드 부재 3초 assertion을 바꾸지 않고 앱·위젯·unit/UI 빌드, hosted unit **41/41**, 평가/개인 메모 UI **1/1(213.483초)**를 통과했다. 평가 제목·과목·메모와 교사 과목·이름·교실의 6개 키보드 닫힘, 평가 저장/재열기/완료 취소, 개인 메모 저장/재실행 보존을 확인했다. 부모도 해당 두 원본 로그와 priority binary 7개 일치 기록을 읽었다. 이전 v2 실패는 보존한다.
- 같은 v3의 기존 최대 글자/dark UI는 날짜 버튼 탭 뒤 ‘다음 달’을 5초 안에 찾지 못해 **1개 실패(133.005초)**했다. 초기 입력·저장·날짜별 완료와 내일 미완료까지 도달했지만 달력·설정·알림 저장은 미도달이다. full AX 103개 노드에는 준비 화면이 남았고 달력은 없었다. 실패 시 날짜 버튼 frame과 navigation bar가 겹치지만 실제 탭 시점 frame은 없으므로 원인을 확정하지 않는다. dark 설정은 07:49:50 UTC 적용되어 이후 planner-large 캡처에 해당하며 초기 onboarding 전체가 dark였다고 주장하지 않는다. 총 **42 PASS/1 FAIL**다.
- 진단 전용 student-v4(archive `4cec6e32…`)는 README와 탭 전 AX attachment/실패 메시지만 바꾸고 제품·설정·제스처·assertion·5초 timeout을 유지했다. fresh 빌드와 기존 최대 글자/dark UI **1/1(183.480초)**가 통과해 달력·설정·알림 설정 저장에 도달했다. dark는 앱 실행 전 08:03:26 UTC 확인했다. 이는 **성공한 비재현이지 제품 수정/원인 규명은 아니다**. v3 실패는 보존한다. 탭 전 날짜 frame은 {{314,79},{48,48}}로 v3 실패 후 frame과 다르지만, 시점과 조건이 다르고 v4 실제 탭 좌표도 보존되지 않아 원인을 단정하지 않는다. Linux Foundation **40/40**과 Swift 문법/YAML 검사는 native 결과를 대체하지 않는다.
- 웹/서버는 Vitest **211/211**, lint/typecheck/production build를 통과했다. 첫 저장 후 선택적 Siri 동선의 별도 브라우저 snapshot은 Chromium/WebKit **24/24**를 통과했다. 새 학사일정 서버의 운영 배포·실물 Siri·실제 구독·CloudKit·알림 전달 검증은 아니다.
- 이전 UIv3의 가격/내보내기 단일 통과는 가격 안전 조건과 Files 닫기·저장 버튼 접근·내보내기 복귀를 확인했다. Boolean 값이 없는 로그로 ‘조회 중+상품 있음’과 ‘조회 완료’를 구별할 수 없으므로 completed-catalog라고 단정하지 않는다. 이전 빈 카탈로그 lifecycle 실패도 남는다.
- 부모는 v3 bundle `2d68aa92…`의 547개 checksum·source 67개·binary 19개, v4 bundle `93b11ad8…`의 205개 checksum·source 67개·binary 7개 저장 bytes 및 두 `recheck-saved.py`를 Linux에서 독립 확인했다. v3 24개/v4 14개 PNG는 media quota로 시각 미검토이며 시각 승인·전체 통과·출시 완료를 주장하지 않는다. SDK 실제 정리·해제는 v3 **07:52:13 UTC**, v4 **08:08:20 UTC**다. v4 소유 phone은 light 복원 후 Shutdown, 최종 SDK 작업/booted 기기 0개이며 추가 SDK 예약은 없다.
- Draft [PR #4](https://github.com/deploy103/siri-school-timetable/pull/4)의 [첫 CI](https://github.com/deploy103/siri-school-timetable/actions/runs/39568570713)는 웹 211개·브라우저 24개·lint/typecheck/audit와 unsigned iPhone Release 빌드를 통과했다. iPhone 16 Pro/iOS 18.5의 hosted **41/41**, UI **17/19** 통과이며 전체 CI는 **실패**다. 평가/개인 메모·공식 일정·최대 글자 UI도 통과했지만 설정 진입 직후 단축어 버튼 hittability와 Files action identifier 조회가 실패했다. 후자는 보존 AX에 identifier 없는 `Move` 버튼이 존재한다. 다음 후보는 제품 코드 없이 설정 버튼을 스크롤로 드러내고 Files의 실제 Move/Save 표기를 허용하되 enabled/hittable·dismissal 검사를 유지한다. Swift 문법 검사만 통과했으며 새 native 결과는 아직 없다. StoreKit CI 단계는 선행 실패로 미실행이고 병합·배포하지 않았다.
- [두 번째 PR CI](https://github.com/deploy103/siri-school-timetable/actions/runs/39574550352)는 09:56:11 UTC 전체 통과했다. unsigned Release·웹 211개/브라우저 24개·hosted **41/41**·UI **19/19**·독립 StoreKit **1/1(23.509초)**다. 설정 단축어/Files 검사 보완은 제품·timeout·enabled/hittable·실제 dismissal 조건을 바꾸지 않았다. StoreKit은 기존 fault injection·상품 조회 복구·로컬 구매·자연 만료·외부 거래 listener·복원·환불 assertion을 통과했다. 이전 CI 실패·v2 중단·v3 최대 글자 실패는 유지하며 production 앱 초기화·실물 구매·Siri 성공으로 확대하지 않는다.
- 후속 workflow는 Release 직후 실제 메타데이터를 보존한다. Xcode **16F6** 산출물에서 두 action·비어 있지 않은 type name·네 한국어 호출문·컴파일된 ko NLU 자산을 독립 확인했다. Xcode 27과 training YAML도 byte-identical이다. dependency list는 widget 메타데이터를 가리키고 앞선 로그는 widget 출력 생략을 기록하지만, `Unable to parse extract.actionsdata`의 원인 확정이나 OS 등록/발화 검증은 아니다. **09:30:27 UTC 운영 학사일정 API는 HTTP 404/HTML**이므로 새 공식 일정은 별도 승인된 서버 배포 전 운영 사용이 불가하다. 캡처는 quota로 미검토다. 후속 revision의 필수 CI/병합 상태는 PR에서 확인하며 소스 푸시가 앱 설치·배포를 뜻하지 않는다.

### 2026-10-17 이전 기본 준비 snapshot 검증 기록

- Linux Foundation 검사 **26/26** 통과. 한 서비스가 대기·실패해도 다른 자료를 먼저 표시하는 회귀 검사는 수정 전 실패를 확인한 뒤 통과했다.
- Mac의 planner-v3 snapshot(51개 파일 SHA 대조)은 iPhone 17 / iOS 27 Simulator에서 **단위 27개 + 기본·최대 글자 UI 2개, 29/29 / exit 0**을 통과했다. 과목 연결·날짜별 완료 분리·재실행 보존·직접 입력·선택적 Siri 안내 접근을 실행했다. 기존 온보딩 전체 UI suite나 다른 기기 매트릭스를 다시 실행한 결과는 아니다.
- 녹색 테스트와 별개로 실제 캡처에서 수정 화면의 두 번째 footer가 표시되지 않는 문제와 작은 위젯 문구 잘림을 확인했다. 두 표시만 보완한 planner-v4(51개 파일 SHA 대조)는 SDK Debug 빌드와 기존 기본 준비 흐름 UI **1/1 / exit 0**을 통과했다. 두 안내 문단과 작은 위젯의 전체 확인 날짜를 새 캡처에서 검토했다. v3 단위·최대 글자 결과를 v4 전체 재검사로 합산하지 않는다.
- 작은/중간 위젯은 동일 view body의 임시 컴포넌트 호스트에서 각각 렌더링했다. 수정 표시와 서로 다른 시간표·급식 확인 날짜를 확인했지만 SpringBoard 설치·TimelineProvider 갱신·실제 App Group 서명은 검증하지 않았다. iOS 27의 반투명 탭 바 뒤로 스크롤 내용이 지나가며 검사한 동작은 스크롤로 접근 가능했다. 화면 전체가 언제나 가림 없이 보인다는 뜻은 아니다.
- 근거는 Mac의 `.amp/in/artifacts/planner-v3/`와 `planner-v4/`에 xcresult·로그·종료 코드·입력/실행 후 SHA·캡처 매핑으로 보존했다. Linux에도 요약과 검토 캡처를 보관했다. SDK 작업은 직렬로 실행했고 임시 앱 삭제·사용한 Simulator 종료·잔여 빌드/테스트 프로세스 없음을 확인했다.
- 당시 실제 iPhone 설치·Siri 음성 호출·알림 권한/실제 전달·백그라운드 갱신·구매/복원/만료·Release/배포 서명은 미검증이었고 StoreKit·개인 동기화도 미구현이었다. 위 결과는 새 달력·Plus·동기화 수정 전 snapshot에만 해당한다.

### 새 달력·Plus·동기화 후속 검증

- Linux Foundation 검사 **32/32**를 통과했다. 기존 기록의 ID·완료 상태를 유지하는 schema 1→2 읽기, 만료 전후 무료 기능·추가 알림 경계, 단계 완료·요약 중지, 종 시간 경계와 겹침 거절, 복원 전 원본 백업·오래된 미리보기 거절을 포함한다. SwiftUI·StoreKit·CloudKit 실통신 검사는 아니다.
- planner-v8에서 iOS SDK 컴파일과 일반 단위 **33/33**을 통과했다. 이때 로컬 StoreKit 카탈로그 설정은 실패했으며 UI는 중단됐다. planner-v9에서는 기본 준비·최대 글자 UI **2/2**를 통과해 날짜별 완료·재실행 보존·달력 취소·설정 저장을 실행했다. 이후 알림 권한 요청 조건과 테스트 구동을 보완했으므로 이 결과를 최종 전체 suite 재실행으로 합산하지 않는다.
- 최종 planner-v13은 입력 archive·manifest 및 실행 전후 **62개 파일 SHA**를 대조했다. iPhone 17 / iOS 27 Simulator에서 직렬 SDK Debug 빌드 **exit 0**, 로컬 StoreKit lifecycle **1/1, 10.454초, exit 0**, 새 달력·입력·설정·Plus·백업 내보내기 UI **1/1, 183.813초, exit 0**을 각각 한 번 실행해 통과했다. 이미 통과한 단위·기본·최대 글자 검사는 반복하지 않았다.
- 로컬 구독 검사는 실제 SKTestSession 상품 조회·검증된 구매, 자동 갱신 중지 후 가속된 자연 만료, 외부 연간 구매의 수동 새로고침 없는 반영, `AppStore.sync()` 복원, 환불의 수동 새로고침 없는 반영을 확인했다. 앞선 강제 만료와 시스템 파일 선택기 취소 검사 실패 로그도 보존했다. 테스트 구동을 수정했으며 통과를 위해 앱의 권한 판정을 완화하지 않았다. UI에서는 로컬 상품 가격을 표시하고 구매 버튼을 누르지 않았다. 운영 상품·실제 결제 검증이 아니다.
- 새 날짜 달력·직접 입력·마감 단계의 실제 제목/날짜 필드·설정·Plus 상품 카드·시스템 내보내기 화면을 캡처해 검토했다. Plus 구매 버튼 아래의 복원·약관 영역은 이번 캡처 범위 밖이다. 큰 글자의 날짜 목록과 일부 하단 동작은 스크롤이 필요하고, iOS 27 반투명 고정 헤더·탭 바 뒤로 내용이 지나가는 화면도 있다. 화면 전체가 언제나 가림 없이 보인다고 주장하지 않는다.
- 준비 위젯은 **원본 view body를 유지한 컴포넌트 호스트**에서 small 170×170 / medium 362×170을 각각 렌더링했다. 활성·개인 표시 켜짐에서는 1/3 완료와 세 항목이 보이고, 만료·개인 표시 꺼짐에서는 개인 제목·완료 수를 숨기고 안내를 온전히 표시함을 확인했다. SpringBoard 설치·TimelineProvider 실행·실제 갱신 및 App Group 서명 검증은 아니다.
- v13 근거는 Mac `.amp/in/artifacts/planner-v13/`의 두 xcresult·로그·종료 코드·SHA·캡처 매핑에 보존했다. Linux에는 검토용 캡처·요약·로그 archive(SHA-256 `91c21b88f3910b6c29a2840c283beb850c6e761adb83dffe1da6fbba519f3360`)를 보관했다. 임시 호스트를 제거하고 Simulator 종료·잔여 빌드/테스트 작업 없음을 확인했다. 실제 CloudKit 쓰기·실물 Siri/알림 전달·현재 소스의 Release/서명/실물 설치·전체 온보딩 suite 재실행은 하지 않았다. 검증 후 변경은 이 문서의 결과 기록뿐이다.

## Mac에서 빌드·테스트

Xcode와 iOS simulator runtime, XcodeGen **2.46.0**이 필요하다. 소스의 기준은 `project.yml`이며 `.xcodeproj`는 생성한다.

로컬 자동 검사(저장소 루트에서 실행):

```sh
bash ios/test-local.sh
# 특정 iPhone Simulator를 선택하려면:
SIMULATOR_UDID=기기_UUID bash ios/test-local.sh
```

설치된 첫 iPhone Simulator를 자동 선택하고 프로젝트 생성 → 기본 scheme의 Debug XCTest/XCUITest → 별도 로컬 StoreKit scheme 검사를 순서대로 실행한다. 실제 NEIS 대신 기존 DEBUG fixture를 쓰는 UI 테스트이며, 실물 Siri 검증은 아니다. 로그·xcresult·화면 attachment는 매번 새 `ios/build/local-test.XXXXXX/` 폴더에 남긴다. 테스트 실패의 종료 코드를 보존하고, 화면 내보내기 실패가 테스트 결과를 성공으로 바꾸지는 않는다. Linux에서는 Mac이 필요하다고 안내하고 종료한다. 스크립트 문법과 도구 대체물을 사용한 성공·기본 검사 실패·StoreKit 실패 전달 분기를 검사했다. 이 스크립트 전체를 Mac에서 실행한 기록은 없으며 위 snapshot 검증은 각 scheme을 직접 실행한 결과다.

수동 빌드·실행은 다음 명령을 사용한다:

```sh
xcodegen generate --spec ios/project.yml --project ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/SchoolToday.xcodeproj -scheme SchoolToday \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

# 설치된 iPhone simulator의 UUID로 교체
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/SchoolToday.xcodeproj -scheme SchoolToday \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ios/build -resultBundlePath ios/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Xcode에서 `ios/SchoolToday.xcodeproj`를 열어 동일한 scheme을 실행할 수 있다. XCTest는 HTTPS 주소/쿼리 인코딩/학과 구분/설정 저장/API payload/KST 날짜를 검증한다. XCUITest는 환영 화면→서버 자동 연결→학교·학급 선택→단계별 Siri 안내→홈→시간표·급식·설정, 중단/뒤로/건너뛰기/재실행/초기화와 빈 결과·실패·운영 서버 미설정을 검증하며 화면 attachment를 남긴다.

### Linux에서 데이터·저장 상태 검사

```sh
bash ios/test-foundation.sh
# swiftc가 PATH에 없다면:
SWIFTC=/절대/경로/swiftc bash ios/test-foundation.sh
```

실제 모델·API·저장/조회 상태 코드와 기존 XCTest 메서드를 임시 폴더에서 컴파일·실행한다. `FoundationNetworking`을 추가하고 관찰 기능·연결 감시·위젯 갱신·OS 알림 서비스를 대체한다. App Intent 테스트는 제외하며 SwiftUI·iOS SDK 빌드·Siri·WidgetKit·실제 알림 전달·실제 네트워크 감시를 검증하지 않는다. 생성 파일은 저장소 로컬 exclude로 제외된 `.amp/in/`에만 두고 종료 시 삭제한다. Mac 검사를 대신하지 않으며 이 명령으로 Mac runner를 시작하지 않는다.

### 가져온 소스로 직접 확인할 항목

소스 압축본은 새 폴더에 풀어 사용한다. 기존 checkout의 변경분을 덮어쓰지 않는다. 앱 기본 실행은 고정 운영 API를 사용하므로 iOS 앱 확인에 NEIS 키나 로컬 Next.js 서버가 필요하지 않다. 서버의 새 헤더·휴업일 요약 변경은 2026-10-15 운영에 배포했으며, 앱은 기존 서버와도 호환된다.

2026-10-17 운영 백엔드를 `feat/mobile-release-readiness`의 [72eb45a](https://github.com/deploy103/siri-school-timetable/commit/72eb45a942c05c91718115e060eb13d1c37ab521)로 갱신했다. 이전 [d42a93e](https://github.com/deploy103/siri-school-timetable/commit/d42a93ef261f2eebcdeb93196c847b91e198d982) 배포의 환경 파일과 롤백 이미지를 유지하고 해당 Compose 서비스만 재생성했다. 컨테이너 `healthy`와 내부 ingress/공개 HTTPS의 `live`, 실제 7일 시간표·급식의 날짜순 응답, 8일 요청 거절, 기존 두 음성 API를 확인했다. 이는 새 iPhone 앱 설치나 실제 Siri 발화 검증이 아니다. 기본 Python urllib User-Agent는 Cloudflare 1010으로 차단됐으며 공개 검증은 정상 curl 클라이언트로 수행했다.

1. Xcode에서 `SchoolToday` scheme으로 실행하고 학교·학과·학급을 선택한다. 앱 종료·재실행 후 선택이 유지되는지 확인한다.
2. 시간표/급식을 조회하는 동안 탭을 바꾸고 돌아온다. 다시 조회할 수 있고 이전 요청의 결과가 새 결과를 덮지 않는지 확인한다. 취소는 연결 실패 안내를 띄우지 않는다.
3. 급식의 알레르기 번호 안내·영양/원산지 펼치기·공유 시트를 확인한다. 작은 화면과 큰 글자에서 아래 버튼까지 스크롤해 접근할 수 있는지 확인한다.
4. 소리내어 읽기 → 중지, 홈 화면으로 나가기, 다른 오디오/전화 중단을 확인한다. 단축어 점검은 시간표·급식 각각 실행하고 닫았다 다시 연다.
5. 서명 설치한 iPhone에서 단축어 앱의 직접 실행을 먼저 확인한 뒤 Siri 호출 문구를 확인한다. 실패 보고에는 iOS 버전·실제 발화·오류 화면과 자동 검사 로그/xcresult를 함께 남긴다.

UI tests의 `--ui-testing`은 DEBUG에서만 별도 UserDefaults와 URLProtocol fixture session 및 고정 fixture backend를 사용한다. 외부 네트워크에 연결하거나 사용자에게 주소를 입력받지 않는다. 앱 기본 실행이나 Release에는 이 fixture를 적용하지 않는다. 테스트 성공은 실제 NEIS/Siri 음성 인식/실물 iPhone 검증을 대신하지 않는다.

PR의 Quality workflow는 macOS에서 같은 네이티브 테스트와 서명 없는 iPhone SDK Release 빌드를 실행한다. XcodeGen 버전과 다운로드 SHA-256을 고정하며 테스트 결과 bundle을 보관한다. Apple 계정·서명·배포를 자동으로 처리하지 않는다.

한국어 전용 앱의 프로젝트 개발 언어와 번들 기본/지원 언어는 `ko`이다. Siri 호출 문구는 `AppShortcuts.xcstrings`에도 선언한다. 기본 언어 선언이 없던 빌드에서는 SSU archive에 실패했으며, `ko` 선언 후 기존 두 문구의 학습과 압축 산출물 생성을 Mac에서 확인했다. 현재는 두 기능에 각각 짧은 문구와 기존 문구를 제공한다. 빌드 산출물만으로 실제 Siri 음성 호출 성공을 주장하지 않는다.

## 실제 백엔드 연결

앱은 하나의 운영 서버를 사용하는 제품이며 Debug/Release 모두 주소 입력·서버 선택 화면을 제공하지 않는다. 기본 빌드 설정은 `SCHOOL_API_BASE_URL=https://time.mvtp.cloud`이며 앱과 Siri가 같은 주소를 사용한다. 이 주소는 기존 교사용 설정 문서에서 찾았고 2026-10-09 공개 API에서 live health, 학교·학급 검색, 시간표·급식과 두 음성 응답을 확인했다. 이는 PV1 Docker 내부 상태나 실물 iPhone 실행을 확인한 것은 아니다. 운영 주소가 바뀌면 개발자가 빌드 설정을 갱신한다.

첫 실행의 환영 화면에서는 연결을 시작하지 않으며 ‘시작하기’를 누른 뒤 자동으로 연결한다. 사용자는 서버 주소 대신 학교·학과·학급만 선택한다. 이전 Debug 빌드에서 저장한 서버 override도 사용하지 않는다. 설정 초기화는 학교 선택과 온보딩 완료 기록만 삭제하고 고정 backend를 유지한다. 이 주소는 비밀이 아니다. 임시 터널 주소를 출시 기본값으로 박아 넣지 않는다. 서버가 mock이면 화면과 Siri 응답 모두 예제임을 알린다. NEIS 키는 서버의 `NEIS_API_KEY`에만 둔다.

기기의 학교·학급 선택은 UserDefaults에 저장하며 실제 서버 변경/초기화 시 삭제한다. 주소 끝 `/`, 호스트 대소문자, HTTPS 기본 포트 `443` 표기 차이는 같은 서버로 취급해 기존 선택과 온보딩 완료 기록을 유지한다. 다른 호스트·포트의 연결 확인에 성공했을 때만 서버 변경을 반영하며, 연결 실패는 기존 설정을 지우지 않는다. 대시보드는 최근 받은 한 주의 자료를 저장한다. 앱 복귀·네트워크 복구 시 재조회하며 KST 날짜는 1분 간격으로 확인한다. API 요청 제한 시간은 20초다. 앱 안에서 학교를 바꾸면 App Intent도 변경된 설정을 읽는다.

음성 API의 성공 응답은 `X-School-Data-Mode: live|mock`을 제공한다. 앱은 이 응답으로 예제 여부를 판단하므로 새 서버에서는 음성 조회 한 번만 필요하다. 응답 형식은 기존 plain text를 유지해 이전 앱·웹 단축어와 호환하며, 예제 안내는 앱에서 붙인다. 헤더가 없는 구형 서버는 음성 조회 후 `/api/health`로 확인한다. 알 수 없는 출처·빈 응답·잘못된 UTF-8·HTML/JSON 응답은 음성 결과로 반환하지 않는다. HTTP 오류의 plain-text 안내는 유지하되 HTML 오류 페이지와 빈 오류 본문은 한국어 재시도 안내로 바꾼다.

학교·학급·시간표·급식·연결 확인의 JSON 응답은 비어 있거나 깨졌거나 필수 필드가 없으면 한국어 재시도 오류를 반환한다. 정상적인 빈 목록은 오류가 아니다. 시간표는 서버와 같은 1~20교시·교시당 한 행 조건을 확인해 비정상 교시나 중복 행이 화면 식별자·누락 교시 계산에 들어가지 않게 한다. HTTP 오류의 서버 안내와 네트워크 취소는 JSON 형식 오류로 바꾸지 않는다.

## 시간표·급식에서 바로 사용하기

- 시간표는 앞부분뿐 아니라 중간에 누락된 교시도 안내한다. 누락은 NEIS에 자료가 없다는 뜻이며 실제로 수업이 없다고 단정하지 않는다.
- 급식의 음식명과 원래 알레르기 번호를 유지하면서 번호를 성분명으로 풀어 표시한다. 번호 목록은 [NEIS 급식식단정보의 공식 19종 목록](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN17320190722180924242823&infSeq=2)을 따른다. `알레르기 번호 안내`에서 전체 목록을 볼 수 있다. 음식 이름만 보고 성분을 추측하거나 표기가 없는 메뉴를 안전하다고 판정하지 않는다.
- 학교가 제공한 영양·원산지 정보가 있으면 해당 식사 카드에서 펼쳐 볼 수 있다. 필드가 없거나 비어 있으면 항목을 표시하지 않는다.
- `시간표 공유`와 `급식 공유`는 iOS 공유 시트를 연다. 학교·학급·자료 날짜와 교시/식사 순서를 포함한다. 공유 텍스트는 알레르기 번호와 선택 수업의 후보를 보존하며, Mock이면 예제임을 표시한다. 공유는 사용자가 공유 시트에서 대상을 고른 뒤 진행한다.
- `소리내어 읽기`는 Siri와 같은 음성 API 결과를 기기의 한국어 합성 음성으로 재생한다. 준비 중 취소와 재생 중 중지를 제공한다. 화면 이탈·앱 비활성화·오디오 중단 시 취소한다. 음성 API는 알레르기 번호를 생략하므로 식단 화면과 학교 안내를 확인해야 한다. 앱 내부 재생은 실제 Siri 인식/단축어 등록 검증이 아니다.
- 화면에는 마지막 성공한 조회 시각을 표시한다. 실패·날짜 변경 시 이전 조회 시각을 지우고, 서버 자료 날짜가 현재 KST 날짜와 다르면 오류를 안내하며 자료·공유·읽기를 노출하지 않는다.

운영 API에서 확인한 반복 `토요휴업일` 항목은 음성에서 한 문장으로 요약한다. 모든 항목이 명시적으로 `토요휴업일`이고 선택 수업이 아닐 때만 적용한다. 토요일이라는 이유로 수업을 숨기거나 빈 데이터를 휴업으로 단정하지 않는다. JSON·화면·공유의 원래 교시 자료는 유지한다.

이 기능의 XCTest/XCUITest 시나리오는 알레르기 표기, 공유 순서, 선택 수업, 누락 교시, 영양/원산지 펼치기, 음성 요청 실패, 잘못된 자료 날짜를 포함한다. 2026-10-10 Linux에서는 Swift 문법 검사와 Foundation 기반 테스트 10개를 실행했다. FoundationNetworking을 사용하는 임시 사본과 저장 기능만 가진 Combine 대체 래퍼로 데이터/요청 상태를 검사했으며, **iOS SDK 빌드·SwiftUI 렌더링·실제 오디오·추가한 XCUITest는 아직 실행하지 못했다.** Mac에서 위 빌드·테스트와 작은 화면/Dynamic Type/VoiceOver 및 실제 음성 중단을 확인해야 한다.

## 단축어 찾기·추가

첫 화면은 **반가워요! → 내 학교 찾기**다. 예제 카드와 진행률 표시는 없고, 한 화면에서 한 가지를 선택한다. 중학교는 **학년 → 반**, 일반고는 **학교 유형 → 학년 → 반**, 특성화고는 **학교 유형 → 학년 → 학과 → 반**으로 진행한다. 실제 학급 자료의 학과 식별자는 조회에 보존하되 일반고 화면에는 표시하지 않는다. 같은 학년·반 번호가 여러 학과에 있으면 임의로 고르지 않고 학과 선택을 안내한다. 이전 화면으로 돌아가도 답을 유지하고, 학년·학과를 바꾸면 그에 의존하는 선택만 비운다.

정상 응답에 학급이 하나도 없으면 ‘학급 다시 불러오기’를 제공한다. 빈 자료로 다음 단계에 진행시키지 않으며 같은 화면에서 재조회하거나 뒤로 돌아가 학교를 바꿀 수 있다. DEBUG의 `--empty-first-classes`는 첫 조회만 비워 이 복구 경로를 재현한다. 빈 자료→재조회→학급 저장의 UI 테스트를 추가했지만 아직 iOS에서 실행하지 않았다.

A+C 혼합안은 밝은 배경·짧은 행동 문구에 남색 환영 카드와 학교·음성 파형 일러스트를 더한다. 일러스트는 장식이며 시스템 안내 화면이 아니다. 접근성 글자 크기에서는 장식 그림·학교 유형 아이콘을 숨겨 글을 위한 공간을 확보하고, VoiceOver에서는 학교 유형의 설명도 읽는다. 홈·시간표·급식 화면의 디자인은 이 단계에서 바꾸지 않는다.

Siri 안내는 **켜기 → 부르기 → 시간표 호출 이름 정하기 → 단축어에서 실행/저장 → 직접 불러보기** 순서다. 기본값은 ‘오늘의 학교 시간표 알려줘’이며 자유롭게 바꿀 수 있다. 급식 이름 설정은 뒤에서 선택한다. 원하는 이름은 기기에 저장하지만 그 자체로 Siri에 등록되지는 않는다. 개인 단축어 만들기·이름 변경·붙여넣기를 각각 안내하고, 복사는 명시적으로 버튼을 눌렀을 때만 한다. ‘저장했어요’는 사용자의 확인이며 앱 복귀나 실행 성공을 자동 판정하지 않는다. 기본 App Shortcuts 문구는 그대로 유지한다.

단축어 앱에 이미 같은 이름으로 저장한 사용자는 호출 이름 화면의 ‘이미 이 이름으로 저장했어요’를 눌러 만들기 안내를 건너뛰고 직접 실행/호출 단계로 갈 수 있다. 빈 이름·다른 기능과 중복된 이름은 허용하지 않는다. 이 선택도 사용자의 확인이며 자동 탐지나 실행 성공 기록이 아니다. 이름을 바꾸면 기존 단축어 앱의 이름도 직접 맞춰야 한다.

Siri는 나중에 설정해도 된다. 완료/건너뛰기 기록을 유지하고 도움말·설정에서 안내를 다시 열 수 있다. 사진 출처는 화면 아래 작은 글씨로, 문제 해결은 별도 도움말로 둔다. 환영 문구는 0.35초 안에 나타나며 시작 버튼을 기다리게 하지 않는다. 다음/이전에는 짧은 전환을 사용하고 Reduce Motion에서는 이동을 없앤다. 큰 글자나 키보드 표시 중에는 하단 버튼을 스크롤 내용에 넣어 화면을 가리지 않는다. 기존 학교 설정과 온보딩 완료 기록은 초기화하지 않는다.

중·고등학생용 문구는 **짧은 제목 + 한 줄 행동 + 실제 캡처**를 기본으로 한다. 예제 자료, 알레르기 위험, 자료 누락과 실제 Siri 검증 여부는 짧게라도 유지한다. 호출 이름 입력 중에는 긴 질문 대신 상단 바에 ‘호출 이름’을 표시하고, 입력을 마치면 원래 질문으로 돌아온다. 사진 정보 링크는 작은 글씨를 유지하면서 터치 영역을 최소 44pt로 넓혔다.

2026-10-13 Mac 검증에서 전체 검사 snapshot v10은 단위 16개·UI 13개 **29/29 통과**, 서명 없는 iPhone SDK Release 빌드도 통과했다. 이 버전에서 다크 모드와 실제 시스템 ‘동작 줄이기’ 켜기/복원도 확인했다. 이후 사진 정보 터치 영역과 작은 화면의 이름 입력 레이아웃을 보완했다. 최종 앱 소스 snapshot v13은 44개 파일 SHA를 대조했고, iPhone SE / iOS 27의 최대 글자 UI·기본 온보딩 **2/2**, 별도 키보드 검사 **1/1**이 통과했다. 긴 기본 문구와 짧은 사용자 문구 모두 입력창 전체가 키보드 위에 보이는 원본 캡처를 직접 확인했다. 이 기록은 서로 다른 snapshot의 결과를 최종 전체 검사로 합산하지 않는다.

사용자 요청으로 Mac 작업을 중단했다. v13 iPhone 17 검사 최초 시도는 테스트 러너 시작 실패였고, 재시도는 취소했으므로 통과로 기록하지 않는다. v13의 사진 정보 링크 실측/모서리 터치·다크 모드 재검사·Release/서명 빌드는 완료하지 않았다. 앞선 이름 포커스 검사에 발생한 `Invalid frame dimension` 경고 원인도 미확정이다. 이 검증 기록은 A+C 적용 전 snapshot에 한정한다.

2026-10-15 A+C 적용은 Linux에서만 작업했고 Mac runner를 재사용하지 않았다. 실제 `Models.swift`와 기존 XCTest의 메서드를 사용하는 Foundation 검사 5개 및 전체 Swift 문법 검사를 통과했다. URL 검사는 한국어·공백·기호를 포함한 이름을 하나의 `name` 매개변수로 유지하고 다른 입력·클립보드 매개변수를 넣지 않는지 확인한다. 저장 확인 전후 실행 버튼 구분은 기존 UI 테스트에 추가했으나 실행하지 못했다. **현재 A+C 수정본의 iOS SDK 빌드·실제 SwiftUI 화면·새 XCUITest·Siri 음성 실행은 미검증**이며 이전 snapshot의 결과를 현재 결과로 합산하지 않는다. 소스의 커밋·푸시와 운영 백엔드 배포는 iPhone 앱 빌드·설치·TestFlight 배포를 뜻하지 않는다. 사용자 요청으로 추가 테스트는 보류하며 현재 수정본은 실물 미설치다.

같은 날 예외처리 후속 점검에서 학교 정보가 없거나 읽히지 않는데 온보딩 완료 기록이 남는 문제를 재현했다. 이때만 완료 기록을 해제해 학교 재선택 후 안내를 건너뛰지 않게 하며, 정상 설정·사용자 호출 이름은 유지한다. 신규 회귀 테스트는 수정 전 실패했고 수정 후 기존 검사와 함께 **13/13 통과**했다. 실제 모델·API·저장 상태 코드와 XCTest 메서드를 Linux에서 실행하되 관찰 기능과 `NWPathMonitor`만 대체했다. 이는 SwiftUI/Combine 동작·실제 연결 감시·iOS 실행 검증이 아니다. 시간 초과·오프라인·취소 보존·잘못된 음성 응답 거절·이전 저장 형식 호환도 검사 범위에 포함한다.

추가 안정화에서는 잘못된 JSON 응답과 비정상 시간표의 회귀 테스트가 수정 전 실패하는 것을 확인했다. 수정 후에는 화면 데이터 상태 코드까지 포함해 Linux에서 실행 가능한 XCTest 메서드 **19/19 통과**를 확인했다. 잘못된 응답 이후 정상 조회 복구, 오래된 자료·확인 시각·공유 문구 제거, 취소 후 재시도, 성공·오류 응답의 도착 순서 뒤바뀜도 포함한다. 실제 App Intent 테스트와 XCUITest는 실행하지 않았고 관찰·연결 감시 대체 조건도 동일하다. 이전 13개와 합산한 수치가 아니다.

후속 업그레이드 점검에서는 동등한 서버 주소 표기 때문에 학교 선택이 지워지는 문제를 수정 전 회귀 테스트로 재현했다. 주소 정규화 후 기존 19개 메서드를 다시 실행해 **19/19 통과**했으며 실제 서버 변경과 연결 실패 시 설정 보존도 함께 검사했다. 실제 fixture/API의 빈 학급→재조회 복구도 별도 Linux 검사로 확인했다. 기존 단축어 재사용과 빈 학급 재시도의 XCUITest는 소스만 추가했으며 **새 화면 렌더링·iOS 실행은 미검증**이다. Mac runner는 사용하지 않았다.

Siri 설정 안내는 [Apple의 Siri 사용 가이드](https://support.apple.com/ko-kr/guide/iphone/iph83aad8922/ios)를 따른다. 설정 앱 → Siri 또는 Apple Intelligence 및 Siri → Siri 켜기(이전 iOS는 Siri에게 말하기/말하기 및 타이핑), 설정 검색, 음성 호출과 측면/홈 버튼 길게 누르기를 설명한다. 앱은 시스템 Siri 설정을 대신 켜거나 설정 완료/개인 단축어 추가 여부를 판정하지 않는다. 마지막 완료 화면도 학교 설정과 안내 완료만 뜻한다.

Apple `ShortcutsLink` 버튼으로 이 앱의 App Shortcuts 페이지를 연다. 시간표·급식을 바로 실행하거나 개인 단축어로 추가할 수 있다. 개인 단축어를 편집하는 단계에서는 일반 단축어 앱 열기 링크를 제공한다. App Shortcuts 자체는 앱 설치 시 시스템이 발견하므로 별도 수동 등록이나 임의 iCloud 공유 링크가 필요하지 않다. 개인 단축어 추가는 사용자가 단축어 앱에서 선택하며, 앱은 버튼을 눌렀다는 이유로 등록 완료를 표시하지 않는다.

부르기 안내와 실행 점검에는 측면(전원) 버튼 길게 누르기를 먼저 보여주고, 홈 버튼 기기 설명과 접어 둔 ‘시리야’ 설정 안내를 제공한다. 사용자가 개인 단축어 저장을 확인한 뒤에는 **저장한 단축어 실행**으로 [공식 실행 URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)을 연다. 기본 문구에는 개인 단축어 URL 대신 App Shortcuts 페이지를 제공한다. 앱을 열 수 없으면 공통 설치·수동 탐색 안내를 유지하고, 앱 복귀 시 열기 가능 여부를 다시 확인한다. 이는 직접 실행 경로를 줄이는 변경이며 Siri 인식 속도 개선이나 실제 실행 성공을 보장하지 않는다.

개인 단축어 실행·일반 단축어 앱 열기 버튼은 시스템의 URL 열기 거절 시 수동 실행 안내를 띄우고 열기 가능 여부를 다시 확인한다. Apple의 `ShortcutsLink`는 그대로 사용한다. [URL 열기 콜백](https://developer.apple.com/documentation/swiftui/openurlaction/callasfunction(_:completion:))의 성공은 외부 앱 안의 단축어 실행 성공이 아니다. 외부에서 단축어를 이름 변경·삭제한 경우 자동 판정하지 않으며 실행 점검에서 이름 확인·재설정을 안내한다. 새 알림의 실제 iOS 표시·외부 앱 전환은 아직 검증하지 못했다.

개인 단축어로 저장하는 단계는 [Apple의 앱 단축어 가이드](https://support.apple.com/ko-kr/guide/shortcuts/apd43295406d/ios)와 실제 한국어 화면을 따른다. iOS 27 Simulator에서 ‘오늘 시간표’ 길게 누르기 → ‘새로운 단축어’ → 생성한 개인 단축어 → ‘편집기’ → 이름 옆 화살표 → ‘이름 변경’ → 이름 입력 → 키보드의 체크(접근성 ‘완료’)를 확인했다. ‘학교 시간표’로 저장한 뒤 단축어 앱 재실행에서도 이름과 동작이 유지됐다. 버전에 따라 ‘새로운 단축어에서 사용’이나 편집 화면의 ‘완료’로 보일 수 있다. 이 검사는 실제 Siri 발화 성공을 뜻하지 않는다.

**앱 단축어**는 앱 이름을 포함한다. ‘시리야’로 Siri를 부른 다음 ‘오늘의 학교 시간표 알려줘’ 또는 ‘오늘의 학교 급식 알려줘’라고 말한다. 기존 ‘오늘의 학교 오늘 시간표 알려줘’, ‘오늘의 학교 오늘 급식 알려줘’도 유지한다. App Shortcuts의 문구 변형 매칭은 모든 자유 문장을 보장하는 기능이 아니다([Apple App Shortcuts 가이드](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)).

**개인 단축어**는 [저장한 이름으로 호출](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios)한다. 이름이 ‘학교 시간표’면 ‘시리야, 학교 시간표’라고 말한다. ‘오늘 학교 시간표’로 부르고 싶다면 [이름도 그렇게 변경](https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios)하도록 안내한다. 사용자가 보고한 웹 검색 전환은 아직 실기기에서 재현하지 못했으므로 원인을 확정하지 않는다. 앱에서는 단축어 앱의 직접 실행, 문구 확인, 이름 변경 순서로 확인하도록 안내한다.

자동 테스트는 온보딩 흐름과 완료 유지, 초기화 후 재안내 및 앱 내부 버튼을 검증한다. 실제 단축어 앱으로 전환·개인 단축어 추가·Siri 음성 실행은 서명 설치한 실제 iPhone에서 별도로 검증해야 한다.

### 실행이 안 될 때

홈·설정·온보딩의 **단축어 실행 점검**에서 다음 경계를 따로 확인한다.

1. 앱에서 시간표·급식 결과 확인: App Intent와 같은 음성 API를 사용한다. 시간 초과와 오프라인 오류는 재실행 방법을 설명한다. 성공은 단축어 등록이나 Siri 인식 성공을 뜻하지 않는다.
2. 단축어 앱에서 직접 실행: 앱을 열 수 없으면 무료 설치 링크와 수동 탐색 경로를 제공한다. `canOpenURL` 실패만으로 미설치를 단정하지 않는다.
3. 버튼으로 Siri 호출 후 앱 문구 확인: 음성 호출 설정 문제와 단축어 실행 문제를 구분한다. 개인 단축어는 저장한 이름으로 호출한다.

실행 점검의 Siri 문구는 확인한 기능에 맞춘다. ‘급식 결과 확인’을 누른 뒤에는 급식 호출 문구를 표시하며, 시간표 확인으로 바꾸면 시간표 문구로 돌아간다. 기존 실패·재시도 UI 테스트에 두 문구 확인을 추가했지만 아직 iOS에서 실행하지 않았다.

두 App Intent는 조회 성공 시 음성 대화뿐 아니라 문자열 결과와 화면 결과도 반환한다. 개인 단축어에서 결과를 다음 동작에 전달할 수 있다. 등록된 자료가 없는 날은 정상 안내 결과이며, 학교 미설정·통신 실패는 오류로 구분해 다음 동작이 오류 안내를 학교 자료로 처리하지 않게 한다. `SchoolError`는 Apple의 `CustomLocalizedStringResourceConvertible`을 제공해 Siri 프로세스에도 한국어 오류 설명을 전달한다. 실제 Siri가 이를 어떻게 표시·발화하는지는 실물 검증이 필요하다.

이 구분은 [Home Assistant의 조회 App Intent](https://github.com/home-assistant/iOS/blob/master/Sources/Extensions/AppIntents/EntityState/GetEntityStateAppIntent.swift)와 [단축어 오류 구현](https://github.com/home-assistant/iOS/blob/master/Sources/Shared/Intents/AppIntent/ShortcutAppIntentError.swift), [Apple의 프로세스 간 지역화 설명](https://developer.apple.com/documentation/foundation/customlocalizedstringresourceconvertible)을 참고했다. 학교 앱 [오늘 뭐임](https://apps.apple.com/kr/app/id1629567018)은 Siri·위젯·영양/알레르기 정보를 제공한다고 공개 설명하지만, 비공개 내부 구현까지 확인한 것은 아니다.

2026-10-10 Linux 검사에서 Foundation 기반 XCTest 13개와 서버/웹 테스트 169개, 린트·타입 검사·프로덕션 빌드가 통과했다. 음성 테스트는 신규/구형 서버 × 실제/예제 × 시간표/급식, 잘못된 본문·출처, 한국어 서버 오류 보존, 명시적 휴업일과 일반 수업의 구분을 포함한다. 취소 회귀 테스트는 변경 전에 시간표·급식 모두 `loading`이 남아 실패했고, 수정 후에는 취소와 재시도가 통과했다. 음성 회귀 테스트도 변경 전 `SchoolAPI`/음성 생성 코드에서 실패했다. Foundation 기반 앱 API 코드로 운영 서버의 시간표·급식 조회도 확인했다. 이는 iOS SDK의 App Intent 실행·Siri 음성·SwiftUI 렌더링 검증을 대신하지 않는다.

Siri 설정·호출 안내는 **Apple이 공개한 실제 설정 화면 캡처**를 사용한다. 설정 안내용 생성형 그림은 제거했다. `SiriSettingsGuide`는 한국어 iOS 27 Siri 켜기 화면, `SiriActivationGuide`는 한국어 iOS 27 요청(음성 호출/측면 버튼) 설정 화면이다. `AppShortcutsGuide`는 **앱을 설치한 iPhone 17 / iOS 27 Simulator의 실제 단축어 앱**에서 촬영한 한국어 ‘오늘의 학교’ 페이지다. ‘오늘 시간표’와 ‘오늘 급식’이 모두 보이며, 일반 영어 예시를 대체했다. 하단 빈 여백만 잘랐고 메뉴·이름·아이콘은 바꾸지 않았다. 촬영 환경, 사용자의 iOS 버전과 메뉴 차이, Apple의 사용법 링크를 앱에 표시한다. 목록 표시가 실제 Siri 실행 성공을 뜻하지는 않는다.

Siri 설정 원본은 [Apple의 Siri 장애 안내](https://support.apple.com/ko-kr/105037)에 포함된 `ios-27-iphone-17-pro-settings-siri-turn_on.png`, `ios-27-iphone-17-pro-settings-siri-requests-hey-siri.png`다. 두 PNG는 변경 없이 앱에 포함한다. 단축어 원본은 2026-10-13 MacBook의 iPhone 17 / iOS 27 Simulator에서 실제 단축어 앱을 촬영했다. 앱 단축어 목록은 상단 1206×1120 픽셀을 사용한다. 추가한 `ShortcutMenuGuide`, `ShortcutEditorGuide`, `ShortcutRenameGuide`, `ShortcutNameGuide`는 각각 실제 생성 메뉴·편집기와 이름 화살표·이름 변경 메뉴·이름 입력란을 자른 이미지이며 원본 영역과 픽셀 일치를 확인했다. 편집기와 이름 변경은 별도 화면으로 안내해 누를 위치를 각각 보여준다. 이름 입력과 급식에 사용하는 시간표 사진은 예시임을 표시한다. 합성·생성 이미지나 메뉴 글자 변경은 하지 않았다. VoiceOver 설명과 탭 확대를 제공하고, 확대 화면은 전체 폭에서 시작하며 선택적으로 2배 확대할 수 있다. **실제 iPhone Siri 음성 호출은 아직 검증하지 않았다.**

## 실물 설치·출시의 별도 조건

- Simulator build는 서명된 `.ipa`가 아니므로 iPhone에 설치할 수 없다.
- 개인 기기 개발 설치는 Mac Xcode의 Apple 계정/Personal Team과 연결한 iPhone이 필요하다. [무료 Personal Team 프로비저닝은 7일 후 만료](https://developer.apple.com/support/compare-memberships)되며 다시 빌드·설치해야 한다. 이 만료를 앱 코드로 막거나 보안 검증을 우회하지 않는다. [TestFlight 빌드도 최대 90일](https://testflight.apple.com/)이므로 영구 설치 방식이 아니다.
- 무료 개발 설치를 준비하려면 사용자가 Xcode → Settings → Accounts에서 자신의 Apple 계정에 직접 로그인하고, 앱 타깃 Signing & Capabilities에서 Personal Team을 선택한다. 연결한 iPhone의 Developer Mode와 기기 신뢰를 확인한 뒤 실행 대상으로 선택한다. 비밀번호·인증번호는 채팅에 보내지 않는다. 개인 team/signing 설정은 소스에 커밋하지 않는다.
- TestFlight/App Store 배포에는 해당 권한을 가진 Apple Developer Program 팀, signing/provisioning 및 App Store Connect 설정이 필요하다. 가입·결제·배포는 자동으로 하지 않는다.
- 출시 전 운영 HTTPS/실제 NEIS, 앱 아이콘/브랜딩, 개인정보 처리방침과 App Store 개인정보 답변, 접근성/Dynamic Type/다크 모드, 실제 iPhone Siri 발화·잠금 상태 동작을 확인해야 한다.
- 현재 초기 네이티브 구현이다. 교사용 전용 화면은 없으며 위젯·오프라인 캐시의 소스 추가가 실물 설치·출시 완료를 뜻하지 않는다. App Group `group.com.deploy103.schooltoday`는 앱과 위젯 양쪽의 서명·프로비저닝에 필요하다. Personal Team의 지원 여부를 먼저 확인하고, 지원되지 않으면 서명 검증을 우회하지 않는다.

UserDefaults required-reason API 사용은 `PrivacyInfo.xcprivacy`에 앱 자신의 설정 접근 사유 CA92.1과 같은 App Group의 위젯 자료 공유 사유 1C8F.1로 선언했다. 광고·추적 SDK는 사용하지 않는다. 실제 운영 서버/호스팅의 로그·데이터 보관 방침을 검토한 뒤 개인정보 문구를 최종 확정해야 한다.
