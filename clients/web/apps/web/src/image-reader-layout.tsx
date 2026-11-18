import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { t } from './i18n.js';
import { usePreferences, useWakeLock } from './preferences.js';
import { buildSpreads, tapAction } from './reader-geometry.js';
import { ReaderOrientation } from './reader-orientation.js';
import { ReaderTools } from './reader-tools.js';
import { useReadingChrome } from './reading-chrome.js';

type Layout = 'scroll' | 'single' | 'double';

export function ImageReaderLayout({
  count,
  title,
  initialPage = 0,
  onPageChange,
  renderPage,
  controls,
  notice,
  chapterFooter,
}: {
  count: number;
  title?: string;
  initialPage?: number;
  onPageChange?: (page: number) => void;
  renderPage: (index: number, active: boolean, cropMargins: boolean) => ReactNode;
  controls?: ReactNode;
  notice?: ReactNode;
  chapterFooter?: ReactNode;
}) {
  const chrome = useReadingChrome();
  const [layout, setLayout] = useState<Layout>('scroll');
  const [page, setPage] = useState(Math.min(initialPage, Math.max(0, count - 1)));
  const [zoom, setZoom] = useState(1);
  const [separated, setSeparated] = useState(false);
  const prefs = usePreferences();
  const p = prefs.settings;
  useWakeLock(p.keepScreenOn === true);
  const rtl = p.readerMode === 'rightToLeft';
  const cropMargins = p.readerCrop === true;

  useEffect(() => {
    if (prefs.ready) setSeparated(Number(p.readerGap) > 0);
  }, [prefs.ready, p.readerGap]);

  useEffect(() => {
    if (!prefs.ready) return;
    const update = () =>
      setLayout(
        p.readerMode === 'vertical'
          ? 'scroll'
          : p.readerDual === 'always' || (p.readerDual === 'landscape' && innerWidth > innerHeight)
            ? 'double'
            : 'single',
      );
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, [prefs.ready, p.readerMode, p.readerDual]);

  const root = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const tools = root.current?.querySelector('.reader-tools');
    if (!tools) return;
    const measure = () => root.current?.style.setProperty('--reader-toolbar-height', tools.getBoundingClientRect().height + 'px');
    const observer = new ResizeObserver(measure);
    observer.observe(tools);
    measure();
    return () => observer.disconnect();
  }, []);

  const figures = useRef<Array<HTMLElement | null>>([]);
  const viewport = useRef<HTMLDivElement>(null);
  const save = useRef(onPageChange);
  const current = useRef(page);
  const swipe = useRef<{ x: number; y: number } | null>(null);
  const pinch = useRef<{ dist: number; zoom: number } | null>(null);
  const lastTap = useRef(0);
  const restoring = useRef(initialPage > 0);
  const [aspects, setAspects] = useState<Record<number, number>>({});
  const [half, setHalf] = useState<'left' | 'right' | undefined>();
  const [visiblePages, setVisiblePages] = useState<Set<number>>(() => new Set());

  useEffect(() => {
    if (layout !== 'scroll') {
      setVisiblePages(new Set());
      return;
    }
    const visible = new Set<number>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const index = Number((entry.target as HTMLElement).dataset.pageIndex);
          if (entry.isIntersecting) visible.add(index);
          else visible.delete(index);
        }
        setVisiblePages(new Set(visible));
      },
      { rootMargin: '600px 0px' },
    );
    figures.current.forEach((figure) => {
      if (figure) observer.observe(figure);
    });
    return () => observer.disconnect();
  }, [layout, count]);

  save.current = onPageChange;
  current.current = page;

  const cover = p.readerCoverSingle === true ? 1 : 0;
  const spreads = buildSpreads(count, aspects, layout === 'double', !!cover, layout === 'single' && p.readerSplitWide === true, rtl);
  const spreadIndex = Math.max(
    0,
    spreads.findIndex((item) => item.pages.includes(page) && (!half || item.half === half)),
  );
  const spread = spreads[spreadIndex];
  const start = layout === 'scroll' ? page : spread?.pages[0] ?? page;
  const step = layout === 'scroll' ? 1 : spread?.pages.length ?? 1;

  const select = useCallback(
    (index: number) => {
      const value = Math.max(0, Math.min(count - 1, index));
      setPage(value);
      save.current?.(value);
      if (layout === 'scroll') {
        figures.current[value]?.scrollIntoView({
          block: 'start',
          behavior: p.readerAnimate && !matchMedia('(prefers-reduced-motion: reduce)').matches ? 'smooth' : 'instant',
        });
      } else {
        viewport.current?.scrollIntoView({ block: 'nearest' });
      }
    },
    [count, layout, p.readerAnimate],
  );

  const move = (direction: number) => {
    if (layout === 'scroll') {
      select(page + direction);
      return;
    }
    const next = spreads[Math.max(0, Math.min(spreads.length - 1, spreadIndex + direction))];
    if (next) {
      setHalf(next.half);
      select(next.pages[0]!);
    }
  };

  useEffect(() => {
    const keyboard = (e: KeyboardEvent) => {
      if (
        e.defaultPrevented ||
        (e.target instanceof Element && e.target.closest('input,textarea,select,button,a,[contenteditable="true"],dialog'))
      ) {
        return;
      }
      if (['ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown'].includes(e.key)) {
        e.preventDefault();
        move(e.key === 'PageDown' || e.key === (rtl ? 'ArrowLeft' : 'ArrowRight') ? 1 : -1);
      }
    };
    window.addEventListener('keydown', keyboard);
    return () => window.removeEventListener('keydown', keyboard);
  }, [select, start, step, rtl, half, aspects, p.readerSplitWide]);

  useEffect(() => {
    if (!prefs.ready || p.readerMode !== 'vertical' || layout !== 'scroll') return;
    let frame = 0;
    const update = () => {
      frame = 0;
      if (restoring.current) return;
      const target = innerHeight * 0.35;
      let best = -1;
      let bestDistance = Infinity;
      figures.current.forEach((figure, index) => {
        if (!figure) return;
        const r = figure.getBoundingClientRect();
        if (r.bottom <= 0 || r.top >= innerHeight) return;
        const distance = r.top <= target && r.bottom >= target ? 0 : Math.min(Math.abs(r.top - target), Math.abs(r.bottom - target));
        if (distance < bestDistance) {
          best = index;
          bestDistance = distance;
        }
      });
      if (best >= 0 && best !== current.current) {
        current.current = best;
        setPage(best);
        save.current?.(best);
      }
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    const observer = new ResizeObserver(schedule);
    figures.current.forEach((f) => f && observer.observe(f));
    schedule();
    return () => {
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      observer.disconnect();
      if (frame) cancelAnimationFrame(frame);
    };
  }, [layout, count, prefs.ready, p.readerMode]);

  useEffect(() => {
    if (initialPage <= 0) {
      restoring.current = false;
      return;
    }
    const target = figures.current[initialPage];
    let active = true;
    const finish = () => {
      active = false;
      restoring.current = false;
      target?.removeEventListener('load', restore, true);
    };
    const restore = () => {
      if (!active || !target) return;
      target.scrollIntoView({ block: 'start' });
      const image = target.querySelector('img');
      if (image?.complete && image.naturalWidth) finish();
    };
    target?.addEventListener('load', restore, true);
    const observer = new ResizeObserver(restore);
    if (target) observer.observe(target);
    restore();
    const timer = setTimeout(finish, 10000);
    window.addEventListener('wheel', finish, { once: true });
    window.addEventListener('pointerdown', finish, { once: true });
    return () => {
      finish();
      clearTimeout(timer);
      observer.disconnect();
      window.removeEventListener('wheel', finish);
      window.removeEventListener('pointerdown', finish);
    };
  }, []);

  const changeMode = (mode: 'vertical' | 'rightToLeft' | 'leftToRight', dual?: 'off' | 'always') => {
    setHalf(undefined);
    const nextLayout: Layout = mode === 'vertical' ? 'scroll' : dual === 'always' ? 'double' : 'single';
    void prefs.save({ readerMode: mode, ...(dual ? { readerDual: dual } : {}) });
    setLayout(nextLayout);
    requestAnimationFrame(() => {
      if (nextLayout === 'scroll') figures.current[current.current]?.scrollIntoView({ block: 'start' });
    });
  };

  return (
    <div ref={root} className={'comic-reader' + (cropMargins ? ' reader-crop' : '')}>
      {title ? <h1 className="reader-heading">{title}</h1> : null}
      {notice}
      {prefs.error ? <p role="status">{prefs.error}</p> : null}

      <div className={chrome.mobile ? 'mobile-reading-panel' : ''} hidden={chrome.mobile && !chrome.open}>
        <ReaderTools title={t('阅读器控制')}>
          <div className="reader-controls" role="toolbar" aria-label={t('阅读器控制')}>
            <label>
              {t('翻页方向')}
              <select
                aria-label={t('翻页方向')}
                value={layout === 'scroll' ? 'vertical' : rtl ? 'rightToLeft' : 'leftToRight'}
                onChange={(e) => {
                  const val = e.target.value as 'vertical' | 'rightToLeft' | 'leftToRight';
                  changeMode(val, val === 'vertical' ? 'off' : layout === 'double' ? 'always' : 'off');
                }}
              >
                <option value="vertical">{t('上下滚动')}</option>
                <option value="rightToLeft">{t('从右到左（日漫）')}</option>
                <option value="leftToRight">{t('从左到右')}</option>
              </select>
            </label>

            {layout !== 'scroll' ? (
              <label>
                {t('阅读布局')}
                <select
                  aria-label={t('阅读布局')}
                  value={layout}
                  onChange={(e) => changeMode(rtl ? 'rightToLeft' : 'leftToRight', e.target.value === 'double' ? 'always' : 'off')}
                >
                  <option value="single">{t('单页')}</option>
                  <option value="double">{t('双页')}</option>
                </select>
              </label>
            ) : (
              <label>
                {t('滚动样式')}
                <select
                  aria-label={t('滚动样式')}
                  value={separated ? 'separated' : 'seamless'}
                  onChange={(event) => {
                    const next = event.target.value === 'separated';
                    setSeparated(next);
                    void prefs.save({ readerGap: next ? 16 : 0, ...(next ? { readerShowPageNumber: true } : {}) });
                  }}
                >
                  <option value="seamless">{t('无缝连续')}</option>
                  <option value="separated">{t('留缝与页码')}</option>
                </select>
              </label>
            )}

            <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <input
                type="checkbox"
                checked={cropMargins}
                onChange={(e) => void prefs.save({ readerCrop: e.target.checked })}
              />
              {t('自动切白边')}
            </label>

            <span className="reader-control-group" role="group" aria-label={t('缩放比例')}>
              <button
                className="chip"
                aria-label={t('缩小')}
                disabled={zoom <= 0.5}
                onClick={() => setZoom((z) => Math.max(0.5, Number((z - 0.1).toFixed(1))))}
              >
                −
              </button>
              <span role="status" aria-label={t('缩放比例')}>
                {Math.round(zoom * 100)}%
              </span>
              <button
                className="chip"
                aria-label={t('放大')}
                disabled={zoom >= 3}
                onClick={() => setZoom((z) => Math.min(3, Number((z + 0.1).toFixed(1))))}
              >
                +
              </button>
            </span>

            <details className="reader-advanced">
              <summary>{t('高级加载设置')}</summary>
              <label>
                {t('预加载页数')}
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={Number(p.preloadPages)}
                  disabled={!prefs.ready || prefs.busy}
                  onChange={(e) => void prefs.save({ preloadPages: Number(e.target.value) })}
                />
              </label>
            </details>
            <a href="/settings?section=reading">{t('阅读设置')}</a>
            {controls}
            <ReaderOrientation value={p.readerOrientation} />
          </div>
        </ReaderTools>
      </div>

      <div
        ref={viewport}
        className="image-reader-viewport"
        data-layout={layout}
        style={
          {
            background: String(p.readerBackground),
            filter: `brightness(${1 - Number(p.readerDim)}) sepia(${Number(p.readerWarm)}) grayscale(${p.readerGrayscale ? 1 : 0}) invert(${p.readerInvert ? 1 : 0})`,
            '--reader-zoom': zoom,
          } as CSSProperties
        }
        tabIndex={0}
        aria-label={t('漫画页面')}
        onWheel={(e) => {
          if (e.ctrlKey) {
            e.preventDefault();
            setZoom((z) => Math.max(0.5, Math.min(3, Number((z * (e.deltaY < 0 ? 1.12 : 0.89)).toFixed(2)))));
          }
        }}
        onClick={(e) => {
          if ((e.target instanceof Element && e.target.closest('button,a,input')) || window.getSelection()?.toString()) return;
          const now = Date.now();
          if (now - lastTap.current < 260) {
            lastTap.current = 0;
            setZoom((z) => (z > 1.05 ? 1 : 2));
            return;
          }
          lastTap.current = now;
          const box = e.currentTarget.getBoundingClientRect();
          const x = (e.clientX - box.left) / box.width;
          const y = layout === 'scroll' ? e.clientY / innerHeight : (e.clientY - box.top) / box.height;
          if (!p.tapToPage) {
            if (chrome.mobile && x >= 1 / 3 && x <= 2 / 3 && y >= 1 / 3 && y <= 2 / 3) chrome.toggle();
            return;
          }
          const action = tapAction(x, y, Number(p.readerTapLayout), layout === 'scroll', rtl, p.readerTapInvertH === true, p.readerTapInvertV === true);
          if (action) move(action);
          else if (chrome.mobile) chrome.toggle();
          else {
            const tools = root.current?.querySelector<HTMLDetailsElement>('details.reader-tools');
            if (tools) tools.open = !tools.open;
          }
        }}
        onTouchStart={(e) => {
          if (e.touches.length === 2) {
            const dx = e.touches[0]!.clientX - e.touches[1]!.clientX;
            const dy = e.touches[0]!.clientY - e.touches[1]!.clientY;
            pinch.current = { dist: Math.hypot(dx, dy), zoom };
            swipe.current = null;
            return;
          }
          if (layout === 'scroll' || zoom > 1 || e.touches.length !== 1) {
            swipe.current = null;
            return;
          }
          const pt = e.touches[0]!;
          swipe.current = { x: pt.clientX, y: pt.clientY };
        }}
        onTouchMove={(e) => {
          if (e.touches.length === 2 && pinch.current) {
            const dx = e.touches[0]!.clientX - e.touches[1]!.clientX;
            const dy = e.touches[0]!.clientY - e.touches[1]!.clientY;
            const ratio = Math.hypot(dx, dy) / Math.max(1, pinch.current.dist);
            setZoom(Math.max(0.5, Math.min(3, Number((pinch.current.zoom * ratio).toFixed(2)))));
          }
        }}
        onTouchEnd={(e) => {
          pinch.current = null;
          const a = swipe.current;
          const b = e.changedTouches[0];
          swipe.current = null;
          if (!a || !b) return;
          const dx = b.clientX - a.x;
          const dy = b.clientY - a.y;
          if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 2) move((dx < 0) !== rtl ? 1 : -1);
        }}
        onTouchCancel={() => {
          swipe.current = null;
          pinch.current = null;
        }}
      >
        <div
          className={
            'comic-pages ' +
            (layout === 'scroll'
              ? 'scroll-pages' + (separated ? ' separated-pages' : '')
              : layout === 'single'
                ? 'single-page'
                : 'double-page')
          }
          style={{
            width: zoom * 100 + '%',
            marginInline: zoom <= 1 ? 'auto' : 0,
            direction: rtl ? 'rtl' : 'ltr',
            gap: layout === 'scroll' ? (separated ? Number(p.readerGap) : 0) : Number(p.readerGap),
          }}
        >
          {Array.from({ length: count }, (_, index) => (
            <figure
              key={index}
              ref={(el) => {
                figures.current[index] = el;
              }}
              style={{
                background: String(p.readerBackground),
                gridColumn: layout === 'double' && step === 1 ? '1 / -1' : undefined,
                overflow: spread?.half ? 'hidden' : undefined,
                maxWidth: layout === 'single' && spread?.half ? 'calc(75dvh * ' + aspects[index]! / 2 + ')' : undefined,
              }}
              data-page-index={index}
              data-half={layout === 'single' && index === start ? spread?.half : undefined}
              onLoadCapture={(event) => {
                const image = event.target;
                if (image instanceof HTMLImageElement && image.naturalHeight) {
                  const ratio = image.naturalWidth / image.naturalHeight;
                  setAspects((old) => (old[index] === ratio ? old : { ...old, [index]: ratio }));
                }
              }}
              hidden={layout !== 'scroll' && (index < start || index >= start + step)}
            >
              {renderPage(
                index,
                prefs.ready &&
                  ((layout === 'scroll' && visiblePages.has(index)) ||
                    (index >= Math.max(0, start - Number(p.preloadPages)) && index < start + step + Number(p.preloadPages))),
                cropMargins,
              )}
              <figcaption hidden={!p.readerShowPageNumber}>
                {layout === 'scroll' && separated ? '— ' + (index + 1) + ' —' : t('第 ') + (index + 1) + t(' 页')}
              </figcaption>
            </figure>
          ))}
        </div>
      </div>

      {/* Bottom Floating Seek Bar & Pagination */}
      <div className="reader-floating-bar image-reader-pagination">
        <div className="reader-seek-row" style={{ direction: rtl && layout !== 'scroll' ? 'rtl' : 'ltr' }}>
          <button
            type="button"
            className="chip"
            disabled={layout === 'scroll' ? page === 0 : spreadIndex === 0}
            onClick={() => move(-1)}
          >
            {t('上一页')}
          </button>
          <input
            type="range"
            aria-label={t('跳转到指定页')}
            min={1}
            max={Math.max(1, count)}
            value={page + 1}
            onChange={(e) => {
              setHalf(undefined);
              select(Number(e.target.value) - 1);
            }}
          />
          <span aria-live="polite">
            {page + 1} / {count}
          </span>
          <button
            type="button"
            className="chip"
            disabled={layout === 'scroll' ? page >= count - 1 : spreadIndex >= spreads.length - 1}
            onClick={() => move(1)}
          >
            {t('下一页')}
          </button>
        </div>
      </div>

      {chapterFooter}
    </div>
  );
}
