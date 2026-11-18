import { readFile, readdir, writeFile, rename } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SourceHost } from '../packages/source-host/dist/index.js';
import { assertSupportedNode } from './node-version.mjs';
import { pluginAppVersion } from './shared-assets.mjs';

assertSupportedNode();
const root = fileURLToPath(new URL('../', import.meta.url));
const repositoryRoot = fileURLToPath(new URL('../../../', import.meta.url));
const appVersion = await pluginAppVersion();
const host = new SourceHost(join(root, 'apps/source-runner/dist/index.js'), appVersion, {
  runtimePath: join(root, 'assets/runtime/park_runtime.js'),
});

const entries = [];
const rejected = [];
const seen = new Set();

try {
  const publicIndex = JSON.parse(await readFile(join(repositoryRoot, 'assets/sources/index.json'), 'utf8'));
  const publicOrder = new Map(publicIndex.sources.map((entry, index) => [String(entry.key), index]));
  const files = (await readdir(join(root, 'assets/sources'))).filter((name) => name.endsWith('.js'));
  files.sort((a, b) => {
    const aOrder = publicOrder.get(a.slice(0, -3)) ?? Number.MAX_SAFE_INTEGER;
    const bOrder = publicOrder.get(b.slice(0, -3)) ?? Number.MAX_SAFE_INTEGER;
    return aOrder - bOrder || a.localeCompare(b);
  });

  // Inspect bundled plugins with bounded concurrency (8 workers) instead of purely sequential spawns
  let cursor = 0;
  const results = new Array(files.length);
  const concurrency = Math.min(8, Math.max(1, files.length));
  await Promise.all(
    Array.from({ length: concurrency }, async () => {
      while (cursor < files.length) {
        const index = cursor++;
        const file = files[index];
        const filePath = join(root, 'assets/sources', file);
        try {
          const manifest = await host.inspect(filePath);
          const sha256 = createHash('sha256').update(await readFile(filePath)).digest('hex');
          results[index] = { ok: true, entry: { source: manifest.key, version: manifest.version, sha256, file, manifest } };
        } catch (error) {
          results[index] = {
            ok: false,
            rejection: {
              source: file.slice(0, -3),
              file,
              code: error.code ?? 'INVALID_MANIFEST',
              reason: String(error.message).slice(0, 256),
            },
          };
        }
      }
    }),
  );

  for (const item of results) {
    if (!item.ok) {
      rejected.push(item.rejection);
      continue;
    }
    if (seen.has(item.entry.source)) {
      rejected.push({
        source: item.entry.source,
        file: item.entry.file,
        code: 'INVALID_MANIFEST',
        reason: 'duplicate source identity',
      });
      continue;
    }
    seen.add(item.entry.source);
    entries.push(item.entry);
  }

  if (!entries.length) throw Error('No compatible sources; index was not replaced');
  for (const [name, value] of [
    ['source-index.json', entries],
    ['source-rejections.json', rejected],
  ]) {
    const outPath = join(root, 'assets', name);
    const temporary = outPath + '.' + process.pid + '.tmp';
    await writeFile(temporary, JSON.stringify(value, null, 2) + '\n', 'utf8');
    await rename(temporary, outPath);
  }
  console.log(JSON.stringify({ appVersion, compatible: entries.length, rejected: rejected.length, rejections: 'assets/source-rejections.json' }));
} finally {
  await host.dispose();
}
