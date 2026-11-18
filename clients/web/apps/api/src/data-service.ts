import type { DatabaseSync } from 'node:sqlite';
import { createHash, randomUUID } from 'node:crypto';
import {
  closeSync,
  createReadStream,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { realpath } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve } from 'node:path';
import type { FastifyInstance } from 'fastify';
import {
  buildComicInfoXml,
  createArchive,
  createCbz,
  createComicPdf,
  imageExtension,
  readCbzWithMetadata,
  type ComicInfoMetadata,
  type ImageFile,
} from './comic-transfer.js';

type Row = Record<string, unknown>;

const fail = (code = 'BAD_REQUEST', statusCode = 400) =>
  Object.assign(new Error(code), { code, statusCode, publicError: true, causeCategory: 'validation' });
const text = (value: unknown, max = 512) => {
  if (typeof value !== 'string' || !value || value.length > max || /[\u0000-\u001f]/.test(value)) throw fail();
  return value;
};

function sanitizeFilename(input: string, fallback = 'comic'): string {
  const cleaned = input.replace(/[<>:"/\\|?*\u0000-\u001f]+/g, '_').trim().slice(0, 120);
  return cleaned || fallback;
}

function localManifest(input: string, files: Row[], taskId: string) {
  if (!input.startsWith('#EXTM3U')) throw fail('INVALID_OFFLINE_MANIFEST', 409);
  const resource = (name: string) => {
    if (!/^\d{6}\.(?:bin|m3u8)$/.test(name)) throw fail('BLOCKED', 403);
    const found = files.find((row) => String(row.path).replaceAll('\\', '/').endsWith('/' + name));
    if (!found) throw fail('NOT_FOUND', 404);
    return '/api/v1/offline/' + encodeURIComponent(taskId) + '/files/' + found.id;
  };
  return input
    .split(/\r?\n/)
    .map((raw) => {
      const line = raw.trim();
      if (!line) return '';
      if (!line.startsWith('#')) return resource(line);
      if (/URI=/i.test(line)) {
        if (!/^#EXT-X-(?:KEY|MAP|MEDIA):/.test(line)) throw fail('BLOCKED', 403);
        let count = 0;
        const rewritten = line.replace(/URI="([^"]+)"/g, (_, name: string) => {
          count++;
          return 'URI="' + resource(name) + '"';
        });
        if (count !== 1 || /URI=/gi.test(rewritten.replace(/URI="[^"]+"/, ''))) throw fail('BLOCKED', 403);
        return rewritten;
      }
      return line;
    })
    .join('\n');
}

export function markContentRead(db: DatabaseSync, ids: string[]) {
  if (!Array.isArray(ids) || !ids.length || ids.length > 500) throw fail();
  const now = new Date().toISOString();
  db.exec('SAVEPOINT content_read');
  try {
    for (const id of ids) {
      text(id);
      if (!db.prepare('SELECT 1 FROM subscription_events WHERE event_id=?').get(id)) throw fail('NOT_FOUND', 404);
      db.prepare('INSERT OR IGNORE INTO event_read_states VALUES(?,?)').run(id, now);
    }
    db.exec('RELEASE content_read');
  } catch (error) {
    db.exec('ROLLBACK TO content_read;RELEASE content_read');
    throw error;
  }
  return { eventIds: ids, readAt: now };
}

export function subscriptionUnread(db: DatabaseSync) {
  const ids = db
    .prepare(
      'SELECT se.event_id FROM subscription_events se LEFT JOIN event_read_states rs ON rs.event_id=se.event_id WHERE rs.event_id IS NULL ORDER BY observed_at',
    )
    .all()
    .map((row) => String(row.event_id));
  return { unreadCount: ids.length, unreadEventIds: ids.slice(0, 500) };
}

function dataMutation(
  db: DatabaseSync,
  request: { url: string; body: unknown; headers: Record<string, unknown> },
  action: () => unknown,
) {
  const body = request.body && typeof request.body === 'object' && !Buffer.isBuffer(request.body) ? (request.body as Row) : undefined;
  const key = text(body?.requestKey ?? request.headers['idempotency-key'], 128);
  const operation = request.url.split('?')[0]!;
  const fingerprint = Buffer.isBuffer(request.body)
    ? createHash('sha256').update(request.body).digest('hex')
    : createHash('sha256').update(JSON.stringify(body ?? {})).digest('hex');
  db.exec('SAVEPOINT data_mutation');
  try {
    const prior = db.prepare('SELECT * FROM idempotency_records WHERE operation=? AND request_key=?').get(operation, key);
    if (prior) {
      if (prior.request_fingerprint !== fingerprint) throw fail('CONFLICT', 409);
      db.exec('RELEASE data_mutation');
      return JSON.parse(String(prior.response_json));
    }
    const result = action();
    const now = new Date().toISOString();
    const sequence = Number(db.prepare('SELECT COALESCE(MAX(sequence),0)+1 AS n FROM domain_events').get()!.n);
    const eventId = randomUUID();
    const eventVersion = Number(
      db
        .prepare(
          "SELECT COALESCE(MAX(event_version),0)+1 AS n FROM domain_events WHERE aggregate_type='collection' AND aggregate_id='library-management'",
        )
        .get()!.n,
    );
    db.prepare(
      "INSERT INTO domain_events VALUES(?,?,'collection.changed','collection','library-management',?,?,?,?)",
    ).run(eventId, sequence, eventVersion, eventVersion, now, JSON.stringify({ operation }));
    db.prepare('INSERT INTO event_outbox(event_id) VALUES(?)').run(eventId);
    db.prepare('INSERT INTO idempotency_records VALUES(?,?,?,?,?,?)').run(
      operation,
      key,
      fingerprint,
      200,
      JSON.stringify(result),
      now,
    );
    db.exec('RELEASE data_mutation');
    return result;
  } catch (error) {
    db.exec('ROLLBACK TO data_mutation;RELEASE data_mutation');
    throw error;
  }
}

function workComicMetadata(db: DatabaseSync, source: string, workId: string, chapterId?: string): ComicInfoMetadata {
  const work = db.prepare('SELECT * FROM works WHERE source=? AND work_id=?').get(source, workId) as Row | undefined;
  const chapter = chapterId
    ? (db.prepare('SELECT * FROM chapters WHERE source=? AND work_id=? AND chapter_id=?').get(source, workId, chapterId) as Row | undefined)
    : undefined;
  const meta = work?.metadata_json ? (JSON.parse(String(work.metadata_json)) as Row) : {};
  const authors = Array.isArray(meta.authors)
    ? meta.authors.filter((a): a is string => typeof a === 'string').join(', ')
    : typeof meta.author === 'string'
      ? meta.author
      : undefined;
  const tags = Array.isArray(meta.tags)
    ? meta.tags
        .map((t) => (typeof t === 'string' ? t : t && typeof t === 'object' ? String((t as Row).label ?? (t as Row).name ?? '') : ''))
        .filter(Boolean)
        .slice(0, 64)
        .join(', ')
    : undefined;
  return {
    title: chapter?.title ? String(chapter.title) : work?.title ? String(work.title) : workId,
    series: work?.title ? String(work.title) : undefined,
    number: chapter?.sort !== undefined ? String(Number(chapter.sort) + 1) : undefined,
    summary: work?.summary ? String(work.summary) : undefined,
    writer: authors,
    genre: tags,
    web: work?.source_url && !String(work.source_url).includes('local.invalid') ? String(work.source_url) : undefined,
  };
}

export function registerDataRoutes(router: FastifyInstance, options: { db: DatabaseSync; downloadDir: string }) {
  const db = options.db;
  const mutate = (action: (request: any) => unknown) => (request: any) =>
    dataMutation(db, request, () => action(request));

  // Accept raw binary archive uploads for zero-Base64 .cbz / .parkbak import
  router.addContentTypeParser(
    ['application/vnd.comicbook+zip', 'application/zip', 'application/octet-stream', 'application/gzip'],
    { parseAs: 'buffer', bodyLimit: 256 * 1024 * 1024 },
    (_req, body, done) => done(null, body),
  );

  // Legacy client-rendered export (preserved for transformed/unscrambled comic pages when needed)
  router.post('/data-transfer/export', { bodyLimit: 180 * 1024 * 1024 }, async (request, reply) => {
    const body = request.body as Row;
    if (!Array.isArray(body?.pages) || !body.pages.length || body.pages.length > 1000) throw fail();
    let total = 0;
    const images = body.pages.map((value) => {
      const encoded = text(value, 28 * 1024 * 1024);
      if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw fail();
      const bytes = Buffer.from(encoded, 'base64');
      if (bytes.length > 20 * 1024 * 1024 || (total += bytes.length) > 128 * 1024 * 1024) throw fail();
      return bytes;
    });
    if (!['cbz', 'pdf'].includes(String(body.format))) throw fail();
    const meta: ComicInfoMetadata | undefined =
      typeof body.title === 'string' ? { title: body.title.slice(0, 512) } : undefined;
    const row = db.prepare('SELECT value_json FROM app_settings WHERE key=?').get('pdfPagesPerFile');
    const limit = row ? Number(JSON.parse(String(row.value_json))) : 300;
    if (body.format === 'pdf' && limit > 0 && images.length > limit) {
      const files = [];
      for (let i = 0; i < images.length; i += limit) {
        files.push({
          name: 'comic-' + String(files.length + 1).padStart(3, '0') + '.pdf',
          bytes: createComicPdf(images.slice(i, i + limit)),
        });
      }
      return reply
        .type('application/zip')
        .header('content-disposition', 'attachment; filename="comic-pdf.zip"')
        .send(createArchive(files));
    }
    const bytes = body.format === 'pdf' ? createComicPdf(images) : createCbz(images, meta);
    return reply
      .type(body.format === 'pdf' ? 'application/pdf' : 'application/vnd.comicbook+zip')
      .header('content-disposition', 'attachment; filename="comic.' + body.format + '"')
      .send(bytes);
  });

  // Server-side zero-reencode lossless export directly from downloaded task files!
  router.get('/downloads/:taskId/export', async (request, reply) => {
    const p = request.params as Row;
    const q = (request.query ?? {}) as Row;
    const taskId = text(p.taskId, 4096);
    const format = String(q.format ?? 'cbz').toLowerCase();
    if (!['cbz', 'pdf', 'raw'].includes(format)) throw fail('BAD_REQUEST', 400);

    const task = db.prepare("SELECT * FROM download_tasks WHERE task_id=? AND status='completed'").get(taskId) as Row | undefined;
    if (!task) throw fail('NOT_FOUND', 404);
    const files = db.prepare("SELECT * FROM download_files WHERE task_id=? AND status='completed' ORDER BY id").all(taskId) as Row[];
    files.sort((a, b) => Number(String(a.resource_key).split(':').at(-1)) - Number(String(b.resource_key).split(':').at(-1)));
    if (!files.length) throw fail('NOT_FOUND', 404);

    const root = await realpath(options.downloadDir);
    const verifiedPaths: Array<{ path: string; meta: Row; bytesCount: number }> = [];
    for (const file of files) {
      if (!file.path || !existsSync(String(file.path))) throw fail('NOT_FOUND', 404);
      const actual = await realpath(String(file.path));
      const rel = relative(root, actual);
      if (rel.startsWith('..') || isAbsolute(rel)) throw fail('BLOCKED', 403);
      const size = statSync(actual).size;
      if (size !== Number(file.bytes)) throw fail('OFFLINE_FILE_CHANGED', 409);
      verifiedPaths.push({ path: actual, meta: JSON.parse(String(file.metadata_json ?? '{}')), bytesCount: size });
    }

    const comicMeta = workComicMetadata(db, String(task.source), String(task.work_id), String(task.chapter_id));
    const baseName = sanitizeFilename(
      comicMeta.series && comicMeta.title && comicMeta.series !== comicMeta.title
        ? `${comicMeta.series} - ${comicMeta.title}`
        : (comicMeta.title ?? String(task.work_id)),
    );

    if (format === 'raw') {
      const single = verifiedPaths.find((f) => ['video', 'audio', 'novel', 'script', 'attachment'].includes(String(f.meta.kind))) ?? verifiedPaths[0]!;
      if (verifiedPaths.length === 1) {
        const ext =
          single.meta.kind === 'video'
            ? 'mp4'
            : single.meta.kind === 'audio'
              ? String(single.meta.format ?? 'mp3')
              : single.meta.kind === 'novel'
                ? 'txt'
                : 'bin';
        if (single.meta.kind === 'novel') {
          const parsed = JSON.parse(readFileSync(single.path, 'utf8')) as { title?: string; paragraphs?: string[] };
          const plain = [parsed.title ?? '', ...(parsed.paragraphs ?? [])].filter(Boolean).join('\n\n');
          return reply
            .type('text/plain; charset=utf-8')
            .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.txt')}`)
            .send(plain);
        }
        return reply
          .type('application/octet-stream')
          .header('content-length', single.bytesCount)
          .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.' + ext)}`)
          .send(createReadStream(single.path));
      }
      // Multiple raw files (e.g. HLS or image folder) -> archive as .zip
      const archiveFiles: ImageFile[] = verifiedPaths.map((f, idx) => ({
        name: `${String(idx + 1).padStart(6, '0')}.${f.meta.kind === 'manifest' || f.meta.kind === 'child-manifest' ? 'm3u8' : f.meta.kind === 'image' ? imageExtension(readFileSync(f.path)) : 'bin'}`,
        bytes: readFileSync(f.path),
      }));
      return reply
        .type('application/zip')
        .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.zip')}`)
        .send(createArchive(archiveFiles));
    }

    const imageBuffers = verifiedPaths
      .filter((f) => f.meta.kind === 'image')
      .map((f) => readFileSync(f.path));
    if (!imageBuffers.length) throw fail('UNSUPPORTED', 422);

    if (format === 'cbz') {
      const cbz = createCbz(imageBuffers, comicMeta);
      return reply
        .type('application/vnd.comicbook+zip')
        .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.cbz')}`)
        .send(cbz);
    }

    // Server-side PDF export (supports JPEG & PNG natively; falls back to CBZ error if WebP/GIF)
    try {
      const row = db.prepare('SELECT value_json FROM app_settings WHERE key=?').get('pdfPagesPerFile');
      const limit = row ? Number(JSON.parse(String(row.value_json))) : 300;
      if (limit > 0 && imageBuffers.length > limit) {
        const volumes: ImageFile[] = [];
        for (let i = 0; i < imageBuffers.length; i += limit) {
          volumes.push({
            name: `${baseName}-${String(volumes.length + 1).padStart(3, '0')}.pdf`,
            bytes: createComicPdf(imageBuffers.slice(i, i + limit)),
          });
        }
        return reply
          .type('application/zip')
          .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '-pdf.zip')}`)
          .send(createArchive(volumes));
      }
      const pdf = createComicPdf(imageBuffers);
      return reply
        .type('application/pdf')
        .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.pdf')}`)
        .send(pdf);
    } catch {
      throw fail('PDF_REQUIRES_CLIENT_TRANSCODE', 422);
    }
  });

  // Multi-chapter whole-work CBZ export!
  router.get('/works/:source/:workId/export', async (request, reply) => {
    const p = request.params as Row;
    const source = text(p.source, 100);
    const workId = text(p.workId, 512);
    const tasks = db
      .prepare(
        "SELECT t.*, COALESCE(c.sort, 0) AS chapter_sort, COALESCE(c.title, t.chapter_id) AS chapter_title FROM download_tasks t LEFT JOIN chapters c ON c.source=t.source AND c.work_id=t.work_id AND c.chapter_id=t.chapter_id WHERE t.source=? AND t.work_id=? AND t.status='completed' ORDER BY chapter_sort, t.created_at",
      )
      .all(source, workId) as Row[];
    if (!tasks.length) throw fail('NOT_FOUND', 404);
    const root = await realpath(options.downloadDir);
    const archiveEntries: ImageFile[] = [];
    let totalBytes = 0;
    for (const [cIdx, task] of tasks.entries()) {
      const files = db
        .prepare("SELECT * FROM download_files WHERE task_id=? AND status='completed' ORDER BY id")
        .all(String(task.task_id)) as Row[];
      files.sort((a, b) => Number(String(a.resource_key).split(':').at(-1)) - Number(String(b.resource_key).split(':').at(-1)));
      const prefix = tasks.length > 1 ? `${String(cIdx + 1).padStart(3, '0')}-${sanitizeFilename(String(task.chapter_title), 'ch')}/` : '';
      let pIdx = 0;
      for (const file of files) {
        const meta = JSON.parse(String(file.metadata_json ?? '{}'));
        if (meta.kind !== 'image' || !file.path || !existsSync(String(file.path))) continue;
        const actual = await realpath(String(file.path));
        const rel = relative(root, actual);
        if (rel.startsWith('..') || isAbsolute(rel)) throw fail('BLOCKED', 403);
        const bytes = readFileSync(actual);
        totalBytes += bytes.length;
        if (totalBytes > 512 * 1024 * 1024) throw fail('RESOURCE_LIMIT', 413);
        archiveEntries.push({
          name: `${prefix}${String(++pIdx).padStart(6, '0')}.${imageExtension(bytes)}`,
          bytes,
        });
      }
    }
    if (!archiveEntries.length) throw fail('UNSUPPORTED', 422);
    const meta = workComicMetadata(db, source, workId);
    archiveEntries.unshift({
      name: 'ComicInfo.xml',
      bytes: buildComicInfoXml({ ...meta, pageCount: archiveEntries.length }),
    });
    const baseName = sanitizeFilename(meta.series ?? meta.title ?? workId);
    return reply
      .type('application/vnd.comicbook+zip')
      .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(baseName + '.cbz')}`)
      .send(createArchive(archiveEntries));
  });

  // CBZ import supporting both binary Buffer upload and JSON contentBase64, parsing ComicInfo.xml & cover!
  router.post(
    '/data-transfer/import-cbz',
    { bodyLimit: 256 * 1024 * 1024 },
    mutate((request) => {
      let archive: Buffer;
      let explicitTitle: string | undefined;
      if (Buffer.isBuffer(request.body)) {
        archive = request.body;
        const rawHeaderTitle = request.headers['x-comic-title'];
        if (typeof rawHeaderTitle === 'string' && rawHeaderTitle) {
          try {
            explicitTitle = decodeURIComponent(rawHeaderTitle).slice(0, 2048);
          } catch {
            explicitTitle = rawHeaderTitle.slice(0, 2048);
          }
        }
      } else {
        const body = request.body as Row;
        const encoded = text(body?.contentBase64, 256 * 1024 * 1024);
        if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw fail();
        archive = Buffer.from(encoded, 'base64');
        if (typeof body.title === 'string' && body.title) explicitTitle = text(body.title, 2048);
      }

      const { files, metadata: comicInfo } = readCbzWithMetadata(archive);
      const id = createHash('sha256').update(archive).digest('hex');
      const source = '_local';
      const resourceKey = 'download:' + JSON.stringify([source, id, '_', 'original']);
      const taskId = resourceKey;
      const existing = db.prepare('SELECT task_id FROM download_tasks WHERE task_id=?').get(taskId);
      if (existing) return { taskId, workId: id, source };

      const root = resolve(options.downloadDir);
      const folder = resolve(root, createHash('sha256').update(taskId).digest('hex'));
      if (relative(root, folder).startsWith('..') || folder === root) throw fail('BLOCKED', 403);
      mkdirSync(root, { recursive: true });
      mkdirSync(folder, { recursive: true });

      try {
        const now = new Date().toISOString();
        const title = explicitTitle || comicInfo?.title || comicInfo?.series || '本地漫画';
        const summary = comicInfo?.summary ?? null;
        const workMeta: Row = {};
        if (comicInfo?.writer) {
          workMeta.authors = comicInfo.writer.split(',').map((s) => s.trim()).filter(Boolean);
        }
        if (comicInfo?.genre) {
          workMeta.tags = comicInfo.genre
            .split(',')
            .map((s) => s.trim())
            .filter(Boolean)
            .map((label) => ({ label, source }));
        }
        const hasSha256Col = db
          .prepare('PRAGMA table_info(download_files)')
          .all()
          .some((col) => (col as { name?: string }).name === 'sha256');

        db.prepare(
          'INSERT INTO works(source,work_id,title,summary,media_kind,category,source_url,capability_json,updated_at,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?)',
        ).run(
          source,
          id,
          title,
          summary,
          'comic',
          'other',
          'https://local.invalid/' + id,
          JSON.stringify({ chapter: true, detail: true }),
          now,
          JSON.stringify(workMeta),
        );
        db.prepare('INSERT INTO chapters(source,work_id,chapter_id,title,sort) VALUES(?,?,?,?,0)').run(
          source,
          id,
          '_',
          title,
        );
        db.prepare(
          "INSERT INTO download_tasks(task_id,source,work_id,chapter_id,variant,resource_key,idempotency_key,status,completed_count,total_count,bytes,created_at,updated_at) VALUES(?,?,?,'_','original',?,?,'completed',?,?,?,?,?)",
        ).run(
          taskId,
          source,
          id,
          resourceKey,
          randomUUID(),
          files.length,
          files.length,
          files.reduce((n, file) => n + file.bytes.length, 0),
          now,
          now,
        );
        const hashes: Row = {};
        files.forEach((file, index) => {
          const path = join(folder, String(index).padStart(6, '0') + '.bin');
          const key = resourceKey + ':file:' + index;
          const digest = createHash('sha256').update(file.bytes).digest('hex');
          writeFileSync(path, file.bytes, { flag: 'wx' });
          hashes[key] = digest;
          if (hasSha256Col) {
            db.prepare(
              "INSERT INTO download_files(task_id,resource_key,path,status,bytes,created_at,updated_at,metadata_json,sha256) VALUES(?,?,?,'completed',?,?,?,?,?)",
            ).run(taskId, key, path, file.bytes.length, now, now, JSON.stringify({ kind: 'image' }), digest);
          } else {
            db.prepare(
              "INSERT INTO download_files(task_id,resource_key,path,status,bytes,created_at,updated_at,metadata_json) VALUES(?,?,?,'completed',?,?,?,?)",
            ).run(taskId, key, path, file.bytes.length, now, now, JSON.stringify({ kind: 'image' }));
          }
        });
        db.prepare('INSERT INTO restore_checkpoints(task_id,checkpoint_json,updated_at) VALUES(?,?,?)').run(
          taskId,
          JSON.stringify({ hashes }),
          now,
        );
        return { taskId, workId: id, source, title, pageCount: files.length };
      } catch (error) {
        rmSync(folder, { recursive: true, force: true });
        throw error;
      }
    }),
  );

  router.get('/categories', async () => ({ items: db.prepare('SELECT * FROM categories ORDER BY sort,id').all() }));
  router.post(
    '/categories',
    mutate((request) => {
      const body = request.body as Row;
      const name = text(body?.name, 128).trim();
      if (!name) throw fail();
      const now = new Date().toISOString();
      const id = randomUUID();
      db.prepare(
        'INSERT INTO categories(id,name,sort,created_at,updated_at) VALUES(?,?,(SELECT COALESCE(MAX(sort),0)+1 FROM categories),?,?)',
      ).run(id, name, now, now);
      return db.prepare('SELECT * FROM categories WHERE id=?').get(id);
    }),
  );
  router.patch(
    '/categories/:id',
    mutate((request) => {
      const id = text((request.params as Row).id);
      const body = request.body as Row;
      const current = db.prepare('SELECT * FROM categories WHERE id=?').get(id);
      if (!current) throw fail('NOT_FOUND', 404);
      if (body.version !== current.version) throw fail('CONFLICT', 409);
      const name = body.name === undefined ? String(current.name) : text(body.name, 128).trim();
      const sort = body.sort === undefined ? Number(current.sort) : Number(body.sort);
      if (!name || !Number.isFinite(sort)) throw fail();
      db.prepare('UPDATE categories SET name=?,sort=?,updated_at=?,version=version+1 WHERE id=?').run(
        name,
        sort,
        new Date().toISOString(),
        id,
      );
      return db.prepare('SELECT * FROM categories WHERE id=?').get(id);
    }),
  );
  router.delete(
    '/categories/:id',
    mutate((request) => {
      const id = text((request.params as Row).id);
      const current = db.prepare('SELECT version FROM categories WHERE id=?').get(id);
      if (!current) throw fail('NOT_FOUND', 404);
      if ((request.body as Row)?.version !== current.version) throw fail('CONFLICT', 409);
      db.exec('SAVEPOINT category_delete');
      try {
        for (const row of db.prepare('SELECT source,work_id,category_ids_json FROM work_collections').all()) {
          const ids = JSON.parse(String(row.category_ids_json)) as string[];
          if (ids.includes(id)) {
            db.prepare(
              'UPDATE work_collections SET category_ids_json=?,version=version+1,updated_at=? WHERE source=? AND work_id=?',
            ).run(
              JSON.stringify(ids.filter((value) => value !== id)),
              new Date().toISOString(),
              row.source,
              row.work_id,
            );
          }
        }
        db.prepare('DELETE FROM categories WHERE id=?').run(id);
        db.exec('RELEASE category_delete');
      } catch (error) {
        db.exec('ROLLBACK TO category_delete;RELEASE category_delete');
        throw error;
      }
      return { deleted: true };
    }),
  );
  router.delete(
    '/history',
    mutate((request) => {
      const body = request.body as Row;
      if (!body || (!Array.isArray(body.scopeKeys) && body.before === undefined && body.all !== true)) throw fail();
      if (Array.isArray(body.scopeKeys)) {
        if (body.scopeKeys.length > 1000) throw fail();
        for (const id of body.scopeKeys) db.prepare('DELETE FROM history WHERE scope_key=?').run(text(id, 4096));
      } else if (body.before !== undefined) {
        const before = text(body.before);
        if (!Number.isFinite(Date.parse(before))) throw fail();
        db.prepare('DELETE FROM history WHERE updated_at<?').run(before);
      } else db.prepare('DELETE FROM history').run();
      return { deleted: true };
    }),
  );

  // Batch target lookup instead of 500x N+1 SQL queries!
  router.get('/subscription-events', async () => {
    const rows = db
      .prepare(
        'SELECT se.*,CASE WHEN rs.event_id IS NULL THEN 1 ELSE 0 END AS unread FROM subscription_events se LEFT JOIN event_read_states rs ON rs.event_id=se.event_id ORDER BY observed_at DESC LIMIT 500',
      )
      .all() as Row[];
    const targetsByEvent = new Map<string, string[]>();
    if (rows.length) {
      const ids = rows.map((r) => String(r.event_id));
      const placeholders = ids.map(() => '?').join(',');
      const targetRows = db
        .prepare(`SELECT event_id, subscription_id FROM subscription_event_targets WHERE event_id IN (${placeholders})`)
        .all(...ids) as Row[];
      for (const tr of targetRows) {
        const eid = String(tr.event_id);
        const list = targetsByEvent.get(eid) ?? [];
        list.push(String(tr.subscription_id));
        targetsByEvent.set(eid, list);
      }
    }
    return {
      items: rows.map((row) => ({
        ...row,
        ...JSON.parse(String(row.payload_json ?? '{}')),
        targets: targetsByEvent.get(String(row.event_id)) ?? [],
      })),
    };
  });

  router.get('/novel-notes/:source/:workId/:chapterId', async (request) => {
    const p = request.params as Row;
    return {
      items: db
        .prepare('SELECT * FROM novel_notes WHERE source=? AND work_id=? AND chapter_id=? ORDER BY offset')
        .all(text(p.source), text(p.workId), text(p.chapterId)),
    };
  });
  router.post(
    '/novel-notes/:source/:workId/:chapterId',
    mutate((request) => {
      const p = request.params as Row;
      const b = request.body as Row;
      const start = Number(b.offset);
      const end = Number(b.endOffset ?? start);
      if (
        !Number.isSafeInteger(start) ||
        start < 0 ||
        !Number.isSafeInteger(end) ||
        end < start ||
        typeof b.quote !== 'string' ||
        b.quote.length > 20000 ||
        typeof b.note !== 'string' ||
        b.note.length > 20000
      ) {
        throw fail();
      }
      const chapter = db
        .prepare(
          'SELECT c.node_metadata_json,w.media_kind FROM chapters c JOIN works w ON w.source=c.source AND w.work_id=c.work_id WHERE c.source=? AND c.work_id=? AND c.chapter_id=?',
        )
        .get(text(p.source), text(p.workId), text(p.chapterId));
      if (!chapter) throw fail('NOT_FOUND', 404);
      const length = Number(JSON.parse(String(chapter.node_metadata_json ?? '{}')).textLength);
      if (chapter.media_kind !== 'novel' || !Number.isSafeInteger(length) || end > length) throw fail();
      const id = randomUUID();
      const now = new Date().toISOString();
      db.prepare(
        'INSERT INTO novel_notes(id,source,work_id,chapter_id,offset,end_offset,quote,note,bookmark,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
      ).run(id, text(p.source), text(p.workId), text(p.chapterId), start, end, b.quote, b.note, b.bookmark === true ? 1 : 0, now);
      return db.prepare('SELECT * FROM novel_notes WHERE id=?').get(id) ?? { id };
    }),
  );
  router.delete(
    '/novel-notes/:id',
    mutate((request) => {
      const id = text((request.params as Row).id);
      const existing = db.prepare('SELECT version FROM novel_notes WHERE id=?').get(id);
      if (!existing) throw fail('NOT_FOUND', 404);
      if ((request.body as Row)?.version !== undefined && (request.body as Row)?.version !== existing.version) {
        throw fail('CONFLICT', 409);
      }
      db.prepare('DELETE FROM novel_notes WHERE id=?').run(id);
      return { deleted: true };
    }),
  );

  router.get('/offline/:taskId', async (request) => {
    const id = text((request.params as Row).taskId, 4096);
    const allowIncomplete = ((request.query ?? {}) as Row).allowIncomplete === 'true';
    const task = db
      .prepare(
        allowIncomplete
          ? "SELECT * FROM download_tasks WHERE task_id=? AND status IN ('completed','running','paused','queued')"
          : "SELECT * FROM download_tasks WHERE task_id=? AND status='completed'",
      )
      .get(id);
    if (!task) throw fail('NOT_FOUND', 404);
    const files = db
      .prepare("SELECT * FROM download_files WHERE task_id=? AND status='completed' ORDER BY id")
      .all(id);
    files.sort(
      (a, b) => Number(String(a.resource_key).split(':').at(-1)) - Number(String(b.resource_key).split(':').at(-1)),
    );
    if (!files.length || files.some((file) => !file.path || !existsSync(String(file.path)))) {
      throw fail('NOT_FOUND', 404);
    }
    const entries: Array<Row & { metadata: Row; url: string }> = files.map((file) => ({
      ...file,
      metadata: JSON.parse(String(file.metadata_json)),
      url: '/api/v1/offline/' + encodeURIComponent(id) + '/files/' + file.id + (allowIncomplete ? '?allowIncomplete=true' : ''),
    }));
    const root = await realpath(options.downloadDir);
    for (const file of entries) {
      const actual = await realpath(String(file.path));
      const rel = relative(root, actual);
      if (rel.startsWith('..') || isAbsolute(rel)) throw fail('BLOCKED', 403);
      if (statSync(actual).size !== Number(file.bytes)) throw fail('OFFLINE_FILE_CHANGED', 409);
    }
    const articleEntries = entries
      .filter((file) => Number.isSafeInteger(file.metadata.blockIndex) && Number(file.metadata.blockIndex) >= 0)
      .sort((a, b) => Number(a.metadata.blockIndex) - Number(b.metadata.blockIndex));
    if (articleEntries.length) {
      const blocks = articleEntries.map((file) => {
        if (file.metadata.kind === 'script') {
          if (Number(file.bytes) > 4_000_000) throw fail('RESOURCE_LIMIT', 413);
          return { type: 'text', text: new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(String(file.path))) };
        }
        if (!['image', 'video', 'manifest'].includes(String(file.metadata.kind))) {
          throw fail('INVALID_OFFLINE_ARTICLE', 409);
        }
        return { type: file.metadata.kind === 'image' ? 'image' : 'video', url: file.url };
      });
      return {
        source: task.source,
        workId: task.work_id,
        chapterId: task.chapter_id,
        offline: true,
        incomplete: task.status !== 'completed',
        mediaKind: 'article',
        blocks,
        pages: [],
        files: entries.map(({ id: fid, url, metadata }) => ({ id: fid, url, ...metadata })),
      };
    }
    const novel = entries.find((file) => file.metadata.kind === 'novel');
    const manifest = entries.find((file) => file.metadata.kind === 'manifest');
    const media = entries.find((file) => ['audio', 'video'].includes(String(file.metadata.kind)));
    if (novel && statSync(String(novel.path)).size > 2 * 1024 * 1024) throw fail('RESOURCE_LIMIT', 413);
    const script = entries.find(
      (file) =>
        file.metadata.kind === 'script' &&
        ['txt', 'text'].includes(String(file.metadata.format)) &&
        Number(file.bytes) <= 2 * 1024 * 1024,
    );
    let inline: Row = {};
    if (novel) inline = JSON.parse(readFileSync(String(novel.path), 'utf8'));
    else if (script) {
      try {
        inline = { paragraphs: new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(String(script.path))).split(/\r?\n/) };
      } catch {
        // Ignore non-UTF8 script fallback
      }
    }
    const workRow = db
      .prepare('SELECT title,media_kind FROM works WHERE source=? AND work_id=?')
      .get(String(task.source), String(task.work_id));
    const chapterRow = db
      .prepare('SELECT title,page_progress,video_position,duration,text_offset,version FROM chapters WHERE source=? AND work_id=? AND chapter_id=?')
      .get(String(task.source), String(task.work_id), String(task.chapter_id));
    const workKind = workRow?.media_kind;
    return {
      source: task.source,
      workId: task.work_id,
      chapterId: task.chapter_id,
      workTitle: workRow?.title ?? task.work_id,
      title: chapterRow?.title ?? task.chapter_id,
      pageProgress: chapterRow?.page_progress ?? null,
      videoPosition: chapterRow?.video_position ?? null,
      duration: chapterRow?.duration ?? null,
      textOffset: chapterRow?.text_offset ?? 0,
      version: chapterRow?.version ?? 1,
      offline: true,
      incomplete: task.status !== 'completed',
      totalCount: Number(task.total_count ?? entries.length),
      previewOnly: entries.some((file) => file.metadata.previewOnly === true),
      mediaKind: novel ? 'novel' : manifest || media ? (media?.metadata.kind === 'audio' || workKind === 'voice' ? 'voice' : 'video') : 'comic',
      format: manifest ? 'hls' : media?.metadata.format ?? (media?.metadata.kind === 'audio' ? 'audio' : media ? 'mp4' : undefined),
      files: entries.map(({ id: fid, url, metadata }) => ({ id: fid, url, ...metadata })),
      volumes: entries
        .filter((file) => file.metadata.kind === 'manifest' && Number.isSafeInteger((file.metadata.recording as Row | undefined)?.volume))
        .map((file) => ({ volume: (file.metadata.recording as Row).volume, url: file.url }))
        .sort((a, b) => Number(a.volume) - Number(b.volume)),
      ...inline,
      ...(manifest || media ? { mediaUrl: (manifest ?? media)!.url } : {}),
      pages: entries
        .filter((file) => file.metadata.kind === 'image')
        .map((file, index) => ({
          index: Number(String(file.resource_key).split(':').at(-1)) || index,
          url: file.url,
          transform: file.metadata.transform,
        })),
    };
  });

  router.route({
    method: ['GET', 'HEAD'],
    url: '/offline/:taskId/files/:id',
    handler: async (request, reply) => {
      const p = request.params as Row;
      const allowIncomplete = ((request.query ?? {}) as Row).allowIncomplete === 'true';
      const taskId = text(p.taskId, 4096);
      const file = db
        .prepare(
          allowIncomplete
            ? "SELECT f.* FROM download_files f JOIN download_tasks t ON t.task_id=f.task_id WHERE f.task_id=? AND f.id=? AND f.status='completed' AND t.status IN ('completed','running','paused','queued')"
            : "SELECT f.* FROM download_files f JOIN download_tasks t ON t.task_id=f.task_id WHERE f.task_id=? AND f.id=? AND f.status='completed' AND t.status='completed'",
        )
        .get(taskId, Number(p.id));
      if (!file?.path) throw fail('NOT_FOUND', 404);
      const root = await realpath(options.downloadDir);
      const path = await realpath(String(file.path));
      const rel = relative(root, path);
      if (rel.startsWith('..') || isAbsolute(rel)) throw fail('BLOCKED', 403);
      const meta = JSON.parse(String(file.metadata_json));
      const size = statSync(path).size;
      if (size !== Number(file.bytes)) throw fail('OFFLINE_FILE_CHANGED', 409);
      if (meta.kind === 'manifest' || meta.kind === 'child-manifest') {
        if (size > 2 * 1024 * 1024) throw fail('RESOURCE_LIMIT', 413);
        const files = db
          .prepare("SELECT id,path FROM download_files WHERE task_id=? AND status='completed' ORDER BY id")
          .all(taskId);
        const manifest = localManifest(readFileSync(path, 'utf8'), files, taskId);
        return reply
          .type('application/vnd.apple.mpegurl')
          .header('cache-control', 'private, no-store')
          .send(request.method === 'HEAD' ? undefined : manifest);
      }
      let start = 0;
      let end = size - 1;
      const range = request.headers.range;
      if (range) {
        const match = /^bytes=(\d*)-(\d*)$/.exec(range);
        if (!match || (!match[1] && !match[2])) {
          return reply.code(416).header('content-range', 'bytes */' + size).send();
        }
        start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
        end = match[1] && match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
        if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start >= size || end < start) {
          return reply.code(416).header('content-range', 'bytes */' + size).send();
        }
        reply.code(206).header('content-range', 'bytes ' + start + '-' + end + '/' + size);
      }
      const magic = Buffer.alloc(192);
      const descriptor = openSync(path, 'r');
      let readLen = 0;
      try {
        readLen = readSync(descriptor, magic, 0, Math.min(192, size), 0);
      } finally {
        closeSync(descriptor);
      }
      const sample = magic.subarray(0, readLen);
      const type =
        meta.kind === 'image'
          ? sample[0] === 137
            ? 'image/png'
            : sample[0] === 255
              ? 'image/jpeg'
              : sample.toString('ascii', 0, 3) === 'GIF'
                ? 'image/gif'
                : 'image/webp'
          : meta.kind === 'segment'
            ? sample[0] === 0x47 && (sample.length < 189 || sample[188] === 0x47)
              ? 'video/mp2t'
              : sample.toString('ascii', 4, 8) === 'ftyp' || sample.toString('ascii', 4, 8) === 'styp'
                ? 'video/mp4'
                : 'application/octet-stream'
            : meta.kind === 'audio'
              ? sample.toString('ascii', 0, 4) === 'RIFF'
                ? 'audio/wav'
                : sample.toString('ascii', 0, 4) === 'fLaC'
                  ? 'audio/flac'
                  : sample.toString('ascii', 0, 4) === 'OggS'
                    ? 'audio/ogg'
                    : sample.toString('ascii', 4, 8) === 'ftyp'
                      ? 'audio/mp4'
                      : meta.format === 'aac'
                        ? 'audio/aac'
                        : 'audio/mpeg'
              : meta.kind === 'video'
                ? 'video/mp4'
                : meta.kind === 'novel'
                  ? 'application/json'
                  : meta.kind === 'subtitle'
                    ? meta.format === 'srt'
                      ? 'application/x-subrip'
                      : meta.format === 'lrc'
                        ? 'text/plain'
                        : 'text/vtt'
                    : meta.kind === 'script'
                      ? 'text/plain; charset=utf-8'
                      : 'application/octet-stream';
      reply
        .type(type)
        .header('cache-control', meta.kind === 'image' ? 'private, max-age=86400' : 'private, no-store')
        .header('accept-ranges', 'bytes')
        .header('content-length', end - start + 1);
      return request.method === 'HEAD' ? reply.send() : reply.send(createReadStream(path, { start, end }));
    },
  });
}
