import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var app: AppState
    @State private var folder: MessageFolder = .inbox
    @State private var cache: [MessageFolder: [MessagePreview]] = [:]
    @State private var loadingFolders: Set<MessageFolder> = []
    @State private var error: String?

    private var messages: [MessagePreview] { cache[folder] ?? [] }
    // Vollständiger Ladebildschirm nur, wenn der Ordner noch nie geladen wurde.
    private var firstLoad: Bool { cache[folder] == nil && loadingFolders.contains(folder) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ordner", selection: $folder.animation(.easeInOut(duration: 0.2))) {
                ForEach(MessageFolder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Group {
                if firstLoad {
                    LoadingView()
                } else if let error, messages.isEmpty {
                    ErrorStateView(message: error) { Task { await load(folder, force: true) } }
                } else if messages.isEmpty {
                    EmptyStateView(systemImage: "tray", title: "Keine Nachrichten", subtitle: "Dieser Ordner ist leer.")
                } else {
                    List(messages) { msg in
                        NavigationLink {
                            MessageDetailScreen(preview: msg, folder: folder)
                        } label: {
                            MessageRow(msg: msg)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .top) {
                        if loadingFolders.contains(folder) {
                            ProgressView().controlSize(.small).tint(Palette.accent).padding(6)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: messages.map(\.id))
        }
        .navigationTitle("Nachrichten")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task(id: folder) { await load(folder) }
    }

    private func load(_ f: MessageFolder, force: Bool = false) async {
        guard let s = app.session else { return }
        // Bereits gecacht → Inhalt bleibt sichtbar, Aktualisierung läuft leise im
        // Hintergrund (kleiner Spinner oben) — kein Flackern beim Tab-Wechsel.
        loadingFolders.insert(f)
        error = nil
        defer { loadingFolders.remove(f) }
        do {
            cache[f] = try await UntisClient.shared.messages(folder: f, s)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
    }
}

struct MessageRow: View {
    let msg: MessagePreview
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                InitialAvatar(name: msg.senderName, size: 42)
                if !msg.isRead {
                    Circle().fill(Palette.accent).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Palette.surface, lineWidth: 2))
                        .offset(x: -2, y: -2)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(msg.subject).font(.subheadline.weight(msg.isRead ? .regular : .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(MessageFormat.date(msg.sentDate)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(msg.senderName + (msg.contentPreview.isEmpty ? "" : " · \(msg.contentPreview)"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if msg.hasAttachments {
                        Image(systemName: "paperclip").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MessageDetailScreen: View {
    let preview: MessagePreview
    let folder: MessageFolder
    @EnvironmentObject var app: AppState
    @State private var detail: MessageDetail?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else if let d = detail {
                    Text(d.subject).font(.title2.bold())
                    HStack(spacing: 12) {
                        InitialAvatar(name: d.senderName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.senderName).font(.subheadline.weight(.semibold))
                            Text(MessageFormat.fullDate(d.sentDate)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text(MessageFormat.plainText(d.body))
                        .font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !d.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anhänge").font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(d.attachments) { att in
                                Label(att.name, systemImage: "doc.fill")
                                    .font(.subheadline)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Nachricht")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task { await load() }
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            detail = try await UntisClient.shared.messageDetail(id: preview.id, s)
            if folder == .inbox && !preview.isRead {
                await UntisClient.shared.markRead(id: preview.id, s)
            }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

nonisolated enum MessageFormat {
    static func date(_ dateStr: String) -> String {
        guard let date = parse(dateStr) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Gestern" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE")
        if days < 7 { f.dateFormat = "EEE"; return f.string(from: date) }
        f.dateFormat = "dd.MM."; return f.string(from: date)
    }
    static func fullDate(_ dateStr: String) -> String {
        guard let date = parse(dateStr) else { return dateStr }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: date)
    }
    static func parse(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
    /// Entfernt HTML-Tags grob (entspricht sanitize → plaintext).
    static func plainText(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var s = raw.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
