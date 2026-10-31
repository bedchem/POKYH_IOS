import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// The widget extension: Home and Lock Screen widgets plus the lesson Live Activity.
@main
struct POKYHWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        TodayScheduleWidget()
        GradesWidget()
        MessagesWidget()
        OverviewWidget()
        LessonLiveActivity()
    }
}

// ── Texts ────────────────────────────────────────────────────────────────────

/// The few widget texts the app's tables don't have.
struct WidgetStrings: Sendable {
    let unread: String
    let pause: String
    let endsIn: String
    let startsIn: String
    let locked: String
    let unlockToView: String
    let openApp: String
    let nextInfo: String
    let todayName: String
    let todayInfo: String
    let gradesInfo: String
    let messagesInfo: String
    let overviewName: String
    let overviewInfo: String

    static func of(_ lang: Lang) -> WidgetStrings {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = WidgetStrings(
        unread: "ungelesen",
        pause: "Pause",
        endsIn: "Ende in",
        startsIn: "Beginn in",
        locked: "Gesperrt",
        unlockToView: "Entsperren zum Anzeigen",
        openApp: "Öffne POKYH, um das zu sehen",
        nextInfo: "Laufende oder nächste Stunde mit Raum, auch auf dem Sperrbildschirm.",
        todayName: "Heutiger Plan",
        todayInfo: "Alle Stunden, die heute noch kommen.",
        gradesInfo: "Dein Notenschnitt und die neuesten Noten.",
        messagesInfo: "Ungelesene Nachrichten und die neuesten Betreffzeilen.",
        overviewName: "Überblick",
        overviewInfo: "Nächste Stunde, Notenschnitt und ungelesene Nachrichten."
    )

    static let it = WidgetStrings(
        unread: "non letti",
        pause: "Pausa",
        endsIn: "Fine tra",
        startsIn: "Inizio tra",
        locked: "Bloccato",
        unlockToView: "Sblocca per vedere",
        openApp: "Apri POKYH per vederlo",
        nextInfo: "L’ora in corso o la prossima con l’aula, anche sulla schermata di blocco.",
        todayName: "Orario di oggi",
        todayInfo: "Tutte le ore che restano oggi.",
        gradesInfo: "La tua media e i voti più recenti.",
        messagesInfo: "Messaggi non letti e gli oggetti più recenti.",
        overviewName: "Panoramica",
        overviewInfo: "Prossima ora, media dei voti e messaggi non letti."
    )

    static let en = WidgetStrings(
        unread: "unread",
        pause: "Break",
        endsIn: "Ends in",
        startsIn: "Starts in",
        locked: "Locked",
        unlockToView: "Unlock to view",
        openApp: "Open POKYH to see this",
        nextInfo: "Your current or next lesson and its room, on the Lock Screen too.",
        todayName: "Today’s timetable",
        todayInfo: "Every lesson still to come today.",
        gradesInfo: "Your grade average and the latest grades.",
        messagesInfo: "Unread messages and the latest subjects.",
        overviewName: "Overview",
        overviewInfo: "Next lesson, grade average and unread messages."
    )
}

/// Widgets speak the app's language: the settings write the choice to the group defaults too.
enum WidgetText {
    static var lang: Lang {
        let group = AppGroup.id.isEmpty ? nil : UserDefaults(suiteName: AppGroup.id)
        return LanguageChoice.current(in: group ?? .standard)
    }

    static var app: Strings { .of(lang) }
    static var own: WidgetStrings { .of(lang) }

    /// 7,5 in German and Italian, 7.5 in English.
    static func grade(_ value: Double) -> String {
        GradeFormat.string(value).replacingOccurrences(of: ",", with: String(app.common.decimal))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Heute", "Morgen" or the weekday.
    static func day(_ date: Date, from now: Date) -> String {
        let s = app, cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return s.common.today }
        if let next = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: next) {
            return s.common.tomorrow
        }
        // Calendar counts from Sunday, the tables from Monday.
        return s.common.weekdays[(cal.component(.weekday, from: date) + 5) % 7]
    }

    static func dayMonth(_ date: Date) -> String {
        let cal = Calendar.current
        return app.common.dayMonthShort(cal.component(.day, from: date), cal.component(.month, from: date))
    }
}

// ── Data ─────────────────────────────────────────────────────────────────────

/// What the app left for the widgets. `sealed` means nothing could be opened at all: no key yet,
/// the phone hasn't been unlocked since it started, or nobody is signed in.
enum WidgetData {
    private static var vaultClosed: Bool { LocalVault.current() == nil }

    static func timetable(preview: Bool = false) -> (snapshot: TimetableSnapshot, sealed: Bool) {
        let snap = SharedStore.readSnapshot()
        if preview && snap.lessons.isEmpty { return (WidgetSamples.timetable(), false) }
        return (snap, snap.lessons.isEmpty && vaultClosed)
    }

