# 开发说明

[环境与构建](#环境与构建) · [项目结构](#项目结构) · [检查与验证](#检查与验证) · [发布](#发布) · [术语](#术语) · [数据语义](#数据语义)

协作规范见仓库根目录的 [AGENTS.md](../AGENTS.md)，界面设计规则见 [DESIGN.md](DESIGN.md)，站点插件协议见 [SOURCE_API.md](SOURCE_API.md)。

## 环境与构建

- 工具链：Flutter 3.47.7（Dart 3.13.5）、JDK 17、Node.js 22。CI 固定这个 Flutter 版本。
- WebView 使用 beta 依赖，用于现有的浏览器桥能力；升级前必须验证 Cookie 分区、验证页和媒体传输。`flutter_tts` 仍使用外部 Kotlin 插件，升级 Flutter 前要核对插件的内置 Kotlin 支持。
- 当前正式运行和发布目标是 Android。Windows 只是开发宿主，桌面目录不代表原生能力已经验证。

### Android SDK

Flutter 的 `android-sdk` 与 `android/local.properties` 的 `sdk.dir` 都应指向包含 `platforms`、`build-tools`、`platform-tools`、`ndk` 的那一层，把 `<Android SDK 目录>` 换成本机实际路径：

```powershell
flutter config --android-sdk '<Android SDK 目录>'
flutter doctor -v
```

`local.properties` 由 Flutter 构建按此配置重写，不提交。更换 SDK 后如果 Lint 使用旧缓存，执行 `:app:lintVitalAnalyzeRelease --rerun`，不要关闭检查规则。

### 构建

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

- 正式构建要求 `android/key.properties` 配置 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`，缺少就失败，不回退到 debug 签名。
- 只检查能否编译时用 `flutter build apk --release --split-per-abi --android-project-arg=verifyUnsignedBuild=true`，输出无签名 APK，不能安装或发布。显式传参是为了避免 Windows 上 Dart 把环境变量名转成大写，导致 Gradle 认不出属性。
- `flutter pub get` 必须成功。Windows 未开启开发者模式时它会中途失败，`GeneratedPluginRegistrant` 缺失会让 APK 一启动就崩溃，不能用 `--no-pub` 绕过。
- 在模拟器上验证时可以构建 profile 包：`flutter build apk --profile --target-platform android-x64`。设备上已装更高的 versionCode 时，加 `--build-number` 指定一个更大的值来覆盖安装，以保留应用数据；不要为此修改 `pubspec.yaml` 的版本。

## 项目结构

| 目录 | 内容 |
| --- | --- |
| `lib/core/` | 模型、设置、国际化（`localization.dart`、`plugin_copy.dart`）、应用锁、诊断 |
| `lib/engine/` | 插件加载与运行时（`source_manager.dart` 及 `source_manager/` 下的各部分）、JS 引擎、网络、Cookie、隔离与原生桥 |
| `lib/images/` | 图片解码、解密与缓存 |
| `lib/library/` | 书库、下载、备份、迁移、`playback_resolver.dart`（“继续”打开什么） |
| `lib/ui/kit/` | 设计令牌与通用组件（见 DESIGN.md） |
| `lib/ui/` | 各页面：`home`、`library`、`history`、`settings`、`detail`、`reader`、`novel`、`video`、`search`… |
| `assets/sources/` | 站点插件，唯一的站点实现；`index.json` 是官方清单 |
| `assets/runtime/park_runtime.js` | 插件运行时（应用与 Node 共用） |
| `assets/i18n/` | 八种语言的界面文案，键为简体中文原文 |
| `tools/` | 检查、发布与构建脚本 |

插件运行时按需启动：应用启动时只读取按“脚本 SHA-256 + 运行时版本”缓存的 manifest（`source_manifests.json`），第一次调用某个站点时才为它启动无界面 WebView；空闲 5 分钟或同时运行超过 6 个时回收最久未用的。账号状态按站点缓存，只在首次使用、登录、退出、网页登录后以及超过 10 分钟时刷新。

设置与书库都按范围通知，界面只订阅自己用到的部分，不监听整个对象：

- `AppSettings.domain(SettingsDomain.x)` 在该领域（外观、漫画阅读、小说、网络、隐私、书库、订阅、搜索、过滤、维护）任一键变化时通知；`AppSettings.watch(keys)` 用于跨领域的少数键。所有值仍存在同一个 `settings.json` 里，存储格式和备份不变；新增设置键必须归入一个领域（调试模式下会断言）。
- `Library.instance.work(uid)` 只在这部作品的收藏、历史、进度或章节状态变化时通知；`Library.instance.collection(LibraryCollection.x)` 按收藏、分类、历史、章节分别通知。
- 大页面按职责拆分：视频页的播放会话在 `VideoSession`，播放区在 `VideoStage`，手势在 `video_page_gestures.dart`；漫画和小说阅读器的翻页、输入、排版与菜单动作分别在各自的 `part` 文件中，共享状态放在抽象基类里。

## 检查与验证

日常检查：

```powershell
.\tools\check.ps1
```

Flutter 不在 PATH 上时传入完整路径：`.\tools\check.ps1 -FlutterCommand '<flutter.bat>' -DartCommand '<dart.bat>'`。它依次运行：

1. `tools/check_localizations.mjs`：八种语言的键、占位符和可静态确定的 `tr()` 引用一致。动态文案键仍需人工审查。
2. `tools/check_styles.mjs`：界面只使用主题与设计令牌（不直接写颜色、圆角、字号，字重不超过 600）。
3. `flutter analyze lib`：静态检查，规则见 `analysis_options.yaml`。
4. `dart format`：格式检查。手写 JS 使用两空格、多行函数与单引号；生成文件按生成器格式保留。
5. `tools/publish_sources.mjs`：官方插件离线校验。

- 所有测试、复现脚本、夹具和测试产物只放在根目录 `test/`，它被 `.gitignore` 忽略，不跟踪、不提交。
- 默认只运行与改动相关的测试。修复要有能复现原问题的针对性验证；完成说明附上新鲜的测试或实际请求证据，并写明没有验证到的部分。
- 离线校验不能代替真实请求。修改插件后用共享运行时（见 SOURCE_API.md 的“在 Node 中试跑”）真实请求首页、分页、搜索、详情、封面解码，以及漫画章节或视频分集/媒体。

## 发布

- 插件版本与应用版本分开管理。修改插件脚本时同时提高插件版本并更新 `assets/sources/index.json`；不擅自提高应用版本。
- 应用发布前核对包名、递增 versionCode、使用正式证书。CI 不自动发布应用。
- 官方插件由 `.github/workflows/publish-sources.yml` 在 `main` 推送后发布到 `sources` 分支，流程见 SOURCE_API.md 的“发布”。
- 已安装旧版插件的用户在接受官方插件更新之前继续使用旧脚本；插件文案、错误提示等随插件更新生效，发布说明中要提醒用户更新插件。
- 官方插件更新最多三个站点并发下载、校验和安装。安装、卸载与恢复内置版本只等待对应站点的操作；其他站点可继续发起请求。同站点的新请求等待自身更新结束。每个站点使用独立的 `source_install_<key>.json` 恢复日志，失败只恢复自身脚本、配置与 Cookie；启动时先恢复未完成事务。全量备份、导入仍使用全局一致性屏障。
- 运行日志（设置 → 关于 → 运行日志）与导出文件是同一份报告：应用版本、是否设置了应用代理、日志涉及的站点插件版本，此前运行的未捕获错误（`logs/crash.log`，JSON 行，读取时重新净化），以及本次运行的事件。事件包括插件调用失败（`event=source`，带方法名）、播放打开失败（`event=playback`）、HLS 分片失败（`event=media`）和未捕获错误（`event=crash`，带代码位置）。字段白名单见 `lib/core/diagnostics.dart`；连续相同的事件合并计数。WebView 控制台输出不记录。
- 发现页各站点的首屏作品在本次应用会话中复用，切换分类、展示站点和滚动不会重新请求。顶部下拉刷新清空全部会话内容，下次可见时重新获取；已加载的横向书架在滚出屏幕后保留。每个分类的展示站点通过标题右侧配置按钮选择，配置随应用设置持久化。

### 许可

项目采用 `AGPL-3.0-only`，全文见 [LICENSE](../LICENSE)。发布包内置项目、Telegram 与 EhTagTranslation 的第三方许可，可在“我的 → 关于 → 开源许可证”查看；分发时同时提供对应源码与第三方声明，入口见 [许可目录](licenses/README.md)。

## 术语

界面和文档统一使用以下说法：

| 用语 | 含义 |
| --- | --- |
| 站点 | 一个站点插件及其对应的网站（代码中仍叫 source） |
| 分类 | 发现页的入口分组：本子、美图、里番、JAV、成人视频、短视频、AI 短剧、小说、游戏、其他（代码中的 `category`） |
| 媒体类型 | 漫画 / 视频 / 小说 / 游戏，决定阅读或播放方式（代码中的 `type`、`mediaKind`） |
| 书架 | 界面入口：收藏、更新、下载 |
| 书库 | 持久化的收藏、进度与历史数据 |
| 订阅 | 关注频道、创作者或关键词的新内容 |

## 数据语义

### 备份

- 备份包含书库、进度、标注、订阅目标、全局设置和站点配置；不含离线正文、媒体缓存和 Cookie。站点的 Token 等私有凭据只在用户勾选“站点登录数据”时导出。
- 成年确认只保存在本机，不进入备份。
- 自动备份只在启动和回到前台时检查，不在应用关闭后定时运行。
- 备份里有、本机没安装的第三方站点，其配置会保留到后续备份中，安装相同 key 的插件后应用。

### 迁移与缓存

- 章节迁移只复制无歧义的一对一进度；目录不完整时不能删减目标章节，有未匹配的原进度时保留原收藏。
- 发现页实时结果保留插件字段，磁盘只缓存显示用的元数据；只有明确的网络或超时错误才降级显示过期缓存。

### 订阅

- 订阅目标、检查点、已见 ID、更新事件和通知队列保存在书库 SQLite 的独立表中。旧的 `subscriptions.json` 只导入一次并保留原文件；恢复备份时在同一事务中合并目标，保留现有名称与状态，新增目标建立新基线。
- 编辑订阅时，只改备注名称保留检查进度；改目标则保留开关与顺序，为新目标建立基线，旧请求的结果不再写入。重复目标拒绝保存。
- 自动检查默认每 6 小时，可选关闭或 1/3/6/12/24 小时，也在启动、回到前台和手动时检查。两个站点并发、同一站点串行，五分钟的数据库租约防止同一目标被重复检查；事件按站点、类型和稳定 ID 跨目标去重。首次只建立基线不推送；失败记录安全错误码并指数退避。
- Android 后台任务由 JobScheduler 启动独立的 Flutter 引擎和原有沙箱，只加载启用订阅关联的站点，不主动刷新全部账号；前台启动时先等后台任务取消并写完。系统可能推迟任务，不保证实时通知。
- 应用内记录不依赖通知权限。系统通知需要用户开启并授权，默认不显示标题；成功显示后才标记已投递，被拒或频道关闭时稍后重试，稳定的通知 ID 避免叠加。最多保留最近 500 条。移除目标会停止它的通知，历史事件保留。
- 订阅附件与图片共用媒体缓存上限，可在“我的 → 存储”中查看和清理；正在使用的附件受保护。缓存只保存可重建的媒体，不替代下载或备份。
