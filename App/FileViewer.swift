import SwiftUI
import QuickLook
import PokyhCore
import PokyhDesign

/// A file shown in the app, the way Mail shows an attachment: PDFs, pictures, Office files, text.
/// QuickLook draws it with its own bar (sharing, pages); until the file is here a plain bar with
/// a spinner stands in.
struct FileViewerSheet: View {
    let name: String
    let load: () async -> URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        if let file {
            QuickLookView(url: file) { dismiss() }
                .ignoresSafeArea()
        } else {
            NavigationStack {
                Group {
                    if failed {
                        ErrorStateView(message: s.messages.attachmentFailed) { Task { await fetch() } }
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Brand.accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bg.ignoresSafeArea())
                // QuickLook titles it without the extension too.
                .navigationTitle((name as NSString).deletingPathExtension)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) { dismiss() }
                    }
                }
            }
            .task { await fetch() }
        }
    }

    private func fetch() async {
        failed = false
        if let url = await load() {
            file = url
        } else {
            failed = true
        }
    }
}

/// QuickLook in a navigation controller of its own: embedded without one it draws nothing.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    let close: () -> Void

    func makeCoordinator() -> Source { Source(url: url, close: close) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        let source = context.coordinator
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in source.close() })
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ host: UINavigationController, context: Context) {
        context.coordinator.close = close
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        (host.viewControllers.first as? QLPreviewController)?.reloadData()
    }

    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL
        var close: () -> Void
        init(url: URL, close: @escaping () -> Void) {
            self.url = url
            self.close = close
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// Each file of an open message is fetched once, by the prefetch or the first tap, whichever
/// comes first. Everything fetched goes again with the message.
@MainActor
final class AttachmentLoads {
    private var tasks: [String: Task<URL?, Never>] = [:]
    private var files: [URL] = []
    private var closed = false

    func file(_ key: String, fetch: @escaping () async -> URL?) async -> URL? {
        if let running = tasks[key] { return await running.value }
        let task = Task { await fetch() }
        tasks[key] = task
        let url = await task.value
        guard let url else {
            tasks[key] = nil
            return nil
        }
        // Arrived after the message was closed: nobody will show it.
        if closed {
            AttachmentFiles.discard([url])
            return nil
        }
        files.append(url)
        return url
    }

    func discard() {
        closed = true
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        AttachmentFiles.discard(files)
        files = []
    }
}
