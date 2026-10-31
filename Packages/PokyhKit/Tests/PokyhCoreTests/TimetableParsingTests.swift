import Foundation
import Testing
@testable import PokyhCore

private func fixture(_ name: String) throws -> Any {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
}

struct PeriodExtrasTests {
    private func gridEntries() throws -> [Any] {
        let root = try #require(try fixture("timetable-entries") as? [String: Any])
        let days = try #require(root["days"] as? [[String: Any]])
        return try #require(days[0]["gridEntries"] as? [Any])
    }

    @Test func readsWhatChangedOnTheCurrentValue() throws {
        let extras = PeriodExtras.read(try gridEntries()[0])
        #expect(extras.addedTeachers == ["SCH"])
        #expect(extras.addedSubjects.isEmpty)
        // Only the room it gained, not the one it always had.
        #expect(extras.addedRooms == ["Inf VI"])
        #expect(extras.icons == ["HOMEWORK", "attachment"])
    }

    @Test func prefersStructuredTextsButFallsBackToTheFlatField() throws {
        let entries = try gridEntries()
        let structured = PeriodExtras.read(entries[0])
        #expect(structured.lessonInfo == "Buch mitnehmen")
        #expect(structured.substitutionText == "statt Müller")
        // Blank in `texts`, there in the flat field.
        #expect(structured.lessonText == "Kapitel 4")
        #expect(structured.texts.map(\.type) == ["LESSON_INFO", "SUBSTITUTION", "EXTRA"])
        #expect(structured.texts.last?.text == "Zusatz & mehr")

        let flat = PeriodExtras.read(entries[1])
        #expect(flat.lessonInfo == "Nur die flache Form")
        #expect(flat.substitutionText == nil)
        #expect(flat.texts.isEmpty)
    }

    @Test func nothingUsableGivesEmptyExtras() {
        #expect(PeriodExtras.read(nil) == PeriodExtras())
        #expect(PeriodExtras.read("kein Objekt") == PeriodExtras())
    }

    @Test func marksAreMatchedLoosely() {
        #expect(LessonMark(untisName: "homeworkGiven") == .homework)
        #expect(LessonMark(untisName: "HOMEWORK_DUE") == .homework)
        #expect(LessonMark(untisName: "exam") == .exam)
        #expect(LessonMark(untisName: "attachment") == .attachment)
        #expect(LessonMark(untisName: "stand_in") == .substitution)
        #expect(LessonMark(untisName: "VIDEO_CALL") == .online)
        #expect(LessonMark(untisName: "classreg") == .classRegister)
        #expect(LessonMark(untisName: "LESSON_INFO") == .note)
        #expect(LessonMark(untisName: "somethingNew") == .unknown)
    }
}

struct FieldChangesTests {
    @Test func anEchoedOriginalIsNoChange() {
        #expect(!FieldChanges.changed(current: "2.05", original: " 2.05 ", added: []))
        #expect(!FieldChanges.changed(current: "2.05", original: "", added: []))
        #expect(!FieldChanges.changed(current: "2.05", original: nil, added: []))
        #expect(FieldChanges.changed(current: "2.05", original: "1.12", added: []))
        #expect(FieldChanges.changed(current: "2.05", original: nil, added: ["2.05"]))
    }

    @Test func onlyTheAddedPartIsMarkedAndItComesFirst() {
        let parts = FieldChanges.parts(current: "a+2/05, Inf VI", added: ["Inf VI"], original: nil)
        #expect(parts == [FieldPart("Inf VI", .added), FieldPart("a+2/05")])
    }

    @Test func aSwapMarksBothHalves() {
        let parts = FieldChanges.parts(current: "SCH", added: [], original: "MUE")
        #expect(parts == [FieldPart("SCH", .added), FieldPart("MUE", .removed)])
    }

    @Test func aTeacherWhoLeftWithoutReplacementShows() {
        let parts = FieldChanges.parts(current: "BER", added: [], original: "BER, MUE")
        #expect(parts == [FieldPart("MUE", .removed), FieldPart("BER")])
    }

    @Test func aDenseCellDropsUnchangedPartsOnlyWhenSomethingChanged() {
        #expect(FieldChanges.parts(current: "A, B", added: ["B"], original: nil, dense: true) == [FieldPart("B", .added)])
        #expect(FieldChanges.parts(current: "A, B", added: [], original: nil, dense: true) == [FieldPart("A"), FieldPart("B")])
    }

    @Test func theSheetUsesLongNamesAndTheDetailsHistory() {
        let history = [
            LessonDetail.Element(name: "SCH", shortName: "SCH", longName: "Schmid Anna", status: "SUBSTITUTED"),
            LessonDetail.Element(name: "MUE", shortName: "MUE", longName: "Müller Hans", status: "REMOVED"),
            LessonDetail.Element(name: "BER", shortName: "BER", longName: "Berger Eva", status: "REGULAR"),
        ]
        // The timetable alone doesn't know anything changed here.
        let parts = FieldChanges.detailParts(current: "SCH, BER", currentLong: "Schmid Anna, Berger Eva", added: [], original: nil, history: history)
        #expect(parts == [FieldPart("Schmid Anna", .added), FieldPart("Müller Hans", .removed), FieldPart("Berger Eva")])
    }

