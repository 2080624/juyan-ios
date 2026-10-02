//
//  PushRegistrar.swift
//  把「这台设备 + 这个账号」的推送地址交给服务端。
//
//  地址改成你自己的域名；接口是服务端 /api/jy/push-token。
//
import Foundation

enum PushRegistrar {

    /// 换成你自己的站点地址（跟网页同一个域名）
    static let endpoint = URL(string: "https://jysl.pw/api/jy/push-token")!

    /// deviceToken 和登录凭证齐了才上报；登录可能比授权通知早，所以两边拿到都叫一次
    static func reportIfReady() {
        let token = AppDelegate.deviceToken
        let auth = AppDelegate.authToken
        guard !token.isEmpty, !auth.isEmpty else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "token": token,
            "platform": "ios",
            "uid": AppDelegate.authUID,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                print("[jy] 推送地址上报失败:", err.localizedDescription)
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            print("[jy] 推送地址上报:", code)
        }.resume()
    }
}
