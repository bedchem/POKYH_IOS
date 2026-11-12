import Foundation
import Testing
@testable import PokyhCore

// Since pokyh-backend 6334b24 GET /dishes names its own pictures by path while PUBLIC_BASE_URL
// is empty; popups do the same with <img src="/popup-images/<id>">.
struct BackendLinkTests {
    private let base = URL(string: "https://api.pokyh.com")!

    private func resolved(_ raw: String?, _ base: URL? = nil) -> String? {
        BackendLink.resolve(raw, against: base ?? self.base)?.absoluteString
    }

    @Test func pathGoesBehindTheBackendAndKeepsItsQuery() {
        #expect(resolved("/dishes/45695d67-8ba5-4787-8d7a-db5f8abf680f/image?v=1794397056101")
            == "https://api.pokyh.com/dishes/45695d67-8ba5-4787-8d7a-db5f8abf680f/image?v=1794397056101")
        #expect(resolved("/dishes/x/image?v=1&w=2") == "https://api.pokyh.com/dishes/x/image?v=1&w=2")
        #expect(resolved("  /dishes/x/image?v=1\n") == "https://api.pokyh.com/dishes/x/image?v=1")
    }

    @Test func backendAddressMayEndInASlashOrAPath() {
        #expect(resolved("/dishes/x/image", URL(string: "https://api.pokyh.com/")!) == "https://api.pokyh.com/dishes/x/image")
        #expect(resolved("/dishes/x/image", URL(string: "https://example.org/api/")!) == "https://example.org/api/dishes/x/image")
        #expect(resolved("/dishes/x/image?v=3", URL(string: "http://localhost:3000")!) == "http://localhost:3000/dishes/x/image?v=3")
    }

    @Test func absoluteLinksStayAsTheyAre() {
        let other = "https://www.example.org/menu/pasta.jpg?size=large"
        #expect(resolved(other) == other)
        #expect(resolved("HTTPS://cdn.example.org/a.webp") != nil)
    }

    @Test func plainHttpOnlyForABackendOnHttp() {
        // A release talks https: an http link would be a request into the phone's network.
        for raw in ["http://router.local/cgi?x=1", "http://nas/a.jpg", "http://192.168.1.1/a.jpg", "http://cdn.example.org/a.jpg"] {
            #expect(resolved(raw) == nil, "\(raw)")
        }
        let dev = URL(string: "http://localhost:3000")!
        #expect(resolved("http://localhost:3000/dishes/x/image", dev) == "http://localhost:3000/dishes/x/image")
    }

    @Test func schemeRelativeTakesTheBackendsScheme() {
        #expect(resolved("//cdn.example.org/a.webp?v=1") == "https://cdn.example.org/a.webp?v=1")
        #expect(resolved("//cdn.example.org/a.webp", URL(string: "http://localhost:3000")!) == "http://cdn.example.org/a.webp")
    }

    @Test func emptyIsNoPicture() {
        #expect(resolved(nil) == nil)
        #expect(resolved("") == nil)
        #expect(resolved("   ") == nil)
    }

    @Test func dropsWhatIsNotAWebLink() {
        for raw in ["javascript:alert(1)", "data:image/png;base64,AAAA", "ftp://example.org/a.jpg",
                    "file:///etc/hosts", "mailto:a@example.org", "dishes/x/image", "pasta.jpg",
                    "https://", "https:///nohost", "//", "https://user:secret@example.org/a.jpg"] {
            #expect(resolved(raw) == nil, "\(raw)")
        }
    }

    @Test func configResolvesAgainstItsOwnBackend() {
        let config = AppConfig(backendURL: URL(string: "https://backend.example.org")!, websiteURL: base,
                               supportEmail: "", apiKey: "", serverKey: "", appGroup: "", keychainGroup: "",
                               backgroundTask: "", appBundleID: "", apsEnvironment: "", version: "", build: "")
        #expect(config.backendLink("/dishes/x/image?v=1")?.absoluteString == "https://backend.example.org/dishes/x/image?v=1")
        #expect(config.backendLink("") == nil)
    }

    // The popup page loads with the backend address as its base URL.
    @Test func popupPicturePathResolvesAgainstTheBaseURL() {
        let src = "/popup-images/0b6f4a1e-3c1d-4a47-9a55-2f3e6c1d9b10"
        #expect(URL(string: src, relativeTo: base)?.absoluteURL.absoluteString
            == "https://api.pokyh.com/popup-images/0b6f4a1e-3c1d-4a47-9a55-2f3e6c1d9b10")
    }
}
