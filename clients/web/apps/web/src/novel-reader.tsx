import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { confirmAction, showToast } from '@hentai-park/design-system';
import { request } from './api.js';
import { t } from './i18n.js';
import { SelectedTextTranslation, TranslateText } from './language-tools.js';
import { novelSpeechPosition, novelSpeechSegment, safeTextOffset as safeOffset, validNovelSpeechRate } from './novel-speech.js';
import { usePreferences, useWakeLock } from './preferences.js';
import { ReaderOrientation } from './reader-orientation.js';
import { ReaderTools } from './reader-tools.js';
import { useReadingChrome } from './reading-chrome.js';

interface NovelReaderProps {
  reader: {
    source: string;
    workId: string;
    chapterId: string;
    workTitle?: string;
    title?: string;
    paragraphs?: string[];
    content?: string;
    textLength?: number;
    language?: string;
  };
  initialOffset: number;
  onOffsetChange: (offset: number) => void;
}
interface Note {
  id: string;
  offset: number;
  endOffset?: number;
  quote: string;
  note?: string;
  bookmark?: boolean;
  version: number;
}

function detectUtteranceLang(sample: string, declared?: string): string {
  if (declared) return declared;
  if (/[\u3040-\u30ff]/.test(sample)) return 'ja-JP';
  if (/[\uac00-\ud7af]/.test(sample)) return 'ko-KR';
  if (/[\u0600-\u06ff]/.test(sample)) return 'ar';
  if (/[\u0400-\u04ff]/.test(sample)) return 'ru-RU';
  if (/[\u4e00-\u9fff]/.test(sample)) return 'zh-CN';
  return 'en-US';
}

function renderHighlightedParagraph(
  text: string,
  paraStart: number,
  notes: Note[],
  onClickNote: (note: Note) => void,
): ReactNode {
  const paraEnd = paraStart + text.length;
  const spans = notes
    .filter((n) => !n.bookmark && (n.endOffset ?? n.offset) > paraStart && n.offset < paraEnd)
    .map((n) => ({
      note: n,
      start: Math.max(0, n.offset - paraStart),
      end: Math.min(text.length, (n.endOffset ?? n.offset + n.quote.length) - paraStart),
    }))
    .filter((s) => s.end > s.start)
    .sort((a, b) => a.start - b.start);

  if (!spans.length) return text;

  const out: ReactNode[] = [];
  let cursor = 0;
  spans.forEach((span, idx) => {
    if (span.start > cursor) out.push(text.slice(cursor, span.start));
    if (span.end > cursor) {
      const sliceStart = Math.max(cursor, span.start);
      out.push(
        <mark
          key={span.note.id + ':' + idx}
          className="novel-highlight-mark"
          title={span.note.note || t('点击查看标注')}
          onClick={(e) => {
            e.stopPropagation();
            onClickNote(span.note);
          }}
        >
          {text.slice(sliceStart, span.end)}
        </mark>,
      );
      cursor = span.end;
    }
  });
  if (cursor < text.length) out.push(text.slice(cursor));
  return out;
}

