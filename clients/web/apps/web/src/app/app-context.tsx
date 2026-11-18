import { createContext, useEffect, useRef, type MouseEvent, type ReactNode } from 'react';
import type { WorkTag } from '@hentai-park/domain-model';
import type { ApiWork, Source } from '../api.js';

export const SourceCatalog = createContext<{ data?: Source[]; loading: boolean; error?: unknown }>({ loading: true });
export const SourceNames = createContext<Record<string, string>>({});
export const CategoryNames = createContext<Record<string, string>>({});

export type Route = { path: string; label: string; href?: string };
export const routes: Route[] = [
  { path: '/discover', label: '发现' },
  { path: '/search', label: '搜索' },
  { path: '/library', label: '收藏' },
  { path: '/downloads', label: '下载' },
  { path: '/subscriptions', label: '订阅' },
  { path: '/history', label: '历史' },
  { path: '/tavern', label: '酒馆' },
  { path: '/sites', label: '内容站点' },
  { path: '/settings', label: '设置' },
  { path: '/sources', label: '站点管理' },
];

export function searchSelectionQuery() {
  const params = new URLSearchParams(window.location.search);
  const selected = new URLSearchParams();
  for (const name of ['sources', 'mediaKind', 'category']) {
    for (const value of params.getAll(name)) selected.append(name, value);
  }
  return selected.size ? '&' + selected.toString() : '';
}

export function currentRoute() {
  return window.location.pathname + window.location.search + window.location.hash;
}

export function tagHref(tag: WorkTag) {
  return (
    '/search?q=' +
    encodeURIComponent(tag.keyword ?? '') +
    '&scope=all&source=' +
    encodeURIComponent(tag.source) +
    (tag.filters ? '&filters=' + encodeURIComponent(JSON.stringify(tag.filters)) : '')
  );
}

export function canSearchTag(tag: WorkTag) {
  return Boolean(tag.keyword || (tag.filters && Object.keys(tag.filters).length));
}

export function hrefFor(work: ApiWork) {
  if (work.presentation === 'post') {
    return '/post/' + [work.source, work.workId].map(encodeURIComponent).join('/');
  }
  if (work.category === 'shortvideo') {
    const path = '/source/' + encodeURIComponent(work.source);
    const params = new URLSearchParams();
    if (window.location.pathname === path) {
      const current = new URLSearchParams(window.location.search);
      for (const key of ['feed', 'link', 'filters', 'cursor']) {
        const value = current.get(key);
        if (value !== null) params.set(key, value);
      }
    }
    params.set('work', work.workId);
    return path + '?' + params.toString();
  }
  return '/work/' + encodeURIComponent(work.source) + '/' + encodeURIComponent(work.workId);
}

export function navigateClick(event: MouseEvent, navigate: (to: string) => void, href: string) {
  if (event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    navigate(href);
  }
}

export function identityMatches(key: string, source: string, workId: string) {
  try {
    const parts = JSON.parse(key.replace(/^download:/, ''));
    return parts[0] === source && parts[1] === workId;
  } catch {
    return false;
  }
}

/** Keeps root tab trees mounted across switches while preserving each root view's window scrollY. */
export function KeepAliveView({ active, children }: { active: boolean; children: ReactNode }) {
  const savedScroll = useRef(0);
  const wasActive = useRef(active);

  useEffect(() => {
    if (wasActive.current && !active) {
      savedScroll.current = window.scrollY;
    } else if (!wasActive.current && active) {
      const target = savedScroll.current;
      requestAnimationFrame(() => {
        window.scrollTo({ top: target, behavior: 'auto' });
      });
    }
    wasActive.current = active;
  }, [active]);

  return (
    <div hidden={!active} aria-hidden={!active || undefined} style={active ? undefined : { display: 'none' }}>
      {children}
    </div>
  );
}
