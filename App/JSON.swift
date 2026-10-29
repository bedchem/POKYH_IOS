import Foundation

/// Leichtgewichtiger dynamischer JSON-Zugriff — spiegelt die defensive
/// Navigation der TypeScript-Routen (Werte können fehlen / verschieden verschachtelt sein).
/// `nonisolated` + `Sendable`: darf von jedem Kontext aus genutzt werden.
@dynamicMemberLookup
nonisolated struct JSON: @unchecked Sendable {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    static func parse(_ data: Data) -> JSON {
        JSON((try? JSONSerialization.jsonObject(with: data, options: [])))
    }

    subscript(dynamicMember key: String) -> JSON { self[key] }

    subscript(_ key: String) -> JSON {
        if let dict = raw as? [String: Any] { return JSON(dict[key]) }
        return JSON(nil)
    }

    subscript(_ index: Int) -> JSON {
        if let arr = raw as? [Any], index >= 0, index < arr.count { return JSON(arr[index]) }
        return JSON(nil)
    }

    var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    var dictionary: [String: JSON] {
        guard let d = raw as? [String: Any] else { return [:] }
        return d.mapValues(JSON.init)
    }

    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }
    var int: Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) }
        return nil
    }
    var double: Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    var bool: Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return s.lowercased() == "true" || s == "1" }
        return nil
    }
    var exists: Bool { raw != nil }
    var isArray: Bool { raw is [Any] }
}
