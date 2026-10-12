import WidgetKit
import SwiftUI

/// 明策桌面小组件 bundle: 行情五币 + 巨鲸异动 + 盯盘 Live Activity.
@main
struct MingceWidgetBundle: WidgetBundle {
  var body: some Widget {
    MingcePriceWidget()
    MingceWhaleWidget()
    if #available(iOS 16.1, *) {
      WatchLiveActivity()
    }
  }
}
