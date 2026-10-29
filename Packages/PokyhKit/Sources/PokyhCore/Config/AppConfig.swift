import Foundation

/// Everything that differs between builds, read from the bundle's Info.plist.
/// The values come from Config/*.xcconfig (see project.yml), nothing is baked in here.
public struct AppConfig: Sendable {
    public let backendURL: URL
    public let websiteURL: URL
    public let supportEmail: String
    public let apiKey: String
    public let serverKey: String
    public let appGroup: String
    public let keychainGroup: String
    public let backgroundTask: String
    public let appBundleID: String
    public let apsEnvironment: String
    public let version: String
    public let build: String

    public init(
        backendURL: URL,
        websiteURL: URL,
        supportEmail: String,
        apiKey: String,
        serverKey: String,
        appGroup: String,
        keychainGroup: String,
        backgroundTask: String,
        appBundleID: String,
        apsEnvironment: String,
        version: String,
        build: String
    ) {
        self.backendURL = backendURL
        self.websiteURL = websiteURL
        self.supportEmail = supportEmail
        self.apiKey = apiKey
        self.serverKey = serverKey
        self.appGroup = appGroup
        self.keychainGroup = keychainGroup
        self.backgroundTask = backgroundTask
        self.appBundleID = appBundleID
        self.apsEnvironment = apsEnvironment
        self.version = version
        self.build = build
    }

    public static let current = AppConfig(bundle: .main)

    public init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        func url(_ key: String) -> URL {
            // A missing URL is a broken build config, not something to limp along with.
            guard let url = URL(string: value(key)), url.scheme != nil else {
                preconditionFailure("\(key) missing in Info.plist, check Config/*.xcconfig")
            }
            return url
        }
        self.init(
            backendURL: url("POKYHBackendURL"),
            websiteURL: url("POKYHWebsiteURL"),
            supportEmail: value("POKYHSupportEmail"),
            apiKey: value("POKYHAPIKey"),
            serverKey: value("POKYHServerKey"),
            appGroup: value("POKYHAppGroup"),
            keychainGroup: value("POKYHKeychainGroup"),
            backgroundTask: value("POKYHBackgroundTask"),
            appBundleID: value("POKYHAppBundleID"),
            apsEnvironment: value("POKYHAPSEnvironment"),
            version: value("CFBundleShortVersionString"),
            build: value("CFBundleVersion")
        )
    }

    /// APNs gateway the backend should use for this build's device token.
    public var apnsEnvironment: String {
        apsEnvironment == "development" ? "sandbox" : "production"
    }

    public var hasBackendKeys: Bool { !apiKey.isEmpty && !serverKey.isEmpty }
}
