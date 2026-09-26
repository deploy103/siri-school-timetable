# 사용 가이드 페이지와 안내 이미지

`/guide` 페이지(`src/app/guide/page.tsx`, `src/components/guide-page.tsx`)는 처음 온 학생이 학교 설정부터 Siri 단축어 연결까지 한 화면에서 따라 할 수 있도록 만든 별도 도움말 페이지다. 서비스 첫 화면(`src/app/page.tsx`)에도 설정이 비어 있을 때 자동으로 뜨는 짧은 온보딩 카드(`src/components/onboarding-guide.tsx`)가 있고, 시간표·급식 화면 헤더의 **가이드 다시 보기** 버튼으로 언제든 다시 볼 수 있다.

## 안내 이미지를 만든 방식

`public/guide/` 아래 6개 SVG는 실제 아이폰 화면 캡처나 iOS 시뮬레이터 캡처가 아니라 **직접 제작한 스키매틱(도식) 일러스트**다.

- 이 작업 환경에서는 실제 iPhone이나 iOS 시뮬레이터에 접근할 수 없어 진짜 화면 캡처를 만들 수 없었다.
- Apple 로고나 실제 단축어 앱 아이콘 등 상표가 있는 시각 요소는 쓰지 않았다. 대신 폰 프레임과 일반적인 도형(둥근 사각형, 원, 화살표, 강조 테두리)으로 같은 흐름을 표현했다.
- 내용(동작 이름, 순서, 화면 문구)은 `docs/RESEARCH.md`의 "2. Apple 단축어와 Siri" 절에서 이미 확인한 Apple 공식 Shortcuts User Guide 조사 결과와, 2026-09-26 웹 검색으로 재확인한 현재 iOS 단축어 앱 용어(URL, URL 콘텐츠 가져오기, 텍스트 말하기, Siri에 추가)를 근거로 했다.
- 각 SVG는 `<title>`/`<desc>`에 같은 내용을 텍스트로도 넣어 스크린리더에서도 읽힌다.

| 파일 | 보여주는 단계 |
| --- | --- |
| `step-1-open-shortcuts-app.svg` | 아이폰 홈 화면에서 단축어 앱 열기 |
| `step-2-new-shortcut-url.svg` | + 버튼으로 새 단축어 만들고 URL 붙여넣기 |
| `step-3-add-actions.svg` | URL 콘텐츠 가져오기 → 텍스트 말하기 동작 추가 |
| `step-4-name-with-phrase.svg` | 단축어 이름을 Siri 문구로 저장 |
| `step-5-run-with-siri.svg` | Siri에게 말해서 실행 |
| `troubleshoot-test-in-safari.svg` | Safari에서 음성 API 주소 직접 열어 테스트 |

## 실제 캡처로 교체하는 방법

나중에 실기기 캡처나 iOS 시뮬레이터 캡처로 바꾸고 싶다면:

1. 위 표의 **같은 파일명**으로 `public/guide/`에 저장한다(확장자를 `.png`나 `.webp`로 바꾼다면 `src/components/guide-page.tsx`의 `STEPS`/`GuideImage` 호출부에 있는 `src` 경로만 함께 바꾸면 된다).
2. 세로 방향(9:16 비율 권장), 가로 폭 640px 이상이면 `.guide-image-button`/라이트박스 레이아웃에서 깨지지 않는다.
3. 화살표·강조 박스가 필요하면 캡처 위에 별도로 그려 합성하거나, 기존 SVG의 화살표/강조 테두리 스타일(보라색 `#7657d6` 점선 원, 파란색 `#3157d5` 강조 테두리)을 참고해 톤을 맞춘다.
4. 각 단계 설명 문구(`title`/`summary`/`detail`)는 `src/components/guide-page.tsx`의 `STEPS` 배열에서 관리하므로 이미지만 바꾸면 텍스트는 그대로 재사용된다.
5. 실제 기기에서 검증한 뒤 배포하는 것을 권장한다. iOS 버전에 따라 버튼 이름이나 배치가 조금 다를 수 있어 페이지에도 "버전에 따라 버튼 이름이 조금 다를 수 있음" 안내를 넣어 두었다.

## 참고 출처

- `docs/RESEARCH.md` §2 (Apple 공식 Shortcuts User Guide 조사, 2026-09-22)
- Apple Support: [Use Siri to run shortcuts with your voice](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios)
- Apple Support: [Request your first API](https://support.apple.com/guide/shortcuts/request-your-first-api-apd58d46713f/ios)
- Apple Support: [About get actions in Shortcuts](https://support.apple.com/guide/shortcuts/get-actions-apd5c2bd430f/ios)
