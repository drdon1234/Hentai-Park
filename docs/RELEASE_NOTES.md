## 中文

### 修复
- 修复部分站点退出登录后仍保留登录状态、刷新后重新显示已登录的问题。
- 修复退出登录依赖原站联网验证，导致网络异常或网页验证时无法正常完成退出的问题。
- 修复后台浏览器验证过早停止重试，导致次元茶馆等站点登录或内容读取失败的问题。

## English

### Fixes
- Fixed some sites retaining their login session after signing out and showing the account as signed in again after refreshing.
- Fixed sign-out depending on an online account check, which could prevent completion during network failures or browser verification.
- Fixed background browser verification stopping retries too early, causing sign-in or content loading to fail on Cycg and other sites.
