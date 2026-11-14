## 中文

### 改进
- 优化酒馆角色卡和世界书详情页操作布局，收藏保留在主操作区，保存与原文件导出移至更多菜单。
- 世界书改用独立的分段浏览页面，大型世界书按需加载词条，减少详情页展开和滚动时的卡顿。
- 酒馆详情、会话标题、世界书内容和已保存资源接入公共翻译能力。
- Character Tavern 支持完整分页、排序、标签包含与排除、令牌长度、世界书和原创内容筛选。
- 酒馆书库提供角色卡、世界书、会话与备份的分开导入入口，并校验导入类型。

### 插件更新
- 新增 RisuRealm 源 0.0.1，支持角色卡与世界书搜索、详情和访客下载。
- 更新 Chub AI 源至 0.0.3，补充酒馆入口与筛选文案翻译。
- 更新 Character Tavern 源至 0.0.3，支持分页、官方筛选和多语言文案。

### 注意事项
- 酒馆需自行配置 AI 服务；消息、角色设定、用户人格及匹配的世界书内容会发送至所选服务，可能产生费用。
- 会话导出与书库备份未加密，应妥善保管；AI 服务配置和密钥不包含在备份中。

## English

### Improvements
- Refined Tavern character and lorebook detail actions: favorites stay in the primary action area, while local save and original-file export move into More.
- Moved lorebook entries to a separate segmented viewer that loads large books on demand, reducing detail-page layout and scrolling jank.
- Added shared translation support to Tavern details, conversation titles, lorebook content, and saved resources.
- Added full Character Tavern pagination, sorting, included and excluded tags, token-length, lorebook, and original-content filters.
- Added separate import entry points for character cards, lorebooks, conversations, and backups with type validation.

### Plugin updates
- Added the RisuRealm source 0.0.1 with character and lorebook search, details, and guest downloads.
- Updated Chub AI to 0.0.3 with translated Tavern entry and filter labels.
- Updated Character Tavern to 0.0.3 with pagination, official filters, and multilingual labels.

### Notes
- Tavern requires your own AI service. Messages, character settings, user personas, and matched lorebook content are sent to that service and may incur charges.
- Conversation exports and library backups are unencrypted and should be stored safely. AI service settings and keys are excluded from backups.
