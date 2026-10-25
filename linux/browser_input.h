#pragma once
#include <cmath>
#include <memory>
#include <nlohmann/json.hpp>
#include "in_app_webview.h"

namespace flutter_inappwebview_plugin {
#ifdef HAVE_WPE_PLATFORM
// 每次操作持有指定 WebView，不使用系统输入；导航、超时或遮挡均拒绝输入。
class ParkBrowserInput {
 public:
  ParkBrowserInput(WebKitWebView* view, FlMethodCall* call, std::string url, std::string token)
      : view_(WEBKIT_WEB_VIEW(g_object_ref(view))),
        call_(FL_METHOD_CALL(g_object_ref(call))), url_(std::move(url)),
        token_(std::move(token)), started_(g_get_monotonic_time()) {
    navigation_ = g_signal_connect(view_, "load-changed", G_CALLBACK(+[](
        WebKitWebView*, WebKitLoadEvent event, gpointer data) {
      if (event == WEBKIT_LOAD_STARTED)
        static_cast<ParkBrowserInput*>(data)->navigated_ = true;
    }), this);
  }
  ~ParkBrowserInput() {
    g_signal_handler_disconnect(view_, navigation_);
    g_object_unref(call_);
    g_object_unref(view_);
  }
  void evaluate() {
    const auto script = "window.__parkChallengeInput?.snapshot('" + token_ +
        (hovered_ ? "', true) ?? null" : "', false) ?? null");
    webkit_web_view_evaluate_javascript(view_, script.c_str(), -1, nullptr,
        nullptr, nullptr, evaluated, this);
  }

 private:
  bool point(const nlohmann::json& obj, double& x, double& y) const {
    if (!obj.is_object() || navigated_ ||
        g_get_monotonic_time() - started_ > 1500000 ||
        g_strcmp0(webkit_web_view_get_uri(view_), url_.c_str()) != 0 ||
        std::abs(webkit_web_view_get_zoom_level(view_) - 1.0) > 0.001) return false;
    auto str = [&obj](const char* key) -> std::string {
      return obj.contains(key) && obj[key].is_string() ? obj[key].get<std::string>() : "";
    };
    auto num = [&obj](const char* key) -> double {
      return obj.contains(key) && obj[key].is_number() ? obj[key].get<double>() : NAN;
    };
    x = num("x"); y = num("y");
    auto width = num("width"), height = num("height");
    g_autoptr(GUri) frame = g_uri_parse(str("frame").c_str(), G_URI_FLAGS_NONE, nullptr);
    return str("url") == url_ && str("token") == token_ && frame &&
        g_strcmp0(g_uri_get_scheme(frame), "https") == 0 &&
        g_strcmp0(g_uri_get_host(frame), "challenges.cloudflare.com") == 0 &&
        !g_uri_get_userinfo(frame) && (g_uri_get_port(frame) == -1 || g_uri_get_port(frame) == 443) &&
        std::isfinite(x) && std::isfinite(y) && std::isfinite(width) && std::isfinite(height) &&
        x > 0 && y > 0 && x < width && y < height;
  }
  static void evaluated(GObject* source, GAsyncResult* result, gpointer data) {
    std::unique_ptr<ParkBrowserInput> self(static_cast<ParkBrowserInput*>(data));
    g_autoptr(GError) error = nullptr;
    g_autoptr(JSCValue) value = webkit_web_view_evaluate_javascript_finish(
        WEBKIT_WEB_VIEW(source), result, &error);
    g_autofree gchar* raw = value ? jsc_value_to_json(value, 0) : nullptr;
    const auto parsed = raw ? nlohmann::json::parse(raw, nullptr, false) : nlohmann::json();
    double x, y;
    auto input = webkit_web_view_get_wpe_view(self->view_);
    if (!error && input && self->point(parsed, x, y)) {
      auto time = static_cast<guint32>(g_get_monotonic_time() / 1000);
      if (!self->hovered_) {
        self->x_ = x; self->y_ = y; self->hovered_ = true;
        auto move = wpe_event_pointer_move_new(WPE_EVENT_POINTER_MOVE, input,
            WPE_INPUT_SOURCE_MOUSE, time, static_cast<WPEModifiers>(0), x, y, 0, 0);
        wpe_view_event(input, move); wpe_event_unref(move);
        // 等待真实 hover 事件处理后重新命中检查，不能点到随后出现的覆盖层。
        g_timeout_add(50, +[](gpointer data) -> gboolean {
          static_cast<ParkBrowserInput*>(data)->evaluate();
          return G_SOURCE_REMOVE;
        }, self.release());
        return;
      }
      if (std::abs(self->x_ - x) < 0.5 && std::abs(self->y_ - y) < 0.5) {
        for (bool down : {true, false}) {
          auto event = wpe_event_pointer_button_new(down ? WPE_EVENT_POINTER_DOWN : WPE_EVENT_POINTER_UP,
              input, WPE_INPUT_SOURCE_MOUSE, time, static_cast<WPEModifiers>(down ? 1 << 8 : 0),
              1, x, y, down ? 1 : 0);
          wpe_view_event(input, event); wpe_event_unref(event);
        }
        fl_method_call_respond_success(self->call_, fl_value_new_bool(true), nullptr);
        return;
      }
    }
    fl_method_call_respond_success(self->call_, fl_value_new_bool(false), nullptr);
  }
  WebKitWebView* view_;
  FlMethodCall* call_;
  std::string url_, token_;
  gint64 started_;
  gulong navigation_;
  bool navigated_ = false, hovered_ = false;
  double x_ = 0, y_ = 0;
};
#endif

inline void parkClickBrowserChallenge(InAppWebView* view, FlMethodCall* call, FlValue* args) {
  auto text = [args](const char* key) -> std::string {
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return {};
    auto value = fl_value_lookup_string(args, key);
    return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
  };
  auto url = text("url"), token = text("token");
#ifdef HAVE_WPE_PLATFORM
  if (view && url.rfind("https://", 0) == 0 && !token.empty() && token.size() <= 160 &&
      token.find_first_not_of("0123456789-") == std::string::npos && view->getUrl() == url) {
    (new ParkBrowserInput(WEBKIT_WEB_VIEW(view->webview()), call, url, token))->evaluate();
    return;
  }
#endif
  fl_method_call_respond_success(call, fl_value_new_bool(false), nullptr);
}
}