    @Test func longNamesAreOnlyTakenWhenTheyLineUp() {
        // A long name with a comma doesn't line up with its short one.
        let parts = FieldChanges.detailParts(current: "SCH", currentLong: "Schmid, Anna", added: ["SCH"], original: nil)
        #expect(parts == [FieldPart("SCH", .added)])
        let swapped = FieldChanges.detailParts(current: "SCH", currentLong: "Schmid Anna", added: [], original: "MUE", originalLong: "Müller Hans")
        #expect(swapped == [FieldPart("Schmid Anna", .added), FieldPart("Müller Hans", .removed)])
    }

    @Test func statusesAreReadBySense() {
        #expect(LessonDetail.Element(name: "x", status: "REGULAR").mark == .plain)
        #expect(LessonDetail.Element(name: "x", status: "").mark == .plain)
        #expect(LessonDetail.Element(name: "x", status: "REMOVED").mark == .removed)
        #expect(LessonDetail.Element(name: "x", status: "cancelled").mark == .removed)
        #expect(LessonDetail.Element(name: "x", status: "SUBSTITUTED").mark == .added)
        #expect(LessonDetail.Element(name: "x", status: "ADDED").mark == .added)
    }
}

struct LessonDetailTests {
    @Test func readsEveryPartOfTheDetail() throws {
        let detail = try #require(LessonDetail.read(try fixture("calendar-entry-detail"), lessonId: 901))
        #expect(detail.texts == [
            .init(kind: .teachingContent, text: "Quadratische Gleichungen\nSeite 42"),
            .init(kind: .teacherNote, text: "Taschenrechner & Heft"),
            .init(kind: .lessonInfo, text: "Buch mitnehmen"),
            .init(kind: .substitution, text: "statt Müller"),
        ])
        #expect(detail.classes == ["4A", "4B"])
        #expect(detail.group == "Gruppe 1")
        #expect(detail.examName == "Schularbeit")
        #expect(detail.examDescription == "Kapitel 3 und 4")
        // Rich text gone, blank dropped, the same homework from the other entry only once.
        #expect(detail.homeworks == ["Seite 12,\nAufgabe 3"])
    }

    @Test func historyComesFromTheLessonsOwnEntry() throws {
        let root = try fixture("calendar-entry-detail")
        let detail = try #require(LessonDetail.read(root, lessonId: 901))
        #expect(detail.teachers.map(\.name) == ["SCH", "MUE"])
        #expect(detail.teachers[1].mark == .removed)
        #expect(detail.teachers[0].longName == "Schmid Anna")
        #expect(detail.rooms.map(\.name) == ["Inf VI"])

        // Several entries and none is this lesson: whose history would it be?
        let unknown = try #require(LessonDetail.read(root, lessonId: 1))
        #expect(unknown.teachers.isEmpty)
        #expect(unknown.rooms.isEmpty)
        #expect(!unknown.homeworks.isEmpty)
    }

    @Test func aSingleEntryIsTheLessonEvenWithAnotherId() {
        let root: [String: Any] = ["calendarEntries": [["id": 5, "teachers": [["displayName": "ABC", "status": "REGULAR"]]]]]
        #expect(LessonDetail.read(root, lessonId: 1)?.teachers.map(\.name) == ["ABC"])
    }

    @Test func notADetailIsNil() {
        #expect(LessonDetail.read(nil, lessonId: 1) == nil)
        #expect(LessonDetail.read(["error": "nope"], lessonId: 1) == nil)
        #expect(LessonDetail.read(["calendarEntries": []], lessonId: 1) == LessonDetail())
    }

    @Test func survivesTheDiskCache() throws {
        let detail = try #require(LessonDetail.read(try fixture("calendar-entry-detail"), lessonId: 901))
        let copy = try JSONDecoder().decode(LessonDetail.self, from: JSONEncoder().encode(detail))
        #expect(copy == detail)
    }

    @Test func queryTimesAreEncodedAndPadded() {
        #expect(LessonDetail.queryTime(date: 20261103, time: 750) == "2026-11-03T07%3A50%3A00")
        #expect(LessonDetail.queryTime(date: 20261103, time: 1405) == "2026-11-03T14%3A05%3A00")
    }

    @Test func notesAppearOnceUnderTheirOwnHeading() throws {
        let detail = LessonDetail(texts: [
            .init(kind: .teachingContent, text: "Lehrstoff"),
            .init(kind: .lessonInfo, text: "BUCH   mitnehmen"),
            .init(kind: .teacherNote, text: "Heft"),
        ])
        let notes = LessonNotes.collect(note: "Buch mitnehmen", lessonText: " Kapitel 4 ", substitutionText: nil, detail: detail, texts: [
            PeriodText(type: "LESSON_INFO", text: "Buch mitnehmen"),
            PeriodText(type: "SUBSTITUTION", text: "statt Müller"),
            PeriodText(type: "OTHER", text: "Zusatz"),
        ])
        #expect(notes == [
            LessonNote(.note, "Buch mitnehmen"),
            LessonNote(.lessonText, "Kapitel 4"),
            LessonNote(.teachingContent, "Lehrstoff"),
            LessonNote(.teacherNote, "Heft"),
            LessonNote(.substitution, "statt Müller"),
            LessonNote(.info, "Zusatz"),
        ])
    }

    @Test func examTextTakesTheTimetablesDescriptionFirst() {
        let detail = LessonDetail(examName: "Schularbeit", examDescription: "aus dem Detail")
        #expect(LessonNotes.examText(detail: detail, description: "aus dem Stundenplan") == "Schularbeit\naus dem Stundenplan")
        #expect(LessonNotes.examText(detail: detail, description: nil) == "Schularbeit\naus dem Detail")
        #expect(LessonNotes.examText(detail: nil, description: nil).isEmpty)
    }

    @Test func extraLabelsExistInEveryLanguage() {
        for lang in Lang.allCases {
            let labels = Strings.of(lang).lessonExtras
            #expect(!labels.teachingContent.isEmpty)
            #expect(!labels.teacherNote.isEmpty)
        }
    }
}

