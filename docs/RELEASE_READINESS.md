# 모바일 출시 준비 기록

확인일: 2026-10-08 (Asia/Seoul). **현재 판정: 출시 보류.** 코드 검증과 실제 서비스·기기 검증을 구분한다.

## 제품과 배포 범위

출시 목표는 **네이티브 iOS 앱**이며 `ios/`에 SwiftUI iPhone 앱, App Intents/App Shortcuts Provider 및 XCTest/XCUITest 소스를 추가했다. Mac에서 빌드·시뮬레이터 테스트를 통과했지만 서명된 iPhone 설치 앱이나 App Store 출시 완료 상태가 아니다. 구체적 절차와 네이티브 미구현 범위는 `ios/README.md`를 따른다.

기존 Next.js 앱은 NEIS 백엔드와 별도 웹 클라이언트로 유지한다. Web Manifest, PNG 아이콘과 `/guide`의 홈 화면 추가 안내는 **웹 버전에만** 해당하며 네이티브 iOS 앱 설치나 App Store 출시 증거로 간주하지 않는다. 아래 자동 검증 기록은 별도 표시가 없는 한 기존 웹/백엔드 검증이다.

Service Worker나 오프라인 데이터 캐시는 제공하지 않는다. 당일 학교 정보를 어제 데이터로 잘못 안내하지 않도록 시간표·급식·Siri 실행에는 네트워크가 필요하다. 로그인·유료 AI·외부 가입 서비스는 앱 동작에 필요하지 않다.

Apple 공식 안내를 2026-10-08에 확인했다:

