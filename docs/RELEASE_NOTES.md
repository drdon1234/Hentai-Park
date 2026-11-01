## 中文

### 改进
- 聚合搜索逐步显示各站关键词联想，并均衡展示不同站点的候选，减少慢站带来的等待。

### 修复
- 修复提交搜索或输入框失去焦点后仍可能出现旧联想的问题，输入空格确认关键词后不再继续替换该词。
- 修复筛选加载与重置冲突时旧条件重新出现的问题；条件恢复完成前暂不可应用筛选。
- 修复切换排序维度后其他下拉框仍显示旧排序的问题。
- 修复超大筛选数值可输入但应用后被拒绝的问题，输入时即可提示无效范围。

### 插件更新
- nhentai 0.0.12、Danbooru 0.0.8、yande.re 0.0.10、Gelbooru 0.0.10：最低应用版本调整为 0.10.5，避免旧版安装无法完整显示分数或收藏数筛选的插件。

## English

### Improvements
- Cross-site search displays keyword suggestions as each site responds and balances candidates across sites, reducing delays caused by slow sites.

### Fixes
- Fixed stale suggestions appearing after submitting a search or leaving the input. A trailing space now confirms the keyword instead of continuing to replace it.
- Fixed old filter conditions reappearing when loading conflicted with a reset. Filters cannot be applied until their conditions have finished restoring.
- Fixed other dropdowns retaining stale sort selections after switching the sorting dimension.
- Fixed oversized filter values being accepted in the input but rejected when applied. Invalid values are now flagged while editing.

### Plugin updates
- nhentai 0.0.12, Danbooru 0.0.8, yande.re 0.0.10 and Gelbooru 0.0.10: require app version 0.10.5 or later so older apps cannot install plugins whose score or favorite count filters they cannot fully display.
