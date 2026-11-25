import Foundation
import TelegramCore
#if canImport(ActivityKit)
@_weakLinked import ActivityKit
#endif

#if canImport(ActivityKit)
/// Must match `MetaGramActivityAttributes` of the widget extension (Telegram/WidgetKitWidget) field for field:
/// ActivityKit hands the activity to the extension by this type.
@available(iOS 16.1, *)
struct MetaGramActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var subtitle: String
    }

    var title: String
}
#endif

/// MetaGram "Logo in Dynamic Island": a Live Activity with the app's logo, shown in the Dynamic Island while MetaGram
/// runs in the background (iOS hides an app's own activity while the app is on screen). Started when the app becomes
/// active, ended when the option is turned off; iOS ends it by itself after about 8 hours, and the next launch starts
/// it again. Needs iOS 16.1 and the widget extension, which shows it.
public enum MetaGramLiveActivity {
    public static func update() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else {
            return
        }
        if MetaGramSettings.get(.islandBadge) {
            self.start()
        } else {
            self.endAll()
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        if !Activity<MetaGramActivityAttributes>.activities.isEmpty {
            return
        }
        let isRussian = (Locale.preferredLanguages.first ?? "").hasPrefix("ru")
        let state = MetaGramActivityAttributes.ContentState(subtitle: isRussian ? "работает в фоне" : "running in the background")
        let _ = try? Activity<MetaGramActivityAttributes>.request(attributes: MetaGramActivityAttributes(title: "METAGRAM"), contentState: state, pushType: nil)
    }

    @available(iOS 16.1, *)
    private static func endAll() {
        for activity in Activity<MetaGramActivityAttributes>.activities {
            Task {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }
    #endif
}
