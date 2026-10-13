import Foundation

/// App Group 共享存储读取 (Dart 侧 WidgetBridge 经 home_widget 写入).
enum SharedStore {
  static let appGroupId = "group.com.hkmc.noahsark.shared"

  struct CoinPrice: Codable {
    let symbol: String
    let price: Double
    let change_pct: Double
  }

  struct WhaleAlert: Codable {
    let symbol: String
    let side: String
    let usd: Double
    let time: Int64  // ms epoch
    let source: String
  }

  static var isZh: Bool {
    if #available(iOS 16, *) {
      return Locale.current.language.languageCode?.identifier.hasPrefix("zh") ?? false
    }
    return Locale.current.languageCode?.hasPrefix("zh") ?? false
  }

  static func prices() -> [CoinPrice] {
    guard let defaults = UserDefaults(suiteName: appGroupId),
          let raw = defaults.string(forKey: "mc_prices"),
          let data = raw.data(using: .utf8),
          let list = try? JSONDecoder().decode([CoinPrice].self, from: data)
    else { return [] }
    return list
  }

  static func whales() -> [WhaleAlert] {
    guard let defaults = UserDefaults(suiteName: appGroupId),
          let raw = defaults.string(forKey: "mc_whales"),
          let data = raw.data(using: .utf8),
          let list = try? JSONDecoder().decode([WhaleAlert].self, from: data)
    else { return [] }
    return list
  }

  static func fmtPrice(_ p: Double) -> String {
    if p >= 1000 { return String(format: "%.1f", p) }
    if p >= 1 { return String(format: "%.2f", p) }
    return String(format: "%.4f", p)
  }

  static func fmtUsd(_ v: Double) -> String {
    if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
    return String(format: "$%.0fK", v / 1_000)
  }
}
