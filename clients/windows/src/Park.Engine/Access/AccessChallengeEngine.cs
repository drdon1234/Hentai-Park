using System.Drawing;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Park.Core.Configuration;

namespace Park.Engine.Access;

public sealed record AgeGateRule(
    string Selector,
    string ReadySelector,
    IReadOnlyList<string> RequiredCookies,
    string? ClickSelector,
    string? CheckSelector,
    string? DateSelector);

/// <summary>
/// Headless browser interaction engine aligned with AGENTS.md, DEVELOPMENT.md, and BrowserChallengeInput.kt:
/// - Declarative age gate confirmation (fixed 1999-12-31 birth date only when AdultConfirmed == true & single form)
/// - Trusted Turnstile challenge verification via offscreen CoreWebView2CompositionController.SendMouseInput
///   (max 3 attempts per document, >= 8s interval, per-document one-time token, never hijacks OS cursor or opens debug ports)
/// </summary>
public static class AccessChallengeEngine
{
    public const string FixedAdultBirthDate = "1999-12-31";

    public static AgeGateRule? ParseConfirmation(JsonObject? networkNode)
    {
        if (networkNode?["confirmation"] is not JsonObject conf) return null;
        var selector = conf["selector"]?.GetValue<string>() ?? string.Empty;
        var ready = conf["readySelector"]?.GetValue<string>() ?? string.Empty;
        if (string.IsNullOrEmpty(selector) || string.IsNullOrEmpty(ready)) return null;

        var reqCookies = new List<string>();
        if (conf["requiredCookies"] is JsonArray rc)
        {
            foreach (var c in rc)
                if (c is JsonValue v && v.TryGetValue<string>(out var s) && !string.IsNullOrEmpty(s))
                    reqCookies.Add(s);
        }

        var auto = conf["auto"] as JsonObject;
        var click = auto?["clickSelector"]?.GetValue<string>();
        var check = auto?["checkSelector"]?.GetValue<string>();
        var birth = auto?["birthDate"] as JsonObject;
        var dateSel = birth?["dateSelector"]?.GetValue<string>();
        return new AgeGateRule(selector, ready, reqCookies, click, check, dateSel);
    }

    public static async Task<bool> TryHandleAgeGateAsync(
        CoreWebView2 webView,
        AgeGateRule rule,
        CancellationToken ct)
    {
        if (!AppSettings.Instance.AdultConfirmed) return false;

        var payload = JsonSerializer.Serialize(new
        {
            selector = rule.Selector,
            readySelector = rule.ReadySelector,
            clickSelector = rule.ClickSelector,
            checkSelector = rule.CheckSelector,
            dateSelector = rule.DateSelector,
            birthDate = FixedAdultBirthDate,
        });

        var script = $$"""
            (() => {
              const cfg = {{payload}};
              if (document.querySelector(cfg.readySelector) && !document.querySelector(cfg.selector)) {
                return 'ready';
              }
              const gate = document.querySelector(cfg.selector);
              if (!gate) return 'absent';
              if (cfg.checkSelector) {
                const checks = gate.querySelectorAll(cfg.checkSelector);
                if (checks.length === 1 && !checks[0].checked) checks[0].click();
              }
              if (cfg.dateSelector) {
                const dates = gate.querySelectorAll(cfg.dateSelector);
                if (dates.length !== 1) return 'ambiguous';
                const el = dates[0];
                el.value = cfg.birthDate;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              }
              if (cfg.clickSelector) {
                const btns = gate.querySelectorAll(cfg.clickSelector);
                if (btns.length !== 1) return 'ambiguous';
                btns[0].click();
                return 'clicked';
              }
              return 'noop';
            })()
            """;

        var resultRaw = await webView.ExecuteScriptAsync(script).WaitAsync(ct);
        var state = JsonSerializer.Deserialize<string>(resultRaw);
        if (state == "ready") return true;
        if (state != "clicked") return false;

        for (var i = 0; i < 12; i++)
        {
            await Task.Delay(500, ct);
            var verifyRaw = await webView.ExecuteScriptAsync(
                $"Boolean(document.querySelector({JsonSerializer.Serialize(rule.ReadySelector)}) && !document.querySelector({JsonSerializer.Serialize(rule.Selector)}))").WaitAsync(ct);
            if (verifyRaw == "true") return true;
        }
        return false;
    }

