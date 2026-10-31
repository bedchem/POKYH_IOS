import Foundation
import Testing
@testable import PokyhCore

private func fixture(_ name: String) throws -> Any {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
}

private struct Entry: ClassregRecord, Equatable {
    var createDate: Int
    var subjectName = ""
    var categoryName = ""
}

private let calendar = Calendar(identifier: .gregorian)
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!

struct ClassServicesTests {
    @Test func eachPersonDutyOnce() throws {
        let services = ClassServices.read(try fixture("classservices"))
        #expect(services.map(\.duty) == ["Klassensprecher", "Tafeldienst", "Klassensprecher", "Klassensprecher"])
        #expect(services[0].personName == "Anna Rossi")
        // No first name is no leading space.
        #expect(services[2].personName == "Bianchi")
    }

    @Test func aParentOnlySeesTheChildsClass() throws {
        let services = ClassServices.read(try fixture("classservices"), klasseId: 11)
        #expect(services.map(\.id) == [1, 3, 4])
    }

    @Test func aClassNobodyIsInStillShowsTheList() throws {
        // A wrongly resolved class mustn't make every duty disappear.
        #expect(ClassServices.read(try fixture("classservices"), klasseId: 999).count == 4)
    }

    @Test func nothingUsableGivesNothing() {
        #expect(ClassServices.read(nil).isEmpty)
        #expect(ClassServices.read(["data": ["classRoles": "x"]]).isEmpty)
    }
}

struct HomeworkListTests {
    @Test func readsTheHomeworkWithItsSubject() throws {
        let items = HomeworkList.read(try fixture("homeworks-lessons"))
        #expect(items.map(\.id) == [1, 2, 3, 4, 5])
        #expect(items[0].subject == "Mathematik")
        #expect(items[0].text == "Seite 12")
        #expect(items[1].subject == "Deutsch")
        #expect(items[1].text == "Aufsatz & Skizze")
        #expect(items[3].subject.isEmpty)
        #expect(items[3].completed)
        #expect(items[4].dueDate == 0)
    }

    @Test func aParentOnlySeesTheChildsHomework() throws {
        let items = HomeworkList.read(try fixture("homeworks-lessons"), childId: 500, klasseId: 11)
        // 3 belongs to someone else; 4 and 5 have no record to say so.
        #expect(items.map(\.id) == [1, 2, 4, 5])
    }

    @Test func recordsThatDontNameTheChildFilterNothing() throws {
        // These records count something else, so they can't decide anything.
        let items = HomeworkList.read(try fixture("homeworks-lessons"), childId: 12345, klasseId: 54321)
        #expect(items.count == 5)
    }

    @Test func aStudentIsNeverFiltered() throws {
        #expect(HomeworkList.read(try fixture("homeworks-lessons"), klasseId: 11).count == 5)
    }

    @Test func openHomeworkSoonestFirstSplitByWeek() throws {
        let open = HomeworkList.open(HomeworkList.read(try fixture("homeworks-lessons")))
        #expect(open.map(\.id) == [3, 1, 2])
        #expect(HomeworkList.due(open, from: 20261102, before: 20261109).map(\.id) == [3, 1])
        #expect(HomeworkList.due(open, from: 20261109, before: 20261116).map(\.id) == [2])
    }

    @Test func survivesTheDiskCache() throws {
        let items = HomeworkList.read(try fixture("homeworks-lessons"))
        #expect(try JSONDecoder().decode([HomeworkItem].self, from: JSONEncoder().encode(items)) == items)
    }
}

struct ClassregGroupingTests {
    private let entries = [
        Entry(createDate: 20260915, subjectName: "M", categoryName: "Vermerk"),
        Entry(createDate: 20261020, subjectName: "D", categoryName: ""),
        Entry(createDate: 20261005, subjectName: "", categoryName: "Vermerk"),
        Entry(createDate: 20260710, subjectName: "m", categoryName: "Täuschung"),
    ]

    private func groups(_ range: ClassregRange, _ sort: ClassregSort) -> [ClassregGroup<Entry>] {
        ClassregGrouping.groups(entries, range: range, sort: sort, noCategory: "Ohne", today: today, calendar: calendar)
    }

    @Test func rangesCutOffByMonth() {
        #expect(ClassregGrouping.cutoff(.all, today: today, calendar: calendar) == 0)
        #expect(ClassregGrouping.cutoff(.month, today: today, calendar: calendar) == 20260930)
        #expect(ClassregGrouping.cutoff(.months3, today: today, calendar: calendar) == 20260731)
        #expect(groups(.month, .dateDesc).flatMap(\.items).map(\.createDate) == [20261020, 20261005])
        #expect(groups(.months3, .dateDesc).flatMap(\.items).count == 3)
        #expect(groups(.all, .dateDesc).flatMap(\.items).count == 4)
    }

    @Test func datesGroupByMonthNewestFirst() {
        let list = groups(.all, .dateDesc)
        #expect(list.map(\.key) == ["202610", "202609", "202607"])
        #expect(list[0].items.map(\.createDate) == [20261020, 20261005])
    }

    @Test func oldestFirstReversesTheMonths() {
        let list = groups(.all, .dateAsc)
        #expect(list.map(\.key) == ["202607", "202609", "202610"])
        #expect(list[2].items.map(\.createDate) == [20261005, 20261020])
    }

    @Test func subjectsGroupByNameCaseSensitiveButSortedWithout() {
        #expect(groups(.all, .subject).map(\.key) == ["-", "D", "M", "m"])
    }

    @Test func categoriesNameTheEmptyOne() {
        let list = groups(.all, .category)
        #expect(list.map(\.key) == ["Ohne", "Täuschung", "Vermerk"])
        #expect(list[2].items.map(\.createDate) == [20261005, 20260915])
    }

    @Test func theClassPageTakesTheNewestFive() {
        let many = (1...9).map { Entry(createDate: 20261000 + $0) } + [Entry(createDate: 20260101)]
        let recent = ClassregGrouping.recent(many, today: today, calendar: calendar)
        #expect(recent.map(\.createDate) == [20261009, 20261008, 20261007, 20261006, 20261005])
    }
}
