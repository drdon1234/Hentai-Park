## 中文

### 改进
- 主页和域页的小说采用竖版书本卡片，支持横向滑动浏览。
- 减少自动翻译完成后重复构建时的计算和刷新。
- 频道与作者搜索保留原站搜索结果，并改进加载失败时的提示。

### 修复
- 修复漫画上下集跳转时继承当前章节页码，以及旧章节延迟回调干扰新章节的问题。
- 修复视频开头和接近结尾的未完成进度无法准确恢复的问题。
- 修复已加入频道和已关注作者页面顶部内容被遮挡的问题。
- 修复 E-Hentai 热门和排行榜筛选后离开原栏目范围的问题。

### 插件更新
- E-Hentai 0.0.19：热门和排行榜支持在原栏目内筛选。
- Reddit 0.0.16：指定社区改用网页加载帖子，支持图片、视频、纯文本和分页，订阅社区不再自动执行原站加入操作。
- X 0.0.25：修正搜索请求方式，改进账号状态检查及频道、作者搜索结果处理。

## English

### Improvements
- Novels on the home and domain pages use portrait book cards with horizontal scrolling.
- Reduced repeated computation and refreshes when rebuilding completed automatic translations.
- Channel and author searches preserve results returned by the site and provide clearer loading errors.

### Fixes
- Fixed chapter navigation inheriting the current comic chapter's page and delayed callbacks affecting the next chapter.
- Fixed unfinished video progress near the beginning or end failing to resume accurately.
- Fixed content being obscured at the top of joined-channel and followed-author pages.
- Fixed E-Hentai popular and ranking filters switching away from the selected feed.

### Plugin updates
- E-Hentai 0.0.19: filter popular and ranking results within their original feeds.
- Reddit 0.0.16: load community posts from webpages with images, videos, text and pagination; saving a community subscription no longer automatically joins it on Reddit.
- X 0.0.25: corrected search requests and improved account checks and channel and author search result handling.
