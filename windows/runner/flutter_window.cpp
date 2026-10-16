#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  // window_manager can quit the message loop without destroying the HWND.
  // Tear down while virtual dispatch and members are still alive; resetting the
  // controller in OnDestroy also clears it before engine shutdown re-enters WndProc.
  Destroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  tray_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "hentai_park/tray",
      &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "isReady") {
          result->Success(flutter::EncodableValue(tray_ready_));
          return;
        }
        if (call.method_name() == "hide") {
          if (tray_ready_) ShowWindow(GetHandle(), SW_HIDE);
          result->Success(flutter::EncodableValue(tray_ready_));
          return;
        }
        const auto* labels = call.arguments()
            ? std::get_if<flutter::EncodableList>(call.arguments()) : nullptr;
        if (call.method_name() != "setLabels" || !labels || labels->size() != 2 ||
            !std::holds_alternative<std::string>((*labels)[0]) ||
            !std::holds_alternative<std::string>((*labels)[1])) {
          result->NotImplemented();
          return;
        }
        auto wide = [](const std::string& text) {
          const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                              static_cast<int>(text.size()), nullptr, 0);
          std::wstring output(size, L'\0');
          MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                              output.data(), size);
          return output;
        };
        restore_label_ = wide(std::get<std::string>((*labels)[0]));
        exit_label_ = wide(std::get<std::string>((*labels)[1]));
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  tray_icon_.cbSize = sizeof(tray_icon_);
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_.uCallbackMessage = WM_APP + 1;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"HentaiPark");
  tray_ready_ = tray_icon_.hIcon != nullptr && Shell_NotifyIconW(NIM_ADD, &tray_icon_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (tray_channel_) {
    tray_channel_->SetMethodCallHandler(nullptr);
    tray_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_ready_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_ready_ = false;
  }
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, 1, restore_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 2, exit_label_.c_str());
  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const auto command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                                      point.x, point.y, 0, GetHandle(), nullptr);
  if (command == 1) RestoreFromTray();
  if (command == 2 && tray_channel_) {
    tray_channel_->InvokeMethod("exit", nullptr);
  }
  DestroyMenu(menu);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

void FlutterWindow::RestoreFromTray() {
  ShowWindow(GetHandle(), IsIconic(GetHandle()) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(GetHandle());
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    // Explorer 重启会移除托盘图标；无法重建时恢复窗口，保留操作入口。
    tray_ready_ = tray_icon_.hIcon != nullptr &&
                  Shell_NotifyIconW(NIM_ADD, &tray_icon_);
    if (!tray_ready_) RestoreFromTray();
    return 0;
  }
  if (message == WM_APP + 1 && tray_ready_) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) RestoreFromTray();
    if (lparam == WM_RBUTTONUP) ShowTrayMenu();
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
