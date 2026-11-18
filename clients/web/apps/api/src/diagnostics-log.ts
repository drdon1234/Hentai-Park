import { appendFile, mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { isSourceKey } from '@hentai-park/source-contract';

/**
 * Whitelist-only rolling diagnostic logger aligned with lib/core/diagnostics.dart.
 * Never logs credentials, cookies, tokens, request bodies, raw exception messages,
 * work titles/content, local paths, or signed URLs.
 */
export interface DiagnosticEntryInput {
  level: 'info' | 'warn' | 'error';
  event: string;
  source?: string;
  code?: string;
  status?: number;
  durationMs?: number;
  requestId?: string;
  count?: number;
}

export interface DiagnosticLogEntry extends DiagnosticEntryInput {
  at: string;
}

const SAFE_TOKEN = /^[A-Za-z0-9._:-]{1,64}$/;
const MAX_BYTES = 512 * 1024;
const MAX_MEMORY = 300;

export class DiagnosticsLogger {
  private readonly ring: DiagnosticLogEntry[] = [];
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(private readonly filePath?: string) {}

  record(input: DiagnosticEntryInput): void {
    if (!SAFE_TOKEN.test(input.event)) return;
    const entry: DiagnosticLogEntry = {
      at: new Date().toISOString(),
      level: input.level,
      event: input.event,
      ...(input.source && isSourceKey(input.source) ? { source: input.source } : {}),
      ...(input.code && SAFE_TOKEN.test(input.code) ? { code: input.code } : {}),
      ...(typeof input.status === 'number' && Number.isInteger(input.status) && input.status >= 100 && input.status <= 599
        ? { status: input.status }
        : {}),
      ...(typeof input.durationMs === 'number' && Number.isFinite(input.durationMs) && input.durationMs >= 0
        ? { durationMs: Math.round(input.durationMs) }
        : {}),
      ...(input.requestId && SAFE_TOKEN.test(input.requestId) ? { requestId: input.requestId } : {}),
      ...(typeof input.count === 'number' && Number.isInteger(input.count) && input.count >= 0
        ? { count: input.count }
        : {}),
    };
    this.ring.push(entry);
    if (this.ring.length > MAX_MEMORY) this.ring.shift();

    if (this.filePath) {
      const target = this.filePath;
      const line = JSON.stringify(entry) + '\n';
      this.writeQueue = this.writeQueue
        .then(async () => {
          await mkdir(dirname(target), { recursive: true });
          const info = await stat(target).catch(() => null);
          if (info && info.size + Buffer.byteLength(line) > MAX_BYTES) {
            await rename(target, `${target}.1`).catch(() => {});
          }
          await appendFile(target, line, 'utf8');
        })
        .catch(() => {});
    }
  }

  async list(limit = 200): Promise<DiagnosticLogEntry[]> {
    await this.writeQueue;
    const bounded = Math.min(Math.max(1, limit), 500);
    if (!this.filePath) return this.ring.slice(-bounded).reverse();
    try {
      const current = await readFile(this.filePath, 'utf8').catch(() => '');
      const previous = await readFile(`${this.filePath}.1`, 'utf8').catch(() => '');
      const lines = `${previous}\n${current}`
        .split(/\r?\n/)
        .filter(Boolean)
        .slice(-bounded);
      const parsed: DiagnosticLogEntry[] = [];
      for (const line of lines) {
        try {
          const item = JSON.parse(line) as DiagnosticLogEntry;
          if (item && typeof item.at === 'string' && SAFE_TOKEN.test(item.event)) {
            parsed.push(item);
          }
        } catch {
          // Ignore truncated line
        }
      }
      return parsed.reverse();
    } catch {
      return this.ring.slice(-bounded).reverse();
    }
  }

  async clear(): Promise<void> {
    this.ring.length = 0;
    await this.writeQueue;
    if (!this.filePath) return;
    const target = this.filePath;
    this.writeQueue = this.writeQueue
      .then(async () => {
        await writeFile(target, '', 'utf8').catch(() => {});
        await writeFile(`${target}.1`, '', 'utf8').catch(() => {});
      })
      .catch(() => {});
    await this.writeQueue;
  }
}
