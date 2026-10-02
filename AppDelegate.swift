//
//  AppDelegate.swift
//  聚言商聊 iOS 壳
//
//  干三件事：
//   1. 起一个 WKWebView 把网页装进来（网页那套功能原样用）
//   2. 申请通知权限、拿 deviceToken
//   3. 网页把登录态递过来之后，把 deviceToken 绑到这个账号上（服务端才有得推）
//
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?

    /// 苹果给的推送地址（16 进制字符串），拿到就存这儿
    static var deviceToken: String = ""
    /// 网页递过来的登录态（谁在登录 + 他的登录凭证），上报推送地址时要用
    static var authUID: String = ""
    static var authToken: String = ""

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = WebShellViewController()
        window?.makeKeyAndVisible()

        UNUserNotificationCenter.current().delegate = self
        registerForPush(application)
        return true
    }

    /// 申请通知权限：同意了才去要 deviceToken
    private func registerForPush(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else {
                print("[jy] 用户没给通知权限，App 退出去就收不到提醒了")
                return
            }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppDelegate.deviceToken = hex
        print("[jy] deviceToken:", hex)
        PushRegistrar.reportIfReady()
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[jy] 推送注册失败:", error.localizedDescription)
    }

    /// App 在前台时收到推送：一样弹出横幅 + 响一声（不然前台没提醒）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点了通知：带上会话 id 打开对应的聊天窗口
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let conv = (info["conv"] as? String) ?? ""
        if !conv.isEmpty {
            NotificationCenter.default.post(name: .jyOpenConv, object: nil, userInfo: ["conv": conv])
        }
        completionHandler()
    }
}

extension Notification.Name {
    /// 点通知 → 打开某个会话
    static let jyOpenConv = Notification.Name("jyOpenConv")
}
