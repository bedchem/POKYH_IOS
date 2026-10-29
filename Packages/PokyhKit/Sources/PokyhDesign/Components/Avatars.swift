import SwiftUI
import PokyhCore

/// Initials on the person's color. Falls back to this while a profile image loads.
public struct InitialAvatar: View {
    let name: String
    let color: Color
    let size: CGFloat

    public init(_ name: String, color: Color, size: CGFloat = 40) {
        self.name = name
        self.color = color
        self.size = size
    }

    public var body: some View {
        Text(Self.initials(of: name))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .circle)
            .accessibilityHidden(true)
    }

    static func initials(of name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" }).prefix(2)
        let letters = parts.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// A remote profile image over the initials, so there's never an empty circle.
public struct PokyhAvatar: View {
    let name: String
    let url: URL?
    let color: Color
    let size: CGFloat

    public init(_ name: String, url: URL?, color: Color, size: CGFloat = 40) {
        self.name = name
        self.url = url
        self.color = color
        self.size = size
    }

    public var body: some View {
        InitialAvatar(name, color: color, size: size)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(.circle)
                }
            }
    }
}
