import Foundation

/// Reads a server's JSON without trusting it: a null, a missing key or the wrong type read as
/// nothing, and counts stay in a range that can't overflow a sum.
struct LooseJSON {
    let raw: Any?

    init(raw: Any?) {
        self.raw = raw
    }

    init(data: Data?) {
        raw = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    subscript(key: String) -> LooseJSON {
        LooseJSON(raw: object?[key])
    }

    var object: [String: Any]? { raw as? [String: Any] }
    var array: [LooseJSON] { (raw as? [Any])?.map(LooseJSON.init(raw:)) ?? [] }
    var string: String? { raw as? String }
    var bool: Bool? { raw as? Bool }

    /// 0 for anything that isn't a number; never negative.
    var count: Int {
        guard let number = raw as? NSNumber else { return 0 }
        return Swift.min(Swift.max(0, Int(saturating: number.doubleValue)), Self.biggestCount)
    }

    // Fits a 32-bit Int too, the watch has one.
    static let biggestCount = 100_000_000
}
