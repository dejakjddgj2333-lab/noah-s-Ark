import ActivityKit
import SwiftUI
import WidgetKit

/// 盯盘 Live Activity 属性 — 与 Runner/AppDelegate.swift 里的定义保持一致,
/// 改字段两边一起改 (content-state 键须对服务端推送 payload).
struct WatchActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var price: Double
    var changePct: Double
  }
  var symbol: String
}

/// 盯盘 Live Activity: 锁屏横幅 + 灵动岛实时价格 (服务端 60s 一轮 APNs 更新).
@available(iOS 16.1, *)
struct WatchLiveActivity: Widget {
  var upColor: Color { Color(red: 46 / 255, green: 189 / 255, blue: 133 / 255) }
  var downColor: Color { Color(red: 240 / 255, green: 90 / 255, blue: 90 / 255) }

  func pctColor(_ pct: Double) -> Color { pct >= 0 ? upColor : downColor }

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WatchActivityAttributes.self) { context in
      // 锁屏/待机横幅
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.symbol + "/USDT")
            .font(.headline)
            .foregroundStyle(.white)
          Text(SharedStore.isZh ? "明策盯盘" : "Mingce Watch")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(context.state.price > 0 ? SharedStore.fmtPrice(context.state.price) : "--")
            .font(.system(.title3, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(pctColor(context.state.changePct))
          Text(String(format: "%+.2f%%", context.state.changePct))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(pctColor(context.state.changePct))
        }
      }
      .padding(14)
      .activityBackgroundTint(Color(red: 11 / 255, green: 14 / 255, blue: 20 / 255))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.symbol)
            .font(.headline)
            .foregroundStyle(.white)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.price > 0 ? SharedStore.fmtPrice(context.state.price) : "--")
            .font(.system(.body, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(pctColor(context.state.changePct))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(String(format: "%+.2f%%", context.state.changePct))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(pctColor(context.state.changePct))
        }
      } compactLeading: {
        Text(context.attributes.symbol)
          .font(.caption2)
          .fontWeight(.bold)
          .foregroundStyle(.white)
      } compactTrailing: {
        Text(context.state.price > 0 ? SharedStore.fmtPrice(context.state.price) : "--")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(pctColor(context.state.changePct))
      } minimal: {
        Text(context.attributes.symbol)
          .font(.caption2)
          .foregroundStyle(pctColor(context.state.changePct))
      }
    }
  }
}
