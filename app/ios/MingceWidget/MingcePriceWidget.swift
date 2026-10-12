import SwiftUI
import WidgetKit

/// 行情小组件: 固定五币 (BTC/ETH/SOL/XRP/DOGE) 最新价 + 24h 涨跌.
/// 数据来自 App Group (Dart WidgetBridge 30s 节流写入), 15 分钟 timeline 兜底.
struct MingcePriceWidget: Widget {
  let kind = "MingcePriceWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PriceProvider()) { entry in
      PriceWidgetView(entry: entry)
        .containerBackground(Color(red: 11 / 255, green: 14 / 255, blue: 20 / 255), for: .widget)
    }
    .configurationDisplayName(SharedStore.isZh ? "行情速览" : "Market Prices")
    .description(SharedStore.isZh ? "主流币种实时价格与 24 小时涨跌" : "Live prices and 24h change for major coins")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct PriceEntry: TimelineEntry {
  let date: Date
  let prices: [SharedStore.CoinPrice]
}

struct PriceProvider: TimelineProvider {
  func placeholder(in context: Context) -> PriceEntry {
    PriceEntry(date: Date(), prices: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
    completion(PriceEntry(date: Date(), prices: SharedStore.prices()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
    let entry = PriceEntry(date: Date(), prices: SharedStore.prices())
    let next = Date().addingTimeInterval(15 * 60)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct PriceWidgetView: View {
  let entry: PriceEntry
  @Environment(\.widgetFamily) var family

  var upColor: Color { Color(red: 46 / 255, green: 189 / 255, blue: 133 / 255) }
  var downColor: Color { Color(red: 240 / 255, green: 90 / 255, blue: 90 / 255) }
  var subColor: Color { Color(red: 139 / 255, green: 143 / 255, blue: 158 / 255) }

  var body: some View {
    if entry.prices.isEmpty {
      VStack(spacing: 6) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .foregroundStyle(subColor)
        Text(SharedStore.isZh ? "打开明策同步行情" : "Open Mingce to sync")
          .font(.caption)
          .foregroundStyle(subColor)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(SharedStore.isZh ? "明策行情" : "Mingce Markets")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(subColor)
          Spacer()
          Text(entry.date, style: .time)
            .font(.caption2)
            .foregroundStyle(subColor)
        }
        .padding(.bottom, 6)
        ForEach(Array(entry.prices.prefix(family == .systemSmall ? 3 : 5).enumerated()), id: \.offset) { _, p in
          HStack {
            Text(p.symbol)
              .font(.system(.caption, design: .rounded))
              .fontWeight(.bold)
              .foregroundStyle(.white)
            Spacer()
            Text(SharedStore.fmtPrice(p.price))
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.white)
            Text(String(format: "%@%+.2f%%", "", p.change_pct))
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(p.change_pct >= 0 ? upColor : downColor)
              .frame(width: 62, alignment: .trailing)
          }
          .padding(.vertical, 3)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 2)
    }
  }
}
