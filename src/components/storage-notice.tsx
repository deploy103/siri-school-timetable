export function StorageNotice({ unavailable }: { unavailable: boolean }) {
  if (!unavailable) return null;
  return (
    <p className="page-shell storage-notice" role="status">
      브라우저 저장소를 사용할 수 없어 설정은 현재 화면에서만 유지됩니다. 다시 열면 변경 내용이 유지되지 않을 수 있어요.
    </p>
  );
}
