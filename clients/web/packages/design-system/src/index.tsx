import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type ReactNode,
} from 'react';

export const designTokens = {
  colors: {
    canvasStart: '#EAF1FC',
    canvasEnd: '#F4F1F4',
    sidebar: '#E7F0FC',
    primary: '#1268D5',
    primaryHover: '#0D58B7',
    text: '#17191D',
    secondary: '#5F6672',
    muted: '#737B88',
    success: '#277E52',
    warning: '#9A6400',
    danger: '#B44250',
    info: '#4B68B5',
  },
  radius: { nav: '20px', panel: '18px', card: '14px', control: '999px', input: '12px' },
  spacing: [4, 8, 12, 16, 24, 32, 48] as const,
} as const;

function parseHexColor(hex: string): [number, number, number] | null {
  const clean = hex.trim().replace(/^#/, '');
  if (/^[0-9a-fA-F]{3}$/.test(clean)) {
    return [
      parseInt(clean[0]! + clean[0]!, 16),
      parseInt(clean[1]! + clean[1]!, 16),
      parseInt(clean[2]! + clean[2]!, 16),
    ];
  }
  if (/^[0-9a-fA-F]{6}$/.test(clean)) {
    return [
      parseInt(clean.slice(0, 2), 16),
      parseInt(clean.slice(2, 4), 16),
      parseInt(clean.slice(4, 6), 16),
    ];
  }
  return null;
}

function rgbToHsl(r: number, g: number, b: number): [number, number, number] {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = 0;
  if (max === rn) h = (gn - bn) / d + (gn < bn ? 6 : 0);
  else if (max === gn) h = (bn - rn) / d + 2;
  else h = (rn - gn) / d + 4;
  return [h * 60, s, l];
}

function hslToHex(h: number, s: number, l: number): string {
  const hue = ((h % 360) + 360) % 360;
  const sat = Math.max(0, Math.min(1, s));
  const lig = Math.max(0, Math.min(1, l));
  const c = (1 - Math.abs(2 * lig - 1)) * sat;
  const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = lig - c / 2;
  let r = 0;
  let g = 0;
  let b = 0;
  if (hue < 60) [r, g, b] = [c, x, 0];
  else if (hue < 120) [r, g, b] = [x, c, 0];
  else if (hue < 180) [r, g, b] = [0, c, x];
  else if (hue < 240) [r, g, b] = [0, x, c];
  else if (hue < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  const toByte = (v: number) => Math.round((v + m) * 255).toString(16).padStart(2, '0');
  return `#${toByte(r)}${toByte(g)}${toByte(b)}`;
}

export function seedColorToHex(seedColor: number | string | undefined): string | undefined {
  if (typeof seedColor === 'number' && Number.isFinite(seedColor)) {
    return `#${(seedColor >>> 0).toString(16).padStart(8, '0').slice(-6).toLowerCase()}`;
  }
  if (typeof seedColor === 'string' && parseHexColor(seedColor)) {
    const rgb = parseHexColor(seedColor)!;
    return `#${rgb.map((b) => b.toString(16).padStart(2, '0')).join('')}`;
  }
  return undefined;
}

export function hexToSeedColor(hex: string): number {
  const rgb = parseHexColor(hex);
  if (!rgb) return 0xff2f6fae;
  return ((0xff000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]) >>> 0);
}

/** Derives WCAG AA contrast-safe accent tokens from a user seed color (ARGB int or hex string). */
export function computeSeedPalette(seedColor: number | string | undefined, mode: 'light' | 'dark') {
  const normalizedHex = seedColorToHex(seedColor);
  const rgb = normalizedHex ? parseHexColor(normalizedHex) : null;
  if (!rgb) {
    return mode === 'dark'
      ? { accent: '#8db7e6', accentHover: '#b4d2f1', soft: '#21344b', onAction: '#0b1522', themeMeta: '#0d1119' }
      : { accent: '#2f6fae', accentHover: '#245b90', soft: '#e8f1fb', onAction: '#ffffff', themeMeta: '#edf1f8' };
  }
  const [h, s] = rgbToHsl(rgb[0], rgb[1], rgb[2]);
  const sat = Math.max(0.38, Math.min(0.82, s));
  if (mode === 'dark') {
    return {
      accent: hslToHex(h, sat * 0.85, 0.72),
      accentHover: hslToHex(h, sat * 0.9, 0.8),
      soft: hslToHex(h, sat * 0.55, 0.22),
      onAction: '#0b121c',
      themeMeta: '#0d1119',
    };
  }
  return {
    accent: hslToHex(h, sat, 0.39),
    accentHover: hslToHex(h, sat, 0.32),
    soft: hslToHex(h, sat * 0.65, 0.93),
    onAction: '#ffffff',
    themeMeta: '#edf1f8',
  };
}

export function applySeedTheme(
  seedColor: number | string | undefined,
  mode: 'light' | 'dark',
  customMetaColor?: string,
) {
  if (typeof document === 'undefined') return;
  const palette = computeSeedPalette(seedColor, mode);
  const root = document.documentElement;
  root.style.setProperty('--control-accent', palette.accent);
  root.style.setProperty('--control-accent-hover', palette.accentHover);
  root.style.setProperty('--control-soft', palette.soft);
  root.style.setProperty('--user-on-accent', palette.onAction);
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (meta) meta.content = customMetaColor ?? palette.themeMeta;
}

export function StatusMessage({
  tone = 'info',
  title,
  children,
}: {
  tone?: 'info' | 'success' | 'warning' | 'danger';
  title: string;
  children?: ReactNode;
}) {
  return (
    <section className={`status status-${tone}`} role={tone === 'danger' ? 'alert' : 'status'} aria-live="polite">
      <strong>{title}</strong>
      {children ? <div className="status-body">{children}</div> : null}
    </section>
  );
}

export function Button({
  variant = 'tonal',
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'tonal' | 'primary' | 'ghost' | 'danger';
}) {
  const variantClass =
    variant === 'primary'
      ? 'primary-link'
      : variant === 'danger'
        ? 'button danger-action'
        : variant === 'ghost'
          ? 'button ghost-button'
          : 'button';
  return <button {...props} className={`${variantClass} ${className}`.trim()} />;
}

export function Chip({
  active = false,
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      aria-pressed={active || props['aria-pressed']}
      {...props}
      className={`chip ${active ? 'active' : ''} ${className}`.trim()}
    />
  );
}

export function SegmentedTabs<T extends string>({
  items,
  value,
  onChange,
  ariaLabel,
}: {
  items: ReadonlyArray<{ value: T; label: string; badge?: number | string }>;
  value: T;
  onChange: (next: T) => void;
  ariaLabel?: string;
}) {
  return (
    <div className="segmented-tabs" role="tablist" aria-label={ariaLabel}>
      {items.map((item) => (
        <button
          key={item.value}
          type="button"
          role="tab"
          aria-selected={value === item.value}
          className={`segmented-tab ${value === item.value ? 'active' : ''}`}
          onClick={() => onChange(item.value)}
        >
          <span>{item.label}</span>
          {item.badge !== undefined ? <small className="segmented-badge">{item.badge}</small> : null}
        </button>
      ))}
    </div>
  );
}

export function Skeleton({
  className = '',
  aspectRatio,
  height,
}: {
  className?: string;
  aspectRatio?: string;
  height?: number | string;
}) {
  return (
    <div
      aria-hidden="true"
      className={`skeleton-block ${className}`.trim()}
      style={{ aspectRatio, height }}
    />
  );
}

export function CoverCardSkeleton({ aspectRatio = '3 / 4' }: { aspectRatio?: string }) {
  return (
    <div className="work-card skeleton-card" aria-hidden="true">
      <div className="home-skeleton-cover" style={{ aspectRatio }} />
      <div className="work-meta">
        <div className="home-skeleton-line home-skeleton-line-title" />
        <div className="home-skeleton-line home-skeleton-line-meta" />
      </div>
    </div>
  );
}

export function EmptyState({ title, detail, action }: { title: string; detail: string; action?: ReactNode }) {
  return (
    <div className="empty-state">
      <svg
        aria-hidden="true"
        className="empty-mark"
        width="40"
        height="40"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
      >
        <path d="M3 7h6l2 2h10v11H3zM3 7V4h7l2 3h9v2" />
      </svg>
      <h3>{title}</h3>
      <p>{detail}</p>
      {action ? <div className="empty-action">{action}</div> : null}
    </div>
  );
}

const UILabelsContext = createContext<(text: string) => string>((text) => text);

/** Adaptive modal: bottom sheet with drag-to-close on <840px, centered modal on >=840px. */
export function AdaptiveSheet({
  open,
  title,
  onClose,
  closeLabel,
  side = 'bottom',
  children,
  footer,
}: {
  open: boolean;
  title: string;
  onClose: () => void;
  closeLabel?: string;
  side?: 'bottom' | 'right';
  children: ReactNode;
  footer?: ReactNode;
}) {
  const tr = useContext(UILabelsContext);
  const resolvedCloseLabel = closeLabel ?? tr('关闭');
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const dragStartY = useRef<number | null>(null);
  const [dragOffset, setDragOffset] = useState(0);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      try {
        dialog.showModal();
      } catch {
        dialog.setAttribute('open', '');
      }
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  if (!open) return null;

  return (
    <dialog
      ref={dialogRef}
      className={`adaptive-sheet adaptive-sheet-${side}`}
      aria-labelledby={titleId}
      style={dragOffset > 0 ? { transform: `translateY(${dragOffset}px)` } : undefined}
      onClose={() => {
        setDragOffset(0);
        onClose();
      }}
      onClick={(event) => {
        if (event.target === dialogRef.current) onClose();
      }}
    >
      <div
        className="adaptive-sheet-handle"
        aria-hidden="true"
        onTouchStart={(e) => {
          dragStartY.current = e.touches[0]?.clientY ?? null;
        }}
        onTouchMove={(e) => {
          if (dragStartY.current === null) return;
          const dy = (e.touches[0]?.clientY ?? dragStartY.current) - dragStartY.current;
          if (dy > 0) setDragOffset(dy);
        }}
        onTouchEnd={() => {
          if (dragOffset > 90) onClose();
          setDragOffset(0);
          dragStartY.current = null;
        }}
      >
        <span />
      </div>
      <header className="adaptive-sheet-header">
        <h2 id={titleId}>{title}</h2>
        <button type="button" className="chip" onClick={onClose}>
          {resolvedCloseLabel}
        </button>
      </header>
      <div className="adaptive-sheet-body">{children}</div>
      {footer ? <footer className="adaptive-sheet-footer">{footer}</footer> : null}
    </dialog>
  );
}

export interface ConfirmOptions {
  title: string;
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
}

type ConfirmResolver = (confirmed: boolean) => void;

let globalConfirmHandler: ((options: ConfirmOptions) => Promise<boolean>) | null = null;

/** Imperative async replacement for window.confirm() across the entire Web client. */
export function confirmAction(options: ConfirmOptions | string): Promise<boolean> {
  const normalized: ConfirmOptions = typeof options === 'string' ? { title: options } : options;
  if (globalConfirmHandler) return globalConfirmHandler(normalized);
  return Promise.resolve(false);
}

const ConfirmContext = createContext<(options: ConfirmOptions) => Promise<boolean>>(confirmAction);
export function useConfirm() {
  return useContext(ConfirmContext);
}

export function ConfirmProvider({
  children,
  defaultConfirmLabel,
  defaultCancelLabel,
  translate = (text: string) => text,
}: {
  children: ReactNode;
  defaultConfirmLabel?: string;
  defaultCancelLabel?: string;
  translate?: (text: string) => string;
}) {
  const [pending, setPending] = useState<{ options: ConfirmOptions; resolve: ConfirmResolver } | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  const ask = useCallback((options: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      setPending((prev) => {
        prev?.resolve(false);
        return { options, resolve };
      });
    });
  }, []);

  useEffect(() => {
    globalConfirmHandler = ask;
    return () => {
      if (globalConfirmHandler === ask) globalConfirmHandler = null;
    };
  }, [ask]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (pending && !dialog.open) {
      try {
        dialog.showModal();
      } catch {
        dialog.setAttribute('open', '');
      }
    } else if (!pending && dialog.open) {
      dialog.close();
    }
  }, [pending]);

  const settle = (value: boolean) => {
    const current = pending;
    setPending(null);
    current?.resolve(value);
  };

  return (
    <UILabelsContext.Provider value={translate}>
      <ConfirmContext.Provider value={ask}>
        {children}
        {pending ? (
          <dialog
            ref={dialogRef}
            className="confirm-dialog"
            aria-labelledby={titleId}
            onCancel={(e) => {
              e.preventDefault();
              settle(false);
            }}
            onClick={(e) => {
              if (e.target === dialogRef.current) settle(false);
            }}
          >
            <h2 id={titleId}>{pending.options.title}</h2>
            {pending.options.description ? <p className="confirm-dialog-desc">{pending.options.description}</p> : null}
            <div className="action-row confirm-dialog-actions">
              <button type="button" className="chip" onClick={() => settle(false)}>
                {pending.options.cancelLabel ?? defaultCancelLabel ?? translate('取消')}
              </button>
              <button
                type="button"
                autoFocus
                className={pending.options.danger ? 'button danger-action' : 'primary-link'}
                onClick={() => settle(true)}
              >
                {pending.options.confirmLabel ?? defaultConfirmLabel ?? translate('确认')}
              </button>
            </div>
          </dialog>
        ) : null}
      </ConfirmContext.Provider>
    </UILabelsContext.Provider>
  );
}

export interface ToastItem {
  id: number;
  message: string;
  tone?: 'info' | 'success' | 'warning' | 'danger';
}

let toastSeq = 0;
const toastSubscribers = new Set<(item: ToastItem) => void>();

export function showToast(message: string, tone: ToastItem['tone'] = 'info') {
  const item: ToastItem = { id: ++toastSeq, message, tone };
  toastSubscribers.forEach((fn) => fn(item));
}

export function ToastHost() {
  const [items, setItems] = useState<ToastItem[]>([]);
  useEffect(() => {
    const listener = (item: ToastItem) => {
      setItems((prev) => [...prev.slice(-3), item]);
      setTimeout(() => {
        setItems((prev) => prev.filter((x) => x.id !== item.id));
      }, 3200);
    };
    toastSubscribers.add(listener);
    return () => {
      toastSubscribers.delete(listener);
    };
  }, []);
  if (!items.length) return null;
  return (
    <div className="toast-host" role="status" aria-live="polite">
      {items.map((item) => (
        <div key={item.id} className={`toast-pill toast-${item.tone ?? 'info'}`}>
          {item.message}
        </div>
      ))}
    </div>
  );
}
