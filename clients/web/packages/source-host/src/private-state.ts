import { CookieJar } from 'tough-cookie';
import type { PluginManifest } from '@hentai-park/source-contract';
import { hostAllowed } from './transport-policy.js';

export interface PrivateStateOptions { includeAccounts?: boolean; includeCookies?: boolean; }
const invalid = (message: string, code = 'CONFIG') => Object.assign(new Error(message), { code, retryable: false });

export function validateSourceSettings(manifest: PluginManifest, value: unknown): asserts value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length > 128) throw invalid('invalid private settings');
  for (const [key, selected] of Object.entries(value)) {
    const declaration = manifest.settings?.find(item => item.key === key);
    if (!declaration) throw invalid('unknown source setting');
    const choices = declaration.values ?? declaration.options;
    const scalar = (item: unknown) => typeof item === 'string' && item.length <= 4096 && !/[\u0000-\u001f\u007f]/.test(item)
      || typeof item === 'number' && Number.isFinite(item) || typeof item === 'boolean';
    if (declaration.type === 'switch' ? typeof selected !== 'boolean'
      : declaration.type === 'number' ? typeof selected !== 'number' || !Number.isFinite(selected)
      : declaration.type === 'multi' ? !Array.isArray(selected) || selected.length > 256 || selected.some(item => !scalar(item) || choices?.length && !choices.some(choice => choice.value === item))
      : declaration.type === 'select' ? !scalar(selected) || choices?.length && !choices.some(choice => choice.value === selected)
      : typeof selected !== 'string' || selected.length > 16384 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(selected)) throw invalid('invalid source setting value');
  }
}

/** Pure preparation shared by backup preview, commit, and live private-state import. */
export function validatePrivateState(manifest: PluginManifest, payload: unknown, options: PrivateStateOptions = {}): void {
  let encoded: string;
  try { encoded = JSON.stringify(payload); } catch { throw invalid('invalid private backup'); }
  if (!encoded || Buffer.byteLength(encoded) > 1024 * 1024 || !payload || typeof payload !== 'object' || Array.isArray(payload)) throw invalid('invalid private backup');
  const value = payload as Record<string, unknown>;
  if (value.source !== manifest.key || Object.keys(value).some(key => !['source', 'data', 'settings', 'cookies'].includes(key))) throw invalid('private backup source or fields mismatch');
  if (options.includeAccounts) {
    if (value.data !== undefined && (!value.data || typeof value.data !== 'object' || Array.isArray(value.data))) throw invalid('invalid private data');
    if (value.settings !== undefined) validateSourceSettings(manifest, value.settings);
  }
  if (options.includeCookies && value.cookies !== undefined) {
    let jar: CookieJar;
    try { jar = CookieJar.deserializeSync(value.cookies as Parameters<typeof CookieJar.deserializeSync>[0]); } catch { throw invalid('invalid private cookies'); }
    const cookies = jar.serializeSync()!.cookies;
    if (cookies.length > 1000) throw invalid('too many private cookies');
    for (const cookie of cookies) {
      if (typeof cookie.domain !== 'string' || !hostAllowed(cookie.domain.replace(/^\./, ''), manifest.domains)) throw invalid('private backup contains out of source cookies', 'BLOCKED');
    }
  }
}
