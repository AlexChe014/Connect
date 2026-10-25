import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let brandBlue = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0xFF / 255)

struct CallLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CallActivityAttributes.self) { context in
      CallLockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CallIcon(isVideo: context.attributes.isVideo, size: 44)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CallStatusText(state: context.state)
            .font(.system(size: 17, weight: .semibold).monospacedDigit())
            .foregroundStyle(.green)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.title)
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CallButtons(muted: context.state.muted)
            .padding(.top, 6)
        }
      } compactLeading: {
        Image(systemName: context.attributes.isVideo ? "video.fill" : "phone.fill")
          .foregroundStyle(.green)
      } compactTrailing: {
        CallStatusText(state: context.state, compact: true)
          .font(.system(size: 14, weight: .semibold).monospacedDigit())
          .foregroundStyle(.green)
          .frame(maxWidth: 52)
      } minimal: {
        Image(systemName: context.attributes.isVideo ? "video.fill" : "phone.fill")
          .foregroundStyle(.green)
      }
      .keylineTint(.green)
    }
  }
}

private struct CallLockScreenView: View {
  let context: ActivityViewContext<CallActivityAttributes>

  var body: some View {
    HStack(spacing: 12) {
      CallIcon(isVideo: context.attributes.isVideo, size: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text(context.attributes.title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
        CallStatusText(state: context.state)
          .font(.system(size: 15).monospacedDigit())
          .foregroundStyle(.white.opacity(0.7))
      }
      Spacer(minLength: 8)
      CallButtons(muted: context.state.muted, compact: true)
    }
    .padding(16)
  }
}

private struct CallIcon: View {
  let isVideo: Bool
  let size: CGFloat

  var body: some View {
    Image(systemName: isVideo ? "video.fill" : "phone.fill")
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(brandBlue))
  }
}

/// Таймер разговора или текущий этап соединения.
private struct CallStatusText: View {
  let state: CallActivityAttributes.ContentState
  var compact = false

  var body: some View {
    if let start = state.startedAt, state.phase == "active" {
      Text(start, style: .timer)
        .multilineTextAlignment(compact ? .trailing : .leading)
    } else {
      Text(label)
    }
  }

  private var label: String {
    switch state.phase {
    case "waiting": return compact ? "…" : "Ожидание собеседника…"
    case "reconnecting": return compact ? "…" : "Переподключение…"
    default: return compact ? "…" : "Соединение…"
    }
  }
}

private struct CallButtons: View {
  let muted: Bool
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 10 : 16) {
      Button(intent: ToggleMuteIntent()) {
        Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(muted ? .black : .white)
          .frame(width: 44, height: 44)
          .background(Circle().fill(muted ? Color.white : Color.white.opacity(0.2)))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(muted ? "Включить микрофон" : "Выключить микрофон")

      Button(intent: EndCallIntent()) {
        Image(systemName: "phone.down.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: compact ? 44 : 64, height: 44)
          .background(Capsule().fill(Color.red))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Завершить звонок")
    }
  }
}
