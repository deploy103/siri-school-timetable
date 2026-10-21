import Foundation

struct TeacherNote: Codable, Identifiable, Equatable {
    let id: UUID
    let selection: String
    var subject: String
    var teacherName: String
    var room: String
    var memo: String

    fileprivate func validated() throws -> TeacherNote {
        var value = self
        value.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        value.teacherName = teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        value.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty, !value.subject.isEmpty, !value.teacherName.isEmpty,
              subject.count <= 80, teacherName.count <= 80, room.count <= 80, memo.count <= 2000 else {
            throw SchoolError.message("과목·선생님 이름은 필수이며 각각 80자까지예요. 교실은 80자, 메모는 2,000자까지 입력해 주세요.")
        }
        return value
    }
}

/// Every mutation reads and validates the current archive before writing. A damaged or
/// newer archive is never treated as an empty collection, including after an earlier load.
struct TeacherNotesArchive {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolToday", isDirectory: true)
    }

    private struct Archive: Codable {
        var version = 1
        var notes: [TeacherNote] = []
    }

    private var url: URL { directory.appendingPathComponent("teacher-notes-v1.json") }

    private func read() throws -> Archive {
        guard FileManager.default.fileExists(atPath: url.path) else { return Archive() }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1, Set(archive.notes.map(\.id)).count == archive.notes.count else {
            throw SchoolError.message("개인 메모 기록을 읽을 수 없어요. 기존 파일은 변경하지 않았어요.")
        }
        for note in archive.notes { _ = try note.validated() }
        return archive
    }

    func notes(for settings: SchoolSettings) throws -> [TeacherNote] {
        try read().notes.filter { $0.selection == settings.planningKey }
    }

    @discardableResult
    func save(id: UUID? = nil, subject: String, teacherName: String, room: String = "", memo: String = "", for settings: SchoolSettings) throws -> TeacherNote {
        var archive = try read()
        let note = try TeacherNote(id: id ?? UUID(), selection: settings.planningKey,
                                   subject: subject, teacherName: teacherName, room: room, memo: memo).validated()
        if let id {
            guard let index = archive.notes.firstIndex(where: { $0.id == id && $0.selection == settings.planningKey }) else {
                throw SchoolError.message("수정할 개인 메모를 찾지 못했어요. 목록을 다시 열어 주세요.")
            }
            archive.notes[index] = note
        } else { archive.notes.append(note) }
        try write(archive)
        return note
    }

    func delete(id: UUID, for settings: SchoolSettings) throws {
        var archive = try read()
        archive.notes.removeAll { $0.id == id && $0.selection == settings.planningKey }
        try write(archive)
    }

    private func write(_ archive: Archive) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(archive).write(to: url, options: options)
    }
}

#if canImport(SwiftUI)
import SwiftUI

struct TeacherNotesView: View {
    let settings: SchoolSettings
    private let archive = TeacherNotesArchive()
    @State private var notes: [TeacherNote] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var draft: TeacherNote?

    var body: some View {
        List {
            Section {
                Text("이 기기에 저장하는 개인 메모예요. 직접 입력한 내용이며 공식 선생님 명단이나 학교 전체 공유 자료가 아니에요. 연락처 등 민감한 정보는 적지 마세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(settings.school.name).font(.headline)
            }
            Section("과목·선생님 메모") {
                if loaded && notes.isEmpty { Text("과목과 선생님, 교실을 직접 기록해 보세요.").foregroundStyle(.secondary) }
                ForEach(notes) { note in
                    Button {
                        draft = note
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.subject).font(.headline)
                            Text("\(note.teacherName) 선생님" + (note.room.isEmpty ? "" : " · \(note.room)"))
                            if !note.memo.isEmpty { Text(note.memo).font(.footnote).foregroundStyle(.secondary) }
                        }.foregroundStyle(SchoolDesign.ink)
                    }
                    .swipeActions {
                        Button("삭제", role: .destructive) {
                            do { try archive.delete(id: note.id, for: settings); reload() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            Section {
                Button("개인 메모 추가") {
                    draft = TeacherNote(id: UUID(), selection: settings.planningKey, subject: "", teacherName: "", room: "", memo: "")
                }.buttonStyle(SchoolPrimaryButtonStyle()).disabled(!loaded)
                if !loaded { Button("다시 읽기", action: reload) }
            }
        }
        .scrollContentBackground(.hidden).background(SchoolDesign.canvas)
        .navigationTitle("개인 선생님 메모")
        .task(id: settings.planningKey) { draft = nil; reload() }
        .sheet(item: $draft) { note in
            TeacherNoteEditor(note: note) { edited in
                _ = try archive.save(id: notes.contains(where: { $0.id == edited.id }) ? edited.id : nil,
                                     subject: edited.subject, teacherName: edited.teacherName,
                                     room: edited.room, memo: edited.memo, for: settings)
                reload()
            }
        }
        .alert("개인 메모를 확인해 주세요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func reload() {
        do { notes = try archive.notes(for: settings); loaded = true }
        catch { notes = []; loaded = false; self.error = "기존 기록을 변경하지 않았어요. \(error.localizedDescription)" }
    }
}

private struct TeacherNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var note: TeacherNote
    let save: (TeacherNote) throws -> Void
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case subject, teacher, room, memo }

    var body: some View {
        NavigationStack {
            Form {
                Section("직접 입력 · 이 기기 개인 메모") {
                    TextField("과목 (필수, 80자까지)", text: $note.subject)
                        .focused($focusedField, equals: .subject).submitLabel(.next)
                        .onSubmit { focusedField = .teacher }
                    TextField("선생님 이름 (필수, 80자까지)", text: $note.teacherName)
                        .focused($focusedField, equals: .teacher).submitLabel(.next)
                        .onSubmit { focusedField = .room }
                    TextField("교실 (80자까지)", text: $note.room)
                        .focused($focusedField, equals: .room).submitLabel(.next)
                        .onSubmit { focusedField = .memo }
                    TextField("메모 (선택, 2,000자까지)", text: $note.memo, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focusedField, equals: .memo)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("저장") {
                    do { try save(note); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(SchoolPrimaryButtonStyle())
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    Button { focusedField = nil } label: {
                        Text("입력 완료")
                            .foregroundStyle(SchoolDesign.blue)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            .background(SchoolDesign.canvas)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("teacher-note-input-done")
                }
            }
            .navigationTitle("개인 메모 편집")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}
#endif
