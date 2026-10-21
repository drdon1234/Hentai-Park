#ifndef HENTAIPARK_WEBVIEW_USER_AGENT_H_
#define HENTAIPARK_WEBVIEW_USER_AGENT_H_

#include <flutter/method_result.h>
#include <memory>
#include <wil/com.h>

#include "utils/string.h"
#include "webview_environment/webview_environment_manager.h"

namespace flutter_inappwebview_plugin {

// Windows 依赖未实现静态接口；从未覆盖标识的临时 WebView 读取真实默认值。
inline void getDefaultWebViewUserAgent(
    const FlutterInappwebviewWindowsPlugin* plugin,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
      std::move(result));
  if (!plugin || !plugin->webViewEnvironmentManager) {
    reply->Error("0", "Cannot obtain the WebViewEnvironment!");
    return;
  }
  plugin->webViewEnvironmentManager->createOrGetDefaultWebViewEnvironment(
      [reply](WebViewEnvironment* environment) {
        if (!environment) {
          reply->Error("0", "Cannot obtain the WebViewEnvironment!");
          return;
        }
        environment->useTempWebView(
            [reply](wil::com_ptr<ICoreWebView2Controller> controller,
                    wil::com_ptr<ICoreWebView2> view) {
              wil::com_ptr<ICoreWebView2Settings> settings;
              wil::com_ptr<ICoreWebView2Settings2> settings2;
              wil::unique_cotaskmem_string agent;
              if (view && SUCCEEDED(view->get_Settings(&settings))) {
                settings2 = settings.try_query<ICoreWebView2Settings2>();
              }
              if (settings2 && SUCCEEDED(settings2->get_UserAgent(&agent)) &&
                  agent && agent.get()[0] != L'\0') {
                reply->Success(flutter::EncodableValue(wide_to_utf8(agent.get())));
              } else {
                reply->Error("0", "Cannot obtain the default WebView user agent!");
              }
              if (controller) controller->Close();
            });
      });
}

}  // namespace flutter_inappwebview_plugin

#endif  // HENTAIPARK_WEBVIEW_USER_AGENT_H_
