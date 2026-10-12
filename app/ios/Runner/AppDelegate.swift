import ActivityKit
import Flutter
import UIKit

/// 盯盘 Live Activity 属性 (锁屏/灵动岛实时价).
/// 注意: MingceWidget 扩展里有一份同名拷贝 (ActivityAttributes 需两端一致),
/// 改字段两边一起改.
struct WatchActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var price: Double
    var changePct: Double
  }
  var symbol: String
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 把 APNs device_token 回传给 Dart 侧的 channel (engine 就绪后建立).
  private var pushChannel: FlutterMethodChannel?
  /// Live Activities 通道 (盯盘).
  private var liveChannel: FlutterMethodChannel?
  /// 当前盯盘 activity (iOS 16.1+), 用 Any 持有规避低版本编译限制.
  private var watchActivity: Any?
  private var pushTokenTask: Task<Void, Never>?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // 申请通知权限 + 注册远程推送 (拿 device_token)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      if granted {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // channel 需在 engine 就绪后建立
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "mc.push") {
      pushChannel = FlutterMethodChannel(name: "mc.push", binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "mc.live") {
      liveChannel = FlutterMethodChannel(name: "mc.live", binaryMessenger: registrar.messenger())
      liveChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleLiveActivity(call, result: result)
      }
    }
  }

  // MARK: - Live Activities (mc.live)

  private func handleLiveActivity(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startActivity":
      guard let args = call.arguments as? [String: Any],
            let symbol = args["symbol"] as? String, !symbol.isEmpty else {
        result(FlutterError(code: "bad_args", message: "symbol required", details: nil))
        return
      }
      startWatchActivity(symbol: symbol, result: result)
    case "endActivity":
      endWatchActivity(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startWatchActivity(symbol: String, result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        result(FlutterError(code: "unsupported", message: "Live Activities disabled", details: nil))
        return
      }
      // 已有盯盘先结束 (单活动策略)
      if let old = watchActivity as? Activity<WatchActivityAttributes> {
        Task {
          if #available(iOS 16.2, *) {
            await old.end(nil, dismissalPolicy: .immediate)
          } else {
            await old.end(using: nil, dismissalPolicy: .immediate)
          }
        }
        pushTokenTask?.cancel()
      }
      let attributes = WatchActivityAttributes(symbol: symbol)
      let state = WatchActivityAttributes.ContentState(price: 0, changePct: 0)
      do {
        let activity: Activity<WatchActivityAttributes>
        if #available(iOS 16.2, *) {
          activity = try Activity<WatchActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: .token
          )
        } else {
          activity = try Activity<WatchActivityAttributes>.request(
            attributes: attributes,
            contentState: state,
            pushType: .token
          )
        }
        watchActivity = activity
        // push token 异步下发 → 转给 Dart 上报服务端
        pushTokenTask = Task {
          for await data in activity.pushTokenUpdates {
            let token = data.map { String(format: "%02x", $0) }.joined()
            liveChannel?.invokeMethod("onActivityToken", arguments: token)
          }
        }
        result(true)
      } catch {
        result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }
    } else {
      result(FlutterError(code: "unsupported", message: "Requires iOS 16.1", details: nil))
    }
  }

  private func endWatchActivity(result: @escaping FlutterResult) {
    pushTokenTask?.cancel()
    pushTokenTask = nil
    if #available(iOS 16.1, *),
       let activity = watchActivity as? Activity<WatchActivityAttributes> {
      Task {
        if #available(iOS 16.2, *) {
          await activity.end(nil, dismissalPolicy: .immediate)
        } else {
          await activity.end(using: nil, dismissalPolicy: .immediate)
        }
      }
    }
    watchActivity = nil
    result(true)
  }

  // MARK: - APNs device token (mc.push)

  // APNs 注册成功 → 回传 token 给 Dart
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pushChannel?.invokeMethod("onPushToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
