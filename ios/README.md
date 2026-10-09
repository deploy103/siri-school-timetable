# 오늘의 학교 — 네이티브 iOS 앱

SwiftUI iPhone 앱(iOS 17+)이다. 웹뷰/PWA 래퍼가 아니며 앱 타깃 안에 App Intents와 App Shortcuts Provider를 제공한다. 기존 Next.js 서버는 NEIS 키를 보관하는 백엔드로 재사용한다. 앱에는 키·결제·로그인 SDK가 없다.

## Mac에서 빌드·테스트

Xcode와 iOS simulator runtime, XcodeGen **2.46.0**이 필요하다. 소스의 기준은 `project.yml`이며 `.xcodeproj`는 생성한다.

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

UI tests의 `--ui-testing`은 DEBUG에서만 별도 UserDefaults와 URLProtocol fixture session 및 고정 fixture backend를 사용한다. 외부 네트워크에 연결하거나 사용자에게 주소를 입력받지 않는다. 앱 기본 실행이나 Release에는 이 fixture를 적용하지 않는다. 테스트 성공은 실제 NEIS/Siri 음성 인식/실물 iPhone 검증을 대신하지 않는다.

PR의 Quality workflow는 macOS에서 같은 네이티브 테스트와 서명 없는 iPhone SDK Release 빌드를 실행한다. XcodeGen 버전과 다운로드 SHA-256을 고정하며 테스트 결과 bundle을 보관한다. Apple 계정·서명·배포를 자동으로 처리하지 않는다.

한국어 전용 앱의 프로젝트 개발 언어와 번들 기본/지원 언어는 `ko`이다. Siri 호출 문구는 `AppShortcuts.xcstrings`에도 선언한다. 기본 언어 선언이 없던 빌드에서는 SSU archive에 실패했으며, `ko` 선언 후 기존 두 문구의 학습과 압축 산출물 생성을 Mac에서 확인했다. 현재는 두 기능에 각각 짧은 문구와 기존 문구를 제공한다. 빌드 산출물만으로 실제 Siri 음성 호출 성공을 주장하지 않는다.

## 실제 백엔드 연결

앱은 하나의 운영 서버를 사용하는 제품이며 Debug/Release 모두 주소 입력·서버 선택 화면을 제공하지 않는다. 기본 빌드 설정은 `SCHOOL_API_BASE_URL=https://time.mvtp.cloud`이며 앱과 Siri가 같은 주소를 사용한다. 이 주소는 기존 교사용 설정 문서에서 찾았고 2026-10-09 공개 API에서 live health, 학교·학급 검색, 시간표·급식과 두 음성 응답을 확인했다. 이는 PV1 Docker 내부 상태나 실물 iPhone 실행을 확인한 것은 아니다. 운영 주소가 바뀌면 개발자가 빌드 설정을 갱신한다.

첫 실행의 환영 화면에서는 연결을 시작하지 않으며 ‘시작하기’를 누른 뒤 자동으로 연결한다. 사용자는 서버 주소 대신 학교·학과·학급만 선택한다. 이전 Debug 빌드에서 저장한 서버 override도 사용하지 않는다. 설정 초기화는 학교 선택과 온보딩 완료 기록만 삭제하고 고정 backend를 유지한다. 이 주소는 비밀이 아니다. 임시 터널 주소를 출시 기본값으로 박아 넣지 않는다. 서버가 mock이면 화면과 Siri 응답 모두 예제임을 알린다. NEIS 키는 서버의 `NEIS_API_KEY`에만 둔다.

기기의 학교·학급 선택은 UserDefaults에 저장하며 서버 변경/초기화 시 삭제한다. 시간표/급식은 영구 캐시하지 않는다. 앱 복귀·네트워크 복구 시 재조회하며 KST 날짜는 1분 간격으로 확인한다. API 요청 제한 시간은 20초다. 앱 안에서 학교를 바꾸면 App Intent도 변경된 설정을 읽는다.

## 단축어 찾기·추가

첫 실행은 **환영 → 학교 선택 → 학급 선택 → Siri 켜기 → 음성/버튼으로 부르기 → 단축어 열기·추가 → 앱 호출 문구 → 개인 단축어 이름 → 학교 설정 완료 → 홈** 순서다. 각 단계는 개별 화면이며 하단의 다음 버튼으로 진행한다. 학교·학급은 선택해야 다음으로 이동하고, Siri 안내는 뒤로 이동하거나 초기 Siri 설정을 나중으로 미룰 수 있다. 완료 기록은 기기에 저장한다. 중간에 종료하면 환영 화면 후 저장된 학교의 안내부터 다시 시작하며 학교 초기화/변경 시 전체 흐름을 다시 진행한다. 홈의 도움말과 설정에서도 안내를 다시 열 수 있다. 설정 Form 대신 여백·네이비 텍스트·절제된 파란색·카드로 구성한다.

