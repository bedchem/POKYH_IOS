import SwiftUI
import PokyhCore
import PokyhDesign

/// Personal to-dos: rows standing on their own (each one swipes on its own, a grouped card would
/// tear), open first, then done, and "Neu" floating at the bottom. A tap or a swipe edits.
struct TodosView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var todos: [ApiTodo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false
    @State private var editing: ApiTodo?
    @State private var actionFailed = false
    @State private var saves = 0

    private var hasBackend: Bool { app.session?.apiToken != nil }
    private var arranged: [ApiTodo] { TodoOrder.arranged(todos) }
    private var open: [ApiTodo] { arranged.filter { !$0.done } }
    private var done: [ApiTodo] { arranged.filter { $0.done } }

    var body: some View {
        Group {
            if !hasBackend {
                BackendUnavailableView(feature: s.tasks.todos)
            } else if loading && todos.isEmpty {
                LoadingView()
            } else if let error, todos.isEmpty {
                ErrorStateView(message: error) { Task { await load() } }
            } else if todos.isEmpty {
                StateView(s.tasks.todosEmpty, message: s.tasks.todosEmptyText) {
                    IconTile("checklist", color: Brand.accent, size: 64)
                } actions: {
                    Button { showAdd = true } label: { ButtonLabel(s.tasks.addTask, symbol: "plus") }
                        .buttonStyle(.secondary(compact: true))
                }
                .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
        .navigationTitle(s.tasks.todos)
        .navigationSubtitle(todos.isEmpty ? "" : s.tasks.todosEyebrow(open.count, todos.count))
        .appBackground()
        .overlay(alignment: .bottomTrailing) {
            if hasBackend {
                FloatingActionButton(s.tasks.new) { showAdd = true }
                    .padding(.trailing, Spacing.screenH)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .sheet(isPresented: $showAdd) {
            TodoSheet { title, details, dueAt in
                try await add(title: title, details: details, dueAt: dueAt)
            }
        }
        .sheet(item: $editing) { todo in
            TodoSheet(editing: todo) { title, details, dueAt in
                try await edit(todo, title: title, details: details, dueAt: dueAt)
            }
        }
        .alert(s.tasks.saveFailed, isPresented: $actionFailed) {
            Button(s.common.ok, role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: saves)
        .task { if hasBackend { await load() } }
        .refreshable { await load() }
    }

    private var list: some View {
        List {
            if !open.isEmpty && !done.isEmpty {
                TaskListLabel(s.tasks.open + " · \(open.count)")
            }
            ForEach(open) { todo in row(todo) }
            if !done.isEmpty {
                TaskListLabel(s.tasks.done + " · \(done.count)")
            }
            ForEach(done) { todo in row(todo) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .animation(Motion.standardEase, value: todos)
    }

    private func row(_ todo: ApiTodo) -> some View {
        TodoRow(todo: todo, onToggle: { Task { await toggle(todo) } }, onEdit: { editing = todo })
            .taskListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { Task { await delete(todo) } } label: {
                    Label(s.common.delete, systemImage: "trash")
                }
                Button { editing = todo } label: {
                    Label(s.tasks.edit, systemImage: "pencil")
                }
                .tint(Brand.accent)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { Task { await toggle(todo) } } label: {
                    Label(todo.done ? s.tasks.markOpen : s.tasks.markDone,
                          systemImage: todo.done ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Brand.success)
            }
    }

    private func load() async {
        guard let s = app.session, let token = s.apiToken else { return }
        loading = todos.isEmpty
        error = nil
        do {
            todos = try await BackendClient.shared.todos(username: s.username, token: token)
            WatchSync.todos(todos, for: s)
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func add(title: String, details: String, dueAt: Date?) async throws {
        guard let s = app.session, let token = s.apiToken else { return }
        let iso = dueAt.map { ISO8601DateFormatter().string(from: $0) }
        _ = try await BackendClient.shared.createTodo(username: s.username, title: title, details: details, dueAt: iso, token: token)
        saves += 1
        await load()
    }

    private func edit(_ todo: ApiTodo, title: String, details: String, dueAt: Date?) async throws {
        guard let s = app.session, let token = s.apiToken else { return }
        let iso = dueAt.map { ISO8601DateFormatter().string(from: $0) }
        try await BackendClient.shared.editTodo(username: s.username, id: todo.id, title: title, details: details, dueAt: iso, token: token)
        if let i = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[i].title = title
            todos[i].details = details
            todos[i].dueAt = iso
        }
        saves += 1
        await load()
    }

    /// Ticked off with the time, as the web sends it: done ones leave the list a day later.
    private func toggle(_ todo: ApiTodo) async {
        guard let s = app.session, let token = s.apiToken else { return }
        let done = !todo.done
        let doneAt = done ? ISO8601DateFormatter().string(from: Date()) : nil
        if let i = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[i].done = done
            todos[i].doneAt = doneAt
        }
        do {
            try await BackendClient.shared.updateTodo(username: s.username, id: todo.id, done: done, doneAt: doneAt, token: token)
        } catch {
            actionFailed = true
        }
        await load()
    }

    private func delete(_ todo: ApiTodo) async {
        guard let s = app.session, let token = s.apiToken else { return }
        todos.removeAll { $0.id == todo.id }
        do {
            try await BackendClient.shared.deleteTodo(username: s.username, id: todo.id, token: token)
        } catch {
            actionFailed = true
        }
        await load()
    }
}

/// As on the web: the open ones by due date (none last), then newest first; the done ones after
/// them, last ticked off first, each gone a day after it was ticked off.
enum TodoOrder {
    static func arranged(_ todos: [ApiTodo], now: Date = Date()) -> [ApiTodo] {
        func at(_ raw: String?) -> Date? { raw.flatMap(MessageFormat.parse) }
        let kept = todos.filter { t in
            guard t.done, let done = at(t.doneAt) else { return true }
            return now.timeIntervalSince(done) < 86_400
        }
        let open = kept.filter { !$0.done }.sorted { a, b in
            let da = at(a.dueAt) ?? .distantFuture, db = at(b.dueAt) ?? .distantFuture
            if da != db { return da < db }
            return (at(a.createdAt) ?? .distantPast) > (at(b.createdAt) ?? .distantPast)
        }
        let done = kept.filter(\.done).sorted { (at($0.doneAt) ?? .distantPast) > (at($1.doneAt) ?? .distantPast) }
        return open + done
    }
}

struct TodoRow: View {
    let todo: ApiTodo
    let onToggle: () -> Void
    var onEdit: (() -> Void)? = nil
    @Environment(\.strings) private var s

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.iconText) {
            Button(action: onToggle) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(todo.done ? Brand.success : Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.done ? s.tasks.markOpen : s.tasks.markDone)
            .sensoryFeedback(.success, trigger: todo.done) { _, done in done }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(todo.title)
                    .textStyle(.body)
                    .foregroundStyle(todo.done ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(todo.done)
                // A done item shows its title only, as on the web.
                if !todo.details.isEmpty && !todo.done {
                    Text(todo.details)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                if !todo.done, let raw = todo.dueAt, let due = MessageFormat.parse(raw) {
                    DuePills(due: due)
                }
            }
            .padding(.top, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { onEdit?() }
            .accessibilityAddTraits(onEdit != nil ? .isButton : [])
            .accessibilityAction(named: s.tasks.edit) { onEdit?() }
        }
    }

    static func dueText(_ d: Date) -> String {
        TaskDates.day(d, Strings.of(.system()))
    }
}

/// "Überfällig" in blush once it's past, then the due day and time.
private struct DuePills: View {
    let due: Date
    @Environment(\.strings) private var s

    var body: some View {
        let overdue = due < Date()
        let tone = Decorative.blush
        HStack(spacing: 6) {
            if overdue {
                Text(s.tasks.overdue)
                    .textStyle(TextStyle.caption.weight(.bold))
                    .foregroundStyle(tone.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(tone.fill, in: .capsule)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                Text(TaskDates.dueLabel(due, s)).textStyle(TextStyle.caption.weight(.bold))
            }
            .foregroundStyle(overdue ? tone.ink : Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(overdue ? Color.clear : Palette.nested, in: .capsule)
        }
    }
}

/// The add sheet, and the same sheet to edit one: title, details, an optional due date with its
/// time, add or save.
private struct TodoSheet: View {
    var editing: ApiTodo? = nil
    let onSave: (_ title: String, _ details: String, _ dueAt: Date?) async throws -> Void
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var details: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var submitting = false
    @State private var error: String?

    init(editing: ApiTodo? = nil, onSave: @escaping (_ title: String, _ details: String, _ dueAt: Date?) async throws -> Void) {
        self.editing = editing
        self.onSave = onSave
        let due = editing?.dueAt.flatMap(MessageFormat.parse)
        _title = State(initialValue: editing?.title ?? "")
        _details = State(initialValue: editing?.details ?? "")
        _hasDue = State(initialValue: due != nil)
        _due = State(initialValue: due ?? TaskDates.defaultDue())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(editing == nil ? s.tasks.newTodo : s.tasks.editTodo)
                    .textStyle(.title1)
                    .foregroundStyle(Palette.textPrimary)
                PokyhTextField(s.tasks.titleField, placeholder: s.tasks.title, text: $title)
                TaskTextArea(label: s.tasks.detailsField, placeholder: s.common.optional, text: $details)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle(isOn: $hasDue.animation(Motion.standardEase)) {
                        Text(s.tasks.dueDate).textStyle(.body).foregroundStyle(Palette.textPrimary)
                    }
                    .tint(Brand.accent)
                    if hasDue {
                        HStack {
                            DatePicker("", selection: $due, displayedComponents: .date).labelsHidden()
                            Spacer()
                            DatePicker("", selection: $due, displayedComponents: .hourAndMinute).labelsHidden()
                        }
                        .environment(\.locale, s.lang.locale)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
            try await onSave(title.trimmingCharacters(in: .whitespaces), details, hasDue ? due : nil)
            dismiss()
        } catch {
            self.error = (error as? AppError)?.message ?? s.tasks.saveFailed
        }
    }
}

// ── Shared with reminders ────────────────────────────────────────────────────

/// Dates on to-dos and reminders, in the language in use.
enum TaskDates {
    /// "21. Okt. 2026" / "21 ott 2026".
    static func day(_ date: Date, _ s: Strings) -> String {
        format(date, s.lang == .de ? "d. MMM yyyy" : "d MMM yyyy", s)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "Heute, 18:00" or "Mi., 29. Okt., 18:00".
    static func dueLabel(_ date: Date, _ s: Strings) -> String {
        if Calendar.current.isDateInToday(date) { return s.tasks.todayAt(time(date)) }
        return s.tasks.dateTime(format(date, s.tasks.dayShort, s), time(date))
    }

    /// "Mittwoch, 29. Oktober".
    static func dayLong(_ date: Date, _ s: Strings) -> String {
        let text = format(date, s.tasks.dayLong, s)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "in 3 Tagen", "in 5 Std.", "Gleich" or "Fällig".
    static func timeUntil(_ date: Date, _ s: Strings, now: Date = Date()) -> String {
        let diff = date.timeIntervalSince(now)
        if diff < 0 { return s.tasks.due }
        let hours = Int(diff / 3600)
        let days = hours / 24
        if days > 1 { return s.tasks.inDays(days) }
        if days == 1 { return s.tasks.inDay }
        if hours > 0 { return s.tasks.inHours(hours) }
        return s.tasks.soon
    }

    /// Today at six in the evening, the web's default for a new due date.
    static func defaultDue() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func format(_ date: Date, _ pattern: String, _ s: Strings) -> String {
        let f = DateFormatter()
        f.locale = s.lang.locale
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// A small caps heading between list rows ("OFFEN · 3").
struct TaskListLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        EyebrowLabel(text)
            .padding(.top, Spacing.sm)
            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.screenH, bottom: Spacing.xxs, trailing: Spacing.screenH))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// A labelled multi-line field in the same recessed style as PokyhTextField.
struct TaskTextArea: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(label, color: Palette.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary), axis: .vertical)
                .textStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .tint(Brand.accent)
                .lineLimit(2...6)
                .focused($focused)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 15)
                .insetSurface(radius: Radius.md)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(focused ? Brand.accent : .clear, lineWidth: 1.5)
                }
                .animation(.easeOut(duration: Motion.fast), value: focused)
        }
    }
}

extension View {
    /// A list row drawn as its own tile on the canvas, so swipe actions still work.
    func taskListRow() -> some View {
        self
            .padding(Spacing.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Radius.lg, fill: Palette.card)
            .contentShape(.rect)
            .listRowInsets(EdgeInsets(top: Spacing.rowGap / 2, leading: Spacing.screenH, bottom: Spacing.rowGap / 2, trailing: Spacing.screenH))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
