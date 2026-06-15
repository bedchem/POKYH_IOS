import SwiftUI

struct TodosView: View {
    @EnvironmentObject var app: AppState
    @State private var todos: [ApiTodo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false
    @State private var newTitle = ""
    @State private var newDetails = ""
    @State private var hasDue = false
    @State private var due = Date()

    private var hasBackend: Bool { app.session?.apiToken != nil }

    var body: some View {
        Group {
            if !hasBackend {
                BackendUnavailableView(feature: "Todos")
            } else if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if todos.isEmpty {
                EmptyStateView(systemImage: "checklist", title: "Keine Todos", subtitle: "Tippe auf +, um eine Aufgabe anzulegen.")
            } else {
                List {
                    ForEach(todos.sorted { !$0.done && $1.done }) { todo in
                        TodoRow(todo: todo) { Task { await toggle(todo) } }
                    }
                    .onDelete { idx in Task { await delete(idx) } }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Todos")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            if hasBackend {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .task { if hasBackend { await load() } }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Titel", text: $newTitle)
                    TextField("Details (optional)", text: $newDetails, axis: .vertical)
                }
                Section {
                    Toggle("Fälligkeitsdatum", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Fällig am", selection: $due, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("Neues Todo")
            .navigationBarTitleDisplayMode(.inline)
        .appBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { resetAdd() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { Task { await add() } }.disabled(newTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func load() async {
        guard let s = app.session, let token = s.apiToken else { return }
        loading = true; error = nil
        do { todos = try await BackendClient.shared.todos(username: s.username, token: token) }
        catch { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        loading = false
    }

    private func add() async {
        guard let s = app.session, let token = s.apiToken else { return }
        let iso = hasDue ? ISO8601DateFormatter().string(from: due) : nil
        _ = try? await BackendClient.shared.createTodo(username: s.username, title: newTitle, details: newDetails, dueAt: iso, token: token)
        resetAdd()
        await load()
    }

    private func toggle(_ todo: ApiTodo) async {
        guard let s = app.session, let token = s.apiToken else { return }
        try? await BackendClient.shared.updateTodo(username: s.username, id: todo.id, done: !todo.done, token: token)
        await load()
    }

    private func delete(_ idx: IndexSet) async {
        guard let s = app.session, let token = s.apiToken else { return }
        let sorted = todos.sorted { !$0.done && $1.done }
        for i in idx { try? await BackendClient.shared.deleteTodo(username: s.username, id: sorted[i].id, token: token) }
        await load()
    }

    private func resetAdd() {
        showAdd = false; newTitle = ""; newDetails = ""; hasDue = false; due = Date()
    }
}

struct TodoRow: View {
    let todo: ApiTodo
    let onToggle: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(todo.done ? Palette.tint : .secondary)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title).strikethrough(todo.done).foregroundStyle(todo.done ? .secondary : .primary)
                if !todo.details.isEmpty {
                    Text(todo.details).font(.caption).foregroundStyle(.secondary)
                }
                if let due = todo.dueAt, let d = MessageFormat.parse(due) {
                    Label(Self.dueText(d), systemImage: "calendar").font(.caption2).foregroundStyle(Palette.orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    static func dueText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM yyyy"
        return f.string(from: d)
    }
}
