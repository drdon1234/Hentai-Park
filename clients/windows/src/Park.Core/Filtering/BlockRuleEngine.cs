using System.Text;
using System.Text.RegularExpressions;
using Park.Core.Models;

namespace Park.Core.Filtering;

/// <summary>
/// Implements HentaiPark content blocklist grammar per DEVELOPMENT.md:
/// - Plain term: exact tag match (and title match when matchTitles is enabled; pure ASCII words match whole-word in titles)
/// - namespace:term: restricts tag namespace
/// - tag:term: matches any tag namespace, never matches title
/// - title:term: matches title only
/// - Wildcards * and ? (full match for tags, substring match for titles)
/// - regex:pattern (case-insensitive, invalid regex safely ignored)
/// </summary>
public sealed class BlockRuleEngine
{
    private enum Scope { Both, TagOnly, TitleOnly, Namespace }

    private sealed record CompiledRule(
        string Raw,
        Scope TargetScope,
        string? NamespaceName,
        Regex? TagPattern,
        Regex? TitlePattern);

    private readonly List<CompiledRule> _rules = [];

    public BlockRuleEngine(IEnumerable<string> rawRules, bool matchTitles = true)
    {
        foreach (var entry in rawRules)
        {
            var trimmed = entry?.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;
            var compiled = TryCompile(trimmed, matchTitles);
            if (compiled is not null) _rules.Add(compiled);
        }
    }

    public int ActiveRuleCount => _rules.Count;

    public bool IsBlocked(WorkItem item) =>
        IsBlocked(item.Title, item.Tags.Select(t => (Namespace: (string?)null, Name: t)));

    public bool IsBlocked(WorkDetail detail) =>
        IsBlocked(
            detail.Item.Title,
            detail.TagGroups.SelectMany(g => g.Tags.Select(t => (Namespace: (string?)g.Namespace, Name: t.Name)))
                .Concat(detail.Item.Tags.Select(t => (Namespace: (string?)null, Name: t))));

    public bool IsBlocked(string title, IEnumerable<(string? Namespace, string Name)> tags)
    {
        if (_rules.Count == 0) return false;
        var tagList = tags as IReadOnlyList<(string? Namespace, string Name)> ?? tags.ToList();

        foreach (var rule in _rules)
        {
            if (rule.TitlePattern is not null && !string.IsNullOrEmpty(title) && rule.TitlePattern.IsMatch(title))
            {
                return true;
            }

            if (rule.TagPattern is not null)
            {
                foreach (var (ns, rawTag) in tagList)
                {
                    var tagNs = ns;
                    var tagName = rawTag;
                    if (tagNs is null)
                    {
                        var colon = rawTag.IndexOf(':');
                        if (colon > 0 && colon < rawTag.Length - 1)
                        {
                            tagNs = rawTag[..colon];
                            tagName = rawTag[(colon + 1)..];
                        }
                    }

                    if (rule.TargetScope == Scope.Namespace &&
                        !string.Equals(rule.NamespaceName, tagNs, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    if (rule.TagPattern.IsMatch(tagName) || (ns is null && rule.TagPattern.IsMatch(rawTag)))
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private static CompiledRule? TryCompile(string raw, bool matchTitles)
    {
        var body = raw;
        var scope = Scope.Both;
        string? ns = null;

        if (body.StartsWith("title:", StringComparison.OrdinalIgnoreCase))
        {
            scope = Scope.TitleOnly;
            body = body[6..].Trim();
        }
        else if (body.StartsWith("tag:", StringComparison.OrdinalIgnoreCase))
        {
            scope = Scope.TagOnly;
            body = body[4..].Trim();
        }
        else if (!body.StartsWith("regex:", StringComparison.OrdinalIgnoreCase))
        {
            var colon = body.IndexOf(':');
            if (colon > 0 && IsAsciiIdentifier(body.AsSpan(0, colon)))
            {
                scope = Scope.Namespace;
                ns = body[..colon];
                body = body[(colon + 1)..].Trim();
            }
        }

        if (string.IsNullOrEmpty(body)) return null;

        const RegexOptions opts = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
        try
        {
            if (body.StartsWith("regex:", StringComparison.OrdinalIgnoreCase))
            {
                var expr = body[6..];
                if (string.IsNullOrEmpty(expr)) return null;
                var rx = new Regex(expr, opts, TimeSpan.FromMilliseconds(100));
                return new CompiledRule(
                    raw,
                    scope,
                    ns,
                    scope == Scope.TitleOnly ? null : rx,
                    scope is Scope.TitleOnly || (scope == Scope.Both && matchTitles) ? rx : null);
            }

            var hasWildcard = body.Contains('*') || body.Contains('?');
            if (hasWildcard)
            {
                var core = WildcardToRegex(body);
                var tagRx = scope == Scope.TitleOnly ? null : new Regex($"^{core}$", opts, TimeSpan.FromMilliseconds(100));
                var titleRx = scope == Scope.TitleOnly || (scope == Scope.Both && matchTitles)
                    ? new Regex(core, opts, TimeSpan.FromMilliseconds(100))
                    : null;
                return new CompiledRule(raw, scope, ns, tagRx, titleRx);
            }

            var escaped = Regex.Escape(body);
            var exactTagRx = scope == Scope.TitleOnly ? null : new Regex($"^{escaped}$", opts, TimeSpan.FromMilliseconds(100));
            Regex? plainTitleRx = null;
            if (scope == Scope.TitleOnly || (scope == Scope.Both && matchTitles))
            {
                var pureAsciiWord = IsPureAsciiWord(body);
                plainTitleRx = new Regex(
                    pureAsciiWord ? $@"\b{escaped}\b" : escaped,
                    opts,
                    TimeSpan.FromMilliseconds(100));
            }
            return new CompiledRule(raw, scope, ns, exactTagRx, plainTitleRx);
        }
        catch (ArgumentException)
        {
            // Invalid explicit regex must never crash list rendering
            return null;
        }
    }

    private static string WildcardToRegex(string pattern)
    {
        var sb = new StringBuilder(pattern.Length * 2);
        foreach (var ch in pattern)
        {
            sb.Append(ch switch
            {
                '*' => ".*",
                '?' => ".",
                _ => Regex.Escape(ch.ToString()),
            });
        }
        return sb.ToString();
    }

    private static bool IsAsciiIdentifier(ReadOnlySpan<char> span)
    {
        foreach (var c in span)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c is '_' or '-')) return false;
        }
        return span.Length > 0;
    }

    private static bool IsPureAsciiWord(string text)
    {
        foreach (var c in text)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or ' ')) return false;
        }
        return text.Any(char.IsAsciiLetterOrDigit);
    }
}
