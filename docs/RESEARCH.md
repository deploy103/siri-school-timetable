# 공식 자료 조사 기록

마지막 확인일: **2026-09-22 (Asia/Seoul)**

이 문서는 서비스 구현에 필요한 나이스(NEIS) 교육정보 개방 포털의 학교·시간표 API와 Apple 단축어/Siri 연동 방식을 공식 자료와 실제 공식 API 응답으로 검증한 기록이다. 블로그나 비공식 SDK의 동작을 명세로 간주하지 않았다.

## 결론 요약

- 학교 검색은 `schoolInfo`, 시간표는 학교 종류에 따라 `elsTimetable`(초), `misTimetable`(중), `hisTimetable`(고), `spsTimetable`(특수)을 사용한다.
- 시간표 API에서 실제 필수인 신청 인자는 `ATPT_OFCDC_SC_CODE`와 `SD_SCHUL_CODE`이다. 오늘 시간표에는 이 둘과 KST 기준 `ALL_TI_YMD=yyyyMMdd`, `GRADE`, `CLASS_NM`을 보낸다.
- `schoolInfo`의 검색 필터는 공식 메타데이터상 모두 선택 사항이다. 이름 검색에는 `SCHUL_NM`을 쓰고, 결과의 교육청, 학교 종류, 시도와 도로명 주소를 함께 표시해야 동명 학교를 구분할 수 있다.
- NEIS의 업무상 성공/실패는 HTTP 상태만으로 판정할 수 없다. 정상 목록의 `head[].RESULT`와, 빈 결과·오류 때 최상위에 오는 `RESULT`를 모두 해석해야 한다. 확인한 논리 오류 응답은 HTTP 200이었다.
- 고등학교 API는 `GRADE + CLASS_NM` 필터를 공식 지원한다. 그러나 응답에는 계열·학과·강의실도 존재하므로 선택수업 등에서 같은 교시가 여러 행으로 나오는 경우 학생 개인의 수업을 이 API만으로 확정할 수 없다.
- 웹사이트가 Siri 명령을 자동 등록할 수는 없다. MVP는 사용자가 Apple 단축어 앱에서 `URL → URL 콘텐츠 가져오기 → 텍스트 말하기`를 구성하고 단축어 이름으로 Siri를 호출하는 방식이 공식 기능과 맞는다.
- 공용 단축어는 제작자가 실제 단축어 앱에서 만든 iCloud 링크로 공유할 수 있다. 서버가 임의의 `icloud.com/shortcuts/...` 링크나 서명되지 않은 단축어 파일을 만들어서는 안 된다.

## 1. NEIS Open API

### 1.1 공식 출처

아래 링크는 NEIS 교육정보 개방 포털의 각 데이터셋 상세 화면에서 **Open API 탭(`infSeq=2`)**을 연 주소다.

