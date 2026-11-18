import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import { navigateClick, searchSelectionQuery } from '../app/app-context.js';
import { NavigationIcon } from '../browse-ui.js';
import { t } from '../i18n.js';
import { useSharedState } from '../native.js';
import { usePreferences } from '../preferences.js';
import { SearchTools } from '../search-tools.js';

function looksResolvable(input: string): boolean {
  const trimmed = input.trim();
  if (!trimmed) return false;
  return (
    /^https?:\/\//i.test(trimmed) ||
    /^(?:RJ|BJ|VJ)\d{5,10}$/i.test(trimmed) ||
    /^[A-Z]{2,6}-\d{2,6}$/i.test(trimmed) ||
    /^d_\d{5,10}$/i.test(trimmed) ||
    /^\d{5,9}$/.test(trimmed)
  );
}

export function SearchBox({
  navigate,
  initial = '',
  scope = 'all',
  source = '',
  view = 'grouped',
  filters = '',
  onSearch,
}: {
  navigate: (to: string) => void;
  initial?: string;
  scope?: string;
  source?: string;
  view?: string;
  filters?: string;
  onSearch?: (query: string) => void;
}) {
  const shared = useSharedState();
  const prefs = usePreferences();
  const [value, setValue] = useState(initial);
  const [composing, setComposing] = useState(false);
  const [focused, setFocused] = useState(false);
  const [suggestions, setSuggestions] = useState<Array<{ keyword: string; label: string; subtitle?: string }>>([]);
  const [resolved, setResolved] = useState<Array<{ source: string; type: string; workId?: string; href?: string; url?: string }>>([]);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setValue(initial);
  }, [initial, scope, source, view]);

  const historyItems = Array.isArray(prefs.settings.searchHistory)
    ? (prefs.settings.searchHistory as unknown[]).filter((x): x is string => typeof x === 'string' && Boolean(x.trim()))
    : [];

  const recordHistory = (term: string) => {
    const clean = term.trim();
    if (!clean || shared.incognito) return;
    const next = [clean, ...historyItems.filter((item) => item !== clean)].slice(0, 20);
    void prefs.save({ searchHistory: next });
    try {
      sessionStorage.setItem('hp-last-search', JSON.stringify({ q: clean, scope, source, view, filters }));
    } catch {
      /* Optional sessionStorage */
    }
  };

  const commitSearch = (queryValue: string) => {
    const clean = queryValue.trim();
    recordHistory(clean);
    setFocused(false);
    if (onSearch) onSearch(clean);
    else {
      navigate(
        '/search?q=' +
          encodeURIComponent(clean) +
          '&scope=' +
          encodeURIComponent(scope) +
          '&source=' +
          encodeURIComponent(source) +
          '&view=' +
          encodeURIComponent(view),
      );
    }
  };

  const effectiveSource =
    source ||
    (new URLSearchParams(window.location.search).getAll('sources').length === 1
      ? new URLSearchParams(window.location.search).get('sources') ?? ''
      : '');

  useEffect(() => {
    if (composing || !focused) return;
    const trimmed = value.trim();
    if (!trimmed) {
      setSuggestions([]);
      setResolved([]);
      return;
    }
    const abort = new AbortController();
    const timer = setTimeout(() => {
      void api
        .suggestions(trimmed, effectiveSource || undefined, abort.signal)
        .then((res) => {
          if (!abort.signal.aborted) setSuggestions(res.items.slice(0, 12));
        })
        .catch(() => {});
      if (looksResolvable(trimmed)) {
        void api
          .resolveSearch(trimmed, effectiveSource || undefined, abort.signal)
          .then((res) => {
            if (!abort.signal.aborted) setResolved(res.items.slice(0, 4));
          })
          .catch(() => {});
      } else {
        setResolved([]);
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [value, composing, focused, effectiveSource]);

  useEffect(() => {
    const onPointerDown = (event: PointerEvent) => {
      if (wrapRef.current && event.target instanceof Node && !wrapRef.current.contains(event.target)) {
        setFocused(false);
      }
    };
    document.addEventListener('pointerdown', onPointerDown);
    return () => document.removeEventListener('pointerdown', onPointerDown);
  }, []);

  const showDropdown =
    focused && !composing && (resolved.length > 0 || suggestions.length > 0 || (!value.trim() && historyItems.length > 0));

  return (
    <div ref={wrapRef} className="search-combobox-wrap">
      <form
        className="search-box"
        role="search"
        onSubmit={(event) => {
          event.preventDefault();
          if (composing) return;
          commitSearch(value);
        }}
      >
        <NavigationIcon name="/search" />
        <input
          value={value}
          onFocus={() => setFocused(true)}
          onCompositionStart={() => setComposing(true)}
          onCompositionEnd={() => setComposing(false)}
          onChange={(event) => setValue(event.target.value)}
          placeholder={t('搜索作品、标签或番号')}
          aria-label={t('搜索关键词')}
          autoComplete="off"
        />
        {value ? (
          <button
            type="button"
            className="chip ghost-button"
            aria-label={t('清除输入')}
            onClick={() => {
              setValue('');
              setSuggestions([]);
              setResolved([]);
            }}
          >
            ×
          </button>
        ) : null}
        <button className="primary-link" type="submit">
          {t('搜索')}
        </button>
        <SearchTools
          keyword={composing ? '' : value}
          source={effectiveSource}
          navigate={navigate}
          search={(keyword, keywords) => {
            recordHistory(keyword);
            setFocused(false);
            navigate(
              '/search?q=' +
                encodeURIComponent(keyword) +
                '&scope=' +
                encodeURIComponent(scope) +
                '&source=' +
                encodeURIComponent(source) +
                '&filters=' +
                encodeURIComponent(filters) +
                (keywords ? '&keywords=' + encodeURIComponent(JSON.stringify(keywords)) : '') +
                searchSelectionQuery(),
            );
          }}
        />
      </form>

      {showDropdown ? (
        <div className="search-combobox-dropdown" role="listbox" aria-label={t('搜索建议')}>
          {resolved.map((item, idx) =>
            item.href ? (
              <a
                key={idx}
                href={item.href}
                className="search-resolve-banner"
                onClick={(e) => {
                  setFocused(false);
                  navigateClick(e, navigate, item.href!);
                }}
              >
                <span>
                  {t('直达内容')} · {item.source} · {item.workId ?? item.type}
                </span>
                <span>→</span>
              </a>
            ) : null,
          )}

          {!value.trim() && historyItems.length > 0 ? (
            <section>
              <div className="section-header" style={{ marginBottom: 8 }}>
                <small className="muted">{t('最近搜索')}</small>
                <button
                  type="button"
                  className="chip ghost-button"
                  onClick={() => void prefs.save({ searchHistory: [] })}
                >
                  {t('清空')}
                </button>
              </div>
              <div className="tag-row" style={{ margin: 0 }}>
                {historyItems.map((term) => (
                  <button key={term} type="button" className="chip" onClick={() => commitSearch(term)}>
                    {term}
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          {suggestions.length > 0 ? (
            <section>
              {suggestions.map((item) => (
                <button
                  key={item.keyword + ':' + item.label}
                  type="button"
                  className="search-suggestion-item"
                  onClick={() => commitSearch(item.keyword)}
                >
                  <strong>{item.label}</strong>
                  {item.subtitle && item.subtitle !== item.label ? (
                    <small className="muted">{item.subtitle}</small>
                  ) : null}
                </button>
              ))}
            </section>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
