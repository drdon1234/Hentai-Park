## 中文

### 新功能
- 首页新增图片、视频、其他筛选，可与二次元、三次元筛选组合使用；从首页进入搜索时只选中筛选后分类里的已启用站点。
- 下载页新增“导出文件”，可查看后台导出进度，分享或删除已导出的文件。
- 排行榜的原站商品页可在应用内打开。

### 改进
- PDF 与 CBZ 导出改为后台进行，切换页面或切到后台不会中断。
- 导出 PDF 可设置每个文件的最多页数，图集过长或文件过大时自动分成多个文件，减少导出失败。
- 视频播放会保留已播放部分，往回拖动不再重新加载。
- 从搜索结果或站点列表打开短视频时按列表顺序连续播放并继续加载后续结果，不再切换为随机推荐。
- 短视频预加载数量上限提高到 20 个。
- 只有一张图片的作品在详情页直接显示，点击即可全屏查看。
- 进入站点页时先显示加载状态，不再误显示“这里什么都没有”。
- 站点更换图片或视频服务器地址后，封面和播放会自动适应，首选线路不可用时自动切换到其他线路。

### 修复
- 修复窄屏内嵌播放器的中央播放、暂停按钮无法点击的问题。
- 修复切换界面语言时页面刷新异常的问题，保留当前页面和操作状态。
- 修复 Reddit 网页登录后无法识别登录状态、登录页一直不关闭的问题。
- 修复 Fansly 已登录时，需订阅或购买的视频仍提示“请先登录”的问题。
- 修复 KoreanBJ.club 录播部分视频无法播放的问题。
- 修复 Stripchat 亚洲直播封面无法显示、部分直播间无法打开的问题。
- 修复部分站点的 Cloudflare 验证页未被识别，一直等待后提示响应超时的问题。
- 站点防火墙拒绝当前网络时直接提示更换网络或代理，不再长时间等待验证。

### 插件更新
- Reddit 0.0.7：修复网页登录识别。
- Fansly 0.0.12：区分需要登录与需要订阅的视频，推荐中不再出现无法观看的付费视频。
- KoreanBJ.club 录播 0.0.5：适配新的播放页面与视频服务器。
- Stripchat 亚洲直播 0.0.6：修复封面显示与直播间打开，使用原站当前的播放线路并在不可用时切换备用线路。
- SupJav 0.0.11：修复所有视频提示没有可用线路、无法播放的问题，支持原站当前的多条播放线路，首选线路不可用时自动切换；分段影片可按 CD 选集播放。
- 次元茶馆 0.0.10：改进游戏帖子识别与搜索结果。
- FANZA 0.0.4、FC2 0.0.5、MGStage 0.0.4、无码厂商 0.0.5：排行榜名称与选项支持多语言。
- 123AV 0.0.12、CAM4 0.0.6、CamwhoresBay 亚洲录播 0.0.5、Eporner 0.0.8、Fyptt 0.0.7、Hanime.tv 0.0.9、Hanime1 0.0.10、HentaiHaven 0.0.4、黄果短剧 0.0.11、iXXX 0.0.16、JableTV 0.0.9、PopkonTV 录播 0.0.3、PopkonTV 短视频 0.0.3、91porn 0.0.9、PornPics 0.0.9、肉视频 0.0.3、肉视频短剧 0.0.3、Rule34Video 0.0.9、SinParty 0.0.6、SOOP 0.0.5、SOOP 录播 0.0.5、SOOP 短视频 0.0.5、SpankBang 0.0.10、SWAG 短视频 0.0.5、Thumbzilla 0.0.9、Tik.porn 0.0.8、TubeSafari 0.0.9、XloveCam 0.0.6、PixiBB、XiuRen、CosplayTele、NudeCosplay 0.0.6：站点更换图片或视频服务器后仍可正常显示和播放，缺少封面的作品不再被隐藏。

## English

### New
- Home adds Images, Videos and Other filters that combine with the 2D and 3D filters; searching from Home only selects the enabled sites in the filtered categories.
- The Downloads page adds Exported files, where you can follow background exports and share or delete exported files.
- Ranking product pages can be opened inside the app.

### Improvements
- PDF and CBZ exports run in the background and continue when you leave the page or switch apps.
- PDF export lets you set a maximum number of pages per file; long galleries or very large files are split into several files to avoid failed exports.
- Video playback keeps the part already played, so seeking back no longer reloads it.
- Short videos opened from search results or a site list play in list order and keep loading further results instead of switching to random recommendations.
- The short-video preload limit is raised to 20.
- Works with a single image show it directly on the details page; tap to view full screen.
- Site pages show a loading state first instead of briefly showing Nothing here.
- Covers and playback adapt when a site moves its image or video servers, and playback switches to another line when the preferred one is unavailable.

### Fixes
- Fix the central play and pause button not responding in narrow embedded players.
- Fix page refresh errors when switching the interface language while preserving the current page and its state.
- Fix Reddit web sign-in not being recognized and the sign-in page never closing.
- Fix Fansly asking you to sign in for subscription or purchase-only videos while already signed in.
- Fix some KoreanBJ.club recordings failing to play.
- Fix Stripchat Asian Live covers not showing and some rooms failing to open.
- Fix Cloudflare checks on some sites not being recognized and ending in a timeout.
- When a site's firewall refuses your current network, the app now says so right away and suggests switching networks or using a proxy instead of waiting for a check.

### Plugin updates
- Reddit 0.0.7: fixes web sign-in recognition.
- Fansly 0.0.12: separates videos that need sign-in from those that need a subscription, and recommendations no longer include paid videos you can't watch.
- KoreanBJ.club Recordings 0.0.5: supports the new player pages and video servers.
- Stripchat Asian Live 0.0.6: fixes covers and opening rooms, uses the site's current streaming line and switches to a backup line when needed.
- SupJav 0.0.11: fixes every video reporting that no server is available, supports the site's current playback servers and switches automatically when the preferred one fails; multi-part videos can be played by CD.
- 次元茶馆 0.0.10: improves game post detection and search results.
- FANZA 0.0.4, FC2 0.0.5, MGStage 0.0.4 and 无码厂商 0.0.5: ranking names and options are translated.
- 123AV 0.0.12, CAM4 0.0.6, CamwhoresBay Asian Recordings 0.0.5, Eporner 0.0.8, Fyptt 0.0.7, Hanime.tv 0.0.9, Hanime1 0.0.10, HentaiHaven 0.0.4, 黄果短剧 0.0.11, iXXX 0.0.16, JableTV 0.0.9, PopkonTV Recordings 0.0.3, PopkonTV Shorts 0.0.3, 91porn 0.0.9, PornPics 0.0.9, 肉视频 0.0.3, 肉视频短剧 0.0.3, Rule34Video 0.0.9, SinParty 0.0.6, SOOP 0.0.5, SOOP Recordings 0.0.5, SOOP Shorts 0.0.5, SpankBang 0.0.10, SWAG Shorts 0.0.5, Thumbzilla 0.0.9, Tik.porn 0.0.8, TubeSafari 0.0.9, XloveCam 0.0.6, PixiBB, XiuRen, CosplayTele and NudeCosplay 0.0.6: images and videos keep working when a site moves its servers, and works without a cover are no longer hidden.
