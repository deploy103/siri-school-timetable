"use client";

import { useState } from "react";
import { SchoolSetup } from "@/components/school-setup";
import { TimetableView } from "@/components/timetable-view";
import { useSchoolSettings } from "@/hooks/use-school-settings";
import type { SchoolSettings } from "@/types/client";

export default function HomePage() {
  const { settings, isRestoring, saveSettings } = useSchoolSettings();
  const [isEditing, setIsEditing] = useState(false);

  function save(next: SchoolSettings) {
    saveSettings(next);
    setIsEditing(false);
  }

  if (isRestoring) {
    return <main className="page-shell restoring" aria-busy="true"><span className="spinner large" aria-hidden="true" /><p>저장된 설정을 확인하고 있어요.</p></main>;
  }

  if (!settings || isEditing) {
    return <SchoolSetup initialSettings={settings} onSave={save} onCancel={settings ? () => setIsEditing(false) : undefined} />;
  }

  return <TimetableView settings={settings} onChangeSettings={() => setIsEditing(true)} />;
}
