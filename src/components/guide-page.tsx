"use client";

import Link from "next/link";
import { ArrowRightIcon } from "@/components/icons";
import { GuideImage } from "@/components/guide-image";

interface Step {
  id: string;
  title: string;
  summary: string;
  detail: string;
  image: { src: string; alt: string };
}

const STEPS: Step[] = [
  {
    id: "open-app",
    title: "1. 단축어 앱 열기",
    summary: "아이폰 기본 앱인 단축어를 엽니다.",
    detail: "홈 화면에서 단축어 앱을 찾아 누르세요. 안 보이면 화면을 아래로 쓸어내려 “단축어”라고 검색하면 나와요. 지웠다면 App Store에서 다시 설치할 수 있어요.",
    image: { src: "/guide/step-1-open-shortcuts-app.svg", alt: "아이폰 홈 화면에서 단축어 앱을 여는 모습" },
  },
  {
    id: "new-shortcut",
    title: "2. 새 단축어 만들고 주소 붙여넣기",
    summary: "오른쪽 위 + 버튼으로 새로 만들고, 사이트에서 복사한 주소를 넣어요.",
    detail: "시간표 또는 급식 화면의 “Siri 설정”에서 주소를 복사하세요. 단축어 앱에서 + 버튼 → 동작 추가 → URL 검색 → 추가한 뒤 복사한 주소를 붙여넣습니다.",
    image: { src: "/guide/step-2-new-shortcut-url.svg", alt: "단축어에 URL 동작을 추가하고 주소를 붙여넣는 모습" },
  },
  {
    id: "add-actions",
    title: "3. 필요한 동작 2개 추가",
    summary: "URL 콘텐츠 가져오기, 텍스트 말하기를 순서대로 추가해요.",
    detail: "동작 추가에서 “URL 콘텐츠 가져오기”를 검색해 추가하고, 이어서 “텍스트 말하기”를 추가하세요. 옵션은 기본값 그대로 두면 됩니다.",
    image: { src: "/guide/step-3-add-actions.svg", alt: "URL 콘텐츠 가져오기와 텍스트 말하기 동작이 추가된 모습" },
  },
  {
    id: "name-phrase",
    title: "4. 부를 문구로 이름 저장",
    summary: "시리에게 말할 문구를 단축어 이름으로 저장해요.",
    detail: "오른쪽 위 설정 아이콘을 눌러 이름을 정합니다. 시간표는 “오늘 학교 시간표 뭐야”, 급식은 “오늘 학교 급식 뭐야”를 추천해요.",
    image: { src: "/guide/step-4-name-with-phrase.svg", alt: "단축어 이름을 시리 문구로 저장하는 모습" },
  },
  {
    id: "run-with-siri",
    title: "5. Siri로 실행",
    summary: "“시리야, ”라고 부른 뒤 저장한 문구를 말하면 끝!",
    detail: "처음엔 단축어 앱에서 직접 눌러 잘 되는지 먼저 확인하세요. 소리 내어 정상적으로 읽어주면 이제 Siri로 불러도 똑같이 동작해요.",
    image: { src: "/guide/step-5-run-with-siri.svg", alt: "시리에게 말해서 단축어를 실행하는 모습" },
  },
];

const VOICE_PHRASES = [
  { label: "시간표", phrase: "시리야, 오늘 학교 시간표 뭐야?" },
  { label: "급식", phrase: "시리야, 오늘 학교 급식 뭐야?" },
];

const TROUBLESHOOT_CHECKLIST = [
  "웹사이트에서 학교·학년·반을 저장했는지 다시 확인",
  "학교를 바꿨다면 단축어 URL도 새로 복사해서 교체",
  "인터넷(와이파이/데이터) 연결 확인",
  "Siri에게 말한 문구와 단축어 이름이 정확히 같은지 확인",
  "설정 > Siri 및 검색에서 “Hey Siri” 또는 음성 사용이 켜져 있는지 확인",
  "Safari에서 단축어에 넣은 주소를 직접 열어 문장이 그대로 나오는지 테스트",
];

const FAQS: { q: string; a: string }[] = [
  { q: "단축어 앱이 안 보여요", a: "아이폰 기본 앱이라 대부분 이미 있어요. 안 보이면 App Store에서 “단축어”를 검색해 설치하세요." },
  { q: "Siri가 말을 못 알아들어요", a: "문구를 짧고 또렷하게 말해보세요. 조용한 곳에서 다시 시도하고, 단축어 이름과 실제로 말한 문구가 같은지 확인하세요." },
  { q: "실행은 되는데 시간표가 안 떠요", a: "인터넷 연결을 확인하고, 웹사이트에서 같은 설정으로 조회했을 때도 시간표가 나오는지 먼저 확인하세요." },
  { q: "학교가 검색되지 않아요", a: "학교의 정식 이름으로 검색해보고, 지역을 선택한 뒤 다시 검색해보세요." },
  { q: "반 설정을 바꾸고 싶어요", a: "언제든 화면 위 “설정 변경” 버튼을 누르면 학교·학년·반을 다시 고를 수 있어요." },
  { q: "오늘 수업이 없다고 나와요", a: "주말·휴업일이거나 학교가 아직 시간표를 올리지 않은 날일 수 있어요. 정상적인 빈 상태예요." },
  { q: "Safari에선 되는데 Siri에선 안 돼요", a: "단축어 안에 들어간 URL이 최신 설정인지, URL 콘텐츠 가져오기 → 텍스트 말하기 순서가 맞는지 확인하세요." },
];

