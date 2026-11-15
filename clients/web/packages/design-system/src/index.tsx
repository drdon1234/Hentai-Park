import type { ButtonHTMLAttributes, ReactNode } from 'react';

export const designTokens = {
  colors: { canvasStart: '#EAF1FC', canvasEnd: '#F4F1F4', sidebar: '#E7F0FC', primary: '#1268D5', primaryHover: '#0D58B7', text: '#17191D', secondary: '#5F6672', muted: '#737B88', success: '#277E52', warning: '#9A6400', danger: '#B44250', info: '#4B68B5' },
  radius: { nav: '28px', panel: '24px', card: '18px', control: '14px' },
  spacing: [4, 8, 12, 16, 24, 32, 48] as const,
} as const;

export function StatusMessage({ tone = 'info', title, children }: { tone?: 'info' | 'success' | 'warning' | 'danger'; title: string; children?: ReactNode }) {
  return <section className={`status status-${tone}`} role={tone === 'danger' ? 'alert' : 'status'} aria-live="polite"><strong>{title}</strong>{children && <p>{children}</p>}</section>;
}

export function Button(props: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button {...props} className={`button ${props.className ?? ''}`} />;
}

export function EmptyState({ title, detail, action }: { title: string; detail: string; action?: ReactNode }) {
  return <div className="empty-state"><svg aria-hidden="true" className="empty-mark" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M3 7h6l2 2h10v11H3zM3 7V4h7l2 3h9v2"/></svg><h3>{title}</h3><p>{detail}</p>{action ? <div className="empty-action">{action}</div> : null}</div>;
}