    public static async Task<bool> TrySolveTurnstileOffscreenAsync(
        CoreWebView2CompositionController compositionController,
        string expectedUrl,
        int viewportWidth,
        int viewportHeight,
        CancellationToken ct)
    {
        var webView = compositionController.CoreWebView2;

        // Maximum 3 attempts on the same document, spaced at least 8 seconds apart per DEVELOPMENT.md
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (attempt > 0)
            {
                await Task.Delay(TimeSpan.FromSeconds(8.2), ct);
            }

            if (!string.Equals(webView.Source, expectedUrl, StringComparison.Ordinal))
                return true; // Navigated past challenge page

            var oneTimeToken = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(20));
            var snapshotScript = $$"""
                (() => {
                  const token = {{JsonSerializer.Serialize(oneTimeToken)}};
                  const frames = [...document.querySelectorAll('iframe[src^="https://challenges.cloudflare.com/"]')];
                  if (frames.length !== 1) return null;
                  const rect = frames[0].getBoundingClientRect();
                  if (rect.width < 40 || rect.height < 24) return null;
                  const x = rect.left + Math.min(34, rect.width * 0.18);
                  const y = rect.top + rect.height * 0.5;
                  const hit = document.elementFromPoint(x, y);
                  if (hit !== frames[0]) return null;
                  return {
                    token,
                    url: location.href,
                    frame: frames[0].src,
                    width: window.innerWidth,
                    height: window.innerHeight,
                    x,
                    y
                  };
                })()
                """;

            var raw = await webView.ExecuteScriptAsync(snapshotScript).WaitAsync(ct);
            if (string.IsNullOrEmpty(raw) || raw == "null") continue;

            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            if (root.GetProperty("token").GetString() != oneTimeToken ||
                root.GetProperty("url").GetString() != expectedUrl)
                continue;

            var frameSrc = root.GetProperty("frame").GetString() ?? string.Empty;
            if (!Uri.TryCreate(frameSrc, UriKind.Absolute, out var frameUri) ||
                frameUri.Scheme != Uri.UriSchemeHttps ||
                frameUri.Host != "challenges.cloudflare.com")
                continue;

            var cssW = root.GetProperty("width").GetDouble();
            var cssH = root.GetProperty("height").GetDouble();
            var cssX = root.GetProperty("x").GetDouble();
            var cssY = root.GetProperty("y").GetDouble();
            if (cssW <= 0 || cssH <= 0 || cssX <= 0 || cssX >= cssW || cssY <= 0 || cssY >= cssH)
                continue;

            var scale = viewportWidth / cssW;
            var pt = new Point((int)Math.Round(cssX * scale), (int)Math.Round(cssY * scale));

            // Dispatch trusted pointer input strictly inside the offscreen CompositionController
            compositionController.SendMouseInput(
                CoreWebView2MouseEventKind.Move,
                CoreWebView2MouseEventVirtualKeys.None,
                0,
                pt);
            compositionController.SendMouseInput(
                CoreWebView2MouseEventKind.LeftButtonDown,
                CoreWebView2MouseEventVirtualKeys.LeftButton,
                0,
                pt);
            await Task.Delay(45, ct);
            compositionController.SendMouseInput(
                CoreWebView2MouseEventKind.LeftButtonUp,
                CoreWebView2MouseEventVirtualKeys.None,
                0,
                pt);

            // Wait to verify whether challenge document disappeared (never treat click dispatch alone as success)
            for (var check = 0; check < 14; check++)
            {
                await Task.Delay(500, ct);
                var stillChallenge = await webView.ExecuteScriptAsync(
                    "Boolean(document.querySelector('iframe[src^=\"https://challenges.cloudflare.com/\"]') || window._cf_chl_opt)").WaitAsync(ct);
                if (stillChallenge == "false")
                    return true;
            }
        }

        return false;
    }
}
