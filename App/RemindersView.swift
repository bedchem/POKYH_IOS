import SwiftUI
import PokyhCore
import PokyhDesign

/// Class reminders: the same swipeable tile rows as the to-dos next door, what's due first, then
/// one section per day. The own ones (all of them for an admin) swipe to edit or delete.
struct RemindersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var reminders: [ApiReminder] = []
    @State private var myClass: ApiClass?
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false
    @State private var selectedId: String?
    @State private var editing: ApiReminder?
    @State private var isAdmin = false
    @State private var actionFailed = false
    @State private var saves = 0

    private var hasBackend: Bool { app.session?.apiToken != nil }

    var body: some View {
        Group {
            if !hasBackend {
                BackendUnavailableView(feature: s.tasks.remindersFeature)
            } else if loading && reminders.isEmpty {
                LoadingView()
            } else if let error, reminders.isEmpty {
                ErrorStateView(message: error) { Task { await load() } }
            } else if myClass == nil {
                emptyState(s.tasks.noClass, s.tasks.noClassText, symbol: "person.3")
            } else if visibleReminders.isEmpty {
                emptyState(s.tasks.remindersEmpty, s.tasks.remindersEmptyText, symbol: "bell")
            } else {
                list
            }
        }
        .navigationTitle(s.tasks.reminders)
        .navigationSubtitle(upcomingCount > 0 ? s.tasks.upcoming(upcomingCount) : "")
        .appBackground()
        .overlay(alignment: .bottomTrailing) {
            if myClass != nil {
                FloatingActionButton(s.tasks.new) { showAdd = true }
                    .padding(.trailing, Spacing.screenH)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .navigationDestination(item: $selectedId) { id in
            if let r = reminders.first(where: { $0.id == id }), let c = myClass {
                ReminderDetailView(reminder: r, classId: c.id, onDelete: { await delete(r) }, onEdited: { changed in
                    if let i = reminders.firstIndex(where: { $0.id == changed.id }) { reminders[i] = changed }
                })
            }
        }
        .sheet(isPresented: $showAdd) {
            ReminderSheet { title, body, remindAt in
                try await add(title: title, body: body, remindAt: remindAt)
            }
        }
        .sheet(item: $editing) { r in
            ReminderSheet(editing: r) { title, body, remindAt in
                try await edit(r, title: title, body: body, remindAt: remindAt)
            }
        }
        .alert(s.tasks.saveFailed, isPresented: $actionFailed) {
            Button(s.common.ok, role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: saves)
        .task { if hasBackend { await load() } }
        .refreshable { await load() }
    }

    private func emptyState(_ title: String, _ text: String, symbol: String) -> some View {
        StateView(title, message: text, art: {
            IconTile(symbol, color: Brand.accent, size: 64)
        })
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        let now = Date()
        let due = visibleReminders.filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) < now }
        let coming = visibleReminders.filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) >= now }
        let days = Dictionary(grouping: coming) { r in
            MessageFormat.parse(r.remindAt).map { Calendar.current.startOfDay(for: $0) } ?? .distantFuture
        }
        return List {
            if !due.isEmpty {
                TaskListLabel(s.tasks.due)
                ForEach(due) { r in row(r, overdue: true) }
            }
            ForEach(days.keys.sorted(), id: \.self) { day in
                TaskListLabel(dayTitle(day))
                ForEach(days[day] ?? []) { r in row(r, overdue: false) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .animation(Motion.standardEase, value: reminders)
    }

    private func row(_ r: ApiReminder, overdue: Bool) -> some View {
        Button { selectedId = r.id } label: {
            ReminderRow(reminder: r, mine: isMine(r), overdue: overdue)
                .taskListRow()
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
        .listRowInsets(EdgeInsets(top: Spacing.rowGap / 2, leading: Spacing.screenH, bottom: Spacing.rowGap / 2, trailing: Spacing.screenH))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(allowsFullSwipe: true) {
            if isMine(r) || isAdmin {
                Button(role: .destructive) { Task { await delete(r) } } label: {
                    Label(s.common.delete, systemImage: "trash")
                }
                Button { editing = r } label: {
                    Label(s.tasks.edit, systemImage: "pencil")
                }
                .tint(Brand.accent)
            }
        }
    }

    private func isMine(_ r: ApiReminder) -> Bool {
        guard let session = app.session else { return false }
        if let uid = session.stableUid, r.createdBy == uid { return true }
        return r.createdByUsername.caseInsensitiveCompare(session.username) == .orderedSame
    }

    /// Only what's still to come counts, as on the web.
    private var upcomingCount: Int {
        visibleReminders.filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) >= Date() }.count
    }

    /// "Heute · Mittwoch, 29. Oktober", "Morgen · …" or the date alone.
    private func dayTitle(_ day: Date) -> String {
        guard day != .distantFuture else { return "" }
        let long = TaskDates.dayLong(day, s)
        if Calendar.current.isDateInToday(day) { return s.mensa.today + " · " + long }
        if Calendar.current.isDateInTomorrow(day) { return s.mensa.tomorrow + " · " + long }
        return long
    }

    private func load() async {
        guard let s = app.session, let token = s.apiToken else { return }
        loading = reminders.isEmpty
        error = nil
        if let me = try? await BackendClient.shared.me(token: token) { isAdmin = me.isAdmin }
        do {
            myClass = try await BackendClient.shared.myClass(token: token)
            if let c = myClass {
                reminders = try await BackendClient.shared.reminders(classId: c.id, token: token)
                // Local notifications, so they fire with the app closed too.
                NotificationManager.shared.scheduleReminders(reminders)
            }
        } catch { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        loading = false
    }

    private func add(title: String, body: String, remindAt: Date) async throws {
        guard let s = app.session, let token = s.apiToken, let c = myClass else { return }
        let iso = ISO8601DateFormatter().string(from: remindAt)
        _ = try await BackendClient.shared.createReminder(classId: c.id, title: title, body: body, remindAt: iso, token: token)
        saves += 1
        await load()
    }

    private func edit(_ r: ApiReminder, title: String, body: String, remindAt: Date) async throws {
        guard let s = app.session, let token = s.apiToken, let c = myClass else { return }
        let iso = ISO8601DateFormatter().string(from: remindAt)
        let changed = try await BackendClient.shared.editReminder(classId: c.id, id: r.id, title: title, body: body, remindAt: iso, token: token)
        if let i = reminders.firstIndex(where: { $0.id == r.id }) { reminders[i] = changed }
        saves += 1
        await load()
    }

    /// Kept 25 hours after they were due, as on the web, next one first.
    private var visibleReminders: [ApiReminder] {
        let cutoff = Date().addingTimeInterval(-25 * 3600)
        return reminders
            .filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) >= cutoff }
            .sorted { (MessageFormat.parse($0.remindAt) ?? .distantFuture) < (MessageFormat.parse($1.remindAt) ?? .distantFuture) }
    }

    private func delete(_ reminder: ApiReminder) async {
        guard let s = app.session, let token = s.apiToken, let c = myClass else { return }
        reminders.removeAll { $0.id == reminder.id }
        do {
            try await BackendClient.shared.deleteReminder(classId: c.id, id: reminder.id, token: token)
        } catch {
            actionFailed = true
        }
        await load()
    }
}

