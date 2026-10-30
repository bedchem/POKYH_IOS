import SwiftUI
import PokyhCore
import PokyhDesign

/// The comment thread under a reminder or a dish. One list card for the whole thread (it's one
/// object, five cards made it look like five things), the composer right under it. The own
/// comments edit in a small sheet, from the pencil or a long press.
struct CommentSection: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    let title: String
    let load: (_ token: String) async throws -> [ApiComment]
    let create: (_ token: String, _ body: String) async throws -> ApiComment
    let delete: (_ token: String, _ id: String) async throws -> Void
    /// Saves an edit of an own comment; without it there's no edit.
    var update: ((_ token: String, _ id: String, _ body: String) async throws -> ApiComment)? = nil
    /// Stars per account (stableUid → 1–5), shown beside the author under a dish.
    var ratings: [String: Double] = [:]
    /// Where the thread lives on the website, for a report.
    var reportPath: String = ""

    @State private var comments: [ApiComment] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var sending = false
    @State private var failed = false
    @State private var editing: ApiComment?
    @State private var confirmDelete: ApiComment?
    @State private var sent = 0

    private static let maxLength = 2000

    private var token: String? { app.session?.apiToken }
    private var myUid: String? { app.session?.stableUid }

    var body: some View {
        PokyhSection(title, spacing: Spacing.md) {
            if !comments.isEmpty {
                EyebrowLabel("\(comments.count)")
            }
        } content: {
            if token == nil {
                Text(s.common.noComments)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                thread
                composer
            }
        }
        .task { await reload() }
        .sheet(item: $editing) { c in
            CommentEditSheet(comment: c, maxLength: Self.maxLength) { body in
                try await save(c, body: body)
            }
        }
        .alert(s.common.delete, isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
               presenting: confirmDelete) { c in
            Button(s.common.delete, role: .destructive) { Task { await remove(c) } }
            Button(s.common.cancel, role: .cancel) {}
        } message: { c in
            Text(c.body.count > 120 ? String(c.body.prefix(120)) + "…" : c.body)
        }
        .sensoryFeedback(.success, trigger: sent)
    }

    @ViewBuilder private var thread: some View {
        if loading && comments.isEmpty {
            ProgressView()
                .controlSize(.small)
                .tint(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
        } else if comments.isEmpty {
            Text("\(s.common.noComments) \(s.common.noCommentsHint)")
                .textStyle(.footnote)
                .foregroundStyle(Palette.textTertiary)
        } else {
            ListCard(comments) { comment in
                row(comment)
            }
        }
    }

    private func row(_ c: ApiComment) -> some View {
        let mine = myUid != nil && c.stableUid == myUid
        let stars = ratings[c.stableUid].map { Int($0.rounded()) } ?? 0
        return HStack(alignment: .top, spacing: Spacing.iconText) {
            InitialAvatar(name: c.username, size: 34, colorSeed: c.username)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(c.username)
                        .textStyle(.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if mine {
                        Text(s.common.you)
                            .textStyle(.caption2)
                            .foregroundStyle(Decorative.periwinkle.ink)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 1)
                            .background(Decorative.periwinkle.fill, in: .capsule)
                    }
                    if stars > 0 { CommentStars(value: stars) }
                    Text(timeAgo(c))
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Text(c.body)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mine {
                HStack(spacing: 0) {
                    if update != nil {
                        IconButton("pencil", label: s.common.editComment, size: 32, tint: Palette.textTertiary) {
                            editing = c
                        }
                    }
                    IconButton("trash", label: s.common.delete, size: 32, tint: Palette.textTertiary) {
                        confirmDelete = c
                    }
                }
            } else if myUid != nil {
                IconButton("flag", label: s.common.reportComment, size: 32, tint: Palette.textTertiary) {
                    report(c)
                }
            }
        }
        .padding(Spacing.card)
        .contentShape(.rect)
        .contextMenu {
            if mine {
                if update != nil {
                    Button { editing = c } label: { Label(s.common.editComment, systemImage: "pencil") }
                }
                Button(role: .destructive) { confirmDelete = c } label: { Label(s.common.delete, systemImage: "trash") }
            } else if myUid != nil {
                Button { report(c) } label: { Label(s.common.reportComment, systemImage: "flag") }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("", text: $draft, prompt: Text(s.common.writeComment).foregroundStyle(Palette.textTertiary), axis: .vertical)
                    .textStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Brand.accent)
                    .lineLimit(1...6)
                    .padding(.vertical, 14)
                    .onChange(of: draft) { _, value in
                        failed = false
                        if value.count > Self.maxLength { draft = String(value.prefix(Self.maxLength)) }
                    }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.onAccent)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Brand.accent : Palette.textTertiary.opacity(0.5), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(s.common.send)
                .padding(.bottom, Spacing.sm)
            }
            .padding(.leading, Spacing.lg)
            .padding(.trailing, Spacing.sm)
            .insetSurface(radius: Radius.lg)

            if failed || sending || draft.count > Self.maxLength - 200 {
                HStack {
                    if failed {
                        Text(s.common.commentFailed).textStyle(.caption).foregroundStyle(Brand.danger)
                    } else if sending {
                        Text(s.common.sending).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if draft.count > Self.maxLength - 200 {
                        Text("\(draft.count)/\(Self.maxLength)")
                            .textStyle(.caption)
                            .foregroundStyle(draft.count >= Self.maxLength ? Brand.danger : Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        sending = true
        failed = false
        defer { sending = false }
        do {
            let c = try await create(token, body)
            withAnimation(Motion.standardEase) { comments.append(c) }
            draft = ""
            sent += 1
        } catch {
            failed = true
        }
    }

    private func remove(_ c: ApiComment) async {
        guard let token else { return }
        withAnimation(Motion.standardEase) { comments.removeAll { $0.id == c.id } }
        do {
            try await delete(token, c.id)
        } catch {
            // Didn't go: it comes back.
            await reload()
        }
    }

    private func save(_ c: ApiComment, body: String) async throws {
        guard let token, let update else { return }
        var changed = try await update(token, c.id, body)
        // An answer without the new time still counts as edited.
        if changed.updatedAt == nil || changed.updatedAt == changed.createdAt { changed.updatedAt = ISO8601DateFormatter().string(from: Date()) }
        if let i = comments.firstIndex(where: { $0.id == c.id }) {
            withAnimation(Motion.standardEase) { comments[i] = changed }
        }
        sent += 1
    }

    /// A report (Art. 16 DSA), as on the web: the mail app opens with the notice filled in.
    private func report(_ c: ApiComment) {
        let website = AppConfig.current.websiteURL.absoluteString
        let date = MessageFormat.parse(c.createdAt)
            .map { $0.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(s.lang.locale)) } ?? c.createdAt
        let text = c.body.count > 400 ? String(c.body.prefix(400)) + "…" : c.body
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = Config.supportEmail
        mail.queryItems = [
            URLQueryItem(name: "subject", value: s.common.reportSubject),
            URLQueryItem(name: "body", value: s.common.reportBody(website + reportPath, c.username, date, c.id, text)),
        ]
        if let url = mail.url { openURL(url) }
    }

    private func timeAgo(_ c: ApiComment) -> String {
        guard let date = MessageFormat.parse(c.createdAt) else { return "" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        let text: String
        switch minutes {
        case ..<1: text = s.common.justNow
        case ..<60: text = s.common.minutesAgo(minutes)
        case ..<(24 * 60): text = s.common.hoursAgo(minutes / 60)
        default: text = s.common.daysAgo(minutes / (24 * 60))
        }
        if let edited = c.updatedAt, !edited.isEmpty, edited != c.createdAt {
            return text + " · " + s.common.edited
        }
        return text
    }
}

/// The stars an author gave the dish, next to their name.
private struct CommentStars: View {
    let value: Int
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= value ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(star <= value ? Brand.star : Palette.textTertiary.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.common.ratedStars(value))
    }
}

/// Edits an own comment: the text, save or cancel.
private struct CommentEditSheet: View {
    let comment: ApiComment
    let maxLength: Int
    let onSave: (_ body: String) async throws -> Void
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var failed = false
    @FocusState private var focused: Bool

    init(comment: ApiComment, maxLength: Int, onSave: @escaping (_ body: String) async throws -> Void) {
        self.comment = comment
        self.maxLength = maxLength
        self.onSave = onSave
        _text = State(initialValue: comment.body)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("", text: Binding(get: { text }, set: { text = String($0.prefix(maxLength)); failed = false }),
                          prompt: Text(s.common.writeComment).foregroundStyle(Palette.textTertiary), axis: .vertical)
                    .textStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Brand.accent)
                    .lineLimit(3...10)
                    .focused($focused)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 15)
                    .insetSurface(radius: Radius.md)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(focused ? Brand.accent : .clear, lineWidth: 1.5)
                    }
                    .disabled(saving)
                HStack {
                    if failed {
                        Text(s.common.commentFailed).textStyle(.caption).foregroundStyle(Brand.danger)
                    }
                    Spacer()
                    if text.count > maxLength - 200 {
                        Text("\(text.count)/\(maxLength)").textStyle(.caption)
                            .foregroundStyle(text.count >= maxLength ? Brand.danger : Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.sm)
            .appBackground()
            .navigationTitle(s.common.editComment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() } label: { Text(s.common.cancel) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if saving {
                        ProgressView().tint(Brand.accent)
                    } else {
                        Button(s.common.save) { Task { await save() } }
                            .buttonStyle(.glassProminent)
                            .tint(Brand.accent)
                            .disabled(trimmed.isEmpty || trimmed == comment.body)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(saving)
        .onAppear { focused = true }
    }

    private func save() async {
        guard !trimmed.isEmpty, !saving else { return }
        saving = true
        failed = false
        defer { saving = false }
        do {
            try await onSave(trimmed)
            dismiss()
        } catch {
            failed = true
        }
    }
}
