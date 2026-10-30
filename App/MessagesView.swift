import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import PokyhCore
import PokyhDesign

// Nachrichten: the WebUntis folders, one grouped list card per folder (today, this week,
// older). On a wide window the list and the open message sit side by side.

struct MessagesView: View {
    /// Opened from Home's "Nachricht schreiben": the compose sheet straight away.
    var startCompose = false

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var folder: MessageFolder = .inbox
    @State private var cache: [MessageFolder: [MessagePreview]] = [:]
    @State private var loadingFolders: Set<MessageFolder> = []
    @State private var error: String?
    @State private var query = ""
    @State private var markingAll = false
    @State private var selected: Int?
    @State private var width: CGFloat = 0
    @State private var compose: ComposeMode?
    @State private var composeOpened = false
    @State private var selecting = false
    @State private var picked: Set<Int> = []
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    @State private var deleted = 0

    private var all: [MessagePreview] { cache[folder] ?? [] }
    private var messages: [MessagePreview] {
        let words = MessageSearch.words(query)
        guard !words.isEmpty else { return all }
        return all.filter { MessageSearch.matches($0, words) }
    }
    /// The full skeleton only when the folder was never loaded.
    private var firstLoad: Bool { cache[folder] == nil && loadingFolders.contains(folder) }
    private var split: Bool { WidthClass(width: width) == .expanded }
    private var unread: [MessagePreview] { folder == .inbox ? all.filter { !$0.isRead } : [] }

