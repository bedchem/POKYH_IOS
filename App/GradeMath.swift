import Foundation

/// Noten-Mathematik — 1:1 portiert aus `lib/grades.ts` + der Fach-Detailseite.
/// Skala 1–10 (Südtirol), positiv ab 6.
enum GradeMath {
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func averageOf(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : round2(values.reduce(0, +) / Double(values.count))
    }

    /// "8,5" / "8.5" → 8.5, nur gültig im Bereich 1…10.
    static func parseGradeInput(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, let parsed = Double(normalized) else { return nil }
        guard parsed >= 1, parsed <= 10 else { return nil }
        return round2(parsed)
    }

    static let gradeStep = 0.5
    static func roundToGradeStep(_ value: Double, up: Bool) -> Double {
        let factor = 1 / gradeStep
        let scaled = value * factor
        let rounded = up ? (scaled - 1e-9).rounded(.up) : (scaled + 1e-9).rounded(.down)
        return round2(min(10, max(4, rounded / factor)))
    }

    enum TargetStatus { case reached, reachable, impossible }
    struct TargetResult { var target: Double; var status: TargetStatus; var count: Int; var needed: Double }

    /// Zielnote-Rechner: wie viele Noten welchen Werts werden gebraucht?
    static func target(_ targetInput: String, values: [Double]) -> TargetResult? {
        guard let target = parseGradeInput(targetInput), !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        let n = Double(values.count)
        let currentAvg = sum / n

        if abs(currentAvg - target) < 1e-6 {
            return TargetResult(target: target, status: .reached, count: 0, needed: 0)
        }
        if currentAvg < target {
            for k in 1...50 {
                let kk = Double(k)
                let perGrade = (target * (n + kk) - sum) / kk
                if perGrade <= 10 {
                    return TargetResult(target: target, status: .reachable, count: k,
                                        needed: roundToGradeStep(max(4, perGrade), up: true))
                }
            }
            return TargetResult(target: target, status: .impossible, count: 0, needed: 0)
        } else {
            if target <= 4 + 1e-6 { return TargetResult(target: target, status: .impossible, count: 0, needed: 0) }
            let kMin = Int(((sum - target * n) / (target - 4) - 1e-9).rounded(.up))
            if kMin <= 0 || kMin > 50 { return TargetResult(target: target, status: .impossible, count: 0, needed: 0) }
            let perGrade = (target * (n + Double(kMin)) - sum) / Double(kMin)
            return TargetResult(target: target, status: .reachable, count: kMin,
                                needed: roundToGradeStep(max(4, perGrade), up: false))
        }
    }
}

/// Lokale „Was-wäre-wenn"-Noten je Fach (entspricht den Drafts im Frontend,
/// dort in localStorage — hier in UserDefaults).
struct GradeDraft: Codable, Equatable {
    var removedTeacherGradeIds: [Int] = []
    var customGrades: [Double] = []
    var isEmpty: Bool { removedTeacherGradeIds.isEmpty && customGrades.isEmpty }
}

@MainActor
enum GradeDraftStore {
    private static let key = "pokyh_grade_drafts"

    static func all() -> [Int: GradeDraft] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: GradeDraft].self, from: data) else { return [:] }
        var out: [Int: GradeDraft] = [:]
        for (k, v) in dict { if let id = Int(k) { out[id] = v } }
        return out
    }

    static func get(_ lessonId: Int) -> GradeDraft { all()[lessonId] ?? GradeDraft() }

    static func set(_ lessonId: Int, _ draft: GradeDraft) {
        var dict = all()
        if draft.isEmpty { dict.removeValue(forKey: lessonId) } else { dict[lessonId] = draft }
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
