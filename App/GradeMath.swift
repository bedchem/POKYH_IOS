import Foundation
import PokyhCore

/// Grade math, ported from the web's `lib/grades.ts` and its subject page.
/// The scale is 1 to 10 (South Tyrol), a pass from 6.
enum GradeMath {
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func averageOf(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : round2(values.reduce(0, +) / Double(values.count))
    }

    /// "8,5" or "8.5" as 8.5; only 1 to 10 counts.
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

    /// The target calculator: how many grades of which value it takes.
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
            let kMin = Int(saturating: ((sum - target * n) / (target - 4) - 1e-9).rounded(.up))
            if kMin <= 0 || kMin > 50 { return TargetResult(target: target, status: .impossible, count: 0, needed: 0) }
            let perGrade = (target * (n + Double(kMin)) - sum) / Double(kMin)
            return TargetResult(target: target, status: .reachable, count: kMin,
                                needed: roundToGradeStep(max(4, perGrade), up: false))
        }
    }
}

/// What-if grades for one subject, the web's drafts. Kept in memory only.
struct GradeDraft: Equatable {
    var removedTeacherGradeIds: [Int] = []
    var customGrades: [Double] = []
    var isEmpty: Bool { removedTeacherGradeIds.isEmpty && customGrades.isEmpty }
}

/// Older builds kept the drafts in the defaults. They only last while a subject is open now.
enum GradeDraftLeftovers {
    static func remove() { UserDefaults.standard.removeObject(forKey: "pokyh_grade_drafts") }
}
