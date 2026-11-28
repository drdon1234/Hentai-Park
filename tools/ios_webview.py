"""在 CocoaPods 构建副本中接入作品隔离，绝不改写 Pub 缓存。"""

from pathlib import Path
import sys


def replace_once(source, anchor, replacement):
    if source.count(anchor) != 1:
        raise ValueError('WebView 依赖结构已变更，请重新核对 iOS 存储绑定时序')
    return source.replace(anchor, replacement, 1)


def patch(name, source):
    source = source.replace('\r\n', '\n')
    if 'parkGameIdentifier' in source or '"parkGameProfile"' in source:
        raise ValueError('必须从原始 WebView 依赖生成构建副本，禁止重复适配')
    if name == 'InAppWebView.swift':
        source = replace_once(source, '        super.init(frame: frame, configuration: configuration)', '''        if #available(iOS 17.0, *),
           let identifier = InAppWebView.parkGameIdentifier(userScripts) {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        }
        super.init(frame: frame, configuration: configuration)''')
        source = replace_once(source, '    var initialUserScripts: [UserScript] = []', '''    var initialUserScripts: [UserScript] = []

    static func parkGameIdentifier(_ scripts: [UserScript]) -> UUID? {
        guard let group = scripts.compactMap({ $0.groupName }).first(where: { $0.hasPrefix("park_game_") }) else { return nil }
        let key = String(group.dropFirst("park_game_".count))
        guard key.count == 64, key.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        // 使用摘要前 128 位构造稳定的 WKWebsiteDataStore 标识。
        let chars = Array(key.prefix(32))
        let ranges = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        return UUID(uuidString: ranges.map { String(chars[$0]) }.joined(separator: "-"))
    }

    var parkGameDataStore: WKWebsiteDataStore? {
        if #available(iOS 17.0, *), let identifier = Self.parkGameIdentifier(initialUserScripts) {
            return WKWebsiteDataStore(forIdentifier: identifier)
        }
        return nil
    }''')
        # 全屏检测按 WebView 所在场景的尺寸比较；分屏、可折叠设备上场景小于整块屏幕。
        source = replace_once(source, '        let screenBounds = UIScreen.main.bounds',
                              '        let screenBounds = myWindow.windowScene?.coordinateSpace.bounds ?? myWindow.bounds')
        # 静态预配置仍按插件默认规则；实例构造在 super.init 前绑定作品。
        # 后续 setSettings 不能将已隔离的游戏切回全局存储。
        start = source.index('    public static func preWKWebViewConfiguration(')
        end = source.index('        return configuration\n    }', start) + len('        return configuration\n    }')
        before, static, after = source[:start], source[start:end], source[end:]
        for factory in ['WKWebsiteDataStore.default()', 'WKWebsiteDataStore.nonPersistent()']:
            anchor = 'configuration.websiteDataStore = ' + factory
            if anchor not in after:
                raise ValueError('WebView 存储配置已变更')
            after = after.replace(anchor, 'configuration.websiteDataStore = parkGameDataStore ?? ' + factory)
        return before + static + after
    if name == 'WebViewChannelDelegate.swift':
        return replace_once(source, '        let arguments = call.arguments as? NSDictionary', '''        let arguments = call.arguments as? NSDictionary
        if call.method == "parkPrivateVideo" {
            result(webView?.configuration.websiteDataStore.isPersistent == false)
            return
        }
        if call.method == "parkGameProfile" {
            if #available(iOS 17.0, *), let view = webView,
               let expected = InAppWebView.parkGameIdentifier(view.initialUserScripts) {
                result(view.configuration.websiteDataStore.identifier == expected)
            } else { result(false) }
            return
        }''')
    raise ValueError('未知 WebView 文件')


if __name__ == '__main__':
    original, destination = map(Path, sys.argv[1:])
    text = patch(original.name, original.read_text(encoding='utf-8'))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding='utf-8', newline='\n')
