import AppIntents
import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.greighstudios.voteaxis"

struct IssueEntry: TimelineEntry {
  let date: Date
  let headline: String
  let question: String
  let status: String
  let axisLabel: String
  let hasProfile: Bool
}

struct IssueProvider: TimelineProvider {
  func placeholder(in context: Context) -> IssueEntry {
    IssueEntry(
      date: Date(),
      headline: "Issue of the day",
      question: "Open Voteaxis to take the quiz.",
      status: "needQuiz",
      axisLabel: "",
      hasProfile: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (IssueEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<IssueEntry>) -> Void) {
    let calendar = Calendar.current
    let tomorrow = calendar.startOfDay(
      for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    completion(Timeline(entries: [currentEntry()], policy: .after(tomorrow)))
  }

  private func currentEntry() -> IssueEntry {
    let data = UserDefaults(suiteName: widgetGroupId)
    return IssueEntry(
      date: Date(),
      headline: data?.string(forKey: "headline") ?? "Issue of the day",
      question: data?.string(forKey: "question") ?? "Open Voteaxis to take the quiz.",
      status: data?.string(forKey: "status") ?? "needQuiz",
      axisLabel: data?.string(forKey: "axisLabel") ?? "",
      hasProfile: data?.string(forKey: "hasProfile") == "1")
  }
}

struct IssueWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: IssueEntry

  var body: some View {
    switch family {
    case .accessoryRectangular:
      lockScreen
    default:
      homeScreen
    }
  }

  private var lockScreen: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.headline.uppercased())
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
      Text(entry.question)
        .font(.caption.weight(.medium))
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(URL(string: "voteaxis://open"))
  }

  private var homeScreen: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(entry.headline.uppercased())
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color(red: 0.36, green: 0.40, blue: 0.46))
        .lineLimit(1)
      Text(entry.question)
        .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold))
        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        .lineLimit(family == .systemSmall ? 4 : 5)
      Spacer(minLength: 0)
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) {
      Color(red: 0.965, green: 0.969, blue: 0.976)
    }
  }

  @ViewBuilder
  private var footer: some View {
    if !entry.hasProfile || entry.status == "needQuiz" {
      Text("Open Voteaxis to take the quiz")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color(red: 0.36, green: 0.40, blue: 0.46))
        .widgetURL(URL(string: "voteaxis://open"))
    } else if entry.status == "saved" {
      Text(entry.axisLabel.isEmpty ? "Saved for today" : "Saved · \(entry.axisLabel)")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color(red: 0.36, green: 0.40, blue: 0.46))
    } else {
      HStack(spacing: 8) {
        if #available(iOSApplicationExtension 17, *) {
          Button(
            intent: BackgroundIntent(
              url: URL(string: "voteaxis://calibrate?side=disagree"),
              appGroup: widgetGroupId)
          ) {
            Text("Disagree")
              .font(.system(size: 12, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .tint(Color(red: 0.07, green: 0.07, blue: 0.09))
          Button(
            intent: BackgroundIntent(
              url: URL(string: "voteaxis://calibrate?side=agree"),
              appGroup: widgetGroupId)
          ) {
            Text("Agree")
              .font(.system(size: 12, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .tint(Color(red: 0.77, green: 0.63, blue: 0.21))
        }
      }
    }
  }
}

@main
struct IssueWidget: Widget {
  let kind: String = "IssueWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: IssueProvider()) { entry in
      IssueWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Issue of the Day")
    .description("Agree or disagree to nudge your Spectrum Issue Index.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}
