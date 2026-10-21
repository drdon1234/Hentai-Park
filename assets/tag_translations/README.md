# 官方标签翻译包

在应用的词库管理中安装、更新或移除词包。词包只改变标签的显示文字，不改变搜索、屏蔽或保存时的原标签；未收录的标签可使用内容翻译。以下格式与构建说明面向词包维护者。

目录按站点、语言排列：`<source>/<locale>.json`。当前只提供有明确来源或实际审校译文的简体中文包；缺少站点依据的外语模板和只有原文占位的包不分发。所有站点词包均有范围限制，不承诺全站自由标签覆盖。

E-Hentai 名称列来自 [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) 固定提交 `f8dab51172abe1355d16b2d7bbe16a36e1af3470`，提取 44,588 个命名空间名称，许可证为 [CC-BY-NC-SA-3.0-CN](../../docs/licenses/ehtagtranslation.txt)，署名归 EhTagTranslation 全体编辑者。不复制描述、示例图片或 Wiki 内容。nhentai 根据实际命名空间映射，歧义名称不合并。使用第三方译文的词包遵守对应署名、非商业及相同方式共享条款。

其他站点仅收录实际观察到的标签与明确审校的译文。公共概念只与本站观察标签求交，不整份加入各站。明确的作者、演员、厂商与人工标记的专名可保留原名；其余未审校词不以原文占位冒充翻译。OpenCC仅简化中文译文，跳过原名、日语和明确的专名命名空间。

重建流程：`tools/import_tag_translations.mjs --input <上游快照目录> --commit <固定提交>`；采样后 `tools/build_reviewed_tag_packs.mjs --inventory <采样文件> --report <根test目录中的报告文件>`。采样中每站提供`source`、`scope`与`tags`；标签提供原始`name`、`namespace`，人工译文用`reviewed: true`和`translation`明确声明，已确认专名可用`preserve: true`。原始采样与审校报告只保存于根`test/`。再次采样时，只复用实际出现且已有审校记录的译文，不保留未观察到的旧词。需要简化中文译文时用安装有OpenCC的Python执行`tools/normalize_tag_chinese.py`。

运行时从实际 Flutter 资源清单发现内置词包，不按固定八站限制解析或安装；新增内置词包需在 `pubspec.yaml` 声明对应资源目录。官方菜单可检查并发现经过身份、地址、版本与摘要校验的远端索引，按实际站点和语言展示可安装包。没有专用词包的域或站点可开启内容翻译，未命中标签交由机器翻译，原标签保持不变。

格式包含 `schema: 1`、`source`、`locale`、三段 `version` 与 `tags` 映射。键为源站标签，命名空间键写作 `namespace:label`，优先于普通 `label`；查找忽略大小写，但不改变用于搜索、屏蔽或保存的原标签。译文不得为空或使用TODO等占位符。明确保留的同名专名不计作新增译文。每次重新采集时都必须保留原始键，不从已简化的展示值反推原文。

非上游包必须包含`coverage`：`scope`说明目录/样本范围，`complete: false`明确不是全站完整词典；`observed`是去重观察数，`translated`、`preserved`、`unchanged`、`unreviewed`分别表示审校译文、专名原样、审校确认不需改变、未审校条目。只把前两类写入词表，且必须有实际译文才分发。发布器检查计数与词表一致；语义准确性仍需逐项审校，计数不代替质量保证。

修改词包时提高该词包版本。执行 `node tools/publish_tag_translations.mjs` 离线校验。官方工作流向独立 `tag-translations` 分支发布索引，词包地址固定到完整 Git 提交，并附 SHA-256；不修改源插件的 `sources` 分支。

词包随应用附带，首次引导经用户选择后只安装当前站点、当前语言的词包；也可选择下次提醒或永久关闭提醒。设置中可手动安装、更新和移除，原标签与搜索参数不变。远端更新失败保留已安装词表。单包最大 8 MiB、100,000 条，远端下载验证身份、版本和 SHA-256。

## 按站点隔离

发布文件始终是 `<source>/<locale>.json`，每个文件独立版本和 SHA-256；官方索引仅汇总地址与元数据，不包含合并词表。公共审校术语仅为构建输入，各站点产物仍独立，不在运行时查找其他站点词表。

本机安装位于 `AppPaths.data/tag_translations/<sourceIdentity>/<locale>.json`，站点身份使用可逆十六进制编码，避免大小写不敏感文件系统冲突。下载、更新、移除及原子写入只影响目标文件。启动仅扫描安装路径，不解析所有词表；页面可见标签或词库管理明确请求某站点语言时才加载。查词范围严格为站点、语言、命名空间，不存在全站词表回退。

旧 `tag_translations.json` 只进行一次性拆分，全部可迁移内容写入独立文件后将原文件原字节归档为 `.migrated`；失败保留原文件，完成后不双写、不从旧包查词。
