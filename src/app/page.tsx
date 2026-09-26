"use client";

import { useState } from "react";
import { OnboardingGuide } from "@/components/onboarding-guide";
import { SchoolSetup } from "@/components/school-setup";
import { MealView } from "@/components/meal-view";
import { TimetableView } from "@/components/timetable-view";
import { useOnboarding } from "@/hooks/use-onboarding";
import { useSchoolSettings } from "@/hooks/use-school-settings";
import type { SchoolSettings } from "@/types/client";

export default function HomePage() {
  const { settings, isRestoring, saveSettings } = useSchoolSettings();
  const onboarding = useOnboarding();
  const [isEditing, setIsEditing] = useState(false);
  const [activeView, setActiveView] = useState<"timetable" | "meal">("timetable");
  const [openSiriOnMount, setOpenSiriOnMount] = useState(false);

  function save(next: SchoolSettings) {
    const isFirstSave = !settings;
    saveSettings(next);
    setIsEditing(false);
    if (isFirstSave) setOpenSiriOnMount(true);
  }

  function showGuideAgain() {
    onboarding.show();
    setIsEditing(true);
  }

  if (isRestoring) {
    return <main className="page-shell restoring" aria-busy="true"><span className="spinner large" aria-hidden="true" /><p>저장된 설정을 확인하고 있어요.</p></main>;
  }

  if (!settings || isEditing) {
    return (
      <SchoolSetup
        initialSettings={settings}
        onSave={save}
        onCancel={settings ? () => setIsEditing(false) : undefined}
        onboardingBanner={
          !onboarding.isRestoring && !onboarding.dismissed
            ? <OnboardingGuide onDismiss={onboarding.dismiss} />
            : undefined
        }
      />
    );
  }

  if (activeView === "meal") {
    return (
      <MealView
        settings={settings}
        onChangeSettings={() => setIsEditing(true)}
        onShowTimetable={() => setActiveView("timetable")}
        onShowGuide={showGuideAgain}
      />
    );
  }

  return (
    <TimetableView
      settings={settings}
      onChangeSettings={() => setIsEditing(true)}
      onShowMeal={() => setActiveView("meal")}
      onShowGuide={showGuideAgain}
      openSiriOnMount={openSiriOnMount}
      onSiriAutoOpened={() => setOpenSiriOnMount(false)}
    />
  );
}
