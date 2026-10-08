# 모바일 출시 준비 기록

확인일: 2026-10-08 (Asia/Seoul). **현재 판정: 출시 보류.** 코드 검증과 실제 서비스·기기 검증을 구분한다.

## 제품과 배포 범위

이 저장소는 Next.js 모바일 웹앱이다. App Store/Play Store 네이티브 앱이나 App Intents 구현은 아니다. Web Manifest, 192/512px PNG 아이콘, 180px Apple 터치 아이콘과 standalone 표시 정보를 제공한다. iPhone Safari의 홈 화면 추가 및 Android Chrome의 설치/홈 화면 추가 안내는 `/guide`에 있다. 설치 메뉴 노출과 실제 설치는 브라우저·OS별 기기 확인이 필요하다.

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
- [ ] 실제 iPhone Safari에서 설치 → 앱 실행 → 설정 → 종료·재실행 → 설정 유지 확인. 브라우저와 홈 화면 앱 간 설정 공유를 가정하지 않는다.
- [ ] iPhone 단축어에서 시간표/급식 각각의 HTTPS URL → URL 콘텐츠 가져오기(GET) → 텍스트 말하기 구성 후 직접 실행과 Siri 호출 확인. 학교 변경 후 URL 교체, 빈 데이터와 네트워크 오류 확인.
- [ ] 실제 Android Chrome에서 설치/홈 화면 추가, 시간표·급식, 재실행 확인. Siri를 Android 기능으로 광고하지 않는다.
- [ ] 별도 GitHub 계정의 최종 코드 리뷰. 동일 계정이 작성한 PR을 그 계정으로 승인할 수 없으므로 자기 리뷰 댓글을 독립 승인으로 표시하지 않는다.

공유 iCloud 단축어 링크가 필요하면 Apple 기기에서 실제 단축어를 제작·검증한 뒤 발급한다. 임의 공유 링크를 만들거나, Windows VM의 브라우저 테스트를 Apple 기기 실행 증거로 사용하지 않는다. 공개 출시는 이 기록의 미완료 항목을 완료한 뒤 별도로 결정한다.
