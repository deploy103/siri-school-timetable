import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { GuidePage } from "@/components/guide-page";

describe("GuidePage", () => {
  it("renders the intro, quick guide, voice phrases, and FAQ", () => {
    render(<GuidePage />);

    expect(screen.getByRole("heading", { name: "Siri로 학교 정보 듣는 법" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "1분 만에 설정하기" })).toBeVisible();
    expect(screen.getAllByText(/오늘 학교 시간표 뭐야/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/오늘 학교 급식 뭐야/).length).toBeGreaterThan(0);
    expect(screen.getByText("단축어 앱이 안 보여요")).toBeVisible();
    expect(screen.getByText("Safari에선 되는데 Siri에선 안 돼요")).toBeVisible();
  });

  it("opens and closes a step image in a lightbox", async () => {
    const user = userEvent.setup();
    render(<GuidePage />);

    const thumbnails = screen.getAllByRole("button", { name: /눌러서 크게 보기/ });
    const firstThumbnail = thumbnails[0];
    if (!firstThumbnail) throw new Error("no step image thumbnail rendered");
    await user.click(firstThumbnail);

    expect(screen.getByRole("dialog")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "이미지 닫기" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });
});