    var body: some View {
        Group {
            if split {
                HStack(spacing: 0) {
                    listColumn.frame(width: 380)
                    Rectangle().fill(Palette.line).frame(width: 1).ignoresSafeArea(edges: .bottom)
                    detailColumn.frame(maxWidth: .infinity)
                }
            } else {
                listColumn.modifier(ReadableContent())
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle(selecting ? s.messages.selectedCount(picked.count) : s.nav.messages)
        .navigationBarTitleDisplayMode(selecting ? .inline : .large)
        .searchable(text: $query, prompt: s.messages.search)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionBar }
        }
        .task(id: folder) { await load(folder) }
        .task {
            guard startCompose, !composeOpened else { return }
            composeOpened = true
            compose = .new
        }
        .onChange(of: folder) {
            selected = nil
            endSelection()
        }
        .sheet(item: $compose) { mode in
            ComposeMessageSheet(mode: mode) { Task { await load(folder) } }
        }
        .alert(s.messages.deleteConfirm(picked.count), isPresented: $confirmDelete) {
            Button(s.messages.delete, role: .destructive) { Task { await deletePicked() } }
            Button(s.common.cancel, role: .cancel) {}
        }
        .alert(s.messages.deleteFailed, isPresented: $deleteFailed) {
            Button(s.common.ok, role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: deleted)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button(s.common.done) { endSelection() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if folder == .inbox {
                        Button {
                            Task { await markAllRead() }
                        } label: {
                            Label(s.messages.markAllRead, systemImage: "envelope.open")
                        }
                        .disabled(unread.isEmpty || markingAll)
                    }
                    Button {
                        withAnimation(Motion.standardEase) { selecting = true }
                    } label: {
                        Label(s.messages.select, systemImage: "checkmark.circle")
                    }
                    .disabled(all.isEmpty)
                } label: {
                    Label(s.common.more, systemImage: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { compose = .new } label: {
                    Label(s.messages.compose, systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// Floats over the list while picking: all or none, and the delete.
    private var selectionBar: some View {
        GlassEffectContainer {
            HStack(spacing: Spacing.md) {
                Button {
                    let ids = Set(messages.map(\.id))
                    picked = picked == ids ? [] : ids
                } label: {
                    Text(s.messages.selectAll).textStyle(.headline).padding(.horizontal, Spacing.sm)
                }
                .buttonStyle(.glass)
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmDelete = true } label: {
                    ButtonLabel(s.messages.delete, symbol: "trash", busy: deleting)
                        .padding(.horizontal, Spacing.sm)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.danger)
                .disabled(picked.isEmpty || deleting)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // ── List ────────────────────────────────────────────────────────────────

    private var listColumn: some View {
        VStack(spacing: 0) {
            PokyhSegmentedControl(MessageFolder.allCases, selection: $folder) { $0.label }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)

            ZStack(alignment: .top) {
                if firstLoad {
                    LoadingView()
                } else if let error, all.isEmpty {
                    ErrorStateView(message: error) { Task { await load(folder) } }
                } else if messages.isEmpty && !query.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass", title: s.messages.noMatches)
                } else if messages.isEmpty {
                    EmptyStateView(systemImage: "tray", title: s.messages.emptyTitle, subtitle: s.messages.emptyFolder)
                } else {
                    list
                }
                if loadingFolders.contains(folder) && !firstLoad {
                    ProgressView().controlSize(.small).tint(Brand.accent).padding(Spacing.sm)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var list: some View {
        let grouped = Dictionary(grouping: messages) { MessageFormat.group($0.sentDate) }
        let keys = grouped.keys.sorted()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(keys, id: \.self) { key in
                    EyebrowLabel(groupTitle(key))
                        .padding(.top, key == keys.first ? 0 : Spacing.lg)
                        .padding(.bottom, Spacing.sm)
                    ListCard(grouped[key] ?? []) { msg in row(msg) }
                        .fadeIn()
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .refreshable { await load(folder) }
        .animation(.easeInOut(duration: Motion.fast), value: messages.map(\.id))
    }

    @ViewBuilder private func row(_ msg: MessagePreview) -> some View {
        let label = MessageRow(msg: msg, selected: selecting && picked.contains(msg.id))
        Group {
            if selecting {
                Button { toggle(msg.id) } label: { label }
            } else if folder == .drafts {
                // A draft opens in the form again, to go on with it.
                Button { compose = .draft(msg.id) } label: { label }
            } else if split {
                Button { selected = msg.id } label: {
                    label.background(selected == msg.id ? Palette.accentTint : .clear)
                }
            } else {
                NavigationLink {
                    MessageDetailScreen(preview: msg, folder: folder) { markReadLocally(msg.id) }
                        .onDelete { removeLocally([msg.id]) }
                } label: { label }
            }
        }
        .buttonStyle(.rowPress)
        .contextMenu {
            if !selecting {
                Button {
                    withAnimation(Motion.standardEase) {
                        selecting = true
                        picked = [msg.id]
                    }
                } label: {
                    Label(s.messages.select, systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    picked = [msg.id]
                    confirmDelete = true
                } label: {
                    Label(s.messages.delete, systemImage: "trash")
                }
            }
        }
    }

    private func groupTitle(_ key: Int) -> String {
        switch key {
        case 0: s.messages.groupToday
        case 1: s.messages.groupWeek
        default: s.messages.groupOlder
        }
    }

    // ── Wide: the open message beside the list ──────────────────────────────

    @ViewBuilder private var detailColumn: some View {
        if let id = selected, let msg = all.first(where: { $0.id == id }) {
            ScrollView {
                MessageDetailBody(preview: msg, folder: folder, onRead: { markReadLocally(msg.id) }, onDeleted: {
                    selected = nil
                    removeLocally([msg.id])
                })
                .modifier(ReadableContent())
            }
            .id(id)
        } else {
            EmptyStateView(systemImage: "envelope", title: s.messages.message)
        }
    }

    // ── Selection ───────────────────────────────────────────────────────────

    private func toggle(_ id: Int) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func endSelection() {
        withAnimation(Motion.standardEase) {
            selecting = false
            picked = []
        }
    }

    private func deletePicked() async {
        guard let session = app.session, !picked.isEmpty, !deleting else { return }
        deleting = true
        defer { deleting = false }
        let ids = Array(picked)
        do {
            let gone = try await UntisClient.shared.deleteMessages(ids: ids, session)
            if selected.map(gone.contains) == true { selected = nil }
            removeLocally(gone)
            if !gone.isEmpty { deleted += 1 }
            if gone.count < ids.count { deleteFailed = true }
            endSelection()
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            deleteFailed = true
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    private func load(_ f: MessageFolder) async {
        guard let session = app.session else { return }
        // A folder already loaded stays on screen; the refresh runs quietly above it.
        loadingFolders.insert(f)
        error = nil
        defer { loadingFolders.remove(f) }
        do {
            let list = try await UntisClient.shared.messages(folder: f, session)
            cache[f] = list
            if f == .inbox { app.noteInbox(list) }
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func markAllRead() async {
        guard let session = app.session, !markingAll else { return }
        markingAll = true
        defer { markingAll = false }
        let ids = unread.map(\.id)
        await UntisClient.shared.markAllRead(ids: ids, session)
        ids.forEach(markReadLocally)
    }

    private func markReadLocally(_ id: Int) {
        guard var list = cache[.inbox], let i = list.firstIndex(where: { $0.id == id }), !list[i].isRead else { return }
        list[i].isRead = true
        cache[.inbox] = list
        app.messageWasRead()
    }

    private func removeLocally(_ ids: [Int]) {
        let gone = Set(ids)
        withAnimation(Motion.standardEase) {
            for (f, list) in cache { cache[f] = list.filter { !gone.contains($0.id) } }
        }
        if let inbox = cache[.inbox] { app.noteInbox(inbox) }
    }
}

/// An inbox row. Unread shows as a heavier subject and an accent dot on the avatar, not as a
/// tinted row, which would put a second surface color inside the card.
struct MessageRow: View {
    let msg: MessagePreview
    var selected = false
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.iconText) {
            InitialAvatar(name: msg.senderName, size: 42)
                .overlay {
                    if selected {
                        Circle().fill(Brand.accent)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Brand.onAccent)
                            }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !msg.isRead && !selected {
                        Circle().fill(Brand.accent)
                            .frame(width: 8, height: 8)
                            .padding(2)
                            .background(Palette.card, in: .circle)
                            .offset(x: 2, y: -2)
                    }
                }
                .animation(.spring(duration: 0.25), value: selected)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(msg.subject)
                        .textStyle(msg.isRead ? .body : TextStyle.body.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(MessageFormat.dateLabel(msg.sentDate, s.common))
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }
                HStack(spacing: Spacing.xs) {
                    Text(msg.senderName + (msg.contentPreview.isEmpty ? "" : " · \(msg.contentPreview)"))
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if msg.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityLabel(s.messages.attachment)
                    }
                    Spacer(minLength: 0)
                }
                if msg.needsConfirmation || (msg.readTotal ?? 0) > 0 {
                    HStack(spacing: Spacing.xs) {
                        if msg.needsConfirmation {
                            Pill(s.messages.needsConfirm, fill: Decorative.butter.fill, ink: Decorative.butter.ink)
                        }
                        if let total = msg.readTotal, total > 0 {
                            Pill(s.messages.readCount(msg.readConfirmed ?? 0, total), fill: Palette.nested, ink: Palette.textSecondary)
                        }
                    }
                    .padding(.top, Spacing.xxs)
                }
            }
        }
        .padding(Spacing.card)
        .contentShape(.rect)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small caption capsule inside a row.
private struct Pill: View {
    let text: String
    let fill: Color
    let ink: Color

    init(_ text: String, fill: Color, ink: Color) {
        self.text = text
        self.fill = fill
        self.ink = ink
    }

    var body: some View {
        Text(text)
            .textStyle(TextStyle.caption2.weight(.semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 1)
            .background(fill, in: .capsule)
    }
}

// ── Detail ──────────────────────────────────────────────────────────────────

struct MessageDetailScreen: View {
    let preview: MessagePreview
    let folder: MessageFolder
    var onRead: (() -> Void)?
    // Set through `onDelete(_:)`, so a trailing closure on the init stays `onRead`.
    private var onDeleted: (() -> Void)?
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    init(preview: MessagePreview, folder: MessageFolder, onRead: (() -> Void)? = nil) {
        self.preview = preview
        self.folder = folder
        self.onRead = onRead
    }

    /// What the list should do once the message is gone.
    func onDelete(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.onDeleted = action
        return copy
    }

    var body: some View {
        ScrollView {
            MessageDetailBody(preview: preview, folder: folder, onRead: onRead, onDeleted: {
                onDeleted?()
                dismiss()
            })
        }
        .navigationTitle(s.messages.message)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }
}

/// The subject as the page's title, the sender as a compact identity row, the text in a card,
/// so a long message reads as a document. Links ask before leaving the app. Below it what
/// Android offers: read confirmation, reply, delete, revoke and the attachments.
struct MessageDetailBody: View {
    let preview: MessagePreview
    let folder: MessageFolder
    var onRead: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var detail: MessageDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var leaving: URL?

    @State private var confirming = false
    @State private var confirmFailed = false
    @State private var confirmedAt: Date?
    @State private var showReadStatus = false
    @State private var replying = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var confirmRevoke = false
    @State private var revoking = false
    @State private var revokeFailed = false
    @State private var revoked = false

    @State private var attachmentsLoading = false
    @State private var downloading: String?
    @State private var downloaded: [String: URL] = [:]
    @State private var downloadError: String?
    @State private var previewURL: URL?
    @State private var success = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            if loading {
                skeleton
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
                    .frame(minHeight: 320)
            } else if let d = detail {
                header(d).fadeIn()
                if revoked { notice(s.messages.revokedNotice, tone: Decorative.blush) }
                if folder == .inbox && (preview.needsConfirmation || confirmedAt != nil) { confirmation(d) }
                if folder == .sent, let total = preview.readTotal, total > 0 { readStatusRow(total) }

                Text(MessageFormat.linked(d.body, color: Palette.accentText))
                    .textStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.card)
                    .cardSurface(radius: Radius.xl, fill: Palette.card)
                    .environment(\.openURL, OpenURLAction { url in
                        leaving = url
                        return .handled
                    })
                    .fadeIn(delay: 0.04)

                actions.fadeIn(delay: 0.06)
                attachments(d).fadeIn(delay: 0.08)
            }
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxxl)
        .task { await load() }
        .onDisappear {
            // Not while QuickLook still shows one of them.
            guard previewURL == nil else { return }
            AttachmentFiles.discard(Array(downloaded.values))
            downloaded = [:]
        }
        .alert(s.messages.externalLink, isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }), presenting: leaving) { url in
            Button(s.messages.openLink) { openURL(url) }
            Button(s.common.cancel, role: .cancel) {}
        } message: { url in
            Text("\(s.messages.leavingApp)\n\(url.absoluteString)")
        }
        .alert(s.messages.deleteConfirm(1), isPresented: $confirmDelete) {
            Button(s.messages.delete, role: .destructive) { Task { await delete() } }
            Button(s.common.cancel, role: .cancel) {}
        }
        .confirmationDialog(s.messages.revokeConfirm, isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(s.messages.revoke, role: .destructive) { Task { await revoke() } }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(s.messages.revokeHint)
        }
        .sheet(isPresented: $replying) {
            ComposeMessageSheet(mode: .reply(preview.id))
        }
        .sheet(isPresented: $showReadStatus) {
            ReadStatusSheet(messageId: preview.id)
        }
        .quickLookPreview($previewURL)
        .sensoryFeedback(.success, trigger: success)
    }

    private func header(_ d: MessageDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(d.subject)
                .textStyle(.title1)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.iconText) {
                InitialAvatar(name: d.senderName, size: 44)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(d.senderName).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                    Text(MessageFormat.fullDate(d.sentDate, s)).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func notice(_ text: String, tone: Tone) -> some View {
        Text(text)
            .textStyle(TextStyle.callout.weight(.semibold))
            .foregroundStyle(tone.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.card)
            .background(tone.fill, in: .pokyh(Radius.lg))
            .transition(.opacity)
    }

    /// A read confirmation the sender asked for, in butter until it's given.
    private func confirmation(_ d: MessageDetail) -> some View {
        let tone = Decorative.butter
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if let confirmedAt {
                Text(s.messages.confirmDone(MessageFormat.fullDate(ISO8601DateFormatter().string(from: confirmedAt), s)))
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .foregroundStyle(tone.ink)
            } else {
                Text(s.messages.confirmTitle).textStyle(TextStyle.callout.weight(.bold)).foregroundStyle(tone.ink)
                Text(s.messages.confirmText(d.senderName)).textStyle(.footnote).foregroundStyle(tone.ink)
                Button { Task { await confirmRead() } } label: {
                    ButtonLabel(s.messages.confirmAction, symbol: "checkmark", busy: confirming)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(confirming)
                .padding(.top, Spacing.xs)
                if confirmFailed {
                    Text(s.messages.confirmFailed).textStyle(.footnote).foregroundStyle(Brand.danger)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.card)
        .background(tone.fill, in: .pokyh(Radius.lg))
        .animation(Motion.standardEase, value: confirmedAt)
    }

    /// How many recipients confirmed reading, with who behind "Ansehen".
    private func readStatusRow(_ total: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(s.messages.readStatus(preview.readConfirmed ?? 0, total))
                .textStyle(.callout)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextLinkButton(s.messages.readStatusOpen) { showReadStatus = true }
        }
        .padding(.leading, Spacing.card)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .cardSurface(radius: Radius.lg, fill: Palette.card)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if folder == .inbox {
                Button { replying = true } label: {
                    ButtonLabel(s.messages.reply, symbol: "arrowshape.turn.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary(compact: true))
            }
            // A sent message can be taken back where WebUntis allows it; it asks first.
            if folder == .sent && !revoked {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button { confirmRevoke = true } label: {
                        ButtonLabel(s.messages.revoke, symbol: "arrow.uturn.backward", busy: revoking)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary(compact: true))
                    .disabled(revoking)
                    Text(s.messages.revokeHint).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                    if revokeFailed {
                        Text(s.messages.revokeFailed).textStyle(.footnote).foregroundStyle(Brand.danger)
                    }
                }
            }
            TextLinkButton(s.messages.delete, symbol: "trash", color: Brand.danger) { confirmDelete = true }
                .padding(.leading, -Spacing.md)
            if deleteFailed {
                Text(s.messages.deleteFailed).textStyle(.footnote).foregroundStyle(Brand.danger)
            }
        }
    }

    // ── Attachments ─────────────────────────────────────────────────────────

    @ViewBuilder private func attachments(_ d: MessageDetail) -> some View {
        if !d.attachments.isEmpty || attachmentsLoading {
            PokyhSection(s.messages.attachments) {
                if d.attachments.isEmpty {
                    Text(s.messages.attachmentsLoading).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                } else {
                    ListCard(d.attachments) { att in attachmentRow(att) }
                }
                if let downloadError {
                    Text(downloadError).textStyle(.footnote).foregroundStyle(Brand.danger)
                        .padding(.top, Spacing.sm)
                }
            }
        } else if preview.hasAttachments {
            // Said to have files, but none came back.
            PokyhSection(s.messages.attachments) {
                Button { Task { await reloadAttachments() } } label: {
                    Text(s.messages.attachmentsError + " · " + s.messages.tapToReload)
                        .textStyle(.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.card)
                        .contentShape(.rect)
                }
                .buttonStyle(.rowPress(radius: Radius.lg))
                .cardSurface(radius: Radius.lg, fill: Palette.card)
            }
        }
    }

    private func attachmentRow(_ att: MessageAttachment) -> some View {
        let key = Self.key(att)
        let file = downloaded[key]
        return HStack(spacing: Spacing.iconText) {
            Button { Task { await open(att) } } label: {
                HStack(spacing: Spacing.iconText) {
                    FileGlyph(name: att.name)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(att.name).textStyle(.body).foregroundStyle(Palette.textPrimary).lineLimit(2)
                        if att.size > 0 {
                            Text(FileSize.label(att.size)).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if downloading == key {
                        ProgressView().controlSize(.small).tint(Brand.accent)
                    } else if file == nil {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accentText)
                            .frame(width: 32, height: 32)
                            .accentSurface(radius: Radius.md)
                            .accessibilityLabel(s.messages.download)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(downloading != nil && downloading != key)
            if let file {
                ShareLink(item: file) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 32, height: 32)
                        .accentSurface(radius: Radius.md)
                }
                .accessibilityLabel(s.messages.openExternally)
            }
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    private static func key(_ a: MessageAttachment) -> String { "\(a.id):\(a.storageId):\(a.name)" }

    private func open(_ att: MessageAttachment) async {
        let key = Self.key(att)
        if let url = downloaded[key] {
            previewURL = url
            return
        }
        guard let session = app.session, downloading == nil else { return }
        downloading = key
        downloadError = nil
        defer { downloading = nil }
        guard let file = await UntisClient.shared.downloadAttachment(messageId: preview.id, attachment: att, session),
              let url = AttachmentFiles.write(file) else {
            downloadError = s.messages.attachmentFailed
            return
        }
        downloaded[key] = url
        previewURL = url
    }

    private func reloadAttachments() async {
        guard let session = app.session, detail != nil else { return }
        attachmentsLoading = true
        let found = await UntisClient.shared.messageAttachments(id: preview.id, session)
        detail?.attachments = found
        attachmentsLoading = false
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    private func confirmRead() async {
        guard let session = app.session, !confirming else { return }
        confirming = true
        confirmFailed = false
        defer { confirming = false }
        do {
            try await UntisClient.shared.confirmMessageRead(id: preview.id, session)
            confirmedAt = Date()
            success += 1
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            confirmFailed = true
        }
    }

    private func delete() async {
        guard let session = app.session else { return }
        deleteFailed = false
        do {
            let gone = try await UntisClient.shared.deleteMessages(ids: [preview.id], session)
            if gone.contains(preview.id) {
                success += 1
                onDeleted?()
            } else {
                deleteFailed = true
            }
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            deleteFailed = true
        }
    }

    private func revoke() async {
        guard let session = app.session, !revoking else { return }
        revoking = true
        revokeFailed = false
        defer { revoking = false }
        do {
            try await UntisClient.shared.revokeMessage(id: preview.id, session)
            withAnimation(Motion.standardEase) { revoked = true }
            success += 1
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            revokeFailed = true
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SkeletonBlock(height: 26, width: 240)
            HStack(spacing: Spacing.iconText) {
                Circle().fill(Palette.cardAlt).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SkeletonBlock(height: 13, width: 140)
                    SkeletonBlock(height: 10, width: 100)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(0..<6, id: \.self) { i in SkeletonBlock(height: 12, width: i == 5 ? 160 : nil) }
            }
            .padding(Spacing.card)
            .cardSurface(radius: Radius.xl, fill: Palette.card)
        }
    }

    private func load() async {
        guard let session = app.session else { return }
        loading = detail == nil
        error = nil
        do {
            var d = try await UntisClient.shared.messageDetail(id: preview.id, session)
            if d.attachments.isEmpty && preview.hasAttachments {
                d.attachments = await UntisClient.shared.messageAttachments(id: preview.id, session)
            }
            detail = d
            if folder == .inbox && !preview.isRead {
                await UntisClient.shared.markRead(id: preview.id, session)
                onRead?()
            }
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

/// Who of the recipients confirmed reading; a class lists its people one by one.
private struct ReadStatusSheet: View {
    let messageId: Int
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var list: [ReadStatusRecipient]?
    @State private var failed = false

    private struct Line: Identifiable {
        let id: Int
        let name: String
        let group: String
        let at: String?
    }

    private var lines: [Line] {
        var out: [Line] = []
        for r in list ?? [] {
            if r.people.count > 1 {
                for p in r.people { out.append(Line(id: out.count, name: p.name, group: r.className.isEmpty ? r.name : r.className, at: p.confirmedAt)) }
            } else {
                out.append(Line(id: out.count, name: r.name, group: r.className, at: r.confirmedAt))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    ErrorStateView(message: s.messages.readStatusFailed) { Task { await load() } }
                } else if list == nil {
                    LoadingView()
                } else {
                    ScrollView {
                        ListCard(lines) { line in
                            HStack(spacing: Spacing.iconText) {
                                InitialAvatar(name: line.name, size: 34)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(line.name).textStyle(TextStyle.callout.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                    if !line.group.isEmpty && line.group != line.name {
                                        Text(line.group).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                                    }
                                }
                                Spacer(minLength: Spacing.sm)
                                Text(line.at.map { s.messages.readConfirmedOn(MessageFormat.fullDate($0, s)) } ?? s.messages.readPending)
                                    .textStyle(.caption)
                                    .foregroundStyle(line.at != nil ? Brand.success : Palette.textTertiary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, Spacing.card)
                            .padding(.vertical, Spacing.md)
                        }
                        .padding(.horizontal, Spacing.screenH)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
            }
            .navigationTitle(s.messages.readStatusTitle)
            .navigationBarTitleDisplayMode(.inline)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel(s.common.close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .task { await load() }
    }

    private func load() async {
        guard let session = app.session else { return }
        failed = false
        do {
            list = try await UntisClient.shared.messageReadStatus(id: messageId, session)
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            failed = true
        }
    }
}

// ── Compose ─────────────────────────────────────────────────────────────────

/// What the compose sheet is for: a new message, a reply, or a saved draft to go on with.
enum ComposeMode: Identifiable, Hashable {
    case new
    case reply(Int)
    case draft(Int)

    var id: String {
        switch self {
        case .new: "new"
        case .reply(let id): "reply-\(id)"
        case .draft(let id): "draft-\(id)"
        }
    }
}

/// "Mitteilung an Lehrkraft", the web's compose sheet. The recipients are a step pushed inside
/// the same sheet, not a sheet on a sheet.
struct ComposeMessageSheet: View {
    let mode: ComposeMode
    /// Sent, saved or deleted: the folder behind should load again.
    var onDone: (() -> Void)? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    @State private var recipients: [MessageRecipient] = []
    @State private var recipientsLoaded = false
    @State private var recipientsFailed = false
    @State private var selected: [MessageRecipient] = []
    @State private var subject = ""
    @State private var content = ""
    @State private var files: [OutgoingAttachment] = []
    @State private var replyRecipient: String?
    @State private var replyLoading = false
    @State private var draftLoading = false
    @State private var sending = false
    @State private var savingDraft = false
    @State private var sent = false
    @State private var draftSaved = false
    @State private var error: String?
    @State private var importing = false
    @State private var confirmDraftDelete = false
    @State private var started = false

    /// Files bigger than this aren't read into memory; WebUntis' own cap is lower still.
    private static let maxFileBytes = 20 * 1024 * 1024

    private var isReply: Bool { if case .reply = mode { true } else { false } }
    private var draftId: Int? { if case .draft(let id) = mode { id } else { nil } }
    private var busy: Bool { sending || savingDraft || sent || draftSaved }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.rowGap) {
                        recipientField
                        PokyhTextField(placeholder: s.messages.subject, text: Binding(get: { subject }, set: {
                            subject = String($0.prefix(255))
                            error = nil
                        }))
                        .disabled(busy)
                        ComposeTextArea(placeholder: s.messages.textHint, text: Binding(get: { content }, set: {
                            content = String($0.prefix(10_000))
                            error = nil
                        }))
                        .disabled(busy)
                    }

                    if !files.isEmpty { fileList }

                    VStack(spacing: Spacing.rowGap) {
                        Button { importing = true } label: {
                            ButtonLabel(s.messages.addAttachment, symbol: "paperclip").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.secondary(compact: true))
                        .disabled(busy)
                        if draftId != nil {
                            Button { confirmDraftDelete = true } label: {
                                ButtonLabel(s.messages.deleteDraft, symbol: "trash").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.secondary(compact: true))
                            .disabled(busy)
                        }
                        if !isReply {
                            Button { Task { await submit(asDraft: true) } } label: {
                                ButtonLabel(draftSaved ? s.messages.draftSaved : s.messages.saveDraft,
                                            symbol: draftSaved ? "checkmark" : "square.and.pencil", busy: savingDraft)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.secondary(compact: true))
                            .disabled(busy)
                        }
                    }

                    if draftLoading {
                        Text(s.messages.draftLoading).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                    }
                    if recipientsFailed && !isReply {
                        Text(s.messages.recipientsFailed).textStyle(.footnote).foregroundStyle(Brand.warning)
                    }
                    if let error { SheetNote(error, color: Brand.danger) }
                    if sent { SheetNote(isReply ? s.messages.replySent : s.messages.messageSent, color: Brand.success) }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
                .animation(Motion.standardEase, value: files.map(\.name))
                .animation(Motion.standardEase, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle(isReply ? s.messages.reply : s.messages.toTeacher)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel(s.common.close)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if sending {
                        ProgressView().tint(Brand.accent)
                    } else {
                        Button { Task { await send() } } label: {
                            Image(systemName: sent ? "checkmark" : "paperplane.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .tint(sent ? Brand.success : Brand.accent)
                        .disabled(busy)
                        .accessibilityLabel(s.common.send)
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            addFiles(urls)
        }
        .alert(s.messages.deleteDraft, isPresented: $confirmDraftDelete) {
            Button(s.messages.delete, role: .destructive) { Task { await deleteDraft() } }
            Button(s.common.cancel, role: .cancel) {}
        }
        .interactiveDismissDisabled(sending || savingDraft)
        .presentationDetents([.large])
        .presentationSizing(.form)
        .sensoryFeedback(.success, trigger: sent || draftSaved) { _, done in done }
        .task {
            guard !started else { return }
            started = true
            await start()
        }
    }

    @ViewBuilder private var recipientField: some View {
        if isReply {
            // A reply goes to the sender; WebUntis says who that is.
            SheetField(label: s.messages.to,
                       value: replyRecipient.flatMap { $0.isEmpty ? nil : $0 } ?? (replyLoading ? "…" : s.messages.unavailable),
                       placeholder: (replyRecipient ?? "").isEmpty, chevron: false)
        } else {
            NavigationLink {
                RecipientPicker(recipients: recipients, loaded: recipientsLoaded, failed: recipientsFailed, selected: $selected)
            } label: {
                SheetField(label: s.messages.to, value: recipientLabel, placeholder: selected.isEmpty, chevron: true)
            }
            .buttonStyle(.rowPress(radius: Radius.lg))
            .disabled(busy)
        }
    }

    private var recipientLabel: String {
        if selected.isEmpty { return recipientsFailed ? s.messages.unavailable : s.messages.choose }
        if selected.count == 1 { return selected[0].name }
        return s.messages.recipientsCount(selected.count)
    }

    private var fileList: some View {
        VStack(spacing: Spacing.rowGap) {
            ForEach(Array(files.enumerated()), id: \.offset) { i, file in
                HStack(spacing: Spacing.iconText) {
                    FileGlyph(name: file.name)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.name).textStyle(.subheadline).foregroundStyle(Palette.textPrimary).lineLimit(1)
                        Text(FileSize.label(file.data.count)).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    IconButton("xmark", label: s.messages.removeFile(file.name), size: 32, tint: Palette.textSecondary) {
                        files.remove(at: i)
                    }
                    .disabled(busy)
                }
                .padding(Spacing.md)
                .nestedSurface(radius: Radius.lg)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    // ── Work ────────────────────────────────────────────────────────────────

    private func start() async {
        guard let session = app.session else { return }
        switch mode {
        case .new:
            await loadRecipients(session)
        case .reply(let id):
            replyLoading = true
            defer { replyLoading = false }
            do {
                let form = try await UntisClient.shared.replyForm(messageId: id, session)
                replyRecipient = form.recipientName
                if subject.isEmpty { subject = String(form.subject.prefix(255)) }
            } catch {
                fail(error, fallback: s.messages.replyFailed)
            }
        case .draft(let id):
            draftLoading = true
            async let people: Void = loadRecipients(session)
            do {
                let d = try await UntisClient.shared.draft(id: id, session)
                subject = String(d.subject.prefix(255))
                content = String(d.content.prefix(10_000))
                selected = Array(d.recipients.prefix(1))
            } catch {
                fail(error, fallback: s.common.unknownError)
            }
            draftLoading = false
            await people
        }
    }

    private func loadRecipients(_ session: UserSession) async {
        do {
            recipients = try await UntisClient.shared.messageRecipients(session)
            recipientsFailed = false
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            recipientsFailed = true
        }
        recipientsLoaded = true
    }

    private func send() async {
        guard !busy else { return }
        let t = s.messages
        if isReply && replyRecipient == nil { error = t.noReply; return }
        if !isReply && selected.isEmpty { error = t.pickTeacher; return }
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = t.needSubject; return }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = t.needText; return }
        await submit(asDraft: false)
    }

    private func submit(asDraft: Bool) async {
        guard let session = app.session, !busy else { return }
        if asDraft && subject.trimmingCharacters(in: .whitespaces).isEmpty
            && content.trimmingCharacters(in: .whitespaces).isEmpty && selected.isEmpty && files.isEmpty {
            error = s.messages.needSomething
            return
        }
        if asDraft { savingDraft = true } else { sending = true }
        error = nil
        defer {
            sending = false
            savingDraft = false
        }
        do {
            let title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if case .reply(let id) = mode {
                try await UntisClient.shared.sendReply(messageId: id, subject: title, content: text, attachments: files, session)
            } else {
                try await UntisClient.shared.sendMessage(subject: title, content: text, recipients: selected, attachments: files,
                                                         asDraft: asDraft, draftId: draftId, session)
            }
            withAnimation(Motion.standardEase) {
                if asDraft { draftSaved = true } else { sent = true }
            }
            onDone?()
            // The confirmation stays a beat before the sheet leaves.
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        } catch {
            fail(error, fallback: asDraft ? s.errors.draftFailed : s.errors.sendFailed)
        }
    }

    private func deleteDraft() async {
        guard let session = app.session, let id = draftId else { return }
        let gone = (try? await UntisClient.shared.deleteMessages(ids: [id], session)) ?? []
        if gone.contains(id) {
            onDone?()
            dismiss()
        } else {
            error = s.messages.deleteFailed
        }
    }

    private func fail(_ e: Error, fallback: String) {
        if let e = e as? AppError {
            if e.isSessionExpired {
                app.handleSessionExpired()
                error = s.common.sessionExpired
            } else {
                error = e.message
            }
        } else {
            error = fallback
        }
    }

    /// Reads the picked files into memory, each once; a file too big or unreadable is reported.
    private func addFiles(_ urls: [URL]) {
        var unreadable = false
        let known = Set(files.map { "\($0.name):\($0.data.count)" })
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maxFileBytes, let data = try? Data(contentsOf: url), data.count <= Self.maxFileBytes else {
                unreadable = true
                continue
            }
            let name = url.lastPathComponent
            guard !known.contains("\(name):\(data.count)") else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            files.append(OutgoingAttachment(name: name, mimeType: mime, data: data))
        }
        error = unreadable ? s.messages.fileUnreadable : nil
    }
}

/// The teachers, grouped as the API groups them: class teachers first, then the rest. One
/// teacher per message; picking one goes back to the form.
private struct RecipientPicker: View {
    let recipients: [MessageRecipient]
    let loaded: Bool
    let failed: Bool
    @Binding var selected: [MessageRecipient]
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matching: [MessageRecipient] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? recipients : recipients.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if recipients.isEmpty {
                    Text(failed ? s.messages.recipientsFailedLater : (loaded ? s.messages.unavailable : s.messages.recipientsLoading))
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.xl)
                } else {
                    group(s.messages.classTeacher, matching.filter(\.isClassTeacher))
                    group(s.messages.others, matching.filter { !$0.isClassTeacher })
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .appBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: s.messages.searchTeacher)
        .navigationTitle(s.messages.recipients)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(s.messages.doneCount(selected.count)) { dismiss() }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    @ViewBuilder private func group(_ title: String, _ items: [MessageRecipient]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.rowGap) {
                EyebrowLabel(title)
                ForEach(items) { r in
                    let on = selected.contains { $0.id == r.id && $0.type == r.type }
                    Button {
                        if on {
                            selected = []
                        } else {
                            selected = [r]
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: Spacing.iconText) {
                            InitialAvatar(name: r.name, size: 36)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.name)
                                    .textStyle(on ? TextStyle.body.weight(.semibold) : .body)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                if let role = r.role {
                                    Text(role).textStyle(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if on {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Brand.accent)
                                    .accessibilityLabel(s.messages.selected)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(on ? Palette.accentTint : .clear, in: .pokyh(Radius.lg))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.rowPress(radius: Radius.lg))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// The message text, at least six lines tall, in the recessed field style.
private struct ComposeTextArea: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary), axis: .vertical)
            .textStyle(.body)
            .foregroundStyle(Palette.textPrimary)
            .tint(Brand.accent)
            .lineLimit(6...)
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

// ── Sheet parts, shared with the absence sheets ─────────────────────────────

/// "Label → value ›" on a recessed strip; the sheet's own surface, no card inside a sheet.
struct SheetField: View {
    let label: String
    let value: String
    var placeholder = false
    var chevron = true

    var body: some View {
        HStack(spacing: Spacing.iconText) {
            Text(label).textStyle(.body).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .textStyle(.subheadline)
                .foregroundStyle(placeholder ? Palette.textTertiary : Palette.textSecondary)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, Spacing.card)
        .insetSurface(radius: Radius.lg)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// An error or confirmation line on a nested strip.
struct SheetNote: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .textStyle(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .nestedSurface(radius: Radius.lg)
            .transition(.opacity)
    }
}

/// The big check a sheet shows once its work is done, with what was done below it.
struct SheetDone: View {
    let text: String
    var detail: String? = nil
    var warning: String? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Brand.success)
                .frame(width: 64, height: 64)
                .accentSurface(radius: Radius.xl)
                .symbolEffect(.bounce, value: text)
            Text(text).textStyle(.headline).foregroundStyle(Palette.textPrimary).multilineTextAlignment(.center)
            if let detail {
                Text(detail).textStyle(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            }
            if let warning {
                Text(warning).textStyle(TextStyle.footnote.weight(.semibold)).foregroundStyle(Brand.danger).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// PDFs and pictures get their own glyph, the two kinds a school actually sends.
struct FileGlyph: View {
    let name: String
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: Self.symbol(name))
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Palette.accentText)
            .frame(width: size, height: size)
            .accentSurface(radius: Radius.md)
            .accessibilityHidden(true)
    }

    static func symbol(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp": "photo"
        case "doc", "docx", "odt", "txt", "rtf": "doc.text"
        case "xls", "xlsx", "ods", "csv": "tablecells"
        case "ppt", "pptx", "odp": "rectangle.on.rectangle"
        case "zip", "rar", "7z": "doc.zipper"
        default: "doc"
        }
    }
}

enum FileSize {
    static func label(_ bytes: Int) -> String {
        bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) : ""
    }
}

/// Downloaded files go to a folder of their own in tmp, so QuickLook and the share sheet see the
/// name as it was sent. They're removed again when the screen goes.
enum AttachmentFiles {
    private static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("attachments", isDirectory: true) }

    static func write(_ file: DownloadedAttachment) -> URL? {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var name = file.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = Strings.current.messages.attachment }
        if (name as NSString).pathExtension.isEmpty, let ext = UTType(mimeType: file.mimeType)?.preferredFilenameExtension {
            name += ".\(ext)"
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try file.data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    static func discard(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
}

// ── Formatting ──────────────────────────────────────────────────────────────

/// The web's message search: accents folded, every word in subject, sender or preview.
nonisolated enum MessageSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func words(_ q: String) -> [String] {
        fold(q).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(_ m: MessagePreview, _ words: [String]) -> Bool {
        let hay = fold(m.subject + " " + m.senderName + " " + m.contentPreview)
        return words.allSatisfy { hay.contains($0) }
    }
}

nonisolated enum MessageFormat {
    /// "08:15" today, "Gestern", the weekday within a week, else "dd.MM.".
    static func dateLabel(_ dateStr: String, _ c: CommonStrings) -> String {
        guard let date = parse(dateStr) else { return "" }
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if cal.isDateInToday(date) { f.dateFormat = "HH:mm"; return f.string(from: date) }
        if cal.isDateInYesterday(date) { return c.yesterday }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if (1...6).contains(days) {
            let i = (cal.component(.weekday, from: date) + 5) % 7
            if c.weekdaysShort.indices.contains(i) { return c.weekdaysShort[i] }
        }
        f.dateFormat = "dd.MM."
        return f.string(from: date)
    }

    /// Same label in the language the app runs in, for screens without the strings at hand.
    static func date(_ dateStr: String) -> String {
        dateLabel(dateStr, Strings.of(LanguageChoice.current(in: .standard)).common)
    }

    static func fullDate(_ dateStr: String) -> String {
        fullDate(dateStr, Strings.of(LanguageChoice.current(in: .standard)))
    }

    /// Today (0), this week since Monday (1) or older (2), for the list's sections.
    static func group(_ dateStr: String) -> Int {
        guard let date = parse(dateStr) else { return 2 }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        if cal.isDateInToday(date) { return 0 }
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        return date >= monday ? 1 : 2
    }

    /// "29. Oktober 2026 um 08:15".
    static func fullDate(_ dateStr: String, _ s: Strings) -> String {
        guard let date = parse(dateStr) else { return dateStr }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = s.common.dateLong(c.day ?? 1, c.month ?? 1, c.year ?? 2000)
        return s.messages.at(day, String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    static func parse(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Strips HTML down to plain text, roughly what the web's sanitizer leaves.
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

    /// The message text with its links tappable. An HTML link keeps its address next to the text.
    static func linked(_ raw: String, color: Color) -> AttributedString {
        let anchors = try? NSRegularExpression(pattern: #"<a\s[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        var withHrefs = raw
        if let anchors {
            let ns = raw as NSString
            var out = ""
            var last = 0
            for m in anchors.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let href = ns.substring(with: m.range(at: 1))
                let label = ns.substring(with: m.range(at: 2))
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                out += label.isEmpty || label == href ? href : "\(label) (\(href))"
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            withHrefs = out
        }
        let text = plainText(withHrefs)
        var result = AttributedString(text)
        guard let urls = try? NSRegularExpression(pattern: #"(https?://[^\s<>"{}|\\^`\[\]]+)|(www\.[^\s<>"]+)"#) else { return result }
        let ns = text as NSString
        for m in urls.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var url = ns.substring(with: m.range)
            while let last = url.last, ".,;:)!?".contains(last) { url.removeLast() }
            let range = NSRange(location: m.range.location, length: (url as NSString).length)
            guard let r = Range(range, in: text),
                  let lower = AttributedString.Index(r.lowerBound, within: result),
                  let upper = AttributedString.Index(r.upperBound, within: result),
                  let target = URL(string: url.hasPrefix("www.") ? "https://\(url)" : url) else { continue }
            result[lower..<upper].link = target
            result[lower..<upper].swiftUI.foregroundColor = color
            result[lower..<upper].swiftUI.underlineStyle = .single
        }
        return result
    }
}