    static func grades(preview: Bool = false) -> (snapshot: GradesSnapshot, sealed: Bool) {
        let snap = SharedStore.readGrades()
        if preview && snap.recent.isEmpty { return (WidgetSamples.grades, false) }
        return (snap, snap.recent.isEmpty && vaultClosed)
    }

    static func messages(preview: Bool = false) -> (snapshot: MessagesSnapshot, sealed: Bool) {
        let snap = SharedStore.readMessages()
        if preview && snap.latest.isEmpty { return (WidgetSamples.messages, false) }
        return (snap, snap.latest.isEmpty && vaultClosed)
    }
}

/// When timetable widgets need a fresh entry.
enum LessonTimeline {
    /// How long before a lesson its countdown takes over from the start time.
    static let countdownLead: TimeInterval = 3600
    /// Hourly is plenty, the app asks for a reload whenever the timetable changes.
    private static let reload: TimeInterval = 3600
    private static let ringStep: TimeInterval = 300

    /// Each start and end, the moment a countdown shows up, and midnight, when "today" moves on.
    /// A gauge can't animate on its own, so `ring` adds a step every few minutes of a lesson.
    static func dates(for snap: TimetableSnapshot, from now: Date, ring: Bool = false) -> [Date] {
        var dates: Set<Date> = [now]
        if ring {
            for step in stride(from: ringStep, to: reload, by: ringStep) {
                let date = now.addingTimeInterval(step)
                if snap.lessons.contains(where: { !$0.isCancelled && $0.start <= date && date < $0.end }) {
                    dates.insert(date)
                }
            }
        }
        for lesson in snap.lessons.prefix(8) {
            for date in [lesson.start.addingTimeInterval(-countdownLead), lesson.start, lesson.end] where date > now {
                dates.insert(date)
            }
        }
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        return dates.sorted()
    }

    static func policy(from now: Date) -> TimelineReloadPolicy {
        .after(now.addingTimeInterval(reload))
    }
}

extension LessonSnapshot {
    var name: String { subject.isEmpty ? WidgetText.app.system.widgetEvent : subject }
    /// Room first, it's what you look for on the way there.
    var place: String { [room, teacher].filter { !$0.isEmpty }.joined(separator: " · ") }
    var span: ClosedRange<Date> { start <= end ? start...end : end...end }
    var timeRange: String { "\(WidgetText.time(start))–\(WidgetText.time(end))" }

    /// How far through the lesson `date` is, 0 to 1.
    func elapsed(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
    }

    func tone(_ hues: SubjectHues) -> Tone {
        if isCancelled { return .cancelled }
        if isExam { return .exam }
        return .subject(subject, hues: hues)
    }

    /// Android's widget greys a cancelled lesson out instead of painting it red.
    func barColor(_ hues: SubjectHues) -> Color {
        isCancelled ? Palette.textTertiary : tone(hues).bar
    }
}

extension TimetableSnapshot {
    /// Hues handed out over the lessons on hand, so two subjects on screen never share one.
    var hues: SubjectHues {
        let hues = SubjectHues()
        hues.register(lessons.map(\.subject))
        return hues
    }
}

extension GradesSnapshot {
    var hues: SubjectHues {
        let hues = SubjectHues()
        hues.register(recent.map(\.subject))
        return hues
    }
}

// ── Look ─────────────────────────────────────────────────────────────────────

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}

extension EnvironmentValues {
    /// Set while WidgetKit draws the copy a locked phone shows.
    var hidesPrivateData: Bool { redactionReasons.contains(.privacy) }
}

/// Home Screen widgets sit on the app's canvas tone, warm in light and the dark ramp's base in
/// dark. Lock Screen ones bring no fill. Tinted and clear modes swap the canvas for glass.
struct WidgetCanvas: ViewModifier {
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if family.isAccessory { Color.clear } else { Palette.bg }
        }
    }
}

/// A raised block inside a widget. Tinted, clear and Lock Screen rendering turn an opaque fill
/// into a solid slab, so it falls back to a quiet system fill there.
struct WidgetTile: ViewModifier {
    var radius: CGFloat
    var fill: Color?
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.background(fill ?? Palette.card, in: .pokyh(radius))
        } else {
            content.background(.quaternary, in: .pokyh(radius))
        }
    }
}

extension View {
    func widgetCanvas() -> some View { modifier(WidgetCanvas()) }

    func widgetTile(radius: CGFloat = Radius.sm, fill: Color? = nil) -> some View {
        modifier(WidgetTile(radius: radius, fill: fill))
    }

