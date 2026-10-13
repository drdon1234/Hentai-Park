# 开发说明

当前验证工具链为 Flutter 3.47.7（Dart 3.13.5）、JDK 17 和 Node.js 22。CI 固定此 Flutter 版本。WebView beta 依赖用于现有浏览器桥能力，升级前须验证 Cookie 分区、验证页与媒体传输。生产源维护入口为 `assets/sources/`；Telegram 只编辑 `telegram_entry.mjs` 后构建，不能手改生成脚本。

正式 APK 构建要求 `android/key.properties` 配置 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`；缺少配置即失败，不回退到 debug 签名。仅检查编译时使用 `flutter build apk --release --split-per-abi --android-project-arg=verifyUnsignedBuild=true`，输出无签名 APK，不能安装或作为正式发布包。显式传递参数避免 Windows Dart 将环境变量名转为大写后，Gradle 无法识别大小写敏感的属性名。发布前核对包名、递增 versionCode 与正式证书；CI 不自动发布。

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

想为新站点编写源插件，请参考 [源插件开发指南](SOURCE_API.md)。

以下路径为开发机器示例，不是项目固定路径。Android SDK 目录示例为 `<Android SDK 目录>`。Flutter 的持久化 `android-sdk` 与 `android/local.properties` 的 `sdk.dir` 均应指向包含 `platforms`、`build-tools`、`platform-tools`、`ndk` 的这一层，不能指向外层 `<Android SDK 上级目录>`。在其他机器使用实际 SDK 路径：

```powershell
flutter config --android-sdk '<Android SDK 目录>'
flutter doctor -v
```

Flutter 构建会依据此配置重写本机 `local.properties`，该文件不提交。更换 SDK 后若 Lint 使用旧依赖缓存，重新执行 `:app:lintVitalAnalyzeRelease --rerun`，保留全部检查规则。当前 `flutter_tts` 仍使用外部 Kotlin 插件；本轮构建成功，但升级 Flutter 前需再次核对插件的内置 Kotlin 支持。

备份包含书库、进度、标注、订阅目标、全局设置和源配置；不含离线正文及 Cookie，源私有凭据取决于用户勾选。自动备份只在启动和回到前台时检查，不在应用关闭后定时运行。缺失第三方源的待恢复配置在后续备份中保留，安装相同 key 后应用。

当前正式运行与发布目标为 Android；Windows 是开发宿主，桌面目录不代表全部原生能力已经验证。

项目采用 `AGPL-3.0-only`，全文见 [LICENSE](../LICENSE)。发布包内置项目、Telegram 与 EhTagTranslation 第三方许可，设置中的“开源许可证”可查看；分发时同时提供与构建对应的源码和第三方声明。

界面与文档术语统一使用“源站”表示站点插件、“内容域”表示入口分类、“媒体类型”表示漫画/视频/小说/游戏，“书架”为界面入口，“书库”为持久化集合。手写 Dart 使用 `dart format`，手写 JS 使用两空格、多行函数与单引号；生成文件按生成器格式保留。测试及复现仅保存在被忽略的根 `test/`，不分发或加入 Git。

日常生产检查使用 `tools/check.ps1`，包含八语言键、占位符和可静态确定的 `tr()` 引用检查、Dart 分析与格式检查、官方源离线校验。动态文案键仍需人工审查；离线校验不能替代源的真实请求与设备验证。第三方许可入口见 [许可目录](licenses/README.md)。

章节迁移只复制无歧义的一对一进度；不完整目录不能删减目标章节，有未匹配的原进度时保留原收藏。实时主页结果保留插件字段，磁盘只存显示元数据；只有明确网络或超时错误才能降级为过期缓存。
