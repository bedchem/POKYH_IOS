import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

@main
struct POKYHWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonComplication()
    }
}

struct NextLessonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLessonComplication", provider: EmptyProvider()) { _ in
            Text("POKYH")
                .containerBackground(.clear, for: .widget)
        }
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
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
