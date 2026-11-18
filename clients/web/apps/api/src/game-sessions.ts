import { createHash, randomBytes } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createGuardedContext } from '@hentai-park/browser-worker';
import { installGameAudio, readGameAudio, startGameAudio } from './game-audio.js';
import type { FastifyReply } from 'fastify';
import { once } from 'node:events';
import type { SourceCatalog } from './catalog.js';
import { contentError, contentObject, contentText, contentUrl } from './content-model.js';

type Guarded = Awaited<ReturnType<typeof createGuardedContext>>;
type Row = Record<string, unknown>;
type Game = {
  id: string;
  owner: string;
  source: string;
  workId: string;
  revision: string;
  storageId: string;
  context: Guarded;
  expires: number;
  controller: AbortController;
  queue: Promise<unknown>;
  pendingInputs: number;
  audioOpen?: boolean;
  commands: Map<string, { fingerprint: string; result: Promise<Row> }>;
};

/** Independent guarded game documents with persistent per-game profile and JSON save import/export. */
export class GameSessions {
  private games = new Map<string, Game>();
  private profiles = new Set<string>();
  private opening = new Map<string, { source: string; owner: string; controller: AbortController }>();
  private timer: ReturnType<typeof setInterval>;

  constructor(
    private readonly catalog: SourceCatalog,
    private readonly directory: string,
  ) {
    this.timer = setInterval(() => {
      for (const game of this.games.values()) {
        if (game.expires < Date.now()) void this.close(game.id).catch(() => {});
      }
    }, 15000);
    this.timer.unref();
  }

  private path(source: string, storageId: string) {
    return resolve(
      this.directory,
      createHash('sha256')
        .update(JSON.stringify([source, storageId]))
        .digest('hex')
        .slice(0, 32),
    );
  }

  async open(source: string, workId: string, owner: string, descriptor: Row, signal?: AbortSignal) {
    if (this.games.size >= 6 || this.profiles.size >= 6) throw contentError('RATE_LIMITED', 429);
    const url = contentUrl(descriptor.url);
    const domains = [new URL(url).hostname, ...((descriptor.navigationDomains as string[]) ?? [])];
    const controller = new AbortController();
    const storageId = contentText(descriptor.storageId, 512);
    const profile = this.path(source, storageId);
    if (this.profiles.has(profile)) {
      // If the same owner already has an open game on this profile, close the stale one first so reopening works cleanly!
      const stale = [...this.games.values()].find((g) => g.owner === owner && this.path(g.source, g.storageId) === profile);
      if (stale) await this.close(stale.id);
      if (this.profiles.has(profile)) throw contentError('CONFLICT', 409);
    }
    this.profiles.add(profile);

    this.opening.set(profile, { source, owner, controller });
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    let guarded: Guarded;
    try {
      await mkdir(profile, { recursive: true });
      guarded = await createGuardedContext({
        domains: [],
        navigationDomains: domains,
        frameDomains: domains,
        resourceDomains: [...domains, ...this.catalog.manifest(source).domains],
        maxResourceBytes: 128 * 1024 * 1024,
        userDataDirectory: profile,
        executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH,
        signal: controller.signal,
      });
      if (controller.signal.aborted) {
        await guarded.close();
        throw contentError('CANCELLED', 499);
      }
    } catch (error) {
      this.opening.delete(profile);
      this.profiles.delete(profile);
      signal?.removeEventListener('abort', abort);
      throw error;
    }
    this.opening.delete(profile);

    const id = randomBytes(24).toString('base64url');
    const game: Game = {
      id,
      owner,
      source,
      workId,
      revision: this.catalog.host.registry.get(source)!.packagePath,
      storageId: String(descriptor.storageId),
      context: guarded,
      expires: Date.now() + 90000,
      controller,
      queue: Promise.resolve(),
      pendingInputs: 0,
      commands: new Map(),
    };
    this.games.set(id, game);

    try {
      await installGameAudio(guarded.context);
      if (descriptor.kind === 'html') {
        await guarded.page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
      } else {
        const player = contentUrl(descriptor.player);
        if (new URL(player).host !== new URL(url).host) throw contentError('BLOCKED', 403);
        await guarded.page.goto(new URL('/', url).href, { waitUntil: 'domcontentloaded', timeout: 25000 });
        const quoted = (v: string) => JSON.stringify(v).replace(/</g, '\\u003c');
        await guarded.page.setContent(
          '<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Flash 游戏</title></head><body style="margin:0;background:#10151f"><div id="game"></div><script>const script=document.createElement("script");script.src=' +
            quoted(player) +
            ';script.onload=()=>{const player=window.RufflePlayer.newest().createPlayer();player.style.width="960px";player.style.height="540px";document.getElementById("game").append(player);player.ruffle().load(' +
            quoted(url) +
            ');};document.head.append(script);</script></body></html>',
          { waitUntil: 'domcontentloaded', timeout: 25000 },
        );
      }
      if (signal?.aborted) throw contentError('CANCELLED', 499);
      return {
        gameId: id,
        frameUrl: `/api/v1/game-sessions/${id}/frame`,
        audioUrl: `/api/v1/game-sessions/${id}/audio`,
        inputUrl: `/api/v1/game-sessions/${id}/input`,
        savesUrl: `/api/v1/game-sessions/${id}/saves`,
        closeUrl: `/api/v1/game-sessions/${id}/close`,
        width: 960,
        height: 540,
      };
    } catch (error) {
      await this.close(id);
      throw error;
    } finally {
      signal?.removeEventListener('abort', abort);
    }
  }

