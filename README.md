# Siri School Timetable

[![Next.js](https://img.shields.io/badge/Next.js-16-000000?logo=nextdotjs)](https://nextjs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Node.js-24_LTS-5FA04E?logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

전국 초·중·고등학교를 검색해 오늘 시간표와 급식을 확인하고, iPhone Siri 단축어로 바로 들을 수 있는 모바일 우선 웹 서비스입니다. 로그인과 데이터베이스 없이 학교·학년·반 설정을 브라우저에 저장합니다.

```text
학교 검색 → 학교·학년·반 저장 → 오늘 시간표·급식 확인 → Siri 단축어 연결
```

> “시리야, 오늘 학교 시간표 뭐야?”
>
> “오늘 시간표는 1교시 자료구조, 2교시 영어, 3교시 체육입니다.”
>
> “시리야, 오늘 학교 급식 뭐야?”
>
> “오늘 급식은 쌀밥, 미역국, 제육볶음, 배추김치입니다.”

## 기능

- 전국 초·중·고 및 지원되는 특수학교 검색(지역·주소·학교 유형 표시)
- 학교 종류에 따른 NEIS 시간표 데이터셋 자동 선택
- NEIS `classInfo` 기반 학과·학년·반 선택으로 특성화고 동명 학급 구분
- 서울 시간 기준 오늘 시간표, 교시 정렬 및 중복/비정상 행 정리
- 같은 학교 설정을 재사용하는 오늘 급식과 조식·중식·석식 구분
- 웹에서는 알레르기 번호를 보존하고 Siri에서는 끝의 알레르기 표기만 제거
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

`http://localhost:3000`을 엽니다. 실제 데이터를 확인하려면 `.env`에 키를 설정합니다. 키 없이 UI와 Siri 흐름을 개발할 때는 `NEIS_MOCK_MODE=true`를 명시해야 합니다.

## 환경변수

```dotenv
NEIS_API_KEY=발급받은_키
NEIS_MOCK_MODE=false
TRUST_PROXY_HEADERS=false
```

- `NEIS_API_KEY`: [NEIS 교육정보 개방 포털](https://open.neis.go.kr/)에서 발급한다. 서버 전용이며 `NEXT_PUBLIC_` 접두사를 붙이지 않는다.
- `NEIS_MOCK_MODE=true`: 키 유무와 관계없이 외부 호출 없이 결정적 Mock 응답을 사용한다. Mock은 이 값을 명시한 경우에만 활성화된다.
- `TRUST_PROXY_HEADERS=true`: 전달 헤더를 덮어쓰는 신뢰 가능한 reverse proxy 뒤에서만 설정한다. 클라이언트 IP별 Rate Limit에 사용된다.

NEIS 동작 모드는 다음 세 가지다.

| 상태 | 조건 | `/api/health` | 데이터 동작 |
| --- | --- | --- | --- |
| Live | 키 있음, Mock 꺼짐 | `status: ok`, `mode: live` | 실제 NEIS 호출 |
| Mock | `NEIS_MOCK_MODE=true` | `status: ok`, `mode: mock` | 개발용 고정 데이터 |
| Unconfigured | 키 없음, Mock 꺼짐 | `status: degraded`, `mode: unconfigured` | API가 `NEIS_NOT_CONFIGURED`(503) 반환 |

`.env`는 Git과 Docker build context에서 제외된다. 실제 키를 `.env.example`에 기록하지 않는다.

상태 응답에는 키가 포함되지 않는다.

```bash
curl http://localhost:3000/api/health
```

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

운영 Compose는 host 포트를 공개하지 않고 기존 외부 Docker network인 `mvtp-web-net`을 사용합니다. 배포 전에 해당 network가 서버에 존재해야 합니다.

```bash
cp .env.example .env
# 실제 운영 데이터가 필요하면 .env에 NEIS_API_KEY를 입력한다.
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
docker compose exec siri-school-timetable wget -qO- http://127.0.0.1:3000/api/health
```

같은 network의 reverse proxy에서는 `http://siri-school-timetable:3000`으로 접근합니다. 종료 명령은 `docker compose down`입니다. 이미지는 multi-stage standalone 빌드이고, 최종 컨테이너는 비루트·읽기 전용 파일 시스템으로 실행됩니다. API 키는 이미지가 아니라 컨테이너 실행 시 주입됩니다.

`.env`가 반영되지 않는 것 같다면 컨테이너를 다시 생성한 뒤 실제 키 값 대신 존재 여부만 확인합니다.

```bash
docker compose up -d --force-recreate
docker compose exec siri-school-timetable \
  node -e 'console.log({hasNeisKey:Boolean(process.env.NEIS_API_KEY),mock:process.env.NEIS_MOCK_MODE})'
```

`hasNeisKey: false`라면 프로젝트 디렉터리의 `.env` 위치와 이름을 확인합니다. 운영 Compose의 `.env` 파일은 optional이므로 파일이 없어도 컨테이너는 시작되지만, 애플리케이션은 Live나 Mock으로 위장하지 않고 Unconfigured 상태를 보고합니다.

## Siri 설정

웹에서 학교 설정을 저장한 뒤 **Siri 설정**을 열고 시간표 또는 급식 URL을 복사한다. iPhone 단축어 앱에서 다음 세 동작을 순서대로 만든다.

```text
URL
→ URL 콘텐츠 가져오기 (GET)
→ 텍스트 말하기
```

시간표 단축어는 `오늘 학교 시간표 뭐야`, 급식 단축어는 `오늘 학교 급식 뭐야`로 각각 저장한다. 웹사이트가 단축어를 자동 설치하거나 Siri에 자동 등록하지는 않는다. 자세한 내용은 [docs/SIRI_SETUP.md](docs/SIRI_SETUP.md)를 참고한다.

## API

```text
GET /api/health
GET /api/schools?name=학교명
GET /api/schools?officeCode=B10&name=학교명
GET /api/classes?officeCode=B10&schoolCode=학교코드
GET /api/timetable/today?officeCode=...&schoolCode=...&kind=...&grade=2&className=1
GET /api/voice/timetable?officeCode=...&schoolCode=...&kind=...&grade=2&className=1
GET /api/meal/today?officeCode=...&schoolCode=...
GET /api/voice/meal?officeCode=...&schoolCode=...
```

학교 설정 화면에서 17개 시도교육청 또는 전체 지역을 선택한 뒤 학교명을 검색합니다. 학교 선택 후에는 NEIS가 제공한 학과·학년·반만 선택할 수 있습니다. 특성화고는 `DDDEP_NM`까지 시간표 요청에 전달해 서로 다른 학과의 같은 학년·반이 섞이지 않습니다. 급식은 같은 설정의 교육청·학교 코드만 재사용하므로 다시 설정할 필요가 없습니다. 학교·시간표·급식 API는 JSON을 반환하고, 음성 API는 단축어가 그대로 말할 수 있는 `text/plain; charset=utf-8` 문장을 반환합니다.

NEIS가 1·2교시 행 없이 3교시부터 반환하면 화면도 3교시부터 표시하고 그 이유를 안내합니다. 서로 다른 과목이 같은 교시에 남는 경우 화면에는 후보를 표시하되 Siri는 긴 후보 목록 대신 `선택 수업`이라고 짧게 읽습니다.

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
- NEIS가 급식을 게시하지 않은 주말·공휴일·방학·미급식일도 정상 빈 결과로 안내된다.
- Rate Limit과 캐시는 프로세스 메모리 기반이다. 수평 확장 시 공유 제한 계층이 필요하다.
- 브라우저 음성 미리 듣기는 Web Speech API 지원 여부와 설치된 한국어 음성에 따라 달라진다.
- Siri 사용에는 iPhone에서 접근 가능한 HTTPS 배포 주소가 필요하다.
- Mock 데이터는 개발 편의를 위한 것이며 실제 학교의 최신 시간표가 아니다.

## 장애 대응

- `400`: 학교 설정 형식과 학년·반 범위를 확인한다.
- `429`: `Retry-After` 이후 다시 요청한다.
- `502/504`: NEIS 상태와 서버 네트워크를 확인하고 잠시 후 다시 시도한다.
- `503 NEIS_NOT_CONFIGURED`: `NEIS_API_KEY`가 컨테이너에 전달되었는지 확인하거나 개발 환경에서만 `NEIS_MOCK_MODE=true`를 명시한다.
- 인증 오류: 키의 유효성과 NEIS 포털 상태를 확인한다. 검색 결과 없음과 인증 실패는 서로 다른 오류로 처리된다.
- 검색/시간표가 Mock으로 보이면 `NEIS_MOCK_MODE`가 의도치 않게 `true`인지 확인한다.
- `docker compose logs --tail=100 siri-school-timetable`과 `/api/health`로 애플리케이션 상태를 확인한다. 로그에는 키나 upstream 원문을 남기지 않는다.

설계와 운영 세부사항은 [아키텍처](docs/ARCHITECTURE.md), [공식 문서 조사](docs/RESEARCH.md), [보안](docs/SECURITY.md)을 참고한다.

한세사이버보안고등학교 교사용 별도 기능의 개발·운영 안내는 [한세 교사용 시간표 설정](docs/HANSEI_TEACHER_SETUP.md)을 참고한다. 이 경로는 기존 학생용 메뉴에 노출하지 않는다.

## 라이선스

[MIT License](LICENSE)로 배포합니다.
