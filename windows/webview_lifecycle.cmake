# WebView 图形资源必须在插件销毁时释放，不能留到 DllMain/loader lock 中。
# 只替换构建目录中的一个翻译单元，不修改共享 Pub 缓存。
set(webview_target flutter_inappwebview_windows_plugin)
get_target_property(webview_source_dir ${webview_target} SOURCE_DIR)
set(webview_manager_source "${webview_source_dir}/in_app_webview/in_app_webview_manager.cpp")
file(READ "${webview_manager_source}" webview_manager)
string(PREPEND webview_manager "#include <winrt/Windows.System.h>\n")
set(webview_release_anchor "    windowWebViews.clear();")
string(CONCAT webview_extra_reference
  "        if (compositor_) {\n"
  "          // fix for KernelBase.dll RaiseFailFastException\n"
  "          // when app is closing \n"
  "          compositor_->AddRef();\n"
  "        }\n")
string(FIND "${webview_manager}" "${webview_release_anchor}" webview_release_at)
string(FIND "${webview_manager}" "${webview_extra_reference}" webview_reference_at)
if(webview_release_at EQUAL -1 OR webview_reference_at EQUAL -1)
  message(FATAL_ERROR "WebView 资源生命周期实现已改变，请核对正常析构后更新集成。")
endif()
string(REPLACE "${webview_extra_reference}" "" webview_manager "${webview_manager}")
string(REPLACE "${webview_release_anchor}" [=[    windowWebViews.clear();
    // 所有视图已销毁；在 COM 和主线程消息循环仍有效时关闭共享图形资源。
    valid_ = false;
    if (compositor_) {
      auto closable = compositor_.try_as<ABI::Windows::Foundation::IClosable>();
      if (closable) closable->Close();
      compositor_ = nullptr;
    }
    graphics_context_.reset();
    if (dispatcher_queue_controller_) {
      auto controller = dispatcher_queue_controller_.as<winrt::Windows::System::DispatcherQueueController>();
      auto shutdown = controller.ShutdownQueueAsync();
      while (shutdown.Status() == winrt::Windows::Foundation::AsyncStatus::Started) {
        MSG message;
        while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
          if (message.message == WM_QUIT) continue;
          TranslateMessage(&message);
          DispatchMessage(&message);
        }
        MsgWaitForMultipleObjectsEx(0, nullptr, 10, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
      }
      dispatcher_queue_controller_ = nullptr;
    }
    rohelper_.reset();]=] webview_manager "${webview_manager}")
set(webview_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/webview_lifecycle/in_app_webview")
file(MAKE_DIRECTORY "${webview_generated_dir}")
file(WRITE "${webview_generated_dir}/in_app_webview_manager.cpp" "${webview_manager}")
# 原文件包含相对路径；第二搜索根保持其 ../ 类型引用指向插件原目录。
target_include_directories(${webview_target} PRIVATE
  "${webview_source_dir}/in_app_webview")
get_target_property(webview_sources ${webview_target} SOURCES)
list(REMOVE_ITEM webview_sources "in_app_webview/in_app_webview_manager.cpp")
set_property(TARGET ${webview_target} PROPERTY SOURCES "${webview_sources}")
target_sources(${webview_target} PRIVATE "${webview_generated_dir}/in_app_webview_manager.cpp")
