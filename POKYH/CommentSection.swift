import SwiftUI

/// Wiederverwendbare Kommentar-Sektion (entspricht components/ui/CommentSection.tsx).
struct CommentSection: View {
    @EnvironmentObject var app: AppState
    let title: String
    let load: (_ token: String) async throws -> [ApiComment]
    let create: (_ token: String, _ body: String) async throws -> ApiComment
    let delete: (_ token: String, _ id: String) async throws -> Void

    @State private var comments: [ApiComment] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var sending = false

    private var token: String? { app.session?.apiToken }
    private var myUid: String? { app.session?.stableUid }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)

            if token == nil {
                Text("Kommentare benötigen ein POKYH-Konto.")
                    .font(.caption).foregroundStyle(Palette.textTertiary)
            } else {
                if loading {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 10) {
                            Circle().fill(Palette.cardAlt).frame(width: 32, height: 32).modifier(Shimmer())
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(height: 11, width: 100)
                                SkeletonBlock(height: 10, width: 200)
                            }
                            Spacer()
                        }
                    }
                } else if comments.isEmpty {
                    Text("Noch keine Kommentare. Sei der Erste!")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                } else {
                    ForEach(comments) { c in commentRow(c) }
                }

                composer
            }
        }
        .task { await reload() }
    }

    private func commentRow(_ c: ApiComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            InitialAvatar(name: c.username, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.username).font(.caption.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                    Text(relative(c.createdAt)).font(.caption2).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    if c.stableUid == myUid {
                        Button { Task { await remove(c) } } label: {
                            Image(systemName: "trash").font(.caption2).foregroundStyle(Palette.danger)
                        }
                    }
                }
                Text(c.body).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Kommentar schreiben…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.pressable)
            .tint(Palette.accent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
    }

    private func reload() async {
        guard let token else { loading = false; return }
        loading = comments.isEmpty
        if let list = try? await load(token) { comments = list }
        loading = false
    }
    private func send() async {
        guard let token else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        if let c = try? await create(token, body) {
            comments.append(c); draft = ""
        }
    }
    private func remove(_ c: ApiComment) async {
        guard let token else { return }
        comments.removeAll { $0.id == c.id }
        try? await delete(token, c.id)
    }

    private func relative(_ iso: String) -> String {
        guard let d = MessageFormat.parse(iso) else { return "" }
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "de_DE")
        return f.localizedString(for: d, relativeTo: Date())
    }
}
