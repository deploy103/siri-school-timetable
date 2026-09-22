# Siri School Timetable

[![Next.js](https://img.shields.io/badge/Next.js-16-000000?logo=nextdotjs)](https://nextjs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Node.js-24_LTS-5FA04E?logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

전국 초·중·고등학교를 검색해 오늘 시간표를 확인하고, iPhone Siri 단축어로 바로 들을 수 있는 모바일 우선 웹 서비스입니다. 로그인과 데이터베이스 없이 학교·학년·반 설정을 브라우저에 저장합니다.

```text
학교 검색 → 학교·학년·반 저장 → 오늘 시간표 확인 → Siri 단축어 연결
```

> “시리야, 오늘 학교 시간표 뭐야?”
>
> “오늘 시간표는 1교시 자료구조, 2교시 영어, 3교시 체육입니다.”

## 기능

- 전국 초·중·고 및 지원되는 특수학교 검색(지역·주소·학교 유형 표시)
- 학교 종류에 따른 NEIS 시간표 데이터셋 자동 선택
- 서울 시간 기준 오늘 시간표, 교시 정렬 및 중복/비정상 행 정리
- `localStorage` 기반 학교·학년·반 복원과 언제든 설정 변경
- 브라우저 Web Speech API로 시간표 미리 듣기
- Siri 단축어용 UTF-8 `text/plain` API와 설정 안내
- 입력 검증, 타임아웃/제한적 재시도, 캐시, Rate Limit, 안전한 오류 응답
- API 키 없이도 개발·테스트 가능한 명시적 Mock 모드

## 기술 스택

Next.js App Router, React, Tailwind CSS, TypeScript strict mode, Zod, Vitest, Testing Library, Playwright, pnpm, Node.js 24 LTS, Docker Compose를 사용합니다. 별도 데이터베이스는 없습니다.

## 로컬 실행

요구 사항은 Node.js 24와 pnpm 12.4.2 이상입니다.

```bash
corepack enable
pnpm install
cp .env.example .env
pnpm dev
```

`http://localhost:3000`을 엽니다. 키 없이 실행하면 결정적인 Mock 학교/시간표를 사용하므로 전체 화면과 Siri 흐름을 테스트할 수 있습니다. 실제 데이터를 확인하려면 `.env`의 키를 설정합니다.

## 환경변수

```dotenv
NEIS_API_KEY=발급받은_키
NEIS_MOCK_MODE=false
TRUST_PROXY_HEADERS=false
```

- `NEIS_API_KEY`: [NEIS 교육정보 개방 포털](https://open.neis.go.kr/)에서 발급한다. 서버 전용이며 `NEXT_PUBLIC_` 접두사를 붙이지 않는다.
- `NEIS_MOCK_MODE=true`: 키가 있더라도 외부 호출 없이 Mock 응답을 사용한다.
- `TRUST_PROXY_HEADERS=true`: 전달 헤더를 덮어쓰는 신뢰 가능한 reverse proxy 뒤에서만 설정한다. 클라이언트 IP별 Rate Limit에 사용된다.
- 키가 비어 있으면 개발 가능성을 위해 자동으로 Mock 모드가 된다.

`.env`는 Git과 Docker build context에서 제외된다. 실제 키를 `.env.example`에 기록하지 않는다.

## 품질 검증

```bash
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm exec playwright install chromium
pnpm test:e2e
```

기본 테스트는 실제 NEIS에 접근하지 않는다. 유효한 키가 있을 때만 선택적 통합 검증을 실행한다.

```bash
NEIS_API_KEY=... pnpm test:integration
```

## Docker 실행

```bash
cp .env.example .env
# 실제 운영 데이터가 필요하면 .env에 NEIS_API_KEY를 입력한다.
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
curl -f http://localhost:3000/api/health
```

종료 명령은 `docker compose down`입니다. 이미지는 multi-stage standalone 빌드이고, 최종 컨테이너는 비루트·읽기 전용 파일 시스템으로 실행됩니다. API 키는 이미지가 아니라 컨테이너 실행 시 주입됩니다.

## Siri 설정

웹에서 학교 설정을 저장한 뒤 **Siri 설정**을 열고 URL을 복사한다. iPhone 단축어 앱에서 다음 세 동작을 순서대로 만든다.

```text
URL
→ URL 콘텐츠 가져오기 (GET)
→ 텍스트 말하기
```

단축어 이름은 `오늘 학교 시간표 뭐야`로 저장한다. 이후 “시리야, 오늘 학교 시간표 뭐야?”라고 말한다. 웹사이트가 단축어를 자동 설치하거나 Siri에 자동 등록하지는 않는다. 자세한 내용은 [docs/SIRI_SETUP.md](docs/SIRI_SETUP.md)를 참고한다.

## API

```text
GET /api/health
GET /api/schools?name=학교명
GET /api/timetable/today?officeCode=...&schoolCode=...&kind=...&grade=2&className=1
GET /api/voice/timetable?officeCode=...&schoolCode=...&kind=...&grade=2&className=1
```

학교·시간표 API는 JSON을 반환한다. 음성 API는 단축어가 그대로 말할 수 있는 `text/plain; charset=utf-8` 문장을 반환한다.

## 디렉터리 구조

```text
src/app/              화면, 전역 스타일, API Route Handler
src/components/       설정·시간표·Siri UI
src/lib/              NEIS 클라이언트, 검증, 캐시, Rate Limit, 날짜/음성 변환
src/test/             테스트 공통 설정
docs/                 조사, 설계, Siri, 보안 문서
public/               정적 파일
Dockerfile            production standalone 이미지
docker-compose.yml    로컬/단일 서버 실행 정의
```

## 알려진 제한사항

- 고등학교의 학과·계열·이동 수업처럼 `학년 + 반`만으로 구분되지 않는 시간표는 가능한 과목을 함께 표시하며, 개인별 수업을 확정할 수 없습니다.
- NEIS가 시간표를 게시하지 않은 주말·휴업일·미게시일은 모두 정상 빈 결과로 안내된다.
- Rate Limit과 캐시는 프로세스 메모리 기반이다. 수평 확장 시 공유 제한 계층이 필요하다.
- 브라우저 음성 미리 듣기는 Web Speech API 지원 여부와 설치된 한국어 음성에 따라 달라진다.
- Siri 사용에는 iPhone에서 접근 가능한 HTTPS 배포 주소가 필요하다.
- Mock 데이터는 개발 편의를 위한 것이며 실제 학교의 최신 시간표가 아니다.

## 장애 대응

- `400`: 학교 설정 형식과 학년·반 범위를 확인한다.
- `429`: `Retry-After` 이후 다시 요청한다.
- `502/504`: NEIS 상태와 서버 네트워크를 확인하고 잠시 후 다시 시도한다.
- 검색/시간표가 계속 Mock으로 보이면 `NEIS_API_KEY`가 컨테이너에 전달되었는지, `NEIS_MOCK_MODE`가 `false`인지 확인한다.
- `docker compose logs --tail=100 web`과 `/api/health`로 애플리케이션 상태를 확인한다. 로그에는 키나 upstream 원문을 남기지 않는다.

설계와 운영 세부사항은 [아키텍처](docs/ARCHITECTURE.md), [공식 문서 조사](docs/RESEARCH.md), [보안](docs/SECURITY.md)을 참고한다.

## 라이선스

[MIT License](LICENSE)로 배포합니다.
