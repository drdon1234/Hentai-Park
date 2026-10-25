# 后台和可见 WPE WebView 共用输入；生成编译副本，不修改共享 Pub 缓存。
set(park_input_target flutter_inappwebview_linux_plugin)
get_target_property(park_input_dir ${park_input_target} SOURCE_DIR)
file(READ "${park_input_dir}/in_app_webview/webview_channel_delegate.cc" park_input_source)
set(park_input_anchor "  // === InAppBrowser-specific methods ===")
string(FIND "${park_input_source}" "${park_input_anchor}" park_input_index)
if(park_input_index LESS 0)
  message(FATAL_ERROR "Linux WebView 控制通道已改变，请更新原生输入集成。")
endif()
string(REPLACE "#include <cstring>" "#include <cstring>\n#include \"browser_input.h\"" park_input_source "${park_input_source}")
string(REPLACE "${park_input_anchor}" [=[
  if (string_equals(methodName, "clickBrowserChallenge")) {
    parkClickBrowserChallenge(webView, method_call, args);
    return;
  }
  // === InAppBrowser-specific methods ===]=] park_input_source "${park_input_source}")
set(park_input_generated "${CMAKE_CURRENT_BINARY_DIR}/browser_input")
file(MAKE_DIRECTORY "${park_input_generated}")
file(WRITE "${park_input_generated}/webview_channel_delegate.cc" "${park_input_source}")
get_target_property(park_input_sources ${park_input_target} SOURCES)
list(REMOVE_ITEM park_input_sources "in_app_webview/webview_channel_delegate.cc")
set_property(TARGET ${park_input_target} PROPERTY SOURCES "${park_input_sources}")
target_include_directories(${park_input_target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${park_input_dir}/in_app_webview")
target_sources(${park_input_target} PRIVATE "${park_input_generated}/webview_channel_delegate.cc")

# Linux 插件的 headless 创建路径还遗漏了 initialUserScripts；必须在首个文档前安装。
file(READ "${park_input_dir}/headless_in_app_webview/headless_in_app_webview_manager.cc" park_headless_source)
set(park_headless_anchor "  // Parse initial settings")
string(FIND "${park_headless_source}" "${park_headless_anchor}" park_headless_index)
if(park_headless_index LESS 0)
  message(FATAL_ERROR "Linux 无头 WebView 创建路径已改变，请更新脚本注入集成。")
endif()
string(REPLACE "${park_headless_anchor}" [=[
  FlValue* scripts = get_fl_map_value_raw(params, "initialUserScripts");
  if (scripts && fl_value_get_type(scripts) == FL_VALUE_TYPE_LIST) {
    for (size_t i = 0; i < fl_value_get_length(scripts); ++i) {
      auto script = fl_value_get_list_value(scripts, i);
      if (fl_value_get_type(script) == FL_VALUE_TYPE_MAP)
        webviewParams.initialUserScripts.push_back(std::make_shared<UserScript>(script));
    }
  }
  // Parse initial settings]=] park_headless_source "${park_headless_source}")
file(WRITE "${park_input_generated}/headless_in_app_webview_manager.cc" "${park_headless_source}")
get_target_property(park_input_sources ${park_input_target} SOURCES)
list(REMOVE_ITEM park_input_sources "headless_in_app_webview/headless_in_app_webview_manager.cc")
set_property(TARGET ${park_input_target} PROPERTY SOURCES "${park_input_sources}")
target_include_directories(${park_input_target} PRIVATE "${park_input_dir}/headless_in_app_webview")
target_sources(${park_input_target} PRIVATE "${park_input_generated}/headless_in_app_webview_manager.cc")
