import Foundation
import Testing
@testable import PokyhCore

// The shape WebUntis' class picker answers with (timetable/filter?resourceType=CLASS), names made up.
nonisolated(unsafe) private let filter: [String: Any] = [
    "resourceType": "CLASS",
    "preSelected": ["id": 1962, "shortName": "4.BFS-FI", "displayName": "4.BFS-FI"] as [String: Any],
    "departments": [["id": 2, "shortName": "V", "longName": "Vollzeit"] as [String: Any]],
    "classes": [[
        "class": ["id": 1962, "shortName": "4.BFS-FI", "longName": "4.Berufsfachschule Fachinformatik / KL Huber Anna"] as [String: Any],
        "classTeacher1": ["id": 31, "shortName": "Hu-An", "longName": "Huber Anna", "displayName": "Huber Anna (Hu-An)"] as [String: Any],
        "classTeacher2": ["id": 69, "shortName": "Ko-Ma", "longName": "Kofler Martin", "displayName": "Kofler Martin (Ko-Ma)"] as [String: Any],
    ] as [String: Any]],
]

private struct Person: Equatable {
    var id: Int
    var name: String
}

private func pick(_ people: [Person], _ teachers: ClassTeachers?) -> Int? {
    ClassTeacherPick.pick(people, name: \.name, teachers: teachers)?.id
}

struct ClassTeacherTests {
    @Test func readsClassTeacherAndDeputy() {
        #expect(ClassTeacherPick.read(filter) == ClassTeachers(
            first: NamedTeacher(shortName: "Hu-An", longName: "Huber Anna"),
            second: NamedTeacher(shortName: "Ko-Ma", longName: "Kofler Martin")))
    }

    @Test func picksThePreselectedClassAmongMany() {
        let many: [String: Any] = [
            "preSelected": ["id": 7],
            "classes": [
                ["class": ["id": 5], "classTeacher1": ["shortName": "Ot-He", "longName": "Other Hedwig"]] as [String: Any],
                ["class": ["id": 7], "classTeacher1": ["shortName": "Hu-An", "longName": "Huber Anna"]] as [String: Any],
            ],
        ]
        #expect(ClassTeacherPick.read(many) == ClassTeachers(first: NamedTeacher(shortName: "Hu-An", longName: "Huber Anna"), second: nil))
    }

    @Test func noOwnClassIsNil() {
        #expect(ClassTeacherPick.read(nil) == nil)
        #expect(ClassTeacherPick.read(["classes": [Any]()]) == nil)
        #expect(ClassTeacherPick.read(["classes": [["class": ["id": 1]], ["class": ["id": 2]]]]) == nil)
    }

    @Test func onlyTheClassTeacherNeverTheDeputy() {
        // Sorted by name, as WebUntis lists them: the deputy comes first here.
        let people = [Person(id: 880, name: "Kofler Martin, Martin (Ko-Ma)"), Person(id: 837, name: "Huber Anna, Anna (Hu-An)")]
        #expect(pick(people, ClassTeacherPick.read(filter)) == 837)
    }

    @Test func matchesByLongNameWithoutShortName() {
        let people = [Person(id: 880, name: "Ebner Lukas, Lukas (Eb-Lu)"), Person(id: 837, name: "Huber Anna, Anna (Hu-An)")]
        #expect(pick(people, ClassTeachers(first: NamedTeacher(shortName: "", longName: "Huber Anna"), second: nil)) == 837)
        #expect(!ClassTeacherPick.names("Huberth Anna, Anna (Hb-An)", NamedTeacher(shortName: "", longName: "Huber Anna")))
    }

    @Test func theOneLeftOnceTheDeputyIsOut() {
        let people = [Person(id: 880, name: "Kofler Martin, Martin (Ko-Ma)"), Person(id: 900, name: "Unbekannt Name, Name (Un-Na)")]
        #expect(pick(people, ClassTeacherPick.read(filter)) == 900)
    }

    @Test func nobodyWhenItCannotBeTold() {
        let two = [Person(id: 880, name: "Ebner Lukas, Lukas (Eb-Lu)"), Person(id: 837, name: "Huber Anna, Anna (Hu-An)")]
        #expect(pick(two, nil) == nil)
        #expect(pick([Person(id: 880, name: "Kofler Martin, Martin (Ko-Ma)")], ClassTeacherPick.read(filter)) == nil)
        #expect(pick([], ClassTeacherPick.read(filter)) == nil)
    }

    @Test func aSingleClassTeacherStandsWithoutThePicker() {
        #expect(pick([Person(id: 837, name: "Huber Anna, Anna (Hu-An)")], nil) == 837)
    }
}
