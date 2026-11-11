#if DEBUG
import Foundation

/// WebUntis and the POKYH backend for the UI tests, answering from inside the app. Only a debug
/// build with `-POKYHStubServer` uses it; project.yml also keeps this folder out of release builds.
///
/// What it answers is picked by a mode, from `POKYH_STUB_MODE` or live from the file named in
/// `POKYH_STUB_CONTROL`, so a test can pull the rug out mid-use. Sign-in routes stay good unless
/// the mode starts with `all:`, otherwise a bad-data run would never get past the login.
nonisolated enum StubServer {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-POKYHStubServer")

    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requestCount = 0

    static func attach(to config: URLSessionConfiguration) {
        if isActive { config.protocolClasses = [StubProtocol.self] }
    }

    /// Before anything else runs: nothing real can leave, and every launch starts from a clean slate if asked.
    static func prepare() {
        guard isActive else { return }
        URLProtocol.registerClass(StubProtocol.self)
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-POKYHStubReset") {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pokyh_") {
                defaults.removeObject(forKey: key)
            }
            StubKeychain.purge()
        }
        // The system's notification question would sit on top of every test.
        if env["POKYH_STUB_NOTIFICATIONS"] == nil { defaults.set(true, forKey: "pokyh_notif_asked") }
    }

    static var mode: String {
        if let path = env["POKYH_STUB_CONTROL"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return env["POKYH_STUB_MODE"] ?? "good"
    }

    /// The account the app should sign into by itself at launch, to skip the sign-in screens.
    static var autoSignIn: String? { isActive ? env["POKYH_STUB_SIGNIN"] : nil }

    /// Face ID fails instead of passing.
    static var biometryFails: Bool { env["POKYH_STUB_BIOMETRY"] == "fail" }

    /// The password WebUntis takes now, as if it had been changed on the website. Unset, any does.
    static var currentPassword: String? { env["POKYH_STUB_PASSWORD"] }

    /// Seconds in the background until the app locks, instead of ten minutes.
    static var autoLockSeconds: Int? { isActive ? env["POKYH_STUB_AUTOLOCK"].flatMap(Int.init) : nil }

    static var showsPopups: Bool { env["POKYH_STUB_POPUPS"] != nil }
    /// The story opens by itself over everything, so only the tests about it get one.
    static var showsRecap: Bool { env["POKYH_STUB_RECAP"] != nil }
    static var showsPrivacyNotice: Bool { env["POKYH_STUB_PRIVACY"] != nil }

    static let school = (loginName: "stub-school", server: "stub-school.invalid", name: "Teststadt Schule")

    fileprivate static func nextRequest() -> Int {
        lock.withLock {
            requestCount += 1
            return requestCount
        }
    }

    static func log(_ line: String) {
        guard let path = env["POKYH_STUB_LOG"], let data = (line + "\n").data(using: .utf8) else { return }
        lock.withLock {
            if let handle = FileHandle(forWritingAtPath: path) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}

/// Passwords for the test accounts. The real Keychain items want a passcode the simulator hasn't got.
nonisolated enum StubKeychain {
    private static let key = "pokyh_stub_passwords"
    private static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func set(_ password: String, for account: String) { all[account] = password }
    static func password(for account: String) -> String? { all[account] }
    static func delete(_ account: String) { all[account] = nil }
    static func purge() { UserDefaults.standard.removeObject(forKey: key) }
}

/// One answer before the modes get to it.
nonisolated struct StubAnswer {
    var status = 200
    var headers: [String: String] = [:]
    /// JSON the modes can bend, or nil when `raw` goes out as it is.
    var json: Any?
    var raw: Data?
    /// Sign-in and the things it needs; the modes leave these alone unless told otherwise.
    var isAuth = false

    init(json: Any, status: Int = 200, isAuth: Bool = false, headers: [String: String] = [:]) {
        self.json = json; self.status = status; self.isAuth = isAuth; self.headers = headers
    }

    init(raw: Data, type: String, status: Int = 200, isAuth: Bool = false, headers: [String: String] = [:]) {
        self.raw = raw; self.status = status; self.isAuth = isAuth
        self.headers = headers.merging(["Content-Type": type]) { a, _ in a }
    }
}

nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = NSLock()
    nonisolated(unsafe) private var isStopped = false
    nonisolated(unsafe) private var pending: (answer: StubAnswer, mode: String, url: URL)?

    override class func canInit(with request: URLRequest) -> Bool { StubServer.isActive }
    override class func canInit(with task: URLSessionTask) -> Bool { StubServer.isActive }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {
        stopped.withLock { isStopped = true }
    }

    private var wasStopped: Bool { stopped.withLock { isStopped } }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.body(of: request)
        var mode = StubServer.mode
        let appliesToAuth = mode.hasPrefix("all:")
        if appliesToAuth { mode.removeFirst(4) }

        let answer = StubRoutes.answer(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:], body: body)
        let n = StubServer.nextRequest()
        let effective = (answer.isAuth && !appliesToAuth) ? "good" : Self.resolve(mode, request: n)
        StubServer.log("\(n) \(request.httpMethod ?? "GET") \(url.host ?? "")\(url.path)\(url.query.map { "?" + $0.prefix(80) } ?? "") mode=\(effective)")

        var delay: TimeInterval = 0.02
        if effective == "slow" { delay = 2.5 }
        if effective == "timeout" { delay = 0.4 }
        pending = (StubMutator.apply(effective, to: answer), effective, url)
        // The client has to hear back on the thread that called startLoading.
        nonisolated(unsafe) let thread = Thread.current
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            perform(#selector(finish), on: thread, with: nil, waitUntilDone: false, modes: [RunLoop.Mode.common.rawValue])
        }
    }

    @objc private func finish() {
        guard !wasStopped, let pending else { return }
        switch pending.mode {
        case "timeout": fail(.timedOut)
        case "offline": fail(.notConnectedToInternet)
        case "cancelled": fail(.cancelled)
        default: deliver(pending.answer, url: pending.url, drop: pending.mode == "dropped")
        }
    }

    /// `flaky` and `expireAfter:N` turn into a plain mode per request.
    private static func resolve(_ mode: String, request n: Int) -> String {
        if mode == "flaky" {
            return ["good", "good", "status500", "timeout", "dropped", "html", "good", "status429"][n % 8]
        }
        if mode.hasPrefix("expireAfter:") {
            let limit = Int(mode.dropFirst("expireAfter:".count)) ?? 20
            return n > limit ? "expire" : "good"
        }
        return mode
    }

    private func fail(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }

    private func deliver(_ answer: StubAnswer, url: URL, drop: Bool) {
        var headers = answer.headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        let data = answer.raw ?? answer.json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) } ?? Data()
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            fail(.badServerResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if drop {
            client?.urlProtocol(self, didLoad: data.prefix(data.count / 2))
            fail(.networkConnectionLost)
            return
        }
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands the body over as a stream by the time it gets here.
    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            out.append(buffer, count: read)
        }
        return out
    }
}

