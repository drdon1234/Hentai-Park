# 开发说明

[环境与构建](#环境与构建) · [项目结构](#项目结构) · [检查与验证](#检查与验证) · [发布](#发布) · [术语](#术语) · [数据语义](#数据语义)

协作规范见仓库根目录的 [AGENTS.md](../AGENTS.md)，界面设计规则见 [DESIGN.md](DESIGN.md)，站点插件协议见 [SOURCE_API.md](SOURCE_API.md)。

## 环境与构建

Windows 的 `windows/webview_lifecycle.cmake` 将 WebView 共享图形资源的释放移到插件析构阶段，按视图、合成器、D3D、DispatcherQueue、WinRT 的顺序关闭，避免 DLL 卸载期间访问图形驱动。构建只生成一个修正后的翻译单元，不修改 Pub 缓存。依赖升级导致对应源码结构变化时构建明确失败，必须核对释放顺序后更新集成。

Windows/Linux 通过 `lib/video/desktop_video_player.dart` 将共享 `video_player` 控制器接入 `media_kit`；Android 与 Apple 平台使用系统实现。桌面桥先返回可释放的播放器标识，原生创建及打开结果通过事件交付；初始化失败也必须释放控制器。升级媒体依赖时需检查创建失败、切集、重播及关闭中的资源释放。

- 工具链：Flutter 3.47.7（Dart 3.13.5）、JDK 17、Node.js 22。CI 固定这个 Flutter 版本。
- WebView 使用 beta 依赖，用于现有的浏览器桥能力；升级前必须验证 Cookie 分区、验证页和媒体传输。`flutter_tts` 仍使用外部 Kotlin 插件，升级 Flutter 前要核对插件的内置 Kotlin 支持。
- Android、Windows、macOS、Linux 与 iOS 模拟器均由 GitHub Actions 执行构建检查；真实设备和 Linux 发行版运行仍需单独验证。Web 因浏览器文件、Cookie、CORS 与本地媒体安全边界暂不宣称完整支持，详见 [平台矩阵](PLATFORMS.md)。

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
- 应用版本只取 pubspec.yaml。正式发布通过 GitHub Actions 的标签或明确启用的手动发布，Android 分发使用正式证书；日常编译不要求商业签名。
- Android 中正在执行的软件安装包、站点插件、媒体、游戏及词包下载共用数据同步前台服务和 CPU 唤醒锁，切后台和锁屏后继续执行；通知只显示通用下载提示。队列交接保留短暂服务窗口，所有任务结束后自动停止。系统停止服务或 Android 的后台时间额度耗尽时取消正在执行的下载；用户强停、移除应用任务或系统回收进程后不承诺继续，重新打开后按各下载队列已有规则恢复或重试。插件安装保留原有事务恢复机制。
- 作品详情的下载入口在已有下载任务时改为移除操作，覆盖排队、下载中、暂停、失败和已完成状态；确认后停止任务并删除本作品已下载内容，取消保持原样。章节选择里的下载操作仍用于补充下载。
- 官方插件源码与唯一清单均在 `main` 维护。`.github/workflows/publish-sources.yml` 分别发布到 `sources` 和 `rankings` 分支：普通插件进入 `sources`，`rankingOnly: true` 的独立排行榜插件进入 `rankings`。两个分支仅保留固定源码提交地址与摘要的索引，版本检查和用户确认更新流程相同，流程见 SOURCE_API.md 的“发布”。
- 已安装旧版插件的用户在接受官方插件更新之前继续使用旧脚本；插件文案、错误提示等随插件更新生效。应用启动时会提示可用的插件更新，发布说明只在“插件更新”小节列出站点与新版本，不再写更新步骤。
- 官方插件更新最多三个站点并发下载、校验和安装。安装、卸载与恢复内置版本只等待对应站点的操作；其他站点可继续发起请求。同站点的新请求等待自身更新结束。每个站点使用独立的 `source_install_<key>.json` 恢复日志，失败只恢复自身脚本、配置与 Cookie；启动时先恢复未完成事务。全量备份、导入仍使用全局一致性屏障。
- 运行日志（设置 → 关于 → 运行日志）与导出文件是同一份报告：应用版本、是否设置了应用代理、日志涉及的站点插件版本，此前运行的未捕获错误（`logs/crash.log`，JSON 行，读取时重新净化），以及本次运行的事件。事件包括插件调用失败（`event=source`，带方法名）、播放打开失败（`event=playback`）、HLS 分片失败（`event=media`）和未捕获错误（`event=crash`，带代码位置）。字段白名单见 `lib/core/diagnostics.dart`；连续相同的事件合并计数。WebView 控制台输出不记录。
- 发现页各站点的首屏作品在本次应用会话中复用，切换分类、展示站点和滚动不会重新请求。顶部下拉刷新清空全部会话内容，下次可见时重新获取；已加载的横向书架在滚出屏幕后保留。每个分类的展示站点通过标题右侧配置按钮选择，配置随应用设置持久化。

### 发布说明

GitHub Release 正文就是应用内“发现软件新版本”对话框里的更新内容，由 `AppRelease.notesFor`（`lib/engine/app_updater.dart`）解析。格式固定，所有历史版本保持一致：

```markdown
## 中文

### 新功能
- 一条一个用户能感知的变化，一行写完。

### 改进
- …

### 修复
- …

### 插件更新
- MissAV 0.0.5、123AV 0.0.6：详情页显示站点的相关推荐。

### 注意事项
- 只写用户必须知道或自己操作的事项，例如无法覆盖安装、某个操作会以用户账号发帖。

## English

### New
- …

### Improvements
### Fixes
### Plugin updates
### Notes
```

- 正文只有 `## 中文` 和 `## English` 两个二级标题，顺序固定，标题前不写内容。简体中文和繁体中文界面显示 `## 中文`，其他语言显示 `## English`；两节内容一一对应。
- 小节只用上面五个三级标题并按此顺序，没有内容的小节省略。新增站点写在“新功能”；“插件更新”只列已有插件的新版本及其变化，不与其他小节重复。条目以 `- ` 开头、一条一行；不用表格、链接、行内代码、代码块、粗体、分隔线或多级列表，应用按纯文本显示。
- 发布标题统一为 `HentaiPark vX.Y.Z`，不加副标题。
- 只写用户需要关心的内容：功能、体验、修复和需要用户操作的事项。不写实现细节、测试与验证数量、构建号、签名、内部重构、APK 架构选择（见 README 的“下载”）或泛泛的提醒（例如“部分站点可能需要 VPN”）。
- 修改格式时同步 `notesFor`、本节以及 `AGENTS.md` 的发布约束，并按新格式重写全部历史 Release 正文。

### 许可

项目采用 `AGPL-3.0-only`，全文见 [LICENSE](../LICENSE)。发布包内置项目、Telegram 与 EhTagTranslation 的第三方许可，可在“我的 → 关于 → 开源许可证”查看；分发时同时提供对应源码与第三方声明，入口见 [许可目录](licenses/README.md)。

## 术语

界面和文档统一使用以下说法：

| 用语 | 含义 |
| --- | --- |
| 站点 | 一个站点插件及其对应的网站（代码中仍叫 source） |
| 分类 | 发现页的入口分组：本子、美图、里番、JAV、成人视频、短视频、AI 短剧、小说、游戏、其他（代码中的 `category`） |
| 媒体类型 | 漫画 / 视频 / 小说 / 游戏，决定阅读或播放方式（代码中的 `type`、`mediaKind`） |
| 书架 | 界面入口：收藏、更新 |
| 下载 | 独立主导航入口：下载任务与离线内容管理 |
| 书库 | 持久化的收藏、进度与历史数据 |
| 订阅 | 关注频道、创作者或关键词的新内容 |

## 数据语义

- 启动初始化失败时保留原有数据并显示重试和诊断信息入口；重试从失败步骤继续，已完成步骤不会重复注册监听。无法读取文件的访问错误不得当作格式损坏而覆盖原文件。
- JSON 保存失败保留最新内存值，显示持续提示并自动重试；显式刷新仍向调用方返回错误，成功落盘后提示消失。
- 删除下载前持久化待删除范围，文件与数据库均处理成功后才从列表移除；失败保留可重试任务，重启后继续未完成的删除。无法解析或身份不符的下载记录在下载页单独显示，保留原始记录与本地文件，禁止同一作品的新任务覆盖；可重试读取或确认仅移除记录。
- 小说正文方向由首个有方向的文字决定，与界面语言独立；显示、分页测量和滚动定位使用一致方向。

### 备份

- 备份包含书库、进度、标注、订阅目标、全局设置和站点配置；不含离线正文、媒体缓存和 Cookie。站点的 Token 等私有凭据只在用户勾选“站点登录数据”时导出。
- 成年确认只保存在本机，不进入备份。
- 自动备份只在启动和回到前台时检查，不在应用关闭后定时运行。
- 桌面退出先暂停订阅、书库更新、备份和下载，等待已接受的备份快照、写盘及恢复任务完成，再释放页面、源运行时与数据库。暂停后迟到的文件选择结果不得创建新备份任务；可逆准备阶段失败后恢复服务，数据库关闭阶段失败只重试退出。
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

### 跨平台构建与发布

平台功能与安装方法见 [PLATFORMS.md](PLATFORMS.md)。原生目标由 check.yml、build.yml、release.yml 统一检查、构建、打包与发布；Web 按本次产品决定明确未支持，不列入构建及发布目标。普通 PR 不传递发布凭据，发布使用受保护的 release 环境；手动 publish 默认 false。

无付费 Apple 凭据时：macOS ad-hoc 包不公证；iOS 执行无签名真机编译和模拟器打包，不生成普通用户可安装的 IPA。TestFlight/App Store 上传尚未接入。请勿通过关闭系统全局安全保护或 TLS 校验解决安装/网络问题。

## GitHub Actions

工作流使用标准 GitHub 托管运行器：Android/Linux 宿主为 ubuntu-24.04（Linux 在 Debian forky（testing）容器中构建）、Windows 为 windows-2022、Apple 为 macos-15。没有收费大型运行器。Flutter 版本与项目 SDK 对齐，依赖按锁文件解析并缓存。

- check.yml：main 推送、PR、手动触发；仅代码、资源、工具和平台文件变动触发，文档变更不触发。生产文案/样式/分析/格式、官方插件离线校验、动态写入被忽略 test/ 的离线 HLS 用例；按变动范围决定平台矩阵。跨平台生产代码变动构建全部原生目标，单个平台宿主变动只构建对应平台；源脚本和翻译资源单独变动只做检查。
- build.yml：被复用的矩阵构建，包含 Linux 系统依赖、Windows NuGet、Android 无签名编译、macOS app、iOS 无签名真机编译和模拟器 app。macOS 验证主程序含 arm64/x86_64。
- release.yml：推送与 pubspec.yaml 对应的 vX.Y.Z 标签，或在 main 手动触发。手动 publish 默认 false，仅构建；启用 publish 或标签触发才创建 Release。生产检查和全部构建成功后才发布。发布前必须更新 docs/RELEASE_NOTES.md，或手动提供仓库内其他双语说明路径。
- 临时产物位于 Actions 的 distribution-平台 artifacts，保留 7 天。正式附件放 GitHub Release，名称含版本、构建号、平台和架构，并附 SHA-256。Windows 是完整目录 ZIP，Linux 是完整 bundle tar.gz，Apple 是完整 .app ZIP，Android 是分架构签名 APK。
- iOS 只做编译与模拟器打包，不宣称模拟器运行成功。Web 当前没有构建或发布任务。

版本标签必须与 pubspec.yaml 一致；没有更新版本时不要重用已有发布标签。Release 正文只含中文和 English 两节，遵守 DEVELOPMENT.md 既有格式。

## Secrets 与外部设置

为 release 环境配置保护规则、允许的发布分支/标签和必要审批；普通 PR 检查不传递发布 Secrets。构建 job 只有 contents:read，只有最终发布 job 有 contents:write；不可信 PR 不得配置为可进入 release 环境。

| Secrets | 用途 | 缺失时 |
| --- | --- | --- |
| ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD | Android 正式签名 | 仅编译，不上传 APK |
| MACOS_CERTIFICATE_BASE64、MACOS_CERTIFICATE_PASSWORD、MACOS_SIGN_IDENTITY | Developer ID Application p12 与身份名称 | ad-hoc app，无 Developer ID |
| APPLE_NOTARY_KEY_ID、APPLE_NOTARY_ISSUER、APPLE_NOTARY_KEY_BASE64 | Apple 公证 API p8 | 已签名包不公证；没有 Developer ID 时也不调用公证 |

Apple 付费会员不是普通构建前提。没有 iOS 分发凭据的配置项：TestFlight、App Store、真机签名及其上传流程尚未实现，不会显示为成功。Windows 商业签名也未启用，不阻断普通 ZIP 构建。

仓库需允许 Actions、artifact 上传和 GITHUB_TOKEN 创建 Release；Linux runner 需能安装依赖，Windows 需能下载 WebView2/NuGet 和媒体依赖，Apple 需 Xcode/插件所需 CocoaPods 或 SPM 网络访问。依赖下载和构建失败会阻止正式发布。
