import Foundation
import PokyhCore

extension Config.Routes {
    static let ownAccount = "/users/me"
    static func qrLogin(_ code: String) -> String { "/auth/qr/\(code.urlEncoded)" }
    static func qrApprove(_ code: String) -> String { "\(qrLogin(code))/approve" }
}

extension BackendClient {
    // ── Signing a computer in (the website's QR code, backend services/qrLogin.ts) ──

    /// The website waiting for a scanned code: its device, place and address as the backend saw them.
    struct QrLoginInfo: Equatable {
        var label: String
        var ip: String?
        var place: String
    }

    /// What the computer gets to sign in with. Its session spares it the authenticator code,
    /// the password or app key renews its sign-in later.
    struct QrCredential {
        var username: String
        var password: String?
        var key: String?
        var sessionId: String?
        var school: School?

        var body: [String: Any] {
            var body: [String: Any] = ["username": username]
            if let key, !key.isEmpty {
                body["key"] = key
            } else if let password, !password.isEmpty {
                body["password"] = password
            }
            if let sessionId, !sessionId.isEmpty { body["sessionId"] = sessionId }
            if let school { body["school"] = ["loginName": school.loginName, "server": school.server] }
            return body
        }
    }

    /// Nil: the code ran out (two minutes) or was used already.
    func qrLoginInfo(code: String, token: String) async throws -> QrLoginInfo? {
        do {
            let j = JSON.parse(try await request(Config.Routes.qrLogin(code), token: token))
            return QrLoginInfo(label: j.label.string ?? "", ip: j.ip.string, place: j.place.string ?? "")
        } catch let error as AppError where error.status == 404 {
            return nil
        }
    }

    /// False: the code ran out in the meantime.
    func approveQrLogin(code: String, credential: QrCredential, token: String) async throws -> Bool {
        do {
            _ = try await request(Config.Routes.qrApprove(code), method: "POST", token: token, body: credential.body)
            return true
        } catch let error as AppError where error.status == 404 {
            return false
        }
    }

    // ── Deleting the account ─────────────────────────────────────────────────

    /// Deletes the POKYH account and what the backend keeps about it. The WebUntis account stays.
    /// A 404 means a backend from before this existed: the route answers 204 even for an account
    /// that's already gone.
    func deleteAccount(token: String) async throws {
        _ = try await request(Config.Routes.ownAccount, method: "DELETE", token: token)
    }
}