/// Bends a good answer into what nobody expected.
nonisolated enum StubMutator {
    /// All the modes a run can loop over. `status<N>`, `expireAfter:<N>` and `all:<mode>` also work.
    static let dataModes = ["empty", "nulls", "nullsAll", "missing", "missingB", "wrongTypes", "wrongContainers", "huge",
                            "negative", "zero", "nan", "dates", "duplicates", "unicode"]

    static func apply(_ mode: String, to answer: StubAnswer) -> StubAnswer {
        var out = answer
        if mode.hasPrefix("status"), let code = Int(mode.dropFirst(6)) {
            out.status = code
            out.json = ["error": "Stub \(code)", "code": code == 401 ? "unauthorized" : "stub"]
            out.raw = nil
            return out
        }
        switch mode {
        case "good", "slow", "dropped": return out
        case "html", "htmlError":
            out.status = mode == "html" ? 200 : 502
            out.json = nil
            out.raw = Data("<!DOCTYPE html><html><body>Bad Gateway</body></html>".utf8)
            out.headers["Content-Type"] = "text/html"
        case "expire":
            out.status = 401
            out.json = nil
            out.raw = Data("<html>session expired</html>".utf8)
            out.headers["Content-Type"] = "text/html"
        case "garbage":
            out.json = nil
            out.raw = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 197 &+ 31) })
        case "truncated":
            let data = (out.json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }) ?? out.raw ?? Data()
            out.json = nil
            out.raw = data.prefix(data.count / 2)
        case "emptyBody":
            out.json = nil
            out.raw = Data()
        default:
            guard let json = out.json else { return out }
            var walker = Walker(mode: mode)
            out.json = walker.bend(json, key: "")
        }
        return out
    }

    private struct Walker {
        let mode: String
        var counter = 0

        private static let badDayNumbers = [0, 20261345, 20260099, 99999999, 20260000, -1, 1, 20261301, 20260230, 20260000, 20261300]
        private static let badTimes = [9999, 2500, -5, 0, 1, 2399, 7000]
        private static let badDateStrings = ["2026-13-45T25:61:00", "0000-00-00", "2026-00-10", "2026-02-30", "not a date", "",
                                             "99999-01-01", "2026-13-01T00:00:00Z", "2026-00-00T00:00:00+99:99", "1-1-1"]

        private func looksLikeDate(_ key: String) -> Bool {
            let k = key.lowercased()
            return k.contains("date") || k.hasSuffix("at") || k == "start" || k == "end" || k.contains("from") || k.contains("to") && k.count <= 8
        }

        private func looksLikeTime(_ key: String) -> Bool { key.lowercased().contains("time") }

        private func isId(_ key: String) -> Bool {
            key == "id" || key == "ids" || key.hasSuffix("Id") || key.hasSuffix("_id")
        }

        mutating func bend(_ value: Any, key: String) -> Any {
            switch value {
            case let dict as [String: Any]:
                if mode == "wrongContainers", !key.isEmpty, dict.count > 1 { return Array(dict.values) }
                var out: [String: Any] = [:]
                for (k, v) in dict {
                    if mode == "missing", k.utf8.count % 2 == 0, !isId(k) { continue }
                    if mode == "missingB", k.utf8.count % 2 == 1, !isId(k) { continue }
                    if mode == "nulls", !isId(k), !(v is [Any]), !(v is [String: Any]) { out[k] = NSNull(); continue }
                    out[k] = bend(v, key: k)
                }
                return out
            case let array as [Any]:
                if mode == "empty" { return [Any]() }
                if mode == "wrongContainers", !key.isEmpty, let first = array.first { return first }
                var list = array.map { bend($0, key: key) }
                if mode == "duplicates" { list += list }
                if mode == "huge", let first = list.first, list.count > 1 { list += Array(repeating: first, count: 25) }
                return list
            default:
                return bendLeaf(value, key: key)
            }
        }

        private mutating func bendLeaf(_ value: Any, key: String) -> Any {
            counter += 1
            if value is NSNull { return value }
            let isBool = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let number = isBool ? nil : value as? NSNumber
            let string = value as? String
            switch mode {
            case "nullsAll":
                return NSNull()
            case "wrongTypes":
                if isBool { return "true" }
                if let number { return number.stringValue }
                return 12345
            case "huge":
                if let number { return number.doubleValue == floor(number.doubleValue) ? Int.max : Double.greatestFiniteMagnitude as Any }
                if string != nil { return String(repeating: "Langer Text ", count: 200) }
            case "negative":
                if let number { return number.doubleValue == floor(number.doubleValue) ? Int.min : -Double.greatestFiniteMagnitude as Any }
            case "zero":
                if isBool { return false }
                if number != nil { return 0 }
                if string != nil { return "" }
            case "nan":
                if number != nil { return ["NaN", "Infinity", "-Infinity", "1e999"][counter % 4] }
            case "dates":
                if looksLikeTime(key), number != nil { return Self.badTimes[counter % Self.badTimes.count] }
                if looksLikeDate(key) {
                    if number != nil { return Self.badDayNumbers[counter % Self.badDayNumbers.count] }
                    if string != nil { return Self.badDateStrings[counter % Self.badDateStrings.count] }
                }
            case "duplicates":
                if isId(key) { return string != nil ? "same" : 1 as Any }
            case "unicode":
                if let string {
                    // Arabic digits still match \d, and the rest stresses layout and string handling.
                    let extras = ["Entschuldigung: ١٢.١٢.٢٠٢٥, ٠٨:٠٠-٠٩:٠٠", "\u{202E}gnirts\u{202C} 👨‍👩‍👧‍👦", "Z͑ͫ̓ͪ̂ͫ̽͏̴̙̤̞͉͚̯̞̠͍", "\u{0}nul", "<script>alert(1)</script>&amp;&#99999999;"]
                    return looksLikeDate(key) || isId(key) ? string : extras[counter % extras.count]
                }
            default:
                break
            }
            return value
        }
    }
}
#endif
