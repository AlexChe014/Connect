import SwiftUI
import WidgetKit

private let brandBlue = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0xFF / 255)

/// Что приложение кладёт в App Group (HomeWidgetService в Dart).
struct TodayData: Codable {
  struct Meeting: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
    var place: String?
  }

  var loggedIn: Bool
  var chatsUnread: Int
  var mailUnread: Int
  var documentsPending: Int
  var meetings: [Meeting]

  static let empty = TodayData(loggedIn: false, chatsUnread: 0, mailUnread: 0, documentsPending: 0, meetings: [])

  static let preview = TodayData(
    loggedIn: true,
    chatsUnread: 3,
    mailUnread: 12,
    documentsPending: 2,
    meetings: [
      Meeting(title: "Планёрка отдела", start: .now.addingTimeInterval(1800), end: .now.addingTimeInterval(5400), place: "Переговорная 2"),
      Meeting(title: "Созвон с подрядчиком", start: .now.addingTimeInterval(9000), end: .now.addingTimeInterval(12600), place: nil),
    ]
  )

  static func load() -> TodayData {
    guard
      let defaults = UserDefaults(suiteName: ConnectAppGroup.id),
      let raw = defaults.data(forKey: ConnectAppGroup.todayKey)
    else { return .empty }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return (try? decoder.decode(TodayData.self, from: raw)) ?? .empty
  }

  /// Встречи, которые ещё не закончились к моменту `date`.
  func upcoming(at date: Date) -> [Meeting] {
    meetings.filter { $0.end > date }.sorted { $0.start < $1.start }
  }
}

struct TodayEntry: TimelineEntry {
  let date: Date
  let data: TodayData
}

struct TodayProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayEntry {
    TodayEntry(date: .now, data: .preview)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
    completion(TodayEntry(date: .now, data: context.isPreview ? .preview : TodayData.load()))
  }

  /// Запись на «сейчас» и на конец каждой встречи — чтобы прошедшие сами
  /// уходили из виджета. Свежие счётчики приложение присылает само
  /// (WidgetCenter.reloadAllTimelines), плюс фоновое обновление раз в 30 мин.
  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
    let data = TodayData.load()
    let now = Date.now
    var dates = [now]
    dates += data.meetings.map(\.end).filter { $0 > now }.sorted().prefix(6)
    let entries = dates.map { TodayEntry(date: $0, data: data) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
  }
}

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
      TodayWidgetView(entry: entry)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
    .configurationDisplayName("Сегодня")
    .description("Ближайшие встречи, непрочитанные чаты и почта, документы на подпись.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
  }
}

struct TodayWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TodayEntry

  var body: some View {
    if !entry.data.loggedIn {
      LoggedOutView()
    } else {
      switch family {
      case .systemMedium: MediumView(entry: entry)
      case .accessoryRectangular: RectangularView(entry: entry)
      case .accessoryCircular: CircularView(entry: entry)
      default: SmallView(entry: entry)
      }
    }
  }
}

// MARK: - Размеры

private struct SmallView: View {
  let entry: TodayEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Header()
      if let next = entry.data.upcoming(at: entry.date).first {
        MeetingRow(meeting: next, now: entry.date)
      } else {
        Text("Встреч больше нет")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Counters(data: entry.data, compact: true)
    }
  }
}

private struct MediumView: View {
  let entry: TodayEntry

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 8) {
        Header()
        Spacer(minLength: 0)
        Counters(data: entry.data, compact: false)
      }
      .frame(width: 112, alignment: .leading)

      VStack(alignment: .leading, spacing: 8) {
        let meetings = entry.data.upcoming(at: entry.date)
        if meetings.isEmpty {
          Spacer()
          Text("На сегодня встреч больше нет")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          Spacer()
        } else {
          ForEach(meetings.prefix(3), id: \.self) { meeting in
            MeetingRow(meeting: meeting, now: entry.date)
          }
          Spacer(minLength: 0)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct RectangularView: View {
  let entry: TodayEntry

  var body: some View {
    if let next = entry.data.upcoming(at: entry.date).first {
      VStack(alignment: .leading, spacing: 1) {
        Text(timeLabel(next, now: entry.date))
          .font(.system(size: 13, weight: .semibold))
          .widgetAccentable()
        Text(next.title)
          .font(.system(size: 14))
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("Сегодня").font(.system(size: 13, weight: .semibold)).widgetAccentable()
        Text("Чаты \(entry.data.chatsUnread) · Почта \(entry.data.mailUnread)")
          .font(.system(size: 14))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct CircularView: View {
  let entry: TodayEntry

  var body: some View {
    let total = entry.data.chatsUnread + entry.data.mailUnread + entry.data.documentsPending
    ZStack {
      AccessoryWidgetBackground()
      VStack(spacing: 0) {
        Image(systemName: "bubble.left.and.bubble.right.fill")
          .font(.system(size: 13))
        Text(total > 99 ? "99+" : "\(total)")
          .font(.system(size: 16, weight: .bold))
      }
    }
    .widgetAccentable()
  }
}

// MARK: - Части

private struct Header: View {
  var body: some View {
    Text("Сегодня")
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(brandBlue)
  }
}

private struct MeetingRow: View {
  let meeting: TodayData.Meeting
  let now: Date

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(brandBlue)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 1) {
        Text(timeLabel(meeting, now: now))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(meeting.start <= now ? .green : .secondary)
        Text(meeting.title)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(2)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct Counters: View {
  let data: TodayData
  let compact: Bool

  var body: some View {
    let items: [(String, Int, String)] = [
      ("bubble.left.fill", data.chatsUnread, "Чаты"),
      ("envelope.fill", data.mailUnread, "Почта"),
      ("signature", data.documentsPending, "Подпись"),
    ]
    if compact {
      HStack(spacing: 10) {
        ForEach(items, id: \.0) { icon, count, _ in
          HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 11))
            Text(count > 99 ? "99+" : "\(count)").font(.system(size: 13, weight: .semibold))
          }
          .foregroundStyle(count > 0 ? brandBlue : .secondary)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(items, id: \.0) { icon, count, label in
          HStack(spacing: 6) {
            Image(systemName: icon)
              .font(.system(size: 12))
              .frame(width: 16)
            Text(label).font(.system(size: 13))
            Spacer(minLength: 2)
            Text(count > 99 ? "99+" : "\(count)").font(.system(size: 13, weight: .semibold))
          }
          .foregroundStyle(count > 0 ? AnyShapeStyle(brandBlue) : AnyShapeStyle(.secondary))
        }
      }
    }
  }
}

private struct LoggedOutView: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "person.crop.circle.badge.exclamationmark")
        .font(.system(size: 24))
        .foregroundStyle(.secondary)
      Text("Войдите в Коннект")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private func timeLabel(_ meeting: TodayData.Meeting, now: Date) -> String {
  if meeting.start <= now { return "Идёт сейчас" }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "ru_RU")
  formatter.dateFormat = Calendar.current.isDate(meeting.start, inSameDayAs: now) ? "HH:mm" : "E, HH:mm"
  let end = DateFormatter()
  end.dateFormat = "HH:mm"
  return "\(formatter.string(from: meeting.start))–\(end.string(from: meeting.end))"
}
