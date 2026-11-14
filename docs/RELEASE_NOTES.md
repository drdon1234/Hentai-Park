## 中文

### 改进
- Android HLS 播放支持更稳定的分片读取、断点续播和媒体窗口加载。
- 改善 HLS 网络异常时的节点切换和播放恢复。
- 停止维护 Windows 客户端，后续版本聚焦 Android，并为 Web 端保留规划空间。

### 修复
- 修复部分 HLS 分片响应异常导致播放失败或卡住的问题。
- 修复媒体转封装和裁剪窗口在部分音视频流上的兼容性问题。

## English

### Improvements
- Improve Android HLS playback with more reliable segment reads, seeking, and media window loading.
- Improve CDN fallback and playback recovery when HLS network requests fail.
- End Windows client maintenance so future releases focus on Android while leaving room for a planned Web client.

### Fixes
- Fixed playback failures or stalls caused by malformed HLS segment responses.
- Fixed compatibility issues with media remuxing and trimmed windows for some audio and video streams.