- [Safari 웹사이트를 홈 화면 앱으로 사용](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios): 공유 → 홈 화면에 추가 → 웹 앱으로 열기 → 추가. UI는 OS 버전에 따라 다르다.
- [단축어 사용 설명서](https://support.apple.com/guide/shortcuts/welcome/ios): Siri 실행, URL 요청, 공유와 가져오기 질문은 별도 단축어 기능이다. 홈 화면 설치 자체가 Siri 명령 등록을 뜻하지 않는다.

## 이번에 확인하고 수정한 문제

- 학교 검색이 첫 100행에서 조용히 끝났다. 101번째 학교가 누락되는 테스트를 실패 상태로 확인하고, 기존 bounded 페이지 조회로 수정했다. 학급 조회도 전체 페이지를 사용한다. 불완전한 응답은 완전한 결과인 것처럼 반환하지 않는다.
- 저장소 접근을 차단하면 학교 설정·가이드·교사용 설정에서 예외가 발생할 수 있었다. 저장 실패 시 화면 내 설정은 유지하고 영구 저장이 되지 않았다는 안내를 표시한다. 손상된 JSON 제거 동작은 유지한다.
- 운영 CSP의 `upgrade-insecure-requests` 때문에 로컬 HTTP에서 WebKit이 JS/CSS 요청을 HTTPS로 바꾸고 TLS handshake 실패로 설정 복원 화면에 멈췄다. 상대 주소·same-origin 제한은 유지하고, 공개 HTTPS 강제는 proxy의 책임으로 문서화했다.
- 초기 `pnpm audit --prod`는 권고 9건(critical 1, high 3 등)을 보고했다. 이것이 이 앱의 모든 경로에서 실제 악용 가능함을 증명하지는 않는다. Next.js/ESLint 설정은 16.3.8, sharp는 0.35.5, source-map-js는 1.2.2로 갱신했고 재검사에서는 알려진 운영 의존성 취약점이 없었다.
- 학생 시간표·급식·교사용 시간표의 조회 생명주기를 통합했다. 새 요청·학교 변경·화면 종료 시 이전 요청을 취소하고, 늦게 도착한 이전 응답이나 오류가 최신 화면을 바꾸지 않도록 한다.
- 화면이 보이고 온라인일 때 30분 주기로 다시 조회하며 한국 날짜 변경은 1분 간격으로 확인한다. 앱 복귀 시 날짜/조회 경과/실패 상태를 확인하고 인터넷 재연결 시 다시 조회한다. 숨겨진 화면과 오프라인 상태에서는 주기적 네트워크 요청을 하지 않는다. 날짜가 바뀐 오프라인 화면은 어제 자료를 제거하고 연결 안내를 표시한다. 조회 중 자정을 넘긴 응답도 새 날짜로 재조회한다. 날짜 판단은 기기의 시계에 의존하며 즉시 자정 전환이나 잘못된 기기 시계의 보정까지 보장하지는 않는다.

## 자동 검증

### 네이티브 iOS

Mac의 Xcode 27.0(27A266a), iOS 27.0 시뮬레이터(24A434), XcodeGen 2.46.0으로 Debug/Release 시뮬레이터 빌드와 서명 없는 실제 iPhone SDK Release 빌드를 통과했다. iPhone 18 Pro 시뮬레이터에서 XCTest 7개와 XCUITest 4개를 통과했고 시작·시간표·급식·설정·빈 결과·오류 화면을 캡처해 확인했다. 학교/학과 선택과 설정 복원도 UI 테스트로 검증했다. `+`가 포함된 학급명은 실제 Swift 생성 URL을 Node URLSearchParams로 파싱해 값이 유지됨을 확인했다. 앱의 UIDeviceFamily는 `[1]`이며 Release에는 개발 서버 입력과 테스트 fixture가 없다.

최초 빌드에서는 App Intents 추출 성공에도 SSU archive 오류가 발생했다. 프로젝트의 개발 언어와 번들 기본/지원 언어를 한국어 `ko`로 명시한 독립 재빌드에서 시뮬레이터·실제 기기 SDK 모두 오류가 사라졌고, 두 한국어 문구의 학습과 `Metadata.appintents/nlu/nlu.lzfse` 생성 및 1개 locale 압축 완료를 확인했다. **이것은 Siri 실제 음성 인식·실행의 증거가 아니다.**

이후 `AppShortcuts.xcstrings` 추가본에서도 시뮬레이터·기기 SDK Release 빌드와 7+4 테스트를 재검증했다. 문구 validation과 한국어 압축이 성공했고 catalog 사용 시 `ko.lproj/nlu.appintents`를 생성한다. 설정의 아래 개인정보 문구와 초기화 버튼은 스크롤 후 전체가 보이는 캡처를 확인했고, 실제 버튼 조작·삭제 확인·재실행 후 삭제 유지도 통과했다.

Quality workflow에 macOS 네이티브 테스트 및 서명 없는 iPhone Release 빌드 job을 추가했다. XcodeGen 2.46.0 다운로드의 SHA-256을 검증하며 signing·배포·계정 생성은 하지 않는다. 로컬 Mac 검증과 GitHub CI 실행 결과는 구분한다.

### 웹/백엔드

`pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm audit --prod`, production build와 Playwright E2E를 검증한다. PR 및 main push의 `.github/workflows/quality.yml`은 같은 검증을 수행하며 배포·출판·자동 병합을 하지 않는다. 키 없이 명시적 mock 모드로 실행한다.

브라우저 대상은 iPhone 13 viewport의 WebKit, 390px Chromium, 768px 및 1440px Chromium이다. 설정 저장/복원, 학과 구분, 교사용 흐름, Siri URL, 저장소 차단 상태, 설치 가이드, manifest와 PNG 응답, 학생 시간표·급식의 오프라인 오류와 재연결 자동 복구를 확인한다. 조회 경쟁·한국 자정 경계·숨김/오프라인 상태는 fake clock과 지연 응답 단위 테스트로 확인한다. **WebKit 에뮬레이션은 실제 iPhone·Siri 음성 실행 검증이 아니다.**

Linux 로컬 검증에서는 관리자 권한 없이 Ubuntu 라이브러리를 로컬에 풀어 WebKit을 실행했다. 시스템 `ldconfig`에 로컬 라이브러리가 등록되지 않아 사전 host 검사만 건너뛰고 브라우저와 테스트는 실제로 실행했다. CI에서는 `playwright install --with-deps chromium webkit`으로 정상 시스템 의존성을 설치하며 host 검사를 우회하지 않는다.

## 출시 전 반드시 통과할 항목

- [ ] 서버 전용 `NEIS_API_KEY` 설정 후 `NEIS_MOCK_MODE=false`로 실제 학교 검색·학급·시간표·급식 및 음성 API 통합 검증. 익명 sample의 5행 제한이나 mock 성공을 실데이터 검증으로 대체하지 않는다.
- [ ] 운영/비공개 시험용 HTTPS 주소와 TLS 인증서 확인. HTTP→HTTPS 리디렉션 및 HSTS 설정, API 키가 번들·응답·로그에 없는지 확인.
- [ ] proxy가 외부 `X-Forwarded-For`를 **덮어쓰는** 환경에서만 `TRUST_PROXY_HEADERS=true`. Nginx 단일 proxy라면 `proxy_set_header X-Forwarded-For $remote_addr;`로 설정한다. append-only 구성을 신뢰하지 않는다. 기본 공용 rate limit 상태는 다중 사용자 운영에 적합하지 않다. 여러 replica는 공유 제한 계층이 필요하다.
- [ ] 네이티브 앱을 실제 iPhone에 서명해 설치 → 학교·학과·학급 설정 → 시간표/급식 → 종료·재실행 → 설정 유지·초기화 확인. 연결된 iPhone은 있으나 Mac에 유효한 signing identity와 Xcode Apple 계정이 없으며 Developer Mode도 미확인이다. 로그인·서명·기기 설치는 아직 수행하지 않았다.
- [ ] 네이티브 App Shortcuts의 시간표/급식 직접 실행과 한국어 Siri 호출, 학교 변경 후 설정 반영, 잠금 상태·빈 자료·네트워크 오류 확인. 시뮬레이터 fixture/API 성공이나 SSU 산출물 생성을 실제 Siri 성공으로 대체하지 않는다.
- [ ] iOS 17 최소 버전과 작은 iPhone, Dynamic Type·VoiceOver·다크 모드 검증; 운영 개인정보 처리방침·App Store 개인정보 답변·브랜딩 확정.
- [ ] App Store Connect/Developer Program 권한과 signing/provisioning 확인. 무료 Personal Team 개발 설치와 유료 멤버십이 필요한 App Store/TestFlight 배포를 구분하고 결제·공개 배포를 별도 승인 없이 하지 않는다.
- [ ] 별도 GitHub 계정의 최종 코드 리뷰. 동일 계정이 작성한 PR을 그 계정으로 승인할 수 없으므로 자기 리뷰 댓글을 독립 승인으로 표시하지 않는다.

기존 웹 클라이언트를 별도로 배포한다면 Safari/Android 홈 화면 설치와 URL 기반 단축어도 실제 기기로 검증한다. 네이티브 App Shortcuts는 수동 URL 단축어 구성이나 공유 iCloud 링크를 설치 조건으로 요구하지 않는다. Windows VM의 브라우저 테스트를 Apple 기기 실행 증거로 사용하지 않는다. 공개 출시는 위 미완료 항목을 완료한 뒤 별도로 결정한다.
