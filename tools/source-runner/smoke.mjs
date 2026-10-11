// Live smoke test for a source script:
//   node smoke.mjs <file.js> [--keyword kw] [--id workId] [--state state.json]
// Exercises feeds → search → detail → chapter → resolveImage → image download.
import fs from 'node:fs';
import { loadSource, probeImage } from './host.mjs';

const args = process.argv.slice(2);
const file = args[0];
const opt = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};

const state = opt('state') ? JSON.parse(fs.readFileSync(opt('state'), 'utf8')) : {};
let failures = 0;

async function step(label, fn) {
  const started = Date.now();
  try {
    const out = await fn();
    console.log(`✓ ${label} (${Date.now() - started}ms)${out ? ' — ' + out : ''}`);
    return true;
  } catch (err) {
    failures++;
    console.log(`✗ ${label} — ${err.message}`);
    if (process.env.PARK_VERBOSE) console.log(err.stack);
    return false;
  }
}

const describe = (page) =>
  `${page.items.length} items, page ${page.page ?? '-'}/${page.totalPages ?? '?'}, next=${page.hasNext}` +
  (page.items[0] ? ` | ${JSON.stringify(page.items[0]).slice(0, 220)}` : '');

const { manifest, call } = await loadSource(file, state);
console.log(`# ${manifest.name} v${manifest.version} (${manifest.type})`);

let sample = opt('id');
for (const feed of manifest.feeds) {
  const options = Object.fromEntries((feed.options || []).map((o) => [o.key, o.default]));
  await step(`feed ${feed.label}`, async () => {
    const page = await call('feed', feed.key, { page: 1, options });
    if (page.sections) {
      if (!page.sections.length || !page.sections[0].items.length) throw new Error('empty sections');
      sample ??= page.sections[0].items[0].id;
      return page.sections.map((s) => `${s.title}(${s.items.length})`).join(', ');
    }
    if (!page.items.length) throw new Error('empty feed');
    sample ??= page.items[0].id;
    if (page.hasNext) {
      const next = await call('feed', feed.key, { page: 2, cursor: page.cursor, options });
      if (!next.items.length) throw new Error('page 2 empty');
      if (next.items[0].id === page.items[0].id) throw new Error('page 2 repeats page 1');
    }
    return describe(page);
  });
}

if (manifest.capabilities.search) {
  const filters = Object.fromEntries((manifest.searchFilters || []).map((f) => [f.key, f.default]));
  await step(`search "${opt('keyword') ?? ''}"`, async () => {
    const page = await call('search', { keyword: opt('keyword') ?? '', page: 1, filters });
    if (!page.items.length) throw new Error('no results');
    sample ??= page.items[0].id;
    return describe(page);
  });
}

if (manifest.capabilities.random) {
  await step('random', async () => `id=${await call('random')}`);
}

let detail;
await step(`detail ${sample}`, async () => {
  detail = await call('detail', sample);
  const tagCount = (detail.tags || []).reduce((n, g) => n + g.tags.length, 0);
  return `${detail.title} | pages=${detail.pages} tags=${tagCount} chapters=${detail.chapters ? detail.chapters.length : '-'} cover=${detail.cover}`;
});

if (detail && detail.cover) {
  await step('cover image', async () => {
    const r = await probeImage(detail.cover, manifest.imageHeaders);
    if (r.status !== 200 || r.bytes < 500) throw new Error(JSON.stringify(r));
    return `${r.bytes} bytes ${r.type}`;
  });
}

if (detail && manifest.type === 'video') {
  await step('videos', async () => {
    const list = await call('videos', detail.id);
    if (!list.length) throw new Error('no video sources');
    return list.map((v) => `${v.quality}p`).join(', ') + ' ' + list[0].url.slice(0, 80);
  });
} else if (detail && manifest.capabilities.chapter) {
  const chapterId = detail.chapters && detail.chapters.length ? detail.chapters[0].id : null;
  let chapter;
  await step(`chapter ${chapterId ?? '(single)'}`, async () => {
    chapter = await call('chapter', detail.id, chapterId);
    if (!chapter.pages.length) throw new Error('no pages');
    return `${chapter.pages.length} pages | ${JSON.stringify(chapter.pages[0]).slice(0, 200)}`;
  });
  if (chapter) {
    for (const index of [0, chapter.pages.length - 1]) {
      await step(`image #${index + 1}`, async () => {
        let page = chapter.pages[index];
        if (!page.url) page = await call('resolveImage', { id: detail.id, chapterId, index, token: page.token, retry: 0 });
        const r = await probeImage(page.url, { ...manifest.imageHeaders, ...(page.headers || {}) });
        if (r.status !== 200 || r.bytes < 500) throw new Error(`${page.url} → ${JSON.stringify(r)}`);
        return `${r.bytes} bytes ${r.type}${page.transform ? ' transform=' + JSON.stringify(page.transform) : ''}`;
      });
    }
  }
}

console.log(failures ? `\n${failures} step(s) failed` : '\nall steps passed');
process.exit(failures ? 1 : 0);
