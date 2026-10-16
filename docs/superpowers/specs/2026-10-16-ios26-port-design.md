# Wenku8 iOS 26 移植设计

日期：2026-10-16（Asia/Shanghai）

状态：设计候选，供用户审阅；尚未进入产品实现。

代码基线：`91f918354c89261a3adfa3fe0ac2f0a1604c007c`。

## 1. 用户目标与已确认选择

把 mikufoxxx/Wenku8_Flutter 移植到 iOS。保留现有功能、内容组织、立体书架、阅读排版、数据格式及业务行为，把控件改为 iOS 原生液态玻璃风格。用户已确认仅支持 iOS 26 及以上，优先原生 Liquid Glass。

保留 Flutter 与 Dart 业务层，新增 Swift 平台实现。iPadOS 26 使用现有自适应页面，不引入新的侧栏、分屏或阅读布局。iPhone 为首轮验收目标；iPad 仍须独立验收后才能声明支持完整。

本次不增加书源、AI 功能、第三方账号体系或新的阅读引擎。Android 实现与既有行为保持兼容。平台本身不支持的 APK 安装更新和 Android TTS 引擎管理需按下文明确处理，不能伪装成已迁移功能。

## 2. 证据与当前边界

已检查 `main.dart`：Android 以外当前使用 DemoNovelRepository，账号与听书未启用。`ios/Runner` 只有基础 Flutter 生命周期和插件注册，没有项目自定义的平台通道。

2026-10-16 的 Windows 独立脚本向 `https://wenku8-relay.mewx.org/` 使用公开旧版参数 `appver=1.13` 进行了只读验证：

| 项目 | 观察结果 | 证据边界 |
| --- | --- | --- |
| 搜索“文学少女” | 1 项，包含 aid=1 | 当前网络下的一次实测 |
| 详情 | 返回书名、作者等元数据 | 不是全部书籍兼容性证明 |
| 目录 | 213 章 | 已解析章节稳定 ID |
| 正文 | cid=2 返回 2060 字符 | 单章样本，不覆盖所有正文与插图格式 |
| 独立本地恢复 | SHA256 一致，恢复预设 offset=100 | 自定义脚本缓存，不是 Flutter 缓存或真实阅读位置 |
| 未登录 userinfo/bookcase | 都返回 4 | 与现有错误映射相符，未验证登录 |

脚本和原始汇总位于工作区 `validation/probe-reading-chain.ps1`、`online-result.json`、`offline-result.json`。这些是独立探针证据，不是产品测试通过证据；正文缓存不纳入源码提交。

原 API 的 Android `.so` 不进入 iOS 包。现有公开代码没有对应 iOS 版本。旧接口可能停止服务；HTTP 200 本身不能当成功，必须检查每个动作的有效载荷。

## 3. 架构与职责

```text
现有 Flutter 页面、书架、阅读器、LibraryState
              │
既有仓库模型、离线缓存、账号与听书控制器
              │
既有 MethodChannel 契约 + iOS 控件适配层
              │
Swift 网络/会话、文件/分享/常亮、原生控件
              │
URLSession / Keychain / UIKit / SwiftUI / audio_service
```

尽量保持已有通道和模型不变。Dart 负责书架、阅读位置、离线目录、正文缓存、听书状态及页面路由；Swift 负责平台资源与原生控件生命周期。网络和账号 Cookie 留在原生侧，避免为了跨平台把 Cookie 引入 LibraryState 或备份。

### 3.1 iOS 网络与账号

在 `ios/Runner` 新增独立的网络桥接、会话存储与图片策略实现，通过现有 `org.mewx.wenku8/legacy_api` 注册。

支持原方法：`request`、`requestBytes`、`cover`、`accountRequest`、`login`、`hasSession`、`clearSession`、`illustration`、`clearIllustrations`、`encodeReview`。Android 继续使用原实现。

Swift 使用 URLSession，发送已验证的旧版表单封装。接口参数、地址和响应校验集中在一个传输实现中，不散落到页面。客户端版本值不能伪装为已验证的新协议，也不缓存从 Android 二进制提取的签名。

请求规则：

- 公共请求不附加账户 Cookie；公共内容失败不能改变登录状态。
- 账号请求串行化；登录、退出和用户切换增加会话代数，旧请求不能覆盖新会话。
- 只在登录返回成功且获得有效会话时持久化；会话放 Keychain，不保存密码，不进入日志或备份。
- 账号返回 4 时清理对应会话，并保留本地书架、缓存与阅读进度。
- 保持有界请求、超时和响应大小上限；采用现有 8 MiB 响应限制。正文必须拒绝纯数字错误码、空响应及 HTML 错误/验证页。
- 原生错误向 Dart 返回既有语义；错误文本不包含表单、密码或 Cookie。

