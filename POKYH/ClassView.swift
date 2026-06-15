import SwiftUI

struct ClassView: View {
    @EnvironmentObject var app: AppState
    @State private var klass: ApiClass?
    @State private var loading = true
    @State private var error: String?

    private var hasBackend: Bool { app.session?.apiToken != nil }

    var body: some View {
        Group {
            if !hasBackend {
                BackendUnavailableView(feature: "Die Klassenansicht")
            } else if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if let c = klass {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(Palette.accent)
                            Text(c.name).font(.title2.bold())
                            HStack(spacing: 6) {
                                Text("Code:").foregroundStyle(.secondary)
                                Text(c.code).font(.body.monospaced().bold())
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Palette.accent.opacity(0.12), in: Capsule())
                            }.font(.subheadline)
                        }
                        .frame(maxWidth: .infinity).padding(20)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(c.members.count) Mitglieder").font(.headline)
                            ForEach(c.members) { m in
                                HStack(spacing: 12) {
                                    InitialAvatar(name: m.username, size: 36)
                                    Text(m.username)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptyStateView(systemImage: "person.3", title: "Keine Klasse", subtitle: "Du bist noch keiner Klasse beigetreten.")
            }
        }
        .navigationTitle("Klasse")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task { if hasBackend { await load() } }
    }

    private func load() async {
        guard let token = app.session?.apiToken else { return }
        loading = true; error = nil
        do { klass = try await BackendClient.shared.myClass(token: token) }
        catch { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        loading = false
    }
}
