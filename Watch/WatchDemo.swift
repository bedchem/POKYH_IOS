#if DEBUG
import Foundation
import PokyhCore

/// A made-up day for screenshots and design work, started with `-POKYHWatchDemo YES`: no phone,
/// no Keychain, no network. `-POKYHWatchDemoLater 300` acts that many minutes later, here past
/// the last lesson, so the next school day shows. `-POKYHWatchDemoPhoto <url>` gives the dishes
/// a photo. Debug builds only.
enum WatchDemo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "POKYHWatchDemo") }
    private static var later: Int { UserDefaults.standard.integer(forKey: "POKYHWatchDemoLater") }

    static let account = StoredAccount(
        username: "anna",
        displayName: "Anna Rossi",
        school: School(loginName: "stub-school", server: "stub-school.invalid", name: "Teststadt Schule"),
        secret: ""
    )

    static func snapshot(now: Date = .now, calendar: Calendar = .current) -> WatchSnapshot {
        let day = calendar.startOfDay(for: now)
        let later = later
        func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval((minutes - later) * 60)) }
        let nextDate = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        func next(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: nextDate) ?? nextDate
        }
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

        let nextLessons = [
            WatchSnapshot.Lesson(id: "n1", subject: "D", subjectLong: "Deutsch", teacher: "BER", room: "2.05",
                                 start: next(7, 50), end: next(8, 40)),
            WatchSnapshot.Lesson(id: "n2", subject: "M", subjectLong: "Mathematik", teacher: "MUE", room: "2.05",
                                 start: next(8, 40), end: next(9, 30), status: .exam),
            WatchSnapshot.Lesson(id: "n3", subject: "GEO", subjectLong: "Geografie", teacher: "PIR", room: "2.05",
                                 start: next(9, 45), end: next(10, 35)),
            WatchSnapshot.Lesson(id: "n4", subject: "ENGL", subjectLong: "Englisch", teacher: "SCH", room: "1.12",
                                 start: next(10, 35), end: next(11, 25)),
            WatchSnapshot.Lesson(id: "n5", subject: "BIO", subjectLong: "Biologie", teacher: "WAL", room: "Labor",
                                 start: next(11, 30), end: next(12, 20)),
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

        let photo = UserDefaults.standard.string(forKey: "POKYHWatchDemoPhoto").flatMap(URL.init(string:))
        let dishes = [
            WatchSnapshot.Dish(id: "d1", name: "Spaghetti mit Tomatensauce", category: "Hauptgericht", tags: ["vegetarisch"],
                               stars: 4.5, ratings: 12, photo: photo,
                               text: "Mit frischem Basilikum und Parmesan.", price: 4.5, calories: 640),
            WatchSnapshot.Dish(id: "d2", name: "Wiener Schnitzel mit Pommes", category: "Hauptgericht", stars: 4, ratings: 9,
                               photo: photo, price: 5.2, calories: 890),
            WatchSnapshot.Dish(id: "d3", name: "Gemischter Salat", category: "Beilage", tags: ["vegan"]),
        ]

        let todos = [
            WatchSnapshot.Todo(id: "t1", title: "Mathe lernen", due: calendar.date(byAdding: .day, value: 1, to: now)),
            WatchSnapshot.Todo(id: "t2", title: "Buch kaufen"),
            WatchSnapshot.Todo(id: "t3", title: "Referat vorbereiten", due: calendar.date(byAdding: .day, value: 3, to: now)),
            WatchSnapshot.Todo(id: "t4", title: "Unterschrift holen", done: true),
        ]

        return WatchSnapshot(username: account.username, updatedAt: now, day: day, lessons: lessons,
                             nextDay: WatchSnapshot.SchoolDay(date: nextDate, lessons: nextLessons),
                             overallAverage: 7.5, gradeCount: grades.count, subjects: subjects,
                             recentGrades: grades.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) },
                             mensaDay: day, dishes: dishes, todos: todos)
    }
}
#endif
