# Dart 桥接结果可能晚于视图销毁；回调只在原视图仍存活时访问它。
set(webview_bridge_target flutter_inappwebview_windows_plugin)
get_target_property(webview_bridge_source_dir ${webview_bridge_target} SOURCE_DIR)
file(READ "${webview_bridge_source_dir}/in_app_webview/in_app_webview.cpp" webview_bridge_source)
set(webview_bridge_anchor "          auto callback = std::make_unique<WebViewChannelDelegate::CallJsHandlerCallback>();")
set(webview_bridge_reply "[this, callHandlerID](const std::optional<const flutter::EncodableValue*> response)")
set(webview_bridge_error "[this, callHandlerID](const std::string& error_code, const std::string& error_message, const flutter::EncodableValue* error_details)")
set(webview_bridge_destructor "  InAppWebView::~InAppWebView()\n  {")
foreach(anchor IN ITEMS "${webview_bridge_anchor}" "${webview_bridge_reply}\n            {" "${webview_bridge_error}\n            {" "${webview_bridge_destructor}")
  string(FIND "${webview_bridge_source}" "${anchor}" anchor_at)
  if(anchor_at EQUAL -1)
    message(FATAL_ERROR "WebView 桥接生命周期实现已改变，请核对回调所有权后更新集成。")
  endif()
endforeach()
string(PREPEND webview_bridge_source [=[#include <map>
#include <memory>
namespace flutter_inappwebview_plugin {
  // 所有访问均在平台消息线程。弱引用避免地址复用时旧回调误用新视图。
  static std::map<const InAppWebView*, std::shared_ptr<bool>> bridgeReplyLifetimes;
}
]=])
# 类型需在声明表之前完整声明。
string(PREPEND webview_bridge_source "#include \"in_app_webview.h\"\n")
string(REPLACE "${webview_bridge_anchor}" [=[          const std::weak_ptr<bool> replyLifetime = bridgeReplyLifetimes.try_emplace(this, std::make_shared<bool>(true)).first->second;
          auto callback = std::make_unique<WebViewChannelDelegate::CallJsHandlerCallback>();]=] webview_bridge_source "${webview_bridge_source}")
string(REPLACE "${webview_bridge_reply}\n            {" "[this, callHandlerID, replyLifetime](const std::optional<const flutter::EncodableValue*> response)\n            {\n              if (replyLifetime.expired()) return;" webview_bridge_source "${webview_bridge_source}")
string(REPLACE "${webview_bridge_error}\n            {" "[this, callHandlerID, replyLifetime](const std::string& error_code, const std::string& error_message, const flutter::EncodableValue* error_details)\n            {\n              if (replyLifetime.expired()) return;" webview_bridge_source "${webview_bridge_source}")
string(REPLACE "${webview_bridge_destructor}" "${webview_bridge_destructor}\n    bridgeReplyLifetimes.erase(this);" webview_bridge_source "${webview_bridge_source}")
set(webview_bridge_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/webview_bridge")
file(MAKE_DIRECTORY "${webview_bridge_generated_dir}")
file(WRITE "${webview_bridge_generated_dir}/in_app_webview.cpp" "${webview_bridge_source}")
target_include_directories(${webview_bridge_target} PRIVATE "${webview_bridge_source_dir}/in_app_webview")
get_target_property(webview_bridge_sources ${webview_bridge_target} SOURCES)
list(REMOVE_ITEM webview_bridge_sources "in_app_webview/in_app_webview.cpp")
set_property(TARGET ${webview_bridge_target} PROPERTY SOURCES "${webview_bridge_sources}")
target_sources(${webview_bridge_target} PRIVATE "${webview_bridge_generated_dir}/in_app_webview.cpp")
