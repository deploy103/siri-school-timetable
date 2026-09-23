# 아키텍처

## 목표와 경계

Time Siri는 로그인이나 데이터베이스 없이 학교·학년·반을 브라우저에 저장하고, NEIS 교육정보 개방 포털의 당일 시간표와 급식을 보여 주는 Next.js 애플리케이션이다. 브라우저는 NEIS에 직접 접속하지 않는다. `NEIS_API_KEY`와 외부 API 통신은 서버 런타임에만 존재한다.

```text
모바일 브라우저 ── same-origin JSON ──> Next.js Route Handler
      │                                  │
      ├─ localStorage(학교/학년/반)       ├─ Zod 검증 / Rate Limit / 캐시
      │                                  └─ 고정된 NEIS HTTPS 호스트
      └─ Web Speech API(미리 듣기)

iPhone 단축어 ── same-origin text/plain ──> /api/voice/timetable
              └─ same-origin text/plain ──> /api/voice/meal

한세 교사용 화면(`/hansei-t`)
      ├─ 별도 localStorage(과목 + 학과 + 학년 + 반)
      └─ 고정 학교 전체 시간표 1회 조회 ──> 서버에서 완전 일치 필터
```

## 주요 흐름

1. `GET /api/schools?officeCode=...&name=...`가 학교명과 선택적인 17개 시도교육청 코드를 검증하고 `schoolInfo`를 조회한다. 전체 지역 검색은 `officeCode`를 생략한다.
2. `classInfo`에서 학과·학년·반을 조회하고, 사용자가 고른 학교의 교육청 코드, 학교 코드, 학교 종류와 선택 학과·학년·반을 `localStorage`에 저장한다. 이 값은 공개 데이터와 사용자 설정이며 인증 정보가 아니다.
3. `GET /api/timetable/today`는 서울 시간대의 날짜를 구하고 학교 종류에 맞는 NEIS 데이터셋을 선택한다.
4. NEIS 행은 공백 제거, 유효 교시 필터, 교시 중복 제거, 오름차순 정렬을 거쳐 안정적인 응답 형식으로 변환된다.
5. 음성 API는 같은 조회 결과를 한국어 문장으로 직렬화해 `text/plain; charset=utf-8`로 반환한다.
6. `GET /api/meal/today`는 같은 학교 코드와 KST 날짜로 `mealServiceDietInfo`를 조회한다. 웹 메뉴에는 알레르기 표기를 보존하고 급식 음성 문장에서만 끝의 알레르기 번호 묶음을 제거한다.

## API 계약

| 경로 | 형식 | 캐시 | Rate Limit |
| --- | --- | --- | --- |
| `/api/health` | JSON | `no-store` | 없음 |
| `/api/schools?officeCode=&name=` | JSON | 지역·검색어별 서버 캐시 + private 캐시 헤더 | 검색용 제한 |
| `/api/classes?officeCode=&schoolCode=` | JSON | 학교·학년도별 서버 캐시 + private 캐시 헤더 | 검색용 제한 |
| `/api/timetable/today?...` | JSON | 짧은 서버 캐시 + private 캐시 헤더 | 시간표용 제한 |
| `/api/voice/timetable?...` | UTF-8 text | 짧은 서버 캐시 | 시간표용 제한 |
| `/api/meal/today?officeCode=&schoolCode=` | JSON | 학교·날짜별 10분 서버 캐시 + private 캐시 헤더 | 조회용 제한 |
| `/api/voice/meal?officeCode=&schoolCode=` | UTF-8 text | 같은 급식 서버 캐시 | 음성용 제한 |
| `/api/hansei-t/subjects` | JSON | 학기 범위 6시간 서버 캐시 | 조회용 제한 |
| `/api/hansei-t/assignment-candidates?subject=` | JSON | 같은 학기 범위 캐시 | 조회용 제한 |
| `/api/hansei-t/timetable?p=` | JSON | 오늘 전체 학교 시간표 60초 서버 캐시 | 조회용 제한 |
| `/api/voice/teacher-timetable?p=` | UTF-8 text | 같은 60초 서버 캐시, 응답은 `no-store` | 음성용 제한 |

시간표의 공통 쿼리 파라미터는 `officeCode`, `schoolCode`, `kind`, `grade`, `className`이다. 오류 JSON은 `{ "error": { "code": "...", "message": "..." } }` 형태이며 스택, 원본 NEIS 본문, API 키를 포함하지 않는다.

## 상태와 저장

- 영속 상태: 브라우저 `localStorage`의 한 개 버전 관리 객체
- 서버 캐시: 프로세스 내부 TTL/LRU 유사 캐시와 동일 요청 병합
- Rate Limit: 프로세스별 고정 시간 창
- 데이터베이스/쿠키/세션: 사용하지 않음

여러 서버 인스턴스를 운영할 경우 캐시와 Rate Limit은 공유되지 않는다. 대규모 배포에서는 신뢰할 수 있는 프록시 또는 관리형 게이트웨이의 분산 Rate Limit을 앞단에 추가해야 한다.

## 장애 모델

- 입력 오류: 외부 호출 전 `400`
- 과도한 요청: `429`와 `Retry-After`
- NEIS 타임아웃: 제한된 재시도 후 `504`
- NEIS 오류/형식 오류: 안전한 메시지와 `502`
- 결과 없음: 성공한 빈 `lessons` 또는 `meals`와 주말·휴업일·미급식일 안내
- API 키 없음 + Mock 꺼짐: `NEIS_NOT_CONFIGURED`와 `503`; health는 `unconfigured/degraded`
- 명시적 `NEIS_MOCK_MODE=true`: 네트워크를 쓰지 않는 결정적 개발 데이터

## 배포

Next.js standalone 빌드를 Node.js 24 LTS Alpine 런타임에 복사한다. 최종 이미지에는 소스, 개발 의존성, 키가 없으며 UID 1001의 비루트 사용자로 실행된다. Compose는 모든 Linux capability를 제거하고, 루트 파일 시스템을 읽기 전용으로 만들며 `/tmp`만 tmpfs로 제공한다.
