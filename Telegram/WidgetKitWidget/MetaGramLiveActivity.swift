#if arch(arm64) || arch(x86_64)

import SwiftUI
import WidgetKit
@_weakLinked import ActivityKit

/// MetaGram's Live Activity: the app's logo in the Dynamic Island while MetaGram runs (as Swiftgram does).
/// The app starts it (`MetaGramLiveActivity` in SettingsUI); this type must match the app's one field for field.
@available(iOS 16.1, *)
struct MetaGramActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var subtitle: String
    }

    var title: String
}

/// The app's glyph: a white circle crossed by a diagonal line.
@available(iOS 16.1, *)
private struct MetaGramGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: size * 0.14)
            Rectangle()
                .fill(Color.white)
                .frame(width: size * 0.14, height: size * 0.95)
                .rotationEffect(.degrees(45))
        }
        .frame(width: size, height: size)
    }
}

@available(iOS 16.1, *)
private struct MetaGramBadge: View {
    let title: String
    let glyphSize: CGFloat
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: glyphSize * 0.35) {
            MetaGramGlyph(size: glyphSize)
            Text(title)
                .font(.system(size: fontSize, weight: .heavy))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

@available(iOS 16.1, *)
struct MetaGramLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MetaGramActivityAttributes.self) { context in
            // lock screen and notification banner
            HStack {
                MetaGramBadge(title: context.attributes.title, glyphSize: 22, fontSize: 18)
                Spacer()
                Text(context.state.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    MetaGramBadge(title: context.attributes.title, glyphSize: 24, fontSize: 20)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } compactLeading: {
                MetaGramGlyph(size: 16)
                    .padding(.leading, 2)
            } compactTrailing: {
                Text(context.attributes.title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
            } minimal: {
                MetaGramGlyph(size: 14)
            }
            .keylineTint(Color.white)
        }
    }
}

#endif
