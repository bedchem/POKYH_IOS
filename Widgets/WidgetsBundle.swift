import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

@main
struct POKYHWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLesson", provider: EmptyProvider()) { _ in
            Text("POKYH")
                .textStyle(.widgetHeader)
                .containerBackground(Palette.card, for: .widget)
        }
        .configurationDisplayName("Nächste Stunde")
    }
}

struct EmptyProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
