#if DEBUG
import Foundation
import PokyhCore

/// A made-up day for screenshots and design work, started with `-POKYHWatchDemo YES`: no phone,
/// no Keychain, no network. Debug builds only.
enum WatchDemo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "POKYHWatchDemo") }

    static let account = StoredAccount(
        username: "anna",
        displayName: "Anna Rossi",
        school: School(loginName: "stub-school", server: "stub-school.invalid", name: "Teststadt Schule"),
        secret: ""
    )

    static func snapshot(now: Date = .now, calendar: Calendar = .current) -> WatchSnapshot {
        let day = calendar.startOfDay(for: now)
        func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }
        func dayAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now) ?? now }

        let lessons = [
            WatchSnapshot.Lesson(id: "1", subject: "R", subjectLong: "Religion", teacher: "VER", room: "2.05",
                                 start: at(-80), end: at(-30)),
            WatchSnapshot.Lesson(id: "2", subject: "M", subjectLong: "Mathematik", teacher: "MUE", room: "2.05",
                                 start: at(-25), end: at(25)),
            WatchSnapshot.Lesson(id: "3", subject: "D", subjectLong: "Deutsch", teacher: "BER", room: "2.05",
                                 start: at(30), end: at(80)),
            WatchSnapshot.Lesson(id: "4", subject: "ENGL", subjectLong: "Englisch", teacher: "SCH", room: "1.12",
                                 start: at(95), end: at(145), status: .roomChange, originalRoom: "2.05"),
            WatchSnapshot.Lesson(id: "5", subject: "IT", subjectLong: "Italienisch", teacher: "VER", room: "2.05",
                                 start: at(150), end: at(200), status: .substitution, originalTeacher: "ROS"),
            WatchSnapshot.Lesson(id: "6", subject: "SPO", subjectLong: "Sport", teacher: "KOF", room: "Halle",
                                 start: at(205), end: at(255), status: .cancelled),
        ]

        let grades = [
            WatchSnapshot.Grade(id: 1, subject: "Englisch", value: 10, date: dayAgo(3), text: "Vokabeltest"),
            WatchSnapshot.Grade(id: 2, subject: "Mathematik", value: 7.5, date: dayAgo(6), text: "Schularbeit"),
            WatchSnapshot.Grade(id: 3, subject: "Deutsch", value: 6.5, date: dayAgo(10), text: "Aufsatz"),
            WatchSnapshot.Grade(id: 4, subject: "Mathematik", value: 8, date: dayAgo(20), text: "Test"),
            WatchSnapshot.Grade(id: 5, subject: "Deutsch", value: 7, date: dayAgo(30), text: "Referat"),
            WatchSnapshot.Grade(id: 6, subject: "Italienisch", value: 5.5, date: dayAgo(14), text: "Test"),
        ]
        let subjects = [
            WatchSnapshot.SubjectAverage(name: "Englisch", average: 10, count: 1, grades: grades.filter { $0.subject == "Englisch" }),
            WatchSnapshot.SubjectAverage(name: "Mathematik", average: 7.75, count: 2, grades: grades.filter { $0.subject == "Mathematik" }),
            WatchSnapshot.SubjectAverage(name: "Deutsch", average: 6.75, count: 2, grades: grades.filter { $0.subject == "Deutsch" }),
            WatchSnapshot.SubjectAverage(name: "Italienisch", average: 5.5, count: 1, grades: grades.filter { $0.subject == "Italienisch" }),
        ]

        let dishes = [
            WatchSnapshot.Dish(id: "d1", name: "Spaghetti mit Tomatensauce", category: "Hauptgericht", tags: ["vegetarisch"],
                               stars: 4.5, ratings: 12),
            WatchSnapshot.Dish(id: "d2", name: "Wiener Schnitzel mit Pommes", category: "Hauptgericht", stars: 4, ratings: 9),
            WatchSnapshot.Dish(id: "d3", name: "Gemischter Salat", category: "Beilage", tags: ["vegan"]),
        ]

        let todos = [
            WatchSnapshot.Todo(id: "t1", title: "Mathe lernen", due: calendar.date(byAdding: .day, value: 1, to: now)),
            WatchSnapshot.Todo(id: "t2", title: "Buch kaufen"),
            WatchSnapshot.Todo(id: "t3", title: "Referat vorbereiten", due: calendar.date(byAdding: .day, value: 3, to: now)),
            WatchSnapshot.Todo(id: "t4", title: "Unterschrift holen", done: true),
        ]

        return WatchSnapshot(username: account.username, updatedAt: now, day: day, lessons: lessons,
                             overallAverage: 7.5, gradeCount: grades.count, subjects: subjects,
                             recentGrades: grades.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) },
                             mensaDay: day, dishes: dishes, todos: todos)
    }
}
#endif