    /// The number a widget is about. Shrinks before it clips.
    func widgetNumeral(_ style: TextStyle = .widgetBigNumber) -> some View {
        textStyle(style).lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// Android's widgetHeader: a small accent glyph and a tracked caps label.
struct WidgetLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = Brand.accent
    var trailing: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
            }
            Text(title.uppercased())
                .textStyle(.widgetHeader)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let trailing {
                Spacer(minLength: Spacing.xs)
                Text(trailing.uppercased())
                    .textStyle(.widgetHeader)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tries the most rows first, then fewer, so small phones and large text lose a row instead of
/// squeezing the rest. Needs the height for itself: a Spacer beside it would take half.
struct FittingCount<Content: View>: View {
    let most: Int
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: most, through: 1, by: -1)), id: \.self) { content($0) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The 4pt bar timetable rows carry in the subject's color.
struct LessonBar: View {
    let color: Color
    var height: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 4, height: height)
            .widgetAccentable()
    }
}

struct SubjectDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(color).frame(width: size, height: size).widgetAccentable()
    }
}

/// The red count next to a header.
struct CountBadge: View {
    let count: Int
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let plain = mode == .fullColor
        Text(count, format: .number)
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(plain ? Brand.onAccent : Palette.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(plain ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(.quaternary), in: Capsule())
            .widgetAccentable()
    }
}

/// The small header of a Lock Screen widget. A Label leaves too wide a gap at this size.
struct AccessoryHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
            Text(title.uppercased()).lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .widgetAccentable()
    }
}

/// A glyph in a soft circle and a line or two: nothing to show, or something hidden. Sits at the
/// bottom of a small widget, like the numbers do, and as a row where there's width for one.
struct WidgetNotice: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = Brand.accent
    var compact = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        if compact {
            row
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                glyph
                texts
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } else {
            row.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var row: some View {
        HStack(spacing: Spacing.md) {
            glyph
            texts
        }
    }

    private var glyph: some View {
        let size: CGFloat = compact ? 26 : 34
        return Image(systemName: symbol)
            .font(.system(size: compact ? 11 : 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(mode == .fullColor ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(.quaternary), in: Circle())
            .widgetAccentable()
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .textStyle(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

extension WidgetNotice {
    /// Stands in for grades or messages while they're hidden.
    static func locked(sealed: Bool, compact: Bool = false) -> WidgetNotice {
        let t = WidgetText.own
        return WidgetNotice(symbol: "lock.fill", title: t.locked,
                            detail: sealed ? t.openApp : t.unlockToView, compact: compact)
    }

    static func dayOver(compact: Bool = false) -> WidgetNotice {
        WidgetNotice(symbol: "checkmark", title: WidgetText.app.system.widgetNoMore,
                     tint: Brand.success, compact: compact)
    }
}

// ── Samples ──────────────────────────────────────────────────────────────────

/// Made-up data for the widget gallery and the previews.
enum WidgetSamples {
    static func timetable(_ now: Date = .now, offset minutes: Double = 0) -> TimetableSnapshot {
        func lesson(_ id: Int, _ subject: String, _ room: String, _ teacher: String, _ from: Double, _ to: Double,
                    cancelled: Bool = false, exam: Bool = false) -> LessonSnapshot {
            LessonSnapshot(id: id, subject: subject, room: room, teacher: teacher,
                           start: now.addingTimeInterval((from - minutes) * 60),
                           end: now.addingTimeInterval((to - minutes) * 60),
                           isCancelled: cancelled, isExam: exam)
        }
        return TimetableSnapshot(generatedAt: now, lessons: [
            lesson(1, "M", "A12", "Huber", -20, 30),
            lesson(2, "D", "B04", "Moser", 45, 95),
            lesson(3, "ENGL", "A12", "Kofler", 100, 150, exam: true),
            lesson(4, "R", "B11", "Gruber", 155, 205, cancelled: true),
            lesson(5, "IT", "Lab 2", "Pichler", 210, 260),
            lesson(6, "Bew.Sport", "Halle", "Mair", 265, 315),
        ].filter { $0.end > now })
    }

    /// The break before the second lesson.
    static func timetableBreak(_ now: Date = .now) -> TimetableSnapshot { timetable(now, offset: 33) }

    static let grades = GradesSnapshot(generatedAt: .now, average: 7.46, positive: 22, negative: 3, recent: [
        GradeItem(id: 4, subject: "M", value: 8.5, date: 0),
        GradeItem(id: 3, subject: "ENGL", value: 7, date: 0),
        GradeItem(id: 2, subject: "D", value: 5.5, date: 0),
        GradeItem(id: 1, subject: "IT", value: 9, date: 0),
    ])

    static let messages = MessagesSnapshot(generatedAt: .now, unread: 2, latest: [
        MessageItem(id: 3, sender: "Sekretariat", subject: "Elternsprechtag am Donnerstag", isRead: false),
        MessageItem(id: 2, sender: "Huber Anna", subject: "Unterlagen für die Prüfung", isRead: false),
        MessageItem(id: 1, sender: "Moser Paul", subject: "Ausflug nach Bozen", isRead: true),
    ])
}
