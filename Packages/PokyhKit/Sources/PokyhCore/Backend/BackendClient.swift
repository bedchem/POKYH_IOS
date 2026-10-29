import Foundation

/// An answer from the backend that isn't a success. `code` is the machine-readable reason
/// where the backend gives one (e.g. "session_revoked").
public struct BackendError: Error, Sendable, Equatable {
    public let message: String
    public let status: Int?
    public let code: String?

    public static func noConnection(_ message: String) -> BackendError {
        BackendError(message: message, status: nil, code: "no_connection")
    }
}

public struct APIUser: Codable, Sendable, Hashable {
    public let stableUid: String
    public let username: String
    public let webuntisKlasseId: Int?
    public let webuntisKlasseName: String?
    public let classId: String?
    public let isAdmin: Bool
}

public struct AuthTokens: Codable, Sendable, Hashable {
    public let token: String
    public let refreshToken: String
}

public enum SchoolSearch: Sendable, Equatable {
    case tooShort
    case tooMany
    case rateLimited
    case failed
    case found([School])
}

public enum UntisSignIn: Sendable, Equatable {
    case ok(AuthTokens)
    /// No class known for the account yet, so the backend can't place it.
    case noClass
    /// This device was signed out from somewhere else.
    case revoked(String)
    case failed(String)
}

/// How a school's people sign in, read from its own WebUntis page.
public struct LoginOptions: Codable, Sendable, Equatable {
    public var office365: Bool = false
    public var password: Bool = true
}

/// The POKYH backend. Every request carries the API key, this install's device id and the
/// app's user agent, so the backend files it under "Geräte & Anmeldungen" as the iOS app.
public final class BackendClient: Sendable {
    let config: AppConfig
    let device: DeviceIdentity
    let session: URLSession
    let errors: ErrorStrings

    public init(config: AppConfig, device: DeviceIdentity, errors: ErrorStrings, session: URLSession = .shared) {
        self.config = config
        self.device = device
        self.errors = errors
        self.session = session
    }

    // MARK: Sign-in

    /// Any school on WebUntis, by name, town or postcode. Public, no account needed.
    public func searchSchools(_ query: String) async -> SchoolSearch {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return .tooShort }
        struct Answer: Decodable { let schools: [School]? }
        do {
            let answer: Answer = try await get("/webuntis/schools", query: ["q": q])
            return answer.schools.map(SchoolSearch.found) ?? .failed
        } catch let error as BackendError {
            switch error.status {
            case 400: return .tooShort
            case 422: return .tooMany
            case 429: return .rateLimited
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    public func loginOptions(for school: School) async -> LoginOptions? {
        try? await get("/webuntis/login-options", query: ["school": school.loginName, "server": school.server])
    }

    /// After WebUntis accepted the credentials: a trusted server-to-server style sign-in with
    /// the server key. `renewal` marks the app signing itself in again (launch, Face ID), which
    /// doesn't count as a sign-in by the person.
    public func signInWithUntis(
        username: String,
        klasseId: Int,
        klasseName: String,
        role: String = "student",
        renewal: Bool = false,
        school: School,
        method: String? = nil
    ) async -> UntisSignIn {
        guard klasseId > 0 else { return .noClass }
        var body: [String: Any] = [
            "username": username,
            "klasseId": klasseId,
            "klasseName": klasseName,
            "role": role,
            "renewal": renewal,
            "school": school.loginName,
            "schoolName": school.name,
            "schoolServer": school.server,
        ]
        if let method { body["method"] = method }
        do {
            let data = try await send("/auth/login", method: "POST", json: body, headers: ["X-Server-Key": config.serverKey])
            let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
            return .ok(tokens)
        } catch let error as BackendError {
            if error.code == "session_revoked" { return .revoked(error.message) }
            return .failed(error.message)
        } catch {
            return .failed(errors.badAnswer)
        }
    }

    /// Accounts without WebUntis: username and password at the backend itself.
    public func signIn(username: String, password: String) async throws -> (AuthTokens, APIUser) {
        struct Answer: Decodable { let token: String; let refreshToken: String; let user: APIUser }
        let data = try await send("/auth/login", method: "POST", json: ["username": username.lowercased(), "password": password])
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        return (AuthTokens(token: answer.token, refreshToken: answer.refreshToken), answer.user)
    }

    public func me(token: String) async throws -> APIUser {
        try await get("/auth/me", token: token)
    }

    // MARK: Plumbing

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:], token: String? = nil) async throws -> T {
        let data = try await send(path, query: query, token: token)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError(message: errors.badAnswer, status: nil, code: "bad_answer")
        }
    }

    @discardableResult
    public func send(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        token: String? = nil,
        json: [String: Any]? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(url: config.backendURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw BackendError(message: errors.badAnswer, status: nil, code: "bad_url") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(device.id, forHTTPHeaderField: "X-Pokyh-Device")
        request.setValue(device.userAgent, forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if ["POST", "PUT", "PATCH"].contains(method) {
            request.httpBody = Data("{}".utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.noConnection(errors.noConnection)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Body: Decodable { let error: String?; let code: String? }
            let body = try? JSONDecoder().decode(Body.self, from: data)
            throw BackendError(message: body?.error ?? "HTTP \(status)", status: status, code: body?.code)
        }
        return data
    }
}
