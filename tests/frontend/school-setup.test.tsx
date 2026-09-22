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
  it("offers grades one through six for a supported special school", () => {
    render(
      <SchoolSetup
        initialSettings={{ school: { ...highSchool, name: "테스트특수학교", kind: "특수학교" }, grade: 4, className: 1 }}
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
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ schools: [highSchool] }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }));
    vi.stubGlobal("fetch", fetchMock);

    render(<SchoolSetup onSave={onSave} />);
    await user.type(screen.getByLabelText("학교 이름"), "한세사이버보안고");
    await user.click(screen.getByRole("button", { name: "검색" }));

    expect(await screen.findByRole("button", { name: /한세사이버보안고등학교/ })).toBeVisible();
    expect(fetchMock).toHaveBeenCalledWith("/api/schools?name=%ED%95%9C%EC%84%B8%EC%82%AC%EC%9D%B4%EB%B2%84%EB%B3%B4%EC%95%88%EA%B3%A0");
    await user.click(screen.getByRole("button", { name: /한세사이버보안고등학교/ }));

    expect(screen.getByText(/선택과목·학과별 이동 수업/)).toBeVisible();
    await user.selectOptions(screen.getByLabelText("학년"), "2");
    await user.selectOptions(screen.getByLabelText("반"), "7");
    await user.click(screen.getByRole("button", { name: "설정 저장하고 시간표 보기" }));

    expect(onSave).toHaveBeenCalledWith({ school: highSchool, grade: 2, className: 7 });
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