  private get(id: string, owner: string) {
    const game = this.games.get(id);
    if (!game || game.owner !== owner || game.expires < Date.now()) throw contentError('NOT_FOUND', 404);
    const record = this.catalog.host.registry.get(game.source);
    if (!record?.enabled || record.packagePath !== game.revision) {
      void this.close(id);
      throw contentError('CONFIG', 409);
    }
    game.expires = Date.now() + 90000;
    return game;
  }

  async frame(id: string, owner: string) {
    const game = this.get(id, owner);
    return game.context.page.screenshot({ type: 'jpeg', quality: 78, timeout: 10000 });
  }

  async audio(id: string, owner: string, reply: FastifyReply) {
    const game = this.get(id, owner);
    if (game.audioOpen) throw contentError('CONFLICT', 409);
    if (!(await startGameAudio(game.context.page))) throw contentError('UNSUPPORTED', 422);
    game.audioOpen = true;
    reply.hijack();
    const raw = reply.raw;
    const disconnected = new AbortController();
    const closed = () => disconnected.abort();
    const signal = AbortSignal.any([game.controller.signal, disconnected.signal]);
    raw.once('close', closed);
    raw.writeHead(200, {
      'content-type': 'audio/webm; codecs=opus',
      'cache-control': 'private, no-store',
      'x-content-type-options': 'nosniff',
    });
    try {
      while (!raw.destroyed && !signal.aborted) {
        this.get(id, owner);
        const next = await readGameAudio(game.context.page);
        if (!Array.isArray(next.chunks) || next.chunks.length > 64) throw contentError();
        for (const encoded of next.chunks) {
          if (encoded.length > 700000 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw contentError();
          if (!raw.write(Buffer.from(encoded, 'base64'))) await once(raw, 'drain', { signal });
        }
        if (!next.active) break;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    } catch {
      if (!raw.destroyed) raw.destroy();
    } finally {
      game.audioOpen = false;
      raw.removeListener('close', closed);
      if (!raw.destroyed) raw.end();
      if (!game.controller.signal.aborted) await readGameAudio(game.context.page, true).catch(() => {});
    }
  }

  async exportSaves(id: string, owner: string) {
    const game = this.get(id, owner);
    const localStorageData = await game.context.page.evaluate(() => {
      const out: Record<string, string> = {};
      try {
        for (let i = 0; i < window.localStorage.length; i++) {
          const k = window.localStorage.key(i);
          if (k !== null) out[k] = window.localStorage.getItem(k) ?? '';
        }
      } catch {
        // Sandboxed origin without localStorage
      }
      return out;
    });
    return {
      format: 'hentai-park-game-save',
      version: 1,
      source: game.source,
      workId: game.workId,
      storageId: game.storageId,
      exportedAt: new Date().toISOString(),
      localStorage: localStorageData,
    };
  }

  async importSaves(id: string, owner: string, payload: Row) {
    const game = this.get(id, owner);
    const entries = contentObject(payload.localStorage ?? payload);
    if (Object.keys(entries).length > 2000 || Buffer.byteLength(JSON.stringify(entries)) > 16 * 1024 * 1024) {
      throw contentError('BAD_REQUEST', 400);
    }
    const sanitized: Record<string, string> = {};
    for (const [k, v] of Object.entries(entries)) {
      if (typeof k !== 'string' || k.length > 512 || typeof v !== 'string' || v.length > 8 * 1024 * 1024) {
        throw contentError('BAD_REQUEST', 400);
      }
      sanitized[k] = v;
    }
    const count = await game.context.page.evaluate((data) => {
      let written = 0;
      for (const [k, v] of Object.entries(data)) {
        window.localStorage.setItem(k, v);
        written++;
      }
      return written;
    }, sanitized);
    if (payload.reload === true) {
      await game.context.page.reload({ waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {});
    }
    return { imported: true, keys: count };
  }

  input(id: string, owner: string, input: Row) {
    const game = this.get(id, owner);
    const key = contentText(input.requestKey, 128);
    const fingerprint = JSON.stringify(input);
    const prior = game.commands.get(key);
    if (prior) {
      if (prior.fingerprint !== fingerprint) throw contentError('CONFLICT', 409);
      return prior.result;
    }
    const action = String(input.action);
    if (!['click', 'pointerDown', 'pointerUp', 'pointerMove', 'keyDown', 'keyUp', 'keyPress', 'wheel'].includes(action)) {
      throw contentError('BAD_REQUEST', 400);
    }
    const x = Number(input.x);
    const y = Number(input.y);
    const button = input.button === undefined ? 'left' : String(input.button);
    if (action.startsWith('pointer') || action === 'click') {
      if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 960 || y < 0 || y > 540 || !['left', 'right', 'middle'].includes(button)) {
        throw contentError('BAD_REQUEST', 400);
      }
    }
    const keyName = String(input.key ?? '');
    if (
      action.startsWith('key') &&
      !/^(?:[a-zA-Z0-9]|ArrowLeft|ArrowRight|ArrowUp|ArrowDown|Space|Enter|Escape|Tab|Shift|Control|Alt|Backspace|Delete|Home|End|PageUp|PageDown|F[1-9]|F1[0-2])$/.test(
        keyName,
      )
    ) {
      throw contentError('BAD_REQUEST', 400);
    }
    const dx = Number(input.deltaX ?? 0);
    const dy = Number(input.deltaY ?? 0);
    if (action === 'wheel' && (!Number.isFinite(dx) || !Number.isFinite(dy) || Math.abs(dx) > 2000 || Math.abs(dy) > 2000)) {
      throw contentError('BAD_REQUEST', 400);
    }
    if (game.pendingInputs >= 128) throw contentError('RATE_LIMITED', 429);
    game.pendingInputs++;
    const result = game.queue
      .catch(() => {})
      .then(async () => {
        if (game.controller.signal.aborted) throw contentError('CANCELLED', 499);
        const page = game.context.page;
        if (action === 'click') await page.mouse.click(x, y, { button: button as 'left' | 'right' | 'middle' });
        if (action.startsWith('pointer')) {
          await page.mouse.move(x, y);
          if (action === 'pointerDown') await page.mouse.down({ button: button as 'left' | 'right' | 'middle' });
          if (action === 'pointerUp') await page.mouse.up({ button: button as 'left' | 'right' | 'middle' });
        }
        if (action === 'keyDown') await page.keyboard.down(keyName);
        if (action === 'keyUp') await page.keyboard.up(keyName);
        if (action === 'keyPress') await page.keyboard.press(keyName);
        if (action === 'wheel') await page.mouse.wheel(dx, dy);
        return { accepted: true };
      })
      .finally(() => {
        game.pendingInputs--;
      });
    game.queue = result;
    game.commands.set(key, { fingerprint, result });
    if (game.commands.size > 256) game.commands.delete(game.commands.keys().next().value!);
    return result;
  }

  async close(id: string) {
    const game = this.games.get(id);
    if (!game) return;
    this.games.delete(id);
    const closing = game.context.close();
    game.controller.abort();
    try {
      await closing;
    } finally {
      this.profiles.delete(this.path(game.source, game.storageId));
    }
  }

  async closeOwned(id: string, owner: string) {
    this.get(id, owner);
    await this.close(id);
  }

  async revoke(owner: string) {
    for (const pending of this.opening.values()) if (pending.owner === owner) pending.controller.abort();
    await Promise.all([...this.games.values()].filter((g) => g.owner === owner).map((g) => this.close(g.id)));
  }

  async revokeSource(source: string) {
    for (const pending of this.opening.values()) if (pending.source === source) pending.controller.abort();
    await Promise.all([...this.games.values()].filter((game) => game.source === source).map((game) => this.close(game.id)));
  }

  async closeAll() {
    clearInterval(this.timer);
    for (const pending of this.opening.values()) pending.controller.abort();
    await Promise.all([...this.games.keys()].map((id) => this.close(id)));
  }
}