export function NovelReader({ reader, initialOffset, onOffsetChange }: NovelReaderProps) {
  const chrome = useReadingChrome();
  const panel = useRef<HTMLDivElement>(null);
  const panelFocus = useRef<HTMLElement | null>(null);
  const panelSelection = useRef<{ offset: number; endOffset: number; quote: string } | undefined>(undefined);
  const prefs = usePreferences();
  const p = prefs.settings;
  const paged = p.novelMode === 'paged';
  const viewport = useRef<HTMLDivElement>(null);
  const paginationNav = useRef<HTMLDivElement>(null);
  const [pageHeight, setPageHeight] = useState(320);
  const [auto, setAuto] = useState(false);
  const [position, setPosition] = useState({ page: 0, pages: 1, offset: initialOffset });
  const [bilingualAll, setBilingualAll] = useState(false);
  const [activeSelection, setActiveSelection] = useState<{ offset: number; endOffset: number; quote: string }>();

  useWakeLock(p.novelKeepScreenOn === true);

  useEffect(() => {
    if (prefs.ready) {
      setSize(Number(p.novelFontSize));
      setTheme(String(p.novelTheme));
    }
  }, [prefs.ready, p.novelFontSize, p.novelTheme]);

  const paragraphs = useMemo(
    () => reader.paragraphs ?? (reader.content ? [reader.content] : []),
    [reader.paragraphs, reader.content],
  );
  const body = useMemo(() => paragraphs.join('\n\n'), [paragraphs]);
  const isRtlContent = useMemo(() => /[\u0600-\u06ff\u0590-\u05ff]/.test(body.slice(0, 600)), [body]);
  const offsets = useMemo(() => {
    let n = 0;
    return paragraphs.map((para) => {
      const at = n;
      n += para.length + 2;
      return at;
    });
  }, [paragraphs]);

  const root = useRef<HTMLElement | null>(null);
  const save = useRef(onOffsetChange);
  const current = useRef(safeOffset(body, initialOffset));
  const restoring = useRef(true);
  const alive = useRef(true);
  save.current = onOffsetChange;

  const [noticeTarget, setNoticeTarget] = useState<'controls' | 'notes'>('controls');
  const [size, setSize] = useState(22);
  const [theme, setTheme] = useState('paper');
  const [notes, setNotes] = useState<Note[]>([]);
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [noteText, setNoteText] = useState('');
  const [speaking, setSpeaking] = useState(false);
  const [speechRate, setSpeechRate] = useState(1);
  const [rateBusy, setRateBusy] = useState(false);
  const [settingsReady, setSettingsReady] = useState(false);
  const settingsVersion = useRef<number | undefined>(undefined);
  const speechActive = useRef(false);
  const manualScroll = useRef(false);
  const speechDirty = useRef(false);
  const speechTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    const abort = new AbortController();
    void request<{ settings: Record<string, unknown>; version: number }>('/api/v1/settings', { signal: abort.signal })
      .then((value) => {
        if (abort.signal.aborted) return;
        settingsVersion.current = value.version;
        setSpeechRate(validNovelSpeechRate(value.settings.novelSpeechRate) ? value.settings.novelSpeechRate : 1);
        setSettingsReady(true);
      })
      .catch(() => {
        if (!abort.signal.aborted) setNotice(t('朗读设置读取失败，请刷新后重试。'));
      });
    return () => abort.abort();
  }, []);

  const path = '/api/v1/novel-notes/' + [reader.source, reader.workId, reader.chapterId].map(encodeURIComponent).join('/');
  const refresh = useCallback(
    async (signal?: AbortSignal) => {
      const value = await request<{ items: Note[] }>(path, { signal });
      if (!signal?.aborted) setNotes(value.items);
    },
    [path],
  );

  useEffect(() => {
    alive.current = true;
    const abort = new AbortController();
    void refresh(abort.signal).catch((error) => {
      if (!abort.signal.aborted) setNotice(t('笔记读取失败：') + String(error.message));
    });
    return () => {
      alive.current = false;
      abort.abort();
    };
  }, [refresh]);

  const locate = useCallback(
    (offset: number) => {
      manualScroll.current = false;
      const value = safeOffset(body, offset);
      current.current = value;
      let index = offsets.findLastIndex((at) => at <= value);
      if (index < 0) index = 0;
      const paragraph = root.current?.querySelector<HTMLElement>('[data-paragraph="' + index + '"]');
      if (!paragraph) return;
      if (paged && viewport.current) {
        const view = viewport.current;
        const stride = view.clientWidth + 32;
        const box = paragraph.getBoundingClientRect();
        view.scrollTo({
          left: Math.floor((view.scrollLeft + box.left - view.getBoundingClientRect().left) / stride) * stride,
          behavior: 'instant',
        });
      } else {
        paragraph.scrollIntoView({ block: 'start' });
      }
    },
    [body, offsets, paged],
  );

  useEffect(() => {
    restoring.current = true;
    current.current = safeOffset(body, initialOffset);
    const frame = requestAnimationFrame(() => {
      locate(current.current);
      restoring.current = false;
    });
    return () => cancelAnimationFrame(frame);
  }, [reader.source, reader.workId, reader.chapterId, body, locate]);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let dirty = false;
    const sample = () => {
      const candidates = Array.from(root.current?.querySelectorAll<HTMLElement>('[data-paragraph]') ?? []);
      if (paged || !manualScroll.current || speechActive.current || restoring.current || document.hidden || !candidates.length) return;
      let left = 0;
      let right = candidates.length;
      while (left < right) {
        const mid = Math.floor((left + right) / 2);
        if (candidates[mid]!.getBoundingClientRect().bottom <= 100) left = mid + 1;
        else right = mid;
      }
      const pNode = candidates[Math.min(left, candidates.length - 1)]!;
      const index = Number(pNode.dataset.paragraph);
      const next = safeOffset(body, offsets[index] ?? 0);
      if (next !== current.current) {
        current.current = next;
        setPosition((old) => ({ ...old, offset: next }));
        dirty = true;
      }
    };
    const persist = () => {
      if (dirty) {
        dirty = false;
        save.current(current.current);
      }
    };
    const mark = (event: Event) => {
      const target = event.target instanceof Element ? event.target : undefined;
      if (target?.closest('input,select,textarea,button,a,[role="toolbar"]')) {
        manualScroll.current = false;
        return;
      }
      manualScroll.current =
        event.type === 'wheel' ||
        event.type === 'touchmove' ||
        (event.type === 'keydown' &&
          ['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes((event as KeyboardEvent).key)) ||
        (event.type === 'pointerdown' && (event as PointerEvent).clientX >= document.documentElement.clientWidth);
    };
    const schedule = () => {
      sample();
      if (timer) clearTimeout(timer);
      timer = setTimeout(persist, 200);
    };
    const flush = () => {
      if (timer) clearTimeout(timer);
      sample();
      persist();
    };
    window.addEventListener('wheel', mark, { passive: true });
    window.addEventListener('pointerdown', mark, { passive: true });
    window.addEventListener('touchmove', mark, { passive: true });
    window.addEventListener('keydown', mark);
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('pagehide', flush);
    return () => {
      flush();
      window.removeEventListener('wheel', mark);
      window.removeEventListener('pointerdown', mark);
      window.removeEventListener('touchmove', mark);
      window.removeEventListener('keydown', mark);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('pagehide', flush);
    };
  }, [body, offsets, paged]);

  useLayoutEffect(() => {
    const view = viewport.current;
    const nav = paginationNav.current;
    if (!paged || chrome.mobile || !view || !nav) return;
    const measure = () => {
      const top = view.getBoundingClientRect().top + window.scrollY;
      const navStyle = getComputedStyle(nav);
      const reserved =
        nav.getBoundingClientRect().height + parseFloat(navStyle.marginTop || '0') + parseFloat(navStyle.marginBottom || '0') + 24;
      setPageHeight(Math.max(160, Math.floor(window.innerHeight - top - reserved)));
    };
    const observer = new ResizeObserver(measure);
    observer.observe(view.parentElement!);
    observer.observe(nav);
    window.addEventListener('resize', measure);
    measure();
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [paged, chrome.mobile]);

  const turn = (direction: number) => {
    manualScroll.current = true;
    const behavior = p.novelAnimate && !matchMedia('(prefers-reduced-motion: reduce)').matches ? 'smooth' : 'instant';
    if (paged && viewport.current) viewport.current.scrollBy({ left: direction * (viewport.current.clientWidth + 32), behavior });
    else window.scrollBy({ top: direction * innerHeight * 0.85, behavior });
  };

  useEffect(() => {
    const view = viewport.current;
    if (!view || !paged) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const sample = () => {
      const stride = view.clientWidth + 32;
      const page = Math.round(view.scrollLeft / stride);
      const pages = Math.max(1, Math.ceil((view.scrollWidth + 32) / stride));
      let value = current.current;
      const left = view.getBoundingClientRect().left;
      for (const paragraph of root.current?.querySelectorAll<HTMLElement>('[data-paragraph]') ?? []) {
        if (paragraph.getBoundingClientRect().right >= left + 1) {
          value = safeOffset(body, offsets[Number(paragraph.dataset.paragraph)] ?? 0);
          break;
        }
      }
      setPosition({ page, pages, offset: value });
      if (manualScroll.current && !restoring.current && value !== current.current) {
        current.current = value;
        save.current(value);
      }
    };
    const schedule = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(sample, 120);
    };
    const observer = new ResizeObserver(() => {
      locate(current.current);
      schedule();
    });
    observer.observe(view);
    view.addEventListener('scroll', schedule);
    schedule();
    return () => {
      observer.disconnect();
      view.removeEventListener('scroll', schedule);
      if (timer) clearTimeout(timer);
    };
  }, [paged, body, offsets, locate, size, p.novelLineHeight, p.novelLetterSpacing, p.novelMargin, p.novelParagraphGap, p.novelFont, p.novelBold]);

  useEffect(() => {
    if (!auto || paged) {
      setAuto(false);
      return;
    }
    let frame = 0;
    let last = 0;
    const tick = (time: number) => {
      if (!document.hidden) {
        if (last) {
          manualScroll.current = true;
          window.scrollBy(0, (Number(p.novelAutoScroll) * Math.min(time - last, 100)) / 1000);
        }
        last = time;
        if ((root.current?.getBoundingClientRect().bottom ?? Infinity) < innerHeight) {
          setAuto(false);
          return;
        }
      } else last = 0;
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [auto, paged, p.novelAutoScroll]);

  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (
        event.defaultPrevented ||
        (event.target instanceof Element && event.target.closest('input,textarea,select,button,a,[contenteditable],dialog'))
      ) {
        return;
      }
      if (['PageDown', 'PageUp', 'ArrowRight', 'ArrowLeft'].includes(event.key)) {
        event.preventDefault();
        turn(event.key === 'PageDown' || event.key === 'ArrowRight' ? 1 : -1);
      }
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [paged, p.novelAnimate]);

  const selected = useCallback(() => {
    const selection = window.getSelection();
    if (!selection?.rangeCount || selection.isCollapsed) return undefined;
    const range = selection.getRangeAt(0);
    if (!root.current?.contains(range.startContainer) || !root.current.contains(range.endContainer)) return undefined;
    const point = (node: Node, offset: number) => {
      const element = node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement;
      const pNode = element?.closest<HTMLElement>('[data-paragraph]');
      if (!pNode) return undefined;
      const prefix = document.createRange();
      prefix.selectNodeContents(pNode);
      prefix.setEnd(node, offset);
      return (offsets[Number(pNode.dataset.paragraph)] ?? 0) + prefix.toString().length;
    };
    const a = point(range.startContainer, range.startOffset);
    const b = point(range.endContainer, range.endOffset);
    if (a === undefined || b === undefined || a === b) return undefined;
    const start = Math.min(a, b);
    const end = Math.max(a, b);
    return { offset: safeOffset(body, start), endOffset: safeOffset(body, end), quote: body.slice(start, end) };
  }, [body, offsets]);

  useEffect(() => {
    const onSelChange = () => {
      setActiveSelection(selected());
    };
    document.addEventListener('selectionchange', onSelChange);
    return () => document.removeEventListener('selectionchange', onSelChange);
  }, [selected]);

  const add = async (bookmark: boolean, explicitSelection = activeSelection) => {
    setNoticeTarget(bookmark ? 'controls' : 'notes');
    const selection = bookmark ? undefined : explicitSelection ?? selected() ?? (chrome.mobile ? panelSelection.current : undefined);
    if (!bookmark && !selection) {
      setNotice(t('请先选择正文中的文字。'));
      return;
    }
    const offset = selection?.offset ?? current.current;
    const endOffset = selection?.endOffset ?? Math.min(body.length, offset + 100);
    setBusy(true);
    setNotice('');
    try {
      await request(path, {
        method: 'POST',
        body: JSON.stringify({
          offset,
          endOffset,
          quote: body.slice(offset, endOffset),
          note: noteText,
          bookmark,
          requestKey: crypto.randomUUID(),
        }),
      });
      await refresh();
      setNoteText('');
      panelSelection.current = undefined;
      window.getSelection()?.removeAllRanges();
      setActiveSelection(undefined);
      showToast(bookmark ? t('书签已保存。') : t('标注已保存。'), 'success');
    } catch (error) {
      setNotice(t('保存失败：') + String((error as Error).message));
    } finally {
      if (alive.current) setBusy(false);
    }
  };

  const remove = async (id: string) => {
    const selectedNote = notes.find((note) => note.id === id);
    if (!selectedNote) return;
    const ok = await confirmAction({
      title: t('删除此') + t(selectedNote.bookmark ? '书签' : '标注') + '？',
      description: selectedNote.quote.slice(0, 120),
      confirmLabel: t('删除'),
      danger: true,
    });
    if (!ok) return;
    setNoticeTarget('notes');
    setBusy(true);
    try {
      const note = notes.find((n) => n.id === id);
      if (!note) throw Error(t('标注已变化，请刷新后重试。'));
      await request('/api/v1/novel-notes/' + encodeURIComponent(id), {
        method: 'DELETE',
        body: JSON.stringify({ version: note.version, requestKey: crypto.randomUUID() }),
      });
      await refresh();
    } catch (error) {
      setNotice(t('删除失败：') + String((error as Error).message));
    } finally {
      setBusy(false);
    }
  };

  const speechGeneration = useRef(0);
  const flushSpeech = useCallback(() => {
    if (speechTimer.current) clearTimeout(speechTimer.current);
    speechTimer.current = undefined;
    if (speechDirty.current) {
      speechDirty.current = false;
      save.current(current.current);
    }
  }, []);
  const stopSpeech = useCallback(() => {
    speechGeneration.current++;
    speechActive.current = false;
    manualScroll.current = false;
    window.speechSynthesis?.cancel();
    flushSpeech();
    if (alive.current) setSpeaking(false);
  }, [flushSpeech]);

  useEffect(() => {
    const hidden = () => {
      if (document.hidden && p.voiceBackgroundPlayback !== true) stopSpeech();
    };
    document.addEventListener('visibilitychange', hidden);
    window.addEventListener('pagehide', stopSpeech);
    return () => {
      document.removeEventListener('visibilitychange', hidden);
      window.removeEventListener('pagehide', stopSpeech);
      stopSpeech();
    };
  }, [stopSpeech, p.voiceBackgroundPlayback]);

  const speak = () => {
    setNoticeTarget('controls');
    manualScroll.current = false;
    if (!window.speechSynthesis || typeof SpeechSynthesisUtterance !== 'function') {
      setNotice(t('此浏览器不提供朗读，可以继续阅读正文。'));
      return;
    }
    if (speechActive.current) {
      stopSpeech();
      return;
    }
    const generation = ++speechGeneration.current;
    speechActive.current = true;
    setSpeaking(true);
    if ('mediaSession' in navigator) {
      try {
        navigator.mediaSession.metadata = new MediaMetadata({
          title: reader.title ?? '',
          artist: reader.workTitle ?? 'HentaiPark',
        });
        navigator.mediaSession.setActionHandler('pause', stopSpeech);
        navigator.mediaSession.setActionHandler('stop', stopSpeech);
      } catch {
        /* Optional MediaSession */
      }
    }
    const updatePos = (offset: number) => {
      if (generation !== speechGeneration.current || !alive.current) return;
      const next = safeOffset(body, offset);
      if (next !== current.current) {
        locate(next);
        speechDirty.current = true;
        if (!speechTimer.current) speechTimer.current = setTimeout(flushSpeech, 1000);
      }
    };
    const play = (offset: number) => {
      if (generation !== speechGeneration.current || !alive.current) return;
      const segment = novelSpeechSegment(paragraphs, offsets, body, offset);
      if (!segment) {
        updatePos(body.length);
        speechActive.current = false;
        setSpeaking(false);
        flushSpeech();
        return;
      }
      const utterance = new SpeechSynthesisUtterance(segment.text);
      utterance.lang = detectUtteranceLang(segment.text, reader.language);
      utterance.rate = speechRate;
      utterance.onboundary = (event) => updatePos(novelSpeechPosition(segment.start, segment.text, event.charIndex));
      utterance.onend = () => {
        if (generation !== speechGeneration.current) return;
        updatePos(segment.end);
        play(offsets[segment.index + 1] ?? body.length);
      };
      utterance.onerror = () => {
        if (generation !== speechGeneration.current) return;
        speechActive.current = false;
        setSpeaking(false);
        flushSpeech();
        setNotice(t('朗读中断，请检查浏览器语音设置后重试。'));
      };
      window.speechSynthesis.speak(utterance);
    };
    play(current.current);
  };

  const saveRate = async () => {
    setNoticeTarget('controls');
    if (!validNovelSpeechRate(speechRate) || settingsVersion.current === undefined) return;
    setRateBusy(true);
    try {
      const result = await request<{ version: number }>('/api/v1/settings', {
        method: 'PATCH',
        body: JSON.stringify({ settings: { novelSpeechRate: speechRate }, version: settingsVersion.current, requestKey: crypto.randomUUID() }),
      });
      settingsVersion.current = result.version;
      setNotice(t('朗读速度已保存。'));
    } catch {
      try {
        settingsVersion.current = (await request<{ version: number }>('/api/v1/settings')).version;
      } catch {
        /* ignore */
      }
      setNotice(t('朗读速度保存失败，当前选择已保留，请重试。'));
    } finally {
      if (alive.current) setRateBusy(false);
    }
  };

  const colors =
    theme === 'dark' || (theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches)
      ? { background: '#10151f', color: '#f3f6fb' }
      : theme === 'paper'
        ? { background: '#f3e9d4', color: '#342c20' }
        : theme === 'green'
          ? { background: '#dce9d6', color: '#233020' }
          : { background: '#fff', color: '#17191d' };

  useEffect(() => {
    if (!chrome.mobile || !chrome.open) return;
    panelSelection.current = selected();
    panelFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    panel.current?.querySelector<HTMLButtonElement>('button')?.focus({ preventScroll: true });
    return () => {
      const previous = panelFocus.current;
      if (previous?.isConnected) previous.focus({ preventScroll: true });
    };
  }, [chrome.mobile, chrome.open, selected]);

  const settingTools = (
    <>
      {prefs.error ? <p role="status">{prefs.error}</p> : null}
      <ReaderTools title={t('小说阅读设置')}>
        <div className="reader-controls novel-settings-controls" style={{ color: 'inherit' }}>
          <label className="reader-control-group">
            {t('字号 ')}
            <input
              aria-label={t('小说字号')}
              type="range"
              min="12"
              max="42"
              value={size}
              onChange={(e) => {
                setSize(Number(e.target.value));
                void prefs.save({ novelFontSize: Number(e.target.value) });
                requestAnimationFrame(() => locate(current.current));
              }}
            />
            <span>{size}px</span>
          </label>
          <label>
            {t('阅读主题 ')}
            <select
              value={theme}
              onChange={(e) => {
                setTheme(e.target.value);
                void prefs.save({ novelTheme: e.target.value });
              }}
            >
              <option value="white">{t('纸白')}</option>
              <option value="paper">{t('暖纸')}</option>
              <option value="dark">{t('夜间')}</option>
              <option value="green">{t('护眼绿')}</option>
              <option value="system">{t('跟随系统')}</option>
            </select>
          </label>
          {p.contentTranslationEnabled ? (
            <button
              type="button"
              className={`chip ${bilingualAll ? 'active' : ''}`}
              aria-pressed={bilingualAll}
              onClick={() => setBilingualAll((v) => !v)}
            >
              {t('全章双语对照')}
            </button>
          ) : null}
        </div>
        <details className="reader-task-group">
          <summary>{t('朗读')}</summary>
          <div className="reader-controls">
            <label className="novel-speech-setting">
              <span>{t('朗读速度（1×为标准）')}</span>
              <span className="reader-control-group">
                <input
                  aria-label={t('朗读速度')}
                  type="range"
                  min="0.5"
                  max="2"
                  step="0.1"
                  value={speechRate}
                  disabled={!settingsReady || rateBusy}
                  onChange={(event) => {
                    stopSpeech();
                    setSpeechRate(Number(event.target.value));
                  }}
                />
                <output>{speechRate.toFixed(1)}×</output>
              </span>
            </label>
            <button className="chip" disabled={!settingsReady || rateBusy} onClick={() => void saveRate()}>
              {t('保存朗读速度')}
            </button>
            <button className="chip" onClick={speak}>
              {speaking ? t('停止朗读') : t('从当前位置朗读')}
            </button>
          </div>
        </details>
        <details className="reader-task-group">
          <summary>{t('阅读辅助')}</summary>
          <div className="reader-controls novel-reading-actions">
            <ReaderOrientation value={p.novelOrientation} />
            {!auto ? (
              <button className="chip" disabled={paged} onClick={() => setAuto(true)}>
                {t('开始自动滚动')}
              </button>
            ) : null}
            <button className="chip" onClick={() => void add(true)} disabled={busy}>
              {t('添加书签')}
            </button>
          </div>
          <a href="/settings?section=reading">{t('全部阅读设置')}</a>
        </details>
      </ReaderTools>
      {notice && noticeTarget === 'controls' ? (
        <p className="novel-feedback" role="status">
          {notice}
        </p>
      ) : null}
    </>
  );

  const percent = Math.round((position.offset / Math.max(1, body.length)) * 100);
  const pageTools = (
    <div ref={paginationNav} className="reader-floating-bar">
      <div className="reader-seek-row">
        <button className="chip" disabled={paged && position.page === 0} onClick={() => turn(-1)}>
          {t('上一页')}
        </button>
        <input
          type="range"
          aria-label={t('阅读进度跳转')}
          min={0}
          max={paged ? Math.max(1, position.pages - 1) : 100}
          value={paged ? position.page : percent}
          onChange={(e) => {
            const val = Number(e.target.value);
            if (paged && viewport.current) {
              const stride = viewport.current.clientWidth + 32;
              viewport.current.scrollTo({ left: val * stride, behavior: 'instant' });
            } else {
              const nextOffset = Math.round((val / 100) * body.length);
              locate(nextOffset);
              save.current(nextOffset);
              setPosition((old) => ({ ...old, offset: nextOffset }));
            }
          }}
        />
        <span>{paged ? `${position.page + 1} / ${position.pages}` : `${percent}%`}</span>
        <button className="chip" disabled={paged && position.page >= position.pages - 1} onClick={() => turn(1)}>
          {t('下一页')}
        </button>
      </div>
    </div>
  );

  const translatedParagraph = Math.max(0, offsets.findLastIndex((offset) => offset <= position.offset));
  const noteTools = (
    <>
      {p.autoTranslateContent && !bilingualAll ? (
        <section className="novel-translation" aria-label={t('当前段落译文')}>
          <h2>{t('当前段落译文')}</h2>
          <p>{t('译文随阅读位置更新，原文位置保持不变。')}</p>
          {p.contentTranslationEnabled ? (
            <TranslateText text={paragraphs[translatedParagraph] ?? ''} automatic />
          ) : (
            <a href="/settings?section=search">{t('在设置中开启内容翻译')}</a>
          )}
        </section>
      ) : null}
      <details className="settings-panel novel-notes" style={{ marginTop: 32, color: 'inherit', background: 'transparent' }}>
        <summary>
          {t('书签与标注（')}
          {notes.length}）
        </summary>
        <label>
          {t('标注备注 ')}
          <textarea aria-label={t('标注备注')} value={noteText} maxLength={4000} onChange={(e) => setNoteText(e.target.value)} />
        </label>
        <button className="chip" disabled={busy} onClick={() => void add(false)}>
          {t('保存所选文字标注')}
        </button>
        <ul>
          {notes.map((note) => (
            <li key={note.id}>
              <button
                className="chip"
                onClick={() => {
                  locate(note.offset);
                  save.current(note.offset);
                }}
              >
                {note.bookmark ? t('书签') : t('标注')}
                {t(' · 位置 ')}
                {note.offset}
              </button>
              <blockquote style={{ whiteSpace: 'pre-wrap' }}>{note.quote}</blockquote>
              {note.note ? <p>{note.note}</p> : null}
              <button className="chip danger-action" disabled={busy} onClick={() => void remove(note.id)}>
                {t('删除此')}
                {note.bookmark ? t('书签') : t('标注')}
              </button>
            </li>
          ))}
        </ul>
      </details>
      {notice && noticeTarget === 'notes' ? (
        <p className="novel-feedback" role="status">
          {notice}
        </p>
      ) : null}
    </>
  );

  return (
    <section
      className={'novel-reader' + (chrome.mobile ? ' novel-reader-mobile' : '')}
      data-reading-theme={theme}
      dir={isRtlContent ? 'rtl' : undefined}
      style={{
        ...colors,
        width: '100%',
        padding: chrome.mobile ? 20 : Number(p.novelMargin),
        filter: chrome.mobile ? undefined : `brightness(${1 - Number(p.novelDim)})`,
        borderRadius: chrome.mobile ? 0 : 16,
      }}
      aria-label={t('小说阅读器')}
    >
      {chrome.mobile ? null : (
        <>
          {settingTools}
          {p.novelShowStatus ? (
            <p className="novel-reading-status" role="status">
              {paged ? position.page + 1 + ' / ' + position.pages : percent + '%'}
            </p>
          ) : null}
        </>
      )}

      <div
        ref={viewport}
        className={paged ? 'novel-pagination-viewport' : 'novel-scroll-viewport'}
        style={{
          ...(paged ? { maxWidth: '72ch', fontSize: size, marginInline: 'auto' } : {}),
          filter: chrome.mobile ? `brightness(${1 - Number(p.novelDim)})` : undefined,
        }}
        onClick={(event) => {
          if (window.getSelection()?.toString() || (event.target instanceof Element && event.target.closest('button,a,input,mark'))) {
            return;
          }
          const box = event.currentTarget.getBoundingClientRect();
          const fraction = (event.clientX - box.left) / box.width;
          if (p.novelTapToPage && fraction < 0.25) turn(-1);
          else if (p.novelTapToPage && fraction > 0.75) turn(1);
          else if (chrome.mobile) chrome.toggle();
        }}
      >
        <article
          ref={root}
          style={{
            maxWidth: paged ? undefined : '72ch',
            height: paged
              ? chrome.mobile
                ? 'calc(100dvh - 76px - env(safe-area-inset-top) - env(safe-area-inset-bottom))'
                : pageHeight
              : undefined,
            columnCount: paged ? 1 : undefined,
            columnGap: paged ? 32 : undefined,
            columnFill: paged ? 'auto' : undefined,
            margin: 'auto',
            fontSize: size,
            lineHeight: Number(p.novelLineHeight),
            letterSpacing: Number(p.novelLetterSpacing),
            fontFamily: p.novelFont === 'system' ? 'system-ui' : String(p.novelFont),
            fontWeight: p.novelBold ? 700 : 400,
            textAlign: p.novelJustify ? 'justify' : undefined,
            overflowWrap: 'anywhere',
          }}
        >
          <h1 style={{ fontSize: chrome.mobile ? 24 : '1.5em', lineHeight: 1.4 }}>{reader.title}</h1>
          {paragraphs.map((paragraph, index) => (
            <div key={index}>
              <p
                data-paragraph={index}
                style={{
                  whiteSpace: 'pre-wrap',
                  margin: `0 0 ${p.novelParagraphGap}px`,
                  textIndent: p.novelIndent ? '2em' : 0,
                }}
              >
                {renderHighlightedParagraph(paragraph, offsets[index] ?? 0, notes, (note) => {
                  showToast(note.note ? `${t('标注')}：${note.note}` : t('已高亮标注'));
                })}
              </p>
              {bilingualAll && p.contentTranslationEnabled && paragraph.trim() ? (
                <div className="novel-inline-translation">
                  <TranslateText text={paragraph} automatic />
                </div>
              ) : null}
            </div>
          ))}
          {!chrome.mobile ? <SelectedTextTranslation /> : null}
        </article>
      </div>

      {activeSelection ? (
        <div className="novel-selection-bar" role="toolbar" aria-label={t('选区操作')}>
          <button type="button" disabled={busy} onClick={() => void add(false, activeSelection)}>
            {t('高亮标注')}
          </button>
          <button
            type="button"
            onClick={() => {
              void navigator.clipboard.writeText(activeSelection.quote).then(() => showToast(t('已复制文字'), 'success'));
            }}
          >
            {t('复制')}
          </button>
        </div>
      ) : null}

      {chrome.mobile ? (
        <>
          <div className="novel-mobile-status" style={{ background: colors.background, color: colors.color }} aria-label={t('阅读进度')}>
            <span>{reader.title}</span>
            {p.novelShowStatus ? (
              <span>{paged ? position.page + 1 + ' / ' + position.pages : percent + '%'}</span>
            ) : null}
          </div>
          <div
            hidden={!chrome.open}
            style={{ background: 'var(--browse-surface)', color: 'var(--browse-text)' }}
            ref={panel}
            className="mobile-reading-panel novel-mobile-panel"
            role="region"
            aria-label={t('阅读工具')}
            onKeyDown={(event) => {
              if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                chrome.toggle();
              }
            }}
          >
            {settingTools}
            {pageTools}
            {noteTools}
            <SelectedTextTranslation readSelection={() => panelSelection.current?.quote} />
          </div>
        </>
      ) : (
        <>
          {pageTools}
          {noteTools}
        </>
      )}

      {speaking
        ? createPortal(
            <button className="chip novel-speech-stop" onClick={stopSpeech}>
              {t('停止朗读')}
            </button>,
            document.body,
          )
        : null}
      {auto
        ? createPortal(
            <button className="chip novel-autoscroll-stop" onClick={() => setAuto(false)}>
              {t('停止自动滚动')}
            </button>,
            document.body,
          )
        : null}
    </section>
  );
}
