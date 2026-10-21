import XCTest
@testable import SchoolToday

final class TeacherNotesTests: XCTestCase {
    private func settings(_ code: String = "one") -> SchoolSettings {
        SchoolSettings(school: School(officeCode: "B10", schoolCode: code, name: "테스트 학교", kind: "고등학교", address: "서울", region: "서울"),
                       schoolClass: SchoolClass(grade: 1, className: "1", department: nil))
    }

    func testPersistenceEditingValidationAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = TeacherNotesArchive(directory: directory)
        let original = try archive.save(subject: " 수학 ", teacherName: " 김선생 ", room: " 201 ", memo: " 질문하기 ", for: settings())
        XCTAssertEqual(original.subject, "수학")
        XCTAssertEqual(original.teacherName, "김선생")
        XCTAssertEqual(original.room, "201")
        XCTAssertEqual(original.memo, "질문하기")
        XCTAssertEqual(try TeacherNotesArchive(directory: directory).notes(for: settings()), [original])
        for (subject, name, room, memo) in [
            (" ", "김", "", ""), ("수학", "\n", "", ""),
            (String(repeating: "가", count: 81), "김", "", ""),
            ("수학", String(repeating: "가", count: 81), "", ""),
            ("수학", "김", String(repeating: "가", count: 81), ""),
            ("수학", "김", "", String(repeating: "가", count: 2001))
        ] {
            XCTAssertThrowsError(try archive.save(id: original.id, subject: subject, teacherName: name, room: room, memo: memo, for: settings()))
            XCTAssertEqual(try archive.notes(for: settings()), [original])
        }
        let edited = try archive.save(id: original.id, subject: "과학", teacherName: "이선생", for: settings())
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(try archive.notes(for: settings()), [edited])
        try archive.delete(id: edited.id, for: settings())
        XCTAssertTrue(try TeacherNotesArchive(directory: directory).notes(for: settings()).isEmpty)
    }

    func testSchoolIsolationPreservesOtherNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = TeacherNotesArchive(directory: directory)
        let first = try archive.save(subject: "수학", teacherName: "김", for: settings())
        XCTAssertTrue(try archive.notes(for: settings("two")).isEmpty)
        let second = try archive.save(subject: "국어", teacherName: "이", for: settings("two"))
        XCTAssertThrowsError(try archive.save(id: first.id, subject: "변경", teacherName: "박", for: settings("two")))
        try archive.delete(id: first.id, for: settings("two"))
        XCTAssertEqual(try archive.notes(for: settings()), [first])
        XCTAssertEqual(try archive.notes(for: settings("two")), [second])
    }

    func testUnreadableOrFutureArchiveCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = TeacherNotesArchive(directory: directory)
        let note = try archive.save(subject: "수학", teacherName: "김", for: settings())
        let url = directory.appendingPathComponent("teacher-notes-v1.json")
        for fixture in ["not json", #"{"version":99,"notes":[]}"#] {
            let bytes = Data(fixture.utf8)
            try bytes.write(to: url)
            XCTAssertThrowsError(try archive.notes(for: settings()))
            XCTAssertThrowsError(try archive.save(subject: "국어", teacherName: "이", for: settings()))
            XCTAssertThrowsError(try archive.delete(id: note.id, for: settings()))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
}
