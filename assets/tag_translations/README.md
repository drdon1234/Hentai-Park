# 官方标签翻译包

目录按站点、语言排列：`<source>/<locale>.json`，目前 81 个词包、25 个带标签站点的简体中文词包。简体中文优先，其他语言既有常用词包保持独立，不声称完整多语言覆盖。

E-Hentai 名称列来自 [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) 固定提交 `f8dab51172abe1355d16b2d7bbe16a36e1af3470`，提取 44,588 个命名空间名称，许可证为 [CC-BY-NC-SA-3.0-CN](../../docs/licenses/ehtagtranslation.txt)，署名归 EhTagTranslation 全体编辑者。不复制描述、示例图片或 Wiki 内容。nhentai 根据实际命名空间映射，歧义名称不合并。使用第三方译文的词包遵守对应署名、非商业及相同方式共享条款。

其他站点使用审校公共概念及实际请求采样的标签；厂牌、艺名和无法确认的专名保留原名并明确入库，防止自动翻译再次误译。传统字形通过 OpenCC 转简体。需登录或被验证页阻断的站点在词包来源中保留限制记录，不声称覆盖未来全部新增词。

重建流程：`tools/import_tag_translations.mjs --input <上游快照目录> --commit <固定提交>`；采样后 `tools/build_reviewed_tag_packs.mjs --inventory <采样文件>`，再用安装有 OpenCC 的 Python 执行 `tools/normalize_tag_chinese.py`。采样与审校记录只保存于根 `test/`。原始键保留不变，仅展示译文简化。

运行时从实际 Flutter 资源清单发现内置词包，不按固定八站限制解析或安装；新增内置词包需在 `pubspec.yaml` 声明对应资源目录。官方菜单可检查并发现经过身份、地址、版本与摘要校验的远端索引，按实际站点和语言展示可安装包。没有专用词包的域或站点可开启内容翻译，未命中标签交由机器翻译，原标签保持不变。

格式包含 `schema: 1`、`source`、`locale`、三段 `version` 与 `tags` 映射。键为源站标签，命名空间键写作 `namespace:label`，优先于普通 `label`；查找忽略大小写，但不改变用于搜索、屏蔽或保存的原标签。译文不得为空或使用 TODO 等占位符，同名专名可作为有效译文。

修改词包时提高该词包版本。执行 `node tools/publish_tag_translations.mjs` 离线校验。官方工作流向独立 `tag-translations` 分支发布索引，词包地址固定到完整 Git 提交，并附 SHA-256；不修改源插件的 `sources` 分支。

词包随应用附带，首次引导经用户选择后只安装当前站点、当前语言的词包；也可选择下次提醒或永久关闭提醒。设置中可手动安装、更新和移除，原标签与搜索参数不变。远端更新失败保留已安装词表。单包最大 8 MiB、100,000 条，远端下载验证身份、版本和 SHA-256。

## 按站点隔离

发布文件始终是 `<source>/<locale>.json`，每个文件独立版本和 SHA-256；官方索引仅汇总地址与元数据，不包含合并词表。公共审校术语仅为构建输入，各站点产物仍独立，不在运行时查找其他站点词表。

本机安装位于 `AppPaths.data/tag_translations/<sourceIdentity>/<locale>.json`，站点身份使用可逆十六进制编码，避免大小写不敏感文件系统冲突。下载、更新、移除及原子写入只影响目标文件。启动仅扫描安装路径，不解析所有词表；页面可见标签或词库管理明确请求某站点语言时才加载。查词范围严格为站点、语言、命名空间，不存在全站词表回退。

旧 `tag_translations.json` 只进行一次性拆分，全部可迁移内容写入独立文件后将原文件原字节归档为 `.migrated`；失败保留原文件，完成后不双写、不从旧包查词。
