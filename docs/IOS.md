# iOS 26 移植候选

基线：上游 `91f9183`；设计：`superpowers/specs/2026-10-16-ios26-port-design.md`。

本分支保留 Flutter 页面、立体书架、阅读排版和数据格式，增加 Swift 联网/会话、文件与原生控件适配。最低 iOS/iPadOS 26.0。Android 继续使用原生 Android 实现。

## 环境与运行

固定 Flutter 3.41.5 / Dart 3.11.3。iOS 编译需要 macOS、Xcode 26+、匹配的 iOS Simulator runtime 和 CocoaPods；真机需要有效的开发者签名。

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --simulator --debug --no-codesign
```

原生玻璃目前是候选原型，默认关闭，避免把尚未在 iOS 验证的跨视图合成直接推广为正式界面。以下命令启用原生底栏、公共图标/主操作按钮和阅读滑块：

```sh
flutter run --dart-define=WENKU8_NATIVE_GLASS=true
flutter build ios --simulator --debug --no-codesign --dart-define=WENKU8_NATIVE_GLASS=true
```

使用系统 UIGlassEffect、UIButton.Configuration.glass 和 UIKit 控件。原型中的玻璃背景能否正确显示 Flutter 内容、中文标签尺寸、VoiceOver 和快速滚动都必须单独检查。开关用于这轮验证；正式启用需要原型验收。菜单、文本按钮和完整面板的原生替换尚未推广；没有 SF Symbol 映射的按钮保留原控件，不能称全部控件已完成玻璃化。

## 联网与数据

iOS 使用现有 legacy_api 通道和已实测的旧版 1.13 表单协议，不加载 Android 二进制。网络响应增量接收，上限 8 MiB。图片受 HTTPS、域名白名单、重定向次数及尺寸限制。

PHP 会话放 Keychain；公共请求不携带账号 Cookie，密码不存储。遇到数值错误码或 HTML 验证页时明确报错，不显示为小说正文。旧接口的长期可用性仍需验证。

书评编码使用严格 Java GBK 映射，避免 iOS 26 运行时不支持 GBK NSString 编码的问题。映射为 23940 个大端序四字节记录（Unicode BMP 标量、GBK 字节值），共 95760 字节；ASCII 直接编码，未映射字符报错。SHA256 为 `e73761b4a3fa5df00f5bccc727d0fea272f3b44670967d7d20cafd9db4584d74`。可用 Java 17+ 标准库重建：

```sh
java native_tests/GenerateGBKMap.java ios/Runner/Resources/gbk-map.bin
```

生成工具和 Swift 读表实现均在仓库内；编码后的 URL 表单仍遵循 Java URLEncoder 的空格、加号和波浪号规则。原生 XCTest 保留对既定字节的断言。

保留现有缓存与备份格式。iOS 的“文件”选择器提供备份导入导出和旧数据文件夹导入；取消不计成功。旧数据文件夹应包含既有 saves/intro 结构或记录文件，不能直接访问 Android 应用私有目录。

在线听书继续使用现有 Edge 协议与音频插件。已添加后台 audio 声明；锁屏、耳机、打断和后台段落合成仍需真机测试。没有把 Android 离线引擎占位实现作为 iOS 产品功能。

iOS 不启用 APK 下载与安装逻辑。当前保留“关于”及许可信息；独立 iOS 发布源与正式 Bundle ID/团队在签名交付前配置。

## 原生验证

Foundation 测试直接执行产品协议代码：

```sh
swiftc -parse-as-library ios/Runner/WenkuProtocol.swift ios/Runner/WenkuControlPolicy.swift ios/Runner/WenkuGBK.swift native_tests/WenkuProtocolTests.swift -o /tmp/wenku-protocol-tests
/tmp/wenku-protocol-tests
```

macOS 的 `.github/workflows/ios.yml` 还会构建模拟器候选，并执行 RunnerTests 中的协议、会话与 GBK 书评编码 XCTest。添加 workflow 不表示 CI 已运行或通过。

原生测试通过后，工作流会捕获模拟器浅色/深色预览，并构建 `Wenku8-ios26-unsigned.ipa`。这是未签名的设备候选，需要自行签名后才能安装；成功生成也不代表真机验收通过。带玻璃开关的构建用于验证原型，不能代替完整控件迁移的验收。

验收时逐项记录：

- 搜索 → 详情 → 目录 → 正文 → 封面与插图。
- 缓存正文后终止应用，再在无网络状态恢复章节、段落位置、书签与历史；缺失章节报错。
- 在设备内登录，重启恢复会话、退出不清理本地数据；不在聊天或日志中提交密码。
- 云书架读取、书评显示；任何账号写操作使用明确授权的测试动作。
- 文件导入/导出、取消、共享、旧数据合并以及 iPad 弹出位置。
- 常亮随阅读页与应用前后台正确释放。
- 听书锁屏/耳机操作、来电打断、睡眠定时及后台连续章节。
- 原生玻璃材质、点击/拖动、键盘恢复、路由返回、深浅主题和系统可访问性。

Windows 上的 Swift 语法解析与 Foundation 测试不能替代 UIKit 类型检查或 iOS 构建。未经独立测试，不声明 iPhone/iPad 真机验收或 IPA 交付完成。