struct ReminderDetailView: View {
    let classId: String
    var onDelete: (() async -> Void)?
    var onEdited: ((ApiReminder) -> Void)?
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: ApiReminder
    @State private var deleting = false
    @State private var editing = false
    @State private var isAdmin = false
    @State private var failed = false
    @State private var saves = 0

    init(reminder: ApiReminder, classId: String, onDelete: (() async -> Void)? = nil, onEdited: ((ApiReminder) -> Void)? = nil) {
        self.classId = classId
        self.onDelete = onDelete
        self.onEdited = onEdited
        _reminder = State(initialValue: reminder)
    }

    private var at: Date? { MessageFormat.parse(reminder.remindAt) }
    private var overdue: Bool { (at ?? .distantFuture) < Date() }
    private var mine: Bool {
        guard let session = app.session else { return false }
        if let uid = session.stableUid, reminder.createdBy == uid { return true }
        return reminder.createdByUsername.caseInsensitiveCompare(session.username) == .orderedSame
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                // "in 3 Tagen · Mittwoch, 29. Oktober, 08:00", as the web's sheet.
                if let at {
                    Text(TaskDates.timeUntil(at, s) + " · " + s.tasks.dateTime(TaskDates.dayLong(at, s), TaskDates.time(at)))
                        .textStyle(.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .fadeIn()
                }

                card.fadeIn()

                if mine || isAdmin {
                    HStack(spacing: Spacing.sm) {
                        Button { editing = true } label: {
                            ButtonLabel(s.tasks.edit, symbol: "pencil")
                        }
                        .buttonStyle(.secondary(compact: true))
                        Button { Task { await remove() } } label: {
                            ButtonLabel(isAdmin && !mine ? s.tasks.deleteAsAdmin : s.tasks.deleteItem, symbol: "trash", busy: deleting)
                        }
                        .buttonStyle(.secondary(compact: true))
                        .disabled(deleting)
                    }
                    if failed {
                        Text(s.tasks.saveFailed).textStyle(.footnote).foregroundStyle(Brand.danger)
                    }
                }

                CommentSection(
                    title: s.common.comments,
                    load: { try await BackendClient.shared.reminderComments(classId: classId, reminderId: reminder.id, token: $0) },
                    create: { try await BackendClient.shared.createReminderComment(classId: classId, reminderId: reminder.id, body: $1, token: $0) },
                    delete: { try await BackendClient.shared.deleteReminderComment(classId: classId, reminderId: reminder.id, commentId: $1, token: $0) },
                    update: { try await BackendClient.shared.updateReminderComment(classId: classId, reminderId: reminder.id, commentId: $1, body: $2, token: $0) },
                    reportPath: "/reminders"
                )
                .fadeIn(delay: 0.04)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .navigationTitle(reminder.title)
        .navigationSubtitle(s.tasks.reminder)
        .navigationBarTitleDisplayMode(.large)
        .appBackground()
        .sheet(isPresented: $editing) {
            ReminderSheet(editing: reminder) { title, body, remindAt in
                try await save(title: title, body: body, remindAt: remindAt)
            }
        }
        .sensoryFeedback(.success, trigger: saves)
        .task {
            guard let token = app.session?.apiToken, let me = try? await BackendClient.shared.me(token: token) else { return }
            isAdmin = me.isAdmin
        }
    }

    private func save(title: String, body: String, remindAt: Date) async throws {
        guard let token = app.session?.apiToken else { return }
        let iso = ISO8601DateFormatter().string(from: remindAt)
        let changed = try await BackendClient.shared.editReminder(classId: classId, id: reminder.id, title: title, body: body, remindAt: iso, token: token)
        withAnimation(Motion.standardEase) { reminder = changed }
        saves += 1
        onEdited?(changed)
    }

    /// Through the list when it opened this, else straight to the backend.
    private func remove() async {
        deleting = true
        failed = false
        defer { deleting = false }
        if let onDelete {
            await onDelete()
            dismiss()
            return
        }
        guard let token = app.session?.apiToken else { return }
        do {
            try await BackendClient.shared.deleteReminder(classId: classId, id: reminder.id, token: token)
            dismiss()
        } catch {
            failed = true
        }
    }

    /// The reminder itself, blush once it's due.
    private var card: some View {
        let tone = Decorative.blush
        let author = reminder.createdByUsername.isEmpty ? reminder.createdByName : reminder.createdByUsername
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if !reminder.body.isEmpty {
                Text(reminder.body)
                    .textStyle(.body)
                    .foregroundStyle(overdue ? tone.ink : Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(mine ? s.common.you : s.tasks.by(author))
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle((overdue ? tone.ink : Palette.textSecondary).opacity(0.75))
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: overdue ? tone.fill : Palette.card)
    }
}

/// The web's row: the time, the title with its text and who added it, the countdown on the right.
struct ReminderRow: View {
    let reminder: ApiReminder
    var mine = false
    var overdue = false
    @Environment(\.strings) private var s

    var body: some View {
        let at = MessageFormat.parse(reminder.remindAt)
        let author = reminder.createdByUsername.isEmpty ? reminder.createdByName : reminder.createdByUsername
        HStack(alignment: .top, spacing: Spacing.iconText) {
            Text(at.map { TaskDates.time($0) } ?? "")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(reminder.title)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                if !reminder.body.isEmpty {
                    Text(reminder.body)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                Text(mine ? s.common.you : s.tasks.by(author))
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let at {
                CountdownPill(at: at, overdue: overdue)
            }
        }
    }
}

/// "in 3 Tagen", blush once it's due.
private struct CountdownPill: View {
    let at: Date
    let overdue: Bool
    @Environment(\.strings) private var s

    var body: some View {
        let tone = Decorative.blush
        Text(TaskDates.timeUntil(at, s))
            .textStyle(TextStyle.caption.weight(.bold))
            .foregroundStyle(overdue ? tone.ink : Palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, Spacing.xs)
            .background(overdue ? tone.fill : Palette.nested, in: .capsule)
    }
}

/// Adds a reminder, or edits one: title, text, the day and time it fires.
private struct ReminderSheet: View {
    var editing: ApiReminder? = nil
    let onSave: (_ title: String, _ body: String, _ remindAt: Date) async throws -> Void
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var remindAt: Date
    @State private var submitting = false
    @State private var error: String?

    init(editing: ApiReminder? = nil, onSave: @escaping (_ title: String, _ body: String, _ remindAt: Date) async throws -> Void) {
        self.editing = editing
        self.onSave = onSave
        _title = State(initialValue: editing?.title ?? "")
        _text = State(initialValue: editing?.body ?? "")
        _remindAt = State(initialValue: editing.flatMap { MessageFormat.parse($0.remindAt) } ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(editing == nil ? s.tasks.newReminder : s.tasks.editReminder)
                    .textStyle(.title1)
                    .foregroundStyle(Palette.textPrimary)
                PokyhTextField(s.tasks.titleField, placeholder: s.tasks.title, text: $title)
                TaskTextArea(label: s.tasks.descriptionField, placeholder: s.common.optional, text: $text)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    EyebrowLabel(s.tasks.remindOn, color: Palette.textSecondary)
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Palette.accentText)
                        DatePicker("", selection: $remindAt, displayedComponents: .date).labelsHidden()
                        Spacer()
                        Image(systemName: "clock").foregroundStyle(Palette.accentText)
                        DatePicker("", selection: $remindAt, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                    .environment(\.locale, s.lang.locale)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .insetSurface(radius: Radius.md)
                }

                if let error {
                    Text(error).textStyle(.footnote).foregroundStyle(Brand.danger)
                }

                HStack(spacing: Spacing.md) {
                    TextLinkButton(s.common.cancel, color: Palette.textSecondary) { dismiss() }
                    Spacer()
                    Button { Task { await submit() } } label: {
                        ButtonLabel(editing == nil ? s.tasks.add : s.tasks.saveChanges, busy: submitting)
                    }
                    .buttonStyle(.primary)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || submitting)
                }
                .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(submitting)
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            try await onSave(title.trimmingCharacters(in: .whitespaces), text, remindAt)
            dismiss()
        } catch {
            self.error = (error as? AppError)?.message ?? s.tasks.saveFailed
        }
    }
}
