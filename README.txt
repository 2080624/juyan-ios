聚言商聊 · iOS 壳源码（云编译出 IPA 用）
==========================================

这个包不用改任何东西，直接整包上传到你的 GitHub 仓库即可。

包里是什么
----------
project.yml                    工程配置（云端会用它生成 Xcode 工程）
AppDelegate.swift              启动 + 通知注册 + 拿设备推送地址
WebShellViewController.swift   网页壳（装 jysl.pw，主地址打不开自动切备用）
PushRegistrar.swift            把设备和账号绑定后交给服务器
Info.plist                     权限文案 + 后台推送模式
JuYan.entitlements             推送开关（未签名包里不生效，签名时才用到）

出包方式
--------
在仓库里建一个 .github/workflows/build-ios.yml（内容用发给你的那段），
提交后在 Actions 页面等 4~6 分钟，就能下到 JuYan-unsigned.ipa。

出来的 IPA 是未签名的，交给代签的人重签即可。
