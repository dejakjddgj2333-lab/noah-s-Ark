import SwiftUI
import WidgetKit

/// 巨鲸异动小组件: 最新 3 条大额成交 (Hyperliquid / Binance 双源聚合).
struct MingceWhaleWidget: Widget {
  let kind = "MingceWhaleWidget"

  var bgColor: Color { Color(red: 11 / 255, green: 14 / 255, blue: 20 / 255) }

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WhaleProvider()) { entry in
      if #available(iOS 17.0, *) {
        WhaleWidgetView(entry: entry)
          .containerBackground(bgColor, for: .widget)
      } else {
        WhaleWidgetView(entry: entry)
          .padding()
          .background(bgColor)
      }
    }
    .configurationDisplayName(SharedStore.isZh ? "巨鲸异动" : "Whale Alerts")
    .description(SharedStore.isZh ? "大额成交实时速递" : "Latest large trades across exchanges")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct WhaleEntry: TimelineEntry {
  let date: Date
  let alerts: [SharedStore.WhaleAlert]
}

struct WhaleProvider: TimelineProvider {
  func placeholder(in context: Context) -> WhaleEntry {
    WhaleEntry(date: Date(), alerts: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (WhaleEntry) -> Void) {
    completion(WhaleEntry(date: Date(), alerts: SharedStore.whales()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WhaleEntry>) -> Void) {
    let entry = WhaleEntry(date: Date(), alerts: SharedStore.whales())
    let next = Date().addingTimeInterval(15 * 60)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct WhaleWidgetView: View {
  let entry: WhaleEntry
  @Environment(\.widgetFamily) var family

  var upColor: Color { Color(red: 46 / 255, green: 189 / 255, blue: 133 / 255) }
  var downColor: Color { Color(red: 240 / 255, green: 90 / 255, blue: 90 / 255) }
  var subColor: Color { Color(red: 139 / 255, green: 143 / 255, blue: 158 / 255) }
  var isSmall: Bool { family == .systemSmall }

  func relTime(_ ms: Int64) -> String {
    let t = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    let mins = Int(Date().timeIntervalSince(t) / 60)
    if mins < 1 { return SharedStore.isZh ? "刚刚" : "now" }
    if mins < 60 { return SharedStore.isZh ? "\(mins)分钟前" : "\(mins)m" }
    return SharedStore.isZh ? "\(mins / 60)小时前" : "\(mins / 60)h"
  }

  var body: some View {
    if entry.alerts.isEmpty {
      VStack(spacing: 6) {
        Image(systemName: "water.waves")
          .foregroundStyle(subColor)
        Text(SharedStore.isZh ? "暂无大额异动" : "No whale moves yet")
          .font(.caption)
          .foregroundStyle(subColor)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Image(systemName: "water.waves")
            .font(.caption2)
            .foregroundStyle(subColor)
          Text(SharedStore.isZh ? "巨鲸异动" : "Whale Alerts")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(subColor)
        }
        .padding(.bottom, 6)
        ForEach(Array(entry.alerts.prefix(isSmall ? 2 : 3).enumerated()), id: \.offset) { _, a in
          if isSmall {
            // 小号: 两行一条, 防截断 — 上行 币+买卖, 下行 金额+时间
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 4) {
                Text(a.symbol)
                  .font(.system(.caption, design: .rounded))
                  .fontWeight(.bold)
                  .foregroundStyle(.white)
                Text(a.side == "Buy" ? (SharedStore.isZh ? "买" : "B") : (SharedStore.isZh ? "卖" : "S"))
                  .font(.caption2)
                  .foregroundStyle(a.side == "Buy" ? upColor : downColor)
                Spacer()
                Text(relTime(a.time))
                  .font(.caption2)
                  .foregroundStyle(subColor)
              }
              Text(SharedStore.fmtUsd(a.usd))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 3)
          } else {
            HStack {
              Text(a.symbol)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.white)
              Text(a.side == "Buy"
                   ? (SharedStore.isZh ? "买入" : "Buy")
                   : (SharedStore.isZh ? "卖出" : "Sell"))
                .font(.caption2)
                .foregroundStyle(a.side == "Buy" ? upColor : downColor)
              Spacer()
              Text(SharedStore.fmtUsd(a.usd))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
              Text(relTime(a.time))
                .font(.caption2)
                .foregroundStyle(subColor)
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 3)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 2)
    }
  }
}