封面按既有 cover 动作取字节；插图移植现有域名白名单、HTTPS、逐次重定向校验和图片有效性检查，不把任意 URL 交给下载器。保留现有内存缓存预算与磁盘缓存行为。

`encodeReview` 必须与 Android 的严格 GBK → URL 编码 → Base64 输出逐字节一致。不能用有损转码、问号替代字符或更宽的编码冒充 GBK；无法精确编码时返回 REVIEW_ENCODING 并保留草稿。编码兼容样本是书评验收的必要条件。

### 3.2 数据与离线阅读

复用 `OfflineCacheStore`、`OfflineNovelRepository`、LibraryState 和现有备份模型；不修改缓存目录版本、稳定书籍/章节 ID 与既有阅读位置表示。

在 iOS 启用真实仓库与缓存，取消该平台的 Demo 分支。应用支持目录由 path_provider 提供。重启恢复须通过真实 Dart 实现验证：目录、已缓存正文、章节 ID、段落位置和书签都能恢复；缺失章节明确报错，不回退到演示数据。

只读离线打开不能隐式上传或修改云书架。缓存写入失败不能抹掉原缓存或让已获取的正文不可读。

### 3.3 文件、分享与常亮

为 `org.mewx.wenku8/local_tools` 补齐 iOS 实现：

| 功能 | iOS 对应行为 |
| --- | --- |
| 备份导入 | 系统文档选择器，保持原校验和数据合并语义 |
| 备份导出 | 系统文档导出，取消返回取消，不报成功 |
| 分享 | UIActivityViewController，iPad 正确指定弹出锚点 |
| 旧数据导入 | 用户从“文件”选择已导出的旧数据文件夹，保留既有解析和大小限制；不读取 Android 私有目录 |
| 阅读常亮 | UIApplication.isIdleTimerDisabled；页面离开、后台和销毁时恢复 |

文件安全访问权限仅在导入期间持有；异步回调只完成一次。不扩大应用的文件访问范围。

### 3.4 听书

复用 Edge 在线合成、段落分段、缓存、播放控制器、语速、定时器及续听存储。继续使用现有 audio_service、audio_session、just_audio 的 iOS 实现。

补齐后台 audio 配置与音频会话。验收锁屏控制、耳机控制、来电打断、耳机断开、暂停恢复、段落合成间隙和睡眠定时。后台合成是否可持续必须真机确认，不能仅凭音频插件支持 iOS 就宣称通过。

当前产品仅提供已启用的在线音色；保留现有音色和设置。Android 离线引擎探索入口不移植为假功能，也不额外新增离线语音产品能力。

## 4. 原生液态玻璃与交互

使用系统 UIKit/SwiftUI 控件和公开 Liquid Glass API。通过 Flutter 官方 platform view 机制嵌入，平台工厂在现有 UIScene/implicit-engine 注册点初始化。SwiftUI 容器须正确持有 UIHostingController 并管理控制器包含关系、尺寸和销毁。

先验证底栏及一个阅读工具栏，再推广公共组件。采用按工具栏/控件组嵌入的方式，避免为长列表中的每个子元素创建原生视图。具体合成方式以 iOS 实测为准，不能默认玻璃能采样 Flutter 引擎绘制的背景。

原型必须证明：动态背景折射/透明表现、点击与拖动、Flutter 滚动、键盘显示与恢复、路由返回、深浅主题、旋转和安全区都正确。若 platform view 无法正确合成，先评估同一原生宿主中的浮层；两种方式都不能满足时记录失败并调整设计，不擅自改成自绘效果后标为原生。

| 元素 | 移植约束 |
| --- | --- |
| 发现/书架/设置底栏 | 保留三个入口、选中状态、可访问名称和原有可用手势，用原生玻璃承载 |
| 顶部导航与操作按钮 | 保留动作和位置关系，系统材质、点击反馈和可访问性 |
| 阅读浮动工具栏 | 保留目录、进度、书签、查找、专注与听书入口及隐藏逻辑 |
| 弹出菜单/设置控制 | 系统菜单、按钮、开关、滑块与分段控件承担相同动作；内容和选项保持 |
| 阅读设置/目录面板 | 只替换控件与承载材质，保留内容布局、顺序及选中行为 |
| 正文、封面、立体书架 | 保留现有 Flutter 绘制、字体、排版和惯性/吸附行为 |