export function GuidePage() {
  return (
    <main className="page-shell guide-page">
      <header className="setup-heading">
        <p className="eyebrow">사용 가이드</p>
        <h1>Siri로 학교 정보 듣는 법</h1>
        <p>학교·학년·반을 설정하고, 단축어를 한 번만 만들어두면 그다음부터는 말로 물어보면 돼요.</p>
      </header>

      <section className="card guide-section" aria-labelledby="what-is-this">
        <h2 id="what-is-this">이 서비스가 뭔가요</h2>
        <p>전국 학교의 오늘 시간표와 급식을 찾아주고, iPhone Siri로 바로 들을 수 있게 해주는 서비스예요. 로그인 없이 이 기기에만 설정을 저장해요.</p>
      </section>

      <section className="card guide-section quick-guide" aria-labelledby="quick-guide-heading">
        <h2 id="quick-guide-heading">1분 만에 설정하기</h2>
        <ol className="quick-guide-list">
          <li>학교, 학년, 반 먼저 저장</li>
          <li>그 다음 단축어 추가</li>
          <li>마지막으로 Siri 문구 등록하면 끝</li>
        </ol>
        <Link className="button primary" href="/"><ArrowRightIcon />학교 설정하러 가기</Link>
      </section>

      <section className="card guide-section" aria-labelledby="siri-steps-heading">
        <h2 id="siri-steps-heading">Siri / 단축어 연결 방법</h2>
        <p className="guide-version-note">버전에 따라 버튼 이름이 조금 다를 수 있어요. 순서와 아이콘 모양은 대부분 비슷해요.</p>
        <div className="guide-step-grid">
          {STEPS.map((step) => (
            <article className="guide-step-card" key={step.id}>
              <GuideImage src={step.image.src} alt={step.image.alt} caption={step.title} />
              <h3>{step.title}</h3>
              <p className="guide-step-summary">{step.summary}</p>
              <p className="guide-step-detail">{step.detail}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="card guide-section" aria-labelledby="voice-example-heading">
        <h2 id="voice-example-heading">실제 사용 예시</h2>
        <p>단축어 이름을 아래 문구 그대로 저장하는 걸 추천해요.</p>
        <div className="voice-phrase-list">
          {VOICE_PHRASES.map((item) => (
            <div className="voice-phrase-box" key={item.label}>
              <span className="voice-phrase-label">{item.label}</span>
              <strong>“{item.phrase}”</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="card guide-section" aria-labelledby="scenario-heading">
        <h2 id="scenario-heading">처음부터 세팅하는 방법</h2>
        <div className="scenario-grid">
          <article className="scenario-card">
            <h3>완전 처음 써봐요</h3>
            <ol className="quick-guide-list">
              <li>단축어 앱을 연다</li>
              <li>+ 버튼을 누른다</li>
              <li>이 사이트에서 복사한 주소를 붙여넣는다</li>
              <li>동작 2개(URL 콘텐츠 가져오기, 텍스트 말하기)를 추가한다</li>
              <li>이름을 “오늘 학교 시간표 뭐야”로 저장한다</li>
              <li>“시리야, 오늘 학교 시간표 뭐야”라고 말한다</li>
            </ol>
          </article>
          <article className="scenario-card">
            <h3>설정은 했는데 Siri가 안 돼요</h3>
            <p>아래 순서대로 하나씩 확인해보세요.</p>
            <ul className="troubleshoot-checklist">
              {TROUBLESHOOT_CHECKLIST.map((item) => <li key={item}>{item}</li>)}
            </ul>
            <GuideImage
              src="/guide/troubleshoot-test-in-safari.svg"
              alt="Safari에서 음성 API 주소를 직접 열어 정상 응답을 확인하는 모습"
              caption="Safari에서 주소 직접 열어보기"
            />
          </article>
        </div>
      </section>

      <section className="card guide-section" aria-labelledby="faq-heading">
        <h2 id="faq-heading">자주 묻는 질문</h2>
        <div className="faq-list">
          {FAQS.map((item) => (
            <details key={item.q}>
              <summary>{item.q}</summary>
              <p>{item.a}</p>
            </details>
          ))}
        </div>
      </section>
    </main>
  );
}
