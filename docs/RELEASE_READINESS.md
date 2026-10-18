# 모바일 출시 준비 기록

확인일: 2026-10-08 (Asia/Seoul). **현재 판정: 출시 보류.** 코드 검증과 실제 서비스·기기 검증을 구분한다.

## 제품과 배포 범위

출시 목표는 **네이티브 iOS 앱**이며 `ios/`에 SwiftUI iPhone 앱, App Intents/App Shortcuts Provider 및 XCTest/XCUITest 소스를 추가했다. Mac에서 빌드·시뮬레이터 테스트를 통과했지만 서명된 iPhone 설치 앱이나 App Store 출시 완료 상태가 아니다. 구체적 절차와 네이티브 미구현 범위는 `ios/README.md`를 따른다.

기존 Next.js 앱은 NEIS 백엔드와 별도 웹 클라이언트로 유지한다. Web Manifest, PNG 아이콘과 `/guide`의 홈 화면 추가 안내는 **웹 버전에만** 해당하며 네이티브 iOS 앱 설치나 App Store 출시 증거로 간주하지 않는다. 아래 자동 검증 기록은 별도 표시가 없는 한 기존 웹/백엔드 검증이다.

Service Worker나 오프라인 데이터 캐시는 제공하지 않는다. 당일 학교 정보를 어제 데이터로 잘못 안내하지 않도록 시간표·급식·Siri 실행에는 네트워크가 필요하다. 로그인·유료 AI·외부 가입 서비스는 앱 동작에 필요하지 않다.

Apple 공식 안내를 2026-10-08에 확인했다:

- [Safari 웹사이트를 홈 화면 앱으로 사용](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios): 공유 → 홈 화면에 추가 → 웹 앱으로 열기 → 추가. UI는 OS 버전에 따라 다르다.
- [단축어 사용 설명서](https://support.apple.com/guide/shortcuts/welcome/ios): Siri 실행, URL 요청, 공유와 가져오기 질문은 별도 단축어 기능이다. 홈 화면 설치 자체가 Siri 명령 등록을 뜻하지 않는다.

## 검증 방법

웹/백엔드는 `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm audit --prod`, production build와 Playwright E2E로 검증합니다. 네이티브 빌드 절차는 `ios/README.md`를 참고하세요.

자동화된 mock·시뮬레이터 검증은 실제 서비스 데이터, 서명된 iPhone 설치 또는 Siri 음성 실행의 증거가 아닙니다. 비공개 기기·계정 정보와 세션별 실행 기록은 Git 밖에서 관리합니다.

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
