import SwiftUI

struct RemindersView: View {
    @EnvironmentObject var app: AppState
    @State private var reminders: [ApiReminder] = []
    @State private var myClass: ApiClass?
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var remindAt = Date()

    private var hasBackend: Bool { app.session?.apiToken != nil }

    var body: some View {
        Group {
            if !hasBackend {
                BackendUnavailableView(feature: "Erinnerungen")
            } else if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if myClass == nil {
                EmptyStateView(systemImage: "person.3", title: "Keine Klasse", subtitle: "Du bist noch keiner Klasse beigetreten.")
            } else if visibleReminders.isEmpty {
                EmptyStateView(systemImage: "bell", title: "Keine Erinnerungen", subtitle: "Lege eine Klassen-Erinnerung an.")
            } else {
                List {
                    ForEach(visibleReminders) { r in
                        NavigationLink {
                            if let c = myClass { ReminderDetailView(reminder: r, classId: c.id) }
                        } label: {
                            ReminderRow(reminder: r)
                        }
                        .swipeActions(allowsFullSwipe: true) {
                            Button(role: .destructive) { Task { await delete(r) } } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Erinnerungen")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            if myClass != nil {
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
                Section("Erinnerung") {
                    TextField("Titel", text: $newTitle)
                    TextField("Beschreibung (optional)", text: $newBody, axis: .vertical)
                }
                Section {
                    DatePicker("Erinnern am", selection: $remindAt, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Neue Erinnerung")
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
        do {
            myClass = try await BackendClient.shared.myClass(token: token)
            if let c = myClass {
                reminders = try await BackendClient.shared.reminders(classId: c.id, token: token)
                // Lokale Benachrichtigungen planen (feuern auch bei geschlossener App).
                NotificationManager.shared.scheduleReminders(reminders)
            }
        } catch { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        loading = false
    }

    private func add() async {
        guard let s = app.session, let token = s.apiToken, let c = myClass else { return }
        let iso = ISO8601DateFormatter().string(from: remindAt)
        _ = try? await BackendClient.shared.createReminder(classId: c.id, title: newTitle, body: newBody, remindAt: iso, token: token)
        resetAdd()
        await load()
    }

    /// Nur aktuelle Erinnerungen: abgelaufene (länger als 1 Tag vorbei) ausblenden,
    /// chronologisch sortiert (nächste zuerst).
    private var visibleReminders: [ApiReminder] {
        let cutoff = Date().addingTimeInterval(-86_400)
        return reminders
            .filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) >= cutoff }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private func delete(_ reminder: ApiReminder) async {
        guard let s = app.session, let token = s.apiToken, let c = myClass else { return }
        try? await BackendClient.shared.deleteReminder(classId: c.id, id: reminder.id, token: token)
        await load()
    }

    private func resetAdd() { showAdd = false; newTitle = ""; newBody = ""; remindAt = Date() }
}

struct ReminderDetailView: View {
    let reminder: ApiReminder
    let classId: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reminder.title).font(.title2.bold()).foregroundStyle(Palette.textPrimary)
                    if let d = MessageFormat.parse(reminder.remindAt) {
                        Label(TodoRow.dueText(d), systemImage: "calendar").font(.subheadline).foregroundStyle(Palette.orange)
                    }
                    if !reminder.body.isEmpty {
                        Text(reminder.body).font(.body).foregroundStyle(Palette.textSecondary)
                    }
                    Text("von \(reminder.createdByName.isEmpty ? reminder.createdByUsername : reminder.createdByName)")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

                Divider().overlay(Palette.separator)

                CommentSection(
                    title: "Kommentare",
                    load: { try await BackendClient.shared.reminderComments(classId: classId, reminderId: reminder.id, token: $0) },
                    create: { try await BackendClient.shared.createReminderComment(classId: classId, reminderId: reminder.id, body: $1, token: $0) },
                    delete: { try await BackendClient.shared.deleteReminderComment(classId: classId, reminderId: reminder.id, commentId: $1, token: $0) }
                )
            }
            .padding(16)
        }
        .navigationTitle("Erinnerung")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }
}

struct ReminderRow: View {
    let reminder: ApiReminder
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill").foregroundStyle(Palette.tint)
                .frame(width: 38, height: 38)
                .background(Palette.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(.subheadline.weight(.semibold))
                if !reminder.body.isEmpty {
                    Text(reminder.body).font(.caption).foregroundStyle(.secondary)
                }
                if let d = MessageFormat.parse(reminder.remindAt) {
                    Text(TodoRow.dueText(d)).font(.caption2).foregroundStyle(Palette.orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
