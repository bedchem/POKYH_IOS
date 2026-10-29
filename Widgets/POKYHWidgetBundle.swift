import WidgetKit
import SwiftUI

/// Einstiegspunkt der Widget-Extension: alle Home-Screen-Widgets + Live Activity.
@main
struct POKYHWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()       // nächste/laufende Stunde (S/M)
        TodayScheduleWidget()    // heutiger Plan als Liste (M/L)
        GradesWidget()           // Schnitt + letzte Noten (S/M)
        MessagesWidget()         // ungelesen + neueste (S/M)
        OverviewWidget()         // kombiniert: Stunde + Schnitt + Nachrichten (M/L)
        LessonLiveActivity()     // Live Activity (Lock Screen + Dynamic Island)
    }
}
