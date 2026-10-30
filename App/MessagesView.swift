import SwiftUI
import PokyhCore
import PokyhDesign

// Nachrichten: the WebUntis folders, one grouped list card per folder (today, this week,
// older). On a wide window the list and the open message sit side by side.

struct MessagesView: View {
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

    private var all: [MessagePreview] { cache[folder] ?? [] }
    private var messages: [MessagePreview] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.subject.localizedCaseInsensitiveContains(q)
                || $0.senderName.localizedCaseInsensitiveContains(q)
                || $0.contentPreview.localizedCaseInsensitiveContains(q)
        }
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
        .navigationTitle(s.nav.messages)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: s.messages.search)
        .toolbar {
            if folder == .inbox {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        Label(s.messages.markAllRead, systemImage: "envelope.open")
                    }
                    .disabled(unread.isEmpty || markingAll)
                }
            }
        }
        .task(id: folder) { await load(folder) }
        .onChange(of: folder) { selected = nil }
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
        if split {
            Button { selected = msg.id } label: {
                MessageRow(msg: msg)
                    .background(selected == msg.id ? Palette.accentTint : .clear)
            }
            .buttonStyle(.rowPress)
        } else {
            NavigationLink {
                MessageDetailScreen(preview: msg, folder: folder) { markReadLocally(msg.id) }
            } label: {
                MessageRow(msg: msg)
            }
            .buttonStyle(.rowPress)
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
                MessageDetailBody(preview: msg, folder: folder) { markReadLocally(msg.id) }
                    .modifier(ReadableContent())
            }
            .id(id)
        } else {
            EmptyStateView(systemImage: "envelope", title: s.messages.message)
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
            cache[f] = try await UntisClient.shared.messages(folder: f, session)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func markAllRead() async {
        guard let session = app.session, !markingAll else { return }
        markingAll = true
        defer { markingAll = false }
        for msg in unread {
            await UntisClient.shared.markRead(id: msg.id, session)
            markReadLocally(msg.id)
        }
    }

    private func markReadLocally(_ id: Int) {
        guard var list = cache[.inbox], let i = list.firstIndex(where: { $0.id == id }), !list[i].isRead else { return }
        list[i].isRead = true
        cache[.inbox] = list
    }
}

/// An inbox row. Unread shows as a heavier subject and an accent dot on the avatar, not as a
/// tinted row, which would put a second surface color inside the card.
struct MessageRow: View {
    let msg: MessagePreview
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.iconText) {
            InitialAvatar(name: msg.senderName, size: 42)
                .overlay(alignment: .topTrailing) {
                    if !msg.isRead {
                        Circle().fill(Brand.accent)
                            .frame(width: 8, height: 8)
                            .padding(2)
                            .background(Palette.card, in: .circle)
                            .offset(x: 2, y: -2)
                    }
                }
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
            }
        }
        .padding(Spacing.card)
        .contentShape(.rect)
    }
}

// ── Detail ──────────────────────────────────────────────────────────────────

struct MessageDetailScreen: View {
    let preview: MessagePreview
    let folder: MessageFolder
    var onRead: (() -> Void)? = nil
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            MessageDetailBody(preview: preview, folder: folder, onRead: onRead)
        }
        .navigationTitle(s.messages.message)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }
}

/// The subject as the page's title, the sender as a compact identity row, the text in a card,
/// so a long message reads as a document. Links ask before leaving the app.
struct MessageDetailBody: View {
    let preview: MessagePreview
    let folder: MessageFolder
    var onRead: (() -> Void)? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var detail: MessageDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var leaving: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            if loading {
                skeleton
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
                    .frame(minHeight: 320)
            } else if let d = detail {
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
                .fadeIn()

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

                if !d.attachments.isEmpty {
                    PokyhSection(s.messages.attachments) {
                        ListCard(d.attachments) { att in
                            HStack(spacing: Spacing.iconText) {
                                IconTile(fileSymbol(att.name), color: Brand.accent, size: 40)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(att.name).textStyle(.body).foregroundStyle(Palette.textPrimary).lineLimit(2)
                                    if att.size > 0 {
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(att.size), countStyle: .file))
                                            .textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Spacing.card)
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .fadeIn(delay: 0.08)
                }
            }
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxxl)
        .task { await load() }
        .alert(s.messages.externalLink, isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }), presenting: leaving) { url in
            Button(s.messages.openLink) { openURL(url) }
            Button(s.common.cancel, role: .cancel) {}
        } message: { url in
            Text("\(s.messages.leavingApp)\n\(url.absoluteString)")
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

    private func fileSymbol(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": "photo"
        case "doc", "docx", "odt", "txt", "rtf": "doc.text"
        case "xls", "xlsx", "ods", "csv": "tablecells"
        case "ppt", "pptx", "odp": "rectangle.on.rectangle"
        case "zip", "rar", "7z": "doc.zipper"
        default: "doc"
        }
    }

    private func load() async {
        guard let session = app.session else { return }
        loading = detail == nil
        error = nil
        do {
            detail = try await UntisClient.shared.messageDetail(id: preview.id, session)
            if folder == .inbox && !preview.isRead {
                await UntisClient.shared.markRead(id: preview.id, session)
                onRead?()
            }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

// ── Formatting ──────────────────────────────────────────────────────────────

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
