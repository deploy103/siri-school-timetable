import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { SchoolSetup } from "@/components/school-setup";
import type { School } from "@/types/client";

const highSchool: School = {
  officeCode: "B10",
  schoolCode: "7010911",
  name: "한세사이버보안고등학교",
  kind: "고등학교",
  region: "서울특별시",
  address: "서울특별시 마포구 테스트로 1",
};

describe("SchoolSetup", () => {
  it("starts with nationwide search and offers all 17 education offices without defaulting to Seoul", () => {
    render(<SchoolSetup onSave={vi.fn()} />);

    const region = screen.getByLabelText("지역");
    expect(region).toHaveValue("");
    expect(screen.getByRole("option", { name: "전체 지역" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "서울" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "제주" })).toBeInTheDocument();
    expect(screen.getAllByRole("option")).toHaveLength(18);
    expect(screen.getByText("전국 17개 시도교육청의 학교를 검색합니다.")).toBeVisible();
  });

  it("offers grades one through six for a supported special school", () => {
    render(
      <SchoolSetup
        initialSettings={{ school: { ...highSchool, name: "테스트특수학교", kind: "특수학교" }, grade: 4, className: "1" }}
        onSave={vi.fn()}
      />,
    );

    expect(screen.getByLabelText("학년")).toHaveValue("4");
    expect(screen.getByRole("option", { name: "6학년" })).toBeInTheDocument();
    expect(screen.getByText(/학교 과정·강의실/)).toBeVisible();
  });

  it("searches for a school, selects it, and saves grade and class", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ schools: [highSchool] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ classes: [
        { grade: 2, className: "1", department: "클라우드보안과" },
        { grade: 2, className: "2", department: "클라우드보안과" },
        { grade: 2, className: "1", department: "메타버스게임과" },
      ] }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    render(<SchoolSetup onSave={onSave} />);
    await user.selectOptions(screen.getByLabelText("지역"), "B10");
    await user.type(screen.getByLabelText("학교 이름"), "한세사이버보안고");
    await user.click(screen.getByRole("button", { name: "검색" }));

    expect(await screen.findByRole("button", { name: /한세사이버보안고등학교/ })).toBeVisible();
    expect(fetchMock).toHaveBeenCalledWith("/api/schools?name=%ED%95%9C%EC%84%B8%EC%82%AC%EC%9D%B4%EB%B2%84%EB%B3%B4%EC%95%88%EA%B3%A0&officeCode=B10");
    expect(screen.queryByRole("button", { name: "설정 저장하고 시간표 보기" })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /한세사이버보안고등학교/ }));

    expect(await screen.findByLabelText("학과")).toHaveValue("클라우드보안과");
    await user.selectOptions(screen.getByLabelText("학년"), "2");
    await user.selectOptions(screen.getByLabelText("반"), "2");
    await user.click(screen.getByRole("button", { name: "설정 저장하고 시간표 보기" }));

    expect(onSave).toHaveBeenCalledWith({
      school: highSchool,
      grade: 2,
      className: "2",
      department: "클라우드보안과",
    });
  });

  it("omits the office code for nationwide searches and distinguishes same-name schools", async () => {
    const user = userEvent.setup();
    const busanSchool: School = {
      ...highSchool,
      officeCode: "C10",
      schoolCode: "C100000001",
      name: "미래중학교",
      kind: "중학교",
      region: "부산광역시교육청",
      locality: "부산광역시",
      address: "부산광역시 부산진구 미래로 1",
    };
    const jejuSchool: School = {
      ...busanSchool,
      officeCode: "T10",
      schoolCode: "T100000001",
      region: "제주특별자치도교육청",
      locality: "제주특별자치도",
      address: "제주특별자치도 제주시 미래로 1",
    };
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      schools: [busanSchool, jejuSchool],
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
    vi.stubGlobal("fetch", fetchMock);

    render(<SchoolSetup onSave={vi.fn()} />);
    await user.type(screen.getByLabelText("학교 이름"), "미래중학교");
    await user.click(screen.getByRole("button", { name: "검색" }));

    expect(fetchMock).toHaveBeenCalledWith("/api/schools?name=%EB%AF%B8%EB%9E%98%EC%A4%91%ED%95%99%EA%B5%90");
    expect(await screen.findByText("부산광역시 · 중학교")).toBeVisible();
    expect(screen.getByText("제주특별자치도 · 중학교")).toBeVisible();
    expect(screen.getByText("부산광역시 부산진구 미래로 1")).toBeVisible();
    expect(screen.getByText("제주특별자치도 제주시 미래로 1")).toBeVisible();
    expect(screen.getAllByRole("button", { name: /미래중학교/ })).toHaveLength(2);
    expect(screen.queryByRole("heading", { name: "학년과 반 설정" })).not.toBeInTheDocument();
  });

  it("clears an incompatible school selection when the region changes", async () => {
    const user = userEvent.setup();
    render(
      <SchoolSetup
        initialSettings={{ school: highSchool, grade: 2, className: "4" }}
        onSave={vi.fn()}
      />,
    );

    expect(screen.getByLabelText("지역")).toHaveValue("B10");
    expect(screen.getByRole("heading", { name: "학년과 반 설정" })).toBeVisible();
    await user.selectOptions(screen.getByLabelText("지역"), "C10");
    expect(screen.queryByRole("heading", { name: "학년과 반 설정" })).not.toBeInTheDocument();
  });

  it("shows loading, empty, and API error search states", async () => {
    const user = userEvent.setup();
    let resolveSearch: ((response: Response) => void) | undefined;
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>((resolve) => { resolveSearch = resolve; })));
    const { rerender } = render(<SchoolSetup onSave={vi.fn()} />);

    await user.type(screen.getByLabelText("학교 이름"), "없는학교");
    await user.click(screen.getByRole("button", { name: "검색" }));
    expect(screen.getByRole("button", { name: /검색 중/ })).toBeDisabled();
    resolveSearch?.(new Response(JSON.stringify({ schools: [] }), { status: 200 }));
    expect(await screen.findByText("검색 결과가 없어요.")).toBeVisible();

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      error: { code: "UPSTREAM_ERROR", message: "학교 정보 서비스가 잠시 불안정합니다." },
    }), { status: 503 })));
    rerender(<SchoolSetup onSave={vi.fn()} />);
    await user.clear(screen.getByLabelText("학교 이름"));
    await user.type(screen.getByLabelText("학교 이름"), "오류학교");
    await user.click(screen.getByRole("button", { name: "검색" }));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("학교 정보 서비스가 잠시 불안정합니다."));
  });
});