struct TimetableFilterTests {
    @Test func classesNestedPerEntryDepartmentsLeftOutSortedByNumber() throws {
        let items = TimetableFilter.read(try fixture("timetable-filter"))
        #expect(items.map(\.name) == ["2.A", "4.BFS-FI", "10.B"])
        // Its long name only comes with the other mention, whichever is read first.
        #expect(items.first { $0.id == 1962 }?.longName == "4. Fachschule Informatik")
        #expect(items.first { $0.id == 1963 }?.longName == "Zweite A")
        #expect(!items.contains { $0.id == 9 })
        #expect(!items.contains { $0.id == 4242 })
    }

    @Test func nothingUsableGivesAnEmptyList() {
        #expect(TimetableFilter.read(nil).isEmpty)
        #expect(TimetableFilter.read(["classes": []]).isEmpty)
        #expect(TimetableFilter.read([["id": "x", "name": "y"]]).isEmpty)
    }

    @Test func searchLooksAtBothNamesAndIgnoresAccents() {
        let room = TimetableResource(id: 1, name: "Inf VI", longName: "Größerer Saal")
        #expect(room.matches(""))
        #expect(room.matches("inf"))
        #expect(room.matches("grosser"))
        #expect(room.matches("saal"))
        #expect(!room.matches("turnhalle"))
        #expect(TimetableResource(id: 2, name: "Müller").matches("muller"))
    }

    @Test func sourceMapsOntoWebUntisElements() {
        #expect(TimetableKind.klass.elementType == 1)
        #expect(TimetableKind.teacher.elementType == 2)
        #expect(TimetableKind.room.elementType == 4)
        #expect(TimetableKind.klass.rawValue == "CLASS")
        #expect(TimetableSource(kind: .room, id: 7, name: "2.05").key == "ROOM7")
    }
}

struct SubjectImageKeysTests {
    @Test func keysMatchTheWeb() {
        #expect(SubjectImageKeys.key(long: " Mathematik ", short: "M") == "mathematik")
        #expect(SubjectImageKeys.key(long: "  ", short: "M") == "m")
    }

    @Test func listIsNormalised() {
        let data = Data(#"[{"subject":"Mathematik"},{"subject":" deutsch "},{"other":1},{"subject":""}]"#.utf8)
        #expect(SubjectImageKeys.read(data) == ["mathematik", "deutsch"])
        #expect(SubjectImageKeys.read(Data("kein json".utf8)).isEmpty)
    }

    @Test func pathsAreFullyEncoded() {
        #expect(SubjectImageKeys.path(for: "bew. sport/ä") == "/subject-images/bew.%20sport%2F%C3%A4")
    }

    @Test func reportStaysWithinTheRoutesLimits() {
        let many = (0..<150).map { (short: "S\($0)", long: "Fach \($0)") }
        #expect(SubjectImageKeys.report(many).count == 100)

        let rows = SubjectImageKeys.report([
            (short: "M", long: "Mathematik"),
            (short: "M2", long: "mathematik"),
            (short: "", long: ""),
            (short: "D", long: ""),
        ])
        #expect(rows == [
            ["key": "mathematik", "longName": "Mathematik", "shortName": "M"],
            ["key": "d", "longName": "D", "shortName": "D"],
        ])
    }
}