搜索输入继续保留 Flutter 输入逻辑，确保中文输入与焦点恢复；搜索提交和清空等外围动作可以原生化。避免同时显示两套滚动边缘模糊或两层玻璃。系统“减少透明度”“增强对比度”“减少动态效果”必须有效。

低性能设置保留；iOS 原生材质不能支持的自绘参数不显示为可调却无效的设置。自绘折射参数仅影响仍由 Flutter 绘制的对应内容，系统材质跟随系统可访问性设置。

## 5. 工程、平台差异与分发

最低 iOS/iPadOS 版本统一为 26.0，覆盖 Xcode 构建配置、Podfile 及相关项目设置。先固定并验证现有 Flutter 3.41.5/Dart 3.11.3 与 Xcode 26+ 的兼容组合；升级工具链须有实际构建原因和独立回归证据。

首轮使用现有 Bundle ID 做无签名构建验证；正式 Bundle ID、开发者团队和发布渠道在签名交付前确认，不代用原作者的发布身份。

“关于”保留版本与许可信息；iOS 不下载或安装 APK，不提示开启“未知来源”。更新入口改为显示当前版本及打开本移植项目的发布页；没有独立发布源时只显示版本和项目主页，不用原 Android 发布版本制造更新提示。

保留原作者署名与第三方许可，记录 iOS 修改。暂不自动发布、上传商店或配置付费签名；最终交付方式确定后再执行对应分发操作。

## 6. 验证与完成标准

按证据独立报告代码实现、静态检查、Dart 测试、iOS 编译、模拟器和真机结果；任一项不替代其他项。

1. 公共接口：使用协议夹具验证表单、错误码、字节与大小限制；实时小样覆盖搜索、详情、目录、正文、封面和插图。限制实时请求数量，不下载整库。
2. 账号：夹具验证 Cookie、会话代数、并发退出、GBK 编码；真实账号在用户设备登录后验证个人信息及云书架读取，修改动作仅在明确测试授权后执行。不得要求用户在聊天中粘贴密码。
3. 离线：运行真实 Dart 缓存测试；模拟远端不可用后重建仓库，验证正文读取无网络请求、缺失章节报错、书签与段落续读恢复。
4. iOS 控件：模拟器验证动作回传、状态同步、销毁、键盘和返回；真机验证玻璃合成、快速滚动、立体书架与正文位置稳定。原生视图在 widget test 中使用明确测试替身，不能把替身测试当原生渲染通过。
5. 文件与听书：验证导入/导出/取消、分享、前后台常亮恢复、锁屏/耳机控制及打断；iPhone 与 iPad 分开记录结果。
6. 回归：保留既有 Dart 行为测试及 Android 构建检查，不通过削弱断言或跳过失败来迁就移植。新增 iOS/macOS CI 运行 Dart 检查与测试、无签名构建和原生测试。

完成定义：上述功能矩阵全部有对应实现和验证；没有 Demo 代替在线功能、没有缺失通道、没有无效设置，且 iPhone 真机完整阅读/听书链路验收。iPad 未测则单独标为未验收。

当前为 Windows 环境，未发现可直接运行的 Flutter/Dart/Xcode 命令。现阶段不能声称 Flutter 测试或 iOS 构建通过。后续可在 Windows 安装固定 Flutter SDK 执行 Dart 检查；iOS 编译和设备验收需要 macOS/Xcode 环境或授权使用的 macOS CI。

## 7. 实施顺序与停止条件

顺序：原生玻璃合成小样与工具链验证 → iOS 网络及最小真实阅读链路 → 离线/账号/文件/听书适配 → 公共控件替换 → 完整回归与真机验收。

小样先验证两项独立风险：原生玻璃与 Flutter 背景合成，以及旧协议在 iOS 上的真实取数。任一失败都保留证据并修订相关设计，不扩散到全部控件。

设计获审阅后，再编写按文件、依赖与验证命令拆分的实施计划。此文档不等同于产品实现、构建成功或已交付 IPA。

## 8. 参考资料

- [上游代码基线](https://github.com/mikufoxxx/Wenku8_Flutter/tree/91f918354c89261a3adfa3fe0ac2f0a1604c007c)
- [上游第三方组件与 API 运行库说明](https://github.com/mikufoxxx/Wenku8_Flutter/blob/91f918354c89261a3adfa3fe0ac2f0a1604c007c/docs/THIRD_PARTY.md)
- [旧协议公开参考实现](https://github.com/zsakvo/wenku8x/blob/57c6312fb2ec619c399be1360d5d16ccdd2cd23c/lib/http/ajax.dart)
- [Flutter iOS platform views 与 UIScene 注册](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [audio_service 的 iOS 配置说明](https://pub.dev/packages/audio_service)