- [Open API 이용 안내](https://open.neis.go.kr/portal/guide/apiGuidePage.do)
- [학교기본정보 (`schoolInfo`)](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN17020190531110010104913&infSeq=2)
- [초등학교시간표 (`elsTimetable`)](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN15020190408160341416743&infSeq=2)
- [중학교시간표 (`misTimetable`)](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN15120190408165334348844&infSeq=2)
- [고등학교시간표 (`hisTimetable`)](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN18620200826103326268120&infSeq=2)
- [특수학교시간표 (`spsTimetable`)](https://open.neis.go.kr/portal/data/service/selectServicePage.do?infId=OPEN18520200826093359591792&infSeq=2)

모든 링크와 아래 명세는 2026-09-22에 확인했다. 포털 화면은 JavaScript로 상세 메타데이터를 불러오므로, 화면 표와 포털 자체 메타데이터 응답을 함께 대조했다.

### 1.2 호스트와 데이터셋 매핑

고정 베이스 URL은 `https://open.neis.go.kr/hub`이다.

| 학교 종류 | 리소스 | 호출 경로 |
| --- | --- | --- |
| 학교 검색/기본정보 | `schoolInfo` | `/hub/schoolInfo` |
| 초등학교 | `elsTimetable` | `/hub/elsTimetable` |
| 중학교 | `misTimetable` | `/hub/misTimetable` |
| 고등학교 | `hisTimetable` | `/hub/hisTimetable` |
| 특수학교 | `spsTimetable` | `/hub/spsTimetable` |

구현에서는 사용자 입력으로 호스트나 리소스명을 조립하지 않고 위 allowlist 중 하나만 선택해야 한다. `SCHUL_KND_SC_NM`이 이 네 종류에 정확히 대응하지 않는 외국인학교, 각종학교 등은 임의로 시간표 API에 매핑하지 말고 지원하지 않는 유형으로 처리한다.

### 1.3 공통 기본 인자

공식 상세 화면은 아래 네 기본 인자를 모두 `필수`로 표기한다.

| 변수 | 타입 | 공식 설명/기본값 |
| --- | --- | --- |
| `KEY` | string | 인증키. 기본값은 sample key |
| `Type` | string | `xml` 또는 `json`. 기본값 `xml` |
| `pIndex` | integer | 페이지 위치. 기본값 `1`; sample key는 1 고정 |
| `pSize` | integer | 페이지당 요청 건수. 기본값 `100`; sample key는 5 고정 |

포털 안내는 Open API 사용에 발급 인증키가 필요하다고 설명한다. 인증키를 생략한 실제 호출은 sample key로 동작했지만, 이때 `pIndex=1`, `pSize=5`로 제한되므로 배포 서비스는 서버의 `NEIS_API_KEY`를 `KEY`로 전달해야 한다. 한 번에 최대 1,000건을 넘기면 `ERROR-336`이다.

권장 공통값은 `Type=json`, `pIndex=1`이며, `pSize`는 필요한 범위만 작게 요청한다. API 키는 URL을 기록하는 로그, 브라우저 응답 및 클라이언트 번들에서 반드시 제거한다.

### 1.4 `schoolInfo` 신청 인자와 결과

공식 메타데이터에서 아래 검색 인자는 모두 선택 사항이다.

| 변수 | 의미 | 이 서비스에서의 사용 |
| --- | --- | --- |
| `ATPT_OFCDC_SC_CODE` | 시도교육청코드 | 이미 교육청을 아는 경우 범위 축소 |
| `SD_SCHUL_CODE` | 행정표준(학교)코드 | 학교의 정확한 재조회 |
| `SCHUL_NM` | 학교명 | 사용자 학교명 검색 |
| `SCHUL_KND_SC_NM` | 학교종류명 | 종류 필터가 필요할 때 사용 |
| `LCTN_SC_NM` | 시도명 | 지역 필터가 필요할 때 사용 |
| `FOND_SC_NM` | 설립명 | 공립/사립 등의 설립 구분 필터 |

학교 선택과 시간표 조회에 특히 필요한 응답 필드는 다음과 같다.

| 필드 | 의미/용도 |
| --- | --- |
| `ATPT_OFCDC_SC_CODE`, `ATPT_OFCDC_SC_NM` | 이후 시간표 조회에 필요한 교육청 코드와 표시명 |
| `SD_SCHUL_CODE` | 이후 시간표 조회에 필요한 학교 코드 |
| `SCHUL_NM` | 학교명 |
| `SCHUL_KND_SC_NM` | 초·중·고·특수 분기 기준 |
| `LCTN_SC_NM` | 시도 표시 |
| `ORG_RDNMA`, `ORG_RDNDA` | 동명 학교 구분용 주소 |
| `HS_SC_NM`, `HS_GNRL_BUSNS_SC_NM` | 고등학교 세부 구분 참고값 |
| `DGHT_SC_NM` | 주간/야간 구분 |
| `LOAD_DTM` | 원천 정보 수정일자 |

그 밖의 공식 출력 필드는 영문학교명, 관할조직, 설립명, 우편번호, 전화·팩스, 홈페이지, 남녀공학 여부, 산업체특별학급 여부, 특수목적고 계열, 입시 전후기, 설립일자, 개교기념일이다. 주소 필드에는 원천 데이터의 공백이 있을 수 있으므로 표시 전에 trim하되 원본 의미를 바꾸지 않는다.

학교 이름은 유일키가 아니다. 선택 상태에는 최소한 `ATPT_OFCDC_SC_CODE + SD_SCHUL_CODE + SCHUL_NM + SCHUL_KND_SC_NM`을 함께 보관한다.

### 1.5 시간표 신청 인자

`Y`는 공식 메타데이터의 필수 항목이며, 나머지는 선택 항목이다. 날짜 문자열은 공식 예시와 응답 모두 하이픈 없는 `yyyyMMdd`이다.

| 변수 | 초 | 중 | 고 | 특수 | 설명 |
| --- | :---: | :---: | :---: | :---: | --- |
| `ATPT_OFCDC_SC_CODE` | Y | Y | Y | Y | 시도교육청 코드 |
| `SD_SCHUL_CODE` | Y | Y | Y | Y | 학교 코드 |
| `AY` | 선택 | 선택 | 선택 | 선택 | 학년도 |
| `SEM` | 선택 | 선택 | 선택 | 선택 | 학기 |
| `ALL_TI_YMD` | 선택 | 선택 | 선택 | 선택 | 시간표 일자 |
| `DGHT_CRSE_SC_NM` | — | 선택 | 선택 | — | 주야과정명 |
| `ORD_SC_NM` | — | — | 선택 | — | 계열명 |
| `DDDEP_NM` | — | — | 선택 | — | 학과명 |
| `SCHUL_CRSE_SC_NM` | — | — | — | 선택 | 학교과정명 |
| `GRADE` | 선택 | 선택 | 선택 | 선택 | 학년 |
| `CLASS_NM` | 선택 | 선택 | 선택 | 선택 | 학급명(반) |
| `CLRM_NM` | — | — | 선택 | 선택 | 강의실명 |
| `PERIO` | 선택 | 선택 | — | 선택 | 교시. 고교 신청 인자에는 없음 |
| `TI_FROM_YMD` | 선택 | 선택 | 선택 | 선택 | 조회 시작일 |
| `TI_TO_YMD` | 선택 | 선택 | 선택 | 선택 | 조회 종료일 |

오늘 시간표의 최소 권장 필터는 다음과 같다.

```text
ATPT_OFCDC_SC_CODE=<선택한 학교의 교육청 코드>
SD_SCHUL_CODE=<선택한 학교 코드>
ALL_TI_YMD=<Asia/Seoul의 오늘, yyyyMMdd>
GRADE=<사용자 학년>
CLASS_NM=<사용자 반>
```

단일 날짜에는 `ALL_TI_YMD`를 우선한다. 범위 조회가 필요할 때만 `TI_FROM_YMD`와 `TI_TO_YMD`를 함께 사용한다. `CLASS_NM`은 숫자형으로 가정할 수 없는 원천 문자열이지만, 이 서비스의 UI는 1~20의 검증된 숫자 반을 문자열로 전달한다.

### 1.6 시간표 출력 필드

네 데이터셋의 공통 핵심 출력은 다음과 같다.

```text
ATPT_OFCDC_SC_CODE, ATPT_OFCDC_SC_NM,
SD_SCHUL_CODE, SCHUL_NM,
AY, SEM, ALL_TI_YMD,
GRADE, CLASS_NM, PERIO, ITRT_CNTNT, LOAD_DTM
```

- 초등학교는 위 공통 필드만 제공한다.
- 중학교는 `DGHT_CRSE_SC_NM`을 추가 제공한다.
- 고등학교는 `DGHT_CRSE_SC_NM`, `ORD_SC_NM`, `DDDEP_NM`, `CLRM_NM`을 추가 제공한다.
- 특수학교는 `SCHUL_CRSE_SC_NM`, `CLRM_NM`을 추가 제공한다.

`PERIO`, `GRADE` 등은 JSON에서도 문자열로 내려온다. 숫자로 변환할 때 전 문자열 일치 검증 후 안전한 정수만 받아야 한다. 과목/수업명은 `ITRT_CNTNT`이며 앞뒤 공백을 제거한다. 교시는 숫자로 정렬하고, 같은 교시의 중복 행은 무작정 첫 행으로 숨기지 말고 동일 과목 중복만 안정적으로 합치며 서로 다른 과목이면 모호성 정책을 적용한다.

### 1.7 JSON 응답 구조와 오류 판정

정상 목록은 데이터셋 이름을 최상위 키로 가지며, `head`와 `row`가 분리된다.

```json
{
  "misTimetable": [
    {
      "head": [
        { "list_total_count": 7 },
        { "RESULT": { "CODE": "INFO-000", "MESSAGE": "정상 처리되었습니다." } }
      ]
    },
    {
      "row": [
        {
          "ALL_TI_YMD": "20250305",
          "GRADE": "1",
          "CLASS_NM": "1",
          "PERIO": "1",
          "ITRT_CNTNT": "도덕"
        }
      ]
    }
  ]
}
```

빈 결과와 오류는 배열 없이 최상위 `RESULT`로 확인됐다.

```json
{ "RESULT": { "CODE": "INFO-200", "MESSAGE": "해당하는 데이터가 없습니다." } }
```

```json
{ "RESULT": { "CODE": "ERROR-300", "MESSAGE": "필수 값이 누락되어 있습니다. 요청인자를 참고 하십시오." } }
```

2026-09-22 실호출에서 정상, `INFO-200`, `ERROR-300`, `ERROR-290`가 모두 HTTP 200 및 `application/json;charset=UTF-8`로 왔다. 따라서 파서는 다음 두 위치를 모두 검사하고 `CODE`로 분기해야 한다.

1. `<dataset>[0].head[*].RESULT`
2. 최상위 `RESULT`

HTML 오류 페이지, JSON 파싱 실패, 네트워크 실패와 timeout은 NEIS 논리 코드와 별도의 upstream 장애로 취급한다.

### 1.8 공식 메시지 코드

다섯 데이터셋의 공식 메타데이터에 같은 메시지 목록이 게시되어 있다.

| 코드 | 공식 메시지 | 서비스 처리 권고 |
| --- | --- | --- |
| `INFO-000` | 정상 처리되었습니다. | 정상 파싱 |
| `INFO-100` | (해당 자료는 단순 참고용으로만 활용하시기 바랍니다.) | 데이터와 함께 참고 상태로 취급 |
| `INFO-200` | 해당하는 데이터가 없습니다. | 주말·휴업일·미등록 가능성을 알리는 빈 상태 |
| `INFO-300` | 관리자에 의해 인증키 사용이 제한되었습니다. | 설정/운영 오류, 사용자에게 내부 키는 숨김 |
| `ERROR-290` | 인증키가 유효하지 않습니다. 인증키가 없는 경우, 홈페이지에서 인증키를 신청하십시오. | 서버 설정 오류 |
| `ERROR-300` | 필수 값이 누락되어 있습니다. 요청인자를 참고 하십시오. | 요청 구성 오류 |
| `ERROR-310` | 해당하는 서비스를 찾을 수 없습니다. 요청인자 중 SERVICE를 확인하십시오. | 리소스 매핑/배포 오류 |
| `ERROR-333` | 요청위치 값의 타입이 유효하지 않습니다.요청위치 값은 정수를 입력하세요. | 페이지 인자 오류 |
| `ERROR-336` | 데이터요청은 한번에 최대 1,000건을 넘을 수 없습니다. | `pSize` 축소 |
| `ERROR-337` | 일별 트래픽 제한을 넘은 호출입니다. 오늘은 더이상 호출할 수 없습니다. | 호출 제한 오류, 재시도 폭주 금지 |
| `ERROR-500` | 서버 오류입니다. 지속적으로 발생시 홈페이지로 문의(Q&A) 바랍니다. | 일시적 upstream 장애 |
| `ERROR-600` | 데이터베이스 연결 오류입니다. 지속적으로 발생시 홈페이지로 문의(Q&A) 바랍니다. | 일시적 upstream 장애 |
| `ERROR-601` | SQL 문장 오류 입니다. 지속적으로 발생시 홈페이지로 문의(Q&A) 바랍니다. | upstream 장애 |

메시지 문자열 비교가 아니라 코드를 기준으로 처리한다. 서버/DB 계열 재시도는 timeout을 포함해 짧고 제한적으로 수행하고, `INFO-200`, 인증키 오류, 요청 오류는 재시도하지 않는다.

### 1.9 고등학교 시간표의 정확도 한계

공식 데이터셋 설명은 고등학교 시간표를 **학교, 계열, 학과, 학기, 학년, 강의실, 교시별 수업내용**으로 정의한다. 공식 신청 인자도 `GRADE`, `CLASS_NM`뿐 아니라 `ORD_SC_NM`, `DDDEP_NM`, `CLRM_NM`을 제공하며 응답에 이 필드들이 포함된다.

따라서 다음을 구분한다.

- `학년 + 반`: 공식적으로 조회 가능하다. 일반적인 학급 공통 시간표에는 이 MVP가 요구하는 결과를 낼 수 있다.
- 계열/학과/강의실별 여러 행: 선택과목, 이동수업 또는 학과 분화로 동일 교시에 서로 다른 `ITRT_CNTNT`가 존재할 수 있다. 계열·학과·강의실을 무시해 한 과목을 임의 선택해서는 안 된다.
- 개인별 선택과목: 이 API에는 학생 식별자나 개인 수강신청 식별자가 없다. 따라서 개인 시간표의 완전한 복원은 공식 필드만으로 보장할 수 없다.

구현 정책은 `GRADE + CLASS_NM + ALL_TI_YMD`로 먼저 조회하되, 동일 교시의 서로 다른 과목이 발견되면 "선택과목/이동수업으로 시간표가 여러 개입니다"라고 명시한다. 향후 사용자가 계열·학과·강의실을 고르는 UX를 추가하기 전까지 임의의 과목을 음성으로 확정하지 않는다. 이 중 "개인 시간표를 확정할 수 없다"는 부분은 공식 필드 구성에서 도출한 한계이며, 포털이 모든 학교의 중복 생성 규칙을 별도 보장한 것은 아니다.

### 1.10 특수학교 시간표의 정확도 한계

`spsTimetable`은 공식 지원 데이터셋이다. 다만 초·중·고와 달리 `SCHUL_CRSE_SC_NM`(학교과정명)과 `CLRM_NM`(강의실명)이 존재한다. 같은 학교 안의 과정 간 학년·반 명칭이 겹치면 `GRADE + CLASS_NM`만으로 모호할 수 있다. 모호한 행이 발견되면 임의 병합하지 말고 과정/강의실 선택이 추가로 필요하다고 안내한다.

### 1.11 공식적으로 공지된 과거 데이터 제약

네 시간표 데이터셋의 현재 설명에는 다음 이력이 동일하게 적혀 있다.

- 2025학년도 이후: 기존과 동일한 방식으로 사용 가능
- 2023학년도 8월~2024학년도: 데이터 분리 작업 때문에 API 연계 조회 불가; 필요 시 포털 문의 메일로 요청
- 2019년~2023년 7월 이전: 일반 리소스 대신 `elsTimetablebgs`, `misTimetablebgs`, `hisTimetablebgs`, `spsTimetablebgs`라는 과거 데이터용 리소스를 안내

이 서비스는 "오늘"만 조회하므로 2026년 현재 과거용 리소스를 구현할 필요는 없다. 날짜 범위 기능을 추가할 때에는 이 공백을 일반적인 "데이터 없음"과 구분해야 한다.

### 1.12 구현에 반영할 불변 조건

- 날짜는 서버에서 `Asia/Seoul` 기준으로 계산한 뒤 `yyyyMMdd`로 변환한다.
- 외부 목적지는 `https://open.neis.go.kr/hub/<allowlisted resource>`로 고정한다.
- API 키는 서버 환경변수에서만 읽고 클라이언트 URL이나 오류 상세에 포함하지 않는다.
- 검색 문자열, 코드, 학년, 반, 날짜는 서버에서 검증하고 길이를 제한한다.
- `INFO-200`과 upstream 실패를 동일한 빈 배열로 만들지 않는다.
- 성공 응답의 데이터셋 루트 이름이 요청한 리소스와 맞는지, `head.RESULT`가 성공인지 확인한 뒤 `row`를 읽는다.
- 응답에 포함된 `ALL_TI_YMD`, 학교 코드, 학년, 반이 요청과 맞지 않는 행은 신뢰하지 않는다.
- `PERIO`를 정수로 검증해 오름차순 정렬하고, 비정상 교시는 버리거나 안전한 오류로 처리한다.
- 원천 API의 미래 필드 추가는 허용하되 필수 필드 누락이나 타입 변경은 조용히 무시하지 않는다.

## 2. Apple 단축어와 Siri

### 2.1 공식 출처

모두 2026-09-22에 확인한 Apple Support의 Shortcuts User Guide다. Apple 문서는 같은 topic ID 아래 최신 OS 문서로 리디렉션될 수 있다.

- [Siri로 단축어 실행](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios)
- [단축어에서 첫 API 요청하기](https://support.apple.com/guide/shortcuts/request-your-first-api-apd58d46713f/ios)
- [단축어의 웹 API 소개](https://support.apple.com/guide/shortcuts/intro-to-web-apis-apd2d448b2de/ios)
- [iPhone/iPad에서 단축어 공유](https://support.apple.com/guide/shortcuts/share-shortcuts-apdf01f8c054/ios)
- [공유 단축어에 가져오기 질문 추가](https://support.apple.com/guide/shortcuts/add-import-questions-to-shared-shortcuts-apdf330fd3a0/ios)

### 2.2 가능한 MVP 연동 방식

Apple은 URL로 API endpoint를 지정하고 그 URL을 **Get Contents of URL** 동작에 전달하는 방식을 공식 안내한다. 또한 단축어를 Siri로 실행할 수 있다고 안내한다. 따라서 네이티브 앱이나 App Intents가 없는 이 웹 프로젝트에서 검증 가능한 흐름은 다음과 같다.

```text
URL (서비스가 보여 준 개인 설정 URL)
→ URL 콘텐츠 가져오기 (GET)
→ 텍스트 말하기
```

단축어 이름을 `오늘 학교 시간표 뭐야`로 저장하면 사용자는 `시리야, 오늘 학교 시간표 뭐야`라고 실행할 수 있다. Siri 인식 문구와 실행 가능 여부는 언어 설정, 기기 상태, 네트워크 및 iOS 버전에 영향을 받을 수 있다.

음성 endpoint가 `text/plain; charset=utf-8` 한 문장으로 응답하도록 하면 단축어에서 JSON 사전 키를 꺼내는 동작이 필요 없다. URL에 넣는 값은 교육청·학교 코드, 학교 종류, 학년, 반처럼 비밀이 아닌 설정으로 제한하고 `NEIS_API_KEY`는 절대 포함하지 않는다.

### 2.3 웹사이트가 할 수 없는 것

- 일반 웹사이트만으로 사용자의 단축어 보관함에 명령을 무인 등록하거나 Siri 구문을 강제로 예약할 수 없다.
- App Intents는 네이티브 앱이 제공하는 기능이다. 이 MVP에는 iOS 앱이 없으므로 App Intent를 구현한 것처럼 안내하지 않는다.
- 임의 문자열로 Apple의 iCloud 단축어 공유 링크를 만들 수 없다. 실제 단축어를 단축어 앱에서 공유해야 링크가 생성된다.
- 동적으로 `.shortcut` 파일을 조립하거나 미검증 URL scheme을 사용해 자동 설치되는 것처럼 제공하지 않는다.

즉, 기본 배포물은 정확한 수동 설정 안내와 복사 가능한 음성 API URL이다.

### 2.4 안전한 공용 단축어 공유

Apple 공식 문서는 단축어 앱에서 다음 두 공유 경로를 제공한다.

1. **iCloud 링크**: 단축어 편집기의 공유 메뉴에서 `Copy iCloud Link`를 선택한다. 수신자는 링크의 설명을 확인하고 `Get Shortcut`을 눌러 자신의 보관함에 추가한다. 공유자는 나중에 `Stop Sharing`으로 링크 공유를 중단할 수 있다.
2. **파일 내보내기**: `Options → File`에서 `Anyone` 또는 `People Who Know Me`를 선택한다. `Anyone` 파일은 무단 변조 방지를 위한 검증을 위해 Apple이 단축어 사본을 받는다고 공식 문서가 명시한다. `People Who Know Me` 파일에는 제작자의 연락처 정보가 포함되므로 불특정 다수 공개 배포에는 적합하지 않다.

공용 템플릿을 만들 경우 권장 절차는 다음과 같다.

- 운영자가 iPhone/iPad의 단축어 앱에서 실제 3단계 단축어를 만든다.
- 고정된 특정 학생의 URL을 넣지 않고, Apple의 **가져오기 질문(Import Questions)**으로 사용자가 자신의 URL을 입력/붙여넣게 구성한다.
- 동작 목록에 데이터 외부 전송, 스크립트 실행 등 불필요한 동작이 없는지 검토한다.
- 단축어 앱에서 iCloud 링크를 발급해 배포하고, 게시 페이지에서 제작자·동작·전송 대상 호스트를 설명한다.
- 서버 호스트나 API 계약이 바뀌면 기존 공유본이 자동 갱신된다고 가정하지 말고 새 템플릿을 검증·배포한다.

현재 저장소나 CI가 iPhone 단축어 앱을 제어해 공식 iCloud 링크를 발급할 수 있다는 근거는 없다. 따라서 **실제 기기에서 만들어 검증한 iCloud 링크가 준비되기 전에는 공용 설치 버튼을 구현하지 않는 것**이 안전하다.

### 2.5 공개 음성 URL의 보안 성격

음성 URL은 암호나 인증 토큰은 아니지만, 학교·학년·반 정보를 담아 공유될 수 있는 bearer-like URL이다.

- HTTPS만 사용한다.
- URL에는 NEIS 키, 내부 오류, 사용자 이름이나 연락처를 넣지 않는다.
- 서버에서 모든 query를 다시 검증하고 rate limit을 적용한다.
- 페이지나 로그에서 URL 전체를 불필요하게 수집하지 않는다.
- iCloud 공유 템플릿에는 특정 학생의 완성 URL을 하드코딩하지 않는다.
- 사용자가 URL을 공유하면 같은 시간표 문장을 제3자가 조회할 수 있음을 UI에서 알린다.

더 강한 프라이버시가 필요하면 향후 짧은 만료 토큰이나 취소 가능한 opaque ID를 도입할 수 있지만, 이는 별도 상태 저장소 없이 동작한다는 현재 범위를 바꾸므로 MVP 요구사항은 아니다.

## 3. 검증 기록과 남은 불확실성

### 3.1 2026-09-22 실제 호출로 확인한 사항

- `schoolInfo?Type=json&SCHUL_NM=서울`에서 `head.RESULT=INFO-000`과 학교 행을 확인했다.
- `misTimetable` 및 `hisTimetable`에서 필수 학교 코드와 날짜·학년·반 필터로 실제 행 구조를 확인했다.
- 파라미터가 빠진 시간표 호출은 최상위 `ERROR-300`, 존재하지 않는 날짜는 최상위 `INFO-200`, 잘못된 키는 최상위 `ERROR-290`을 반환했다.
- 위 세 논리 상태와 정상 상태는 모두 HTTP 200이었다.
- 익명 sample key 호출은 요청한 `pSize`와 무관하게 공식 설명대로 최대 5행을 반환하는 동작을 확인했다.
- 공식 포털의 메타데이터에서 다섯 리소스의 요청 변수, 출력 컬럼, 메시지 코드를 대조했다.

실제 키를 사용한 일일 quota와 대량 페이지네이션은 키가 제공되지 않아 검증하지 않았다. 공식 메타데이터의 `apiTrf=0` 표시를 무제한 보장으로 해석하지 않았으며, `ERROR-337`이 존재하므로 운영상 rate limit과 캐시가 필요하다.

### 3.2 명시적으로 남는 불확실성

- 학교별 선택과목/이동수업 입력 방식은 전국적으로 동일하다고 공식 문서가 보장하지 않는다. 고교·특수학교 중복 처리 정책은 운영 데이터로 계속 관찰해야 한다.
- 시간표 원천 데이터의 게시 시각, 수정 주기, 당일 변경 반영 지연에 대한 정량 SLA는 확인한 상세 문서에 없다.
- Apple 단축어의 화면 문구는 iOS 버전과 기기 언어에 따라 한국어 번역이 달라질 수 있다. 문서의 동작명보다 아이콘/순서를 함께 안내하는 편이 안전하다.
- iCloud 공용 링크의 실제 설치·Siri 음성 재생은 Apple 기기에서 수동 검증해야 한다. 웹/Node 테스트만으로 이를 증명할 수 없다.
- Apple 문서 URL은 topic ID는 유지하면서 최신 OS 버전으로 리디렉션될 수 있으므로, 배포 전에 현재 지원 iOS에서 안내 화면을 다시 확인한다.