Siri 설정 안내는 [Apple의 Siri 사용 가이드](https://support.apple.com/ko-kr/guide/iphone/iph83aad8922/ios)를 따른다. 설정 앱 → Siri 또는 Apple Intelligence 및 Siri → Siri 켜기(이전 iOS는 Siri에게 말하기/말하기 및 타이핑), 설정 검색, 음성 호출과 측면/홈 버튼 길게 누르기를 설명한다. 앱은 시스템 Siri 설정을 대신 켜거나 설정 완료/개인 단축어 추가 여부를 판정하지 않는다. 마지막 완료 화면도 학교 설정과 안내 완료만 뜻한다.

Apple `ShortcutsLink` 버튼으로 이 앱의 App Shortcuts 페이지를 연다. 시간표·급식을 바로 실행하거나 개인 단축어로 추가할 수 있다. 각 기능의 `SiriTipView`와 한국어 문구 안내도 제공한다. App Shortcuts 자체는 앱 설치 시 시스템이 발견하므로 별도 수동 등록이나 임의 iCloud 공유 링크가 필요하지 않다. 개인 단축어 추가는 사용자가 단축어 앱에서 선택하며, 앱은 버튼을 눌렀다는 이유로 등록 완료를 표시하지 않는다.

**앱 단축어**는 앱 이름을 포함한다. ‘시리야’로 Siri를 부른 다음 ‘오늘의 학교 시간표 알려줘’ 또는 ‘오늘의 학교 급식 알려줘’라고 말한다. 기존 ‘오늘의 학교 오늘 시간표 알려줘’, ‘오늘의 학교 오늘 급식 알려줘’도 유지한다. App Shortcuts의 문구 변형 매칭은 모든 자유 문장을 보장하는 기능이 아니다([Apple App Shortcuts 가이드](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)).

**개인 단축어**는 [저장한 이름으로 호출](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios)한다. 이름이 ‘학교 시간표’면 ‘시리야, 학교 시간표’라고 말한다. ‘오늘 학교 시간표’로 부르고 싶다면 [이름도 그렇게 변경](https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios)하도록 안내한다. 사용자가 보고한 웹 검색 전환은 아직 실기기에서 재현하지 못했으므로 원인을 확정하지 않는다. 앱에서는 단축어 앱의 직접 실행, 문구 확인, 이름 변경 순서로 확인하도록 안내한다.

자동 테스트는 온보딩 흐름과 완료 유지, 초기화 후 재안내 및 앱 내부 버튼을 검증한다. 실제 단축어 앱으로 전환·개인 단축어 추가·Siri 음성 실행은 서명 설치한 실제 iPhone에서 별도로 검증해야 한다.

## 실물 설치·출시의 별도 조건

- Simulator build는 서명된 `.ipa`가 아니므로 iPhone에 설치할 수 없다.
- 개인 기기 개발 설치는 Mac Xcode의 Apple 계정/Personal Team과 연결한 iPhone이 필요하다. Apple의 무료 개발 서명에는 기간·기능 제약이 있다.
- 무료 개발 설치를 준비하려면 사용자가 Xcode → Settings → Accounts에서 자신의 Apple 계정에 직접 로그인하고, 앱 타깃 Signing & Capabilities에서 Personal Team을 선택한다. 연결한 iPhone의 Developer Mode와 기기 신뢰를 확인한 뒤 실행 대상으로 선택한다. 비밀번호·인증번호는 채팅에 보내지 않는다. 개인 team/signing 설정은 소스에 커밋하지 않는다.
- TestFlight/App Store 배포에는 해당 권한을 가진 Apple Developer Program 팀, signing/provisioning 및 App Store Connect 설정이 필요하다. 가입·결제·배포는 자동으로 하지 않는다.
- 출시 전 운영 HTTPS/실제 NEIS, 앱 아이콘/브랜딩, 개인정보 처리방침과 App Store 개인정보 답변, 접근성/Dynamic Type/다크 모드, 실제 iPhone Siri 발화·잠금 상태 동작을 확인해야 한다.
- 현재 초기 네이티브 구현이다. 교사용 전용 화면, 위젯 및 오프라인 기능은 아직 네이티브 앱에 없다. 웹 기능이 있다고 네이티브 구현 완료로 간주하지 않는다.

UserDefaults required-reason API 사용은 `PrivacyInfo.xcprivacy`에 앱 자신의 설정 접근 사유 CA92.1로 선언했다. 광고·추적 SDK는 사용하지 않는다. 실제 운영 서버/호스팅의 로그·데이터 보관 방침을 검토한 뒤 개인정보 문구를 최종 확정해야 한다.
