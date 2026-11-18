import { readFile, readdir, mkdir, copyFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const webRoot = fileURLToPath(new URL('../', import.meta.url));
export const repositoryRoot = fileURLToPath(new URL('../../../', import.meta.url));

export async function applicationVersion() {
  const text = await readFile(join(repositoryRoot, 'clients/web/package.json'), 'utf8');
  const version = JSON.parse(text).version;
  if (
    typeof version !== 'string' ||
    !/^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?$/.test(version)
  ) {
    throw Error('clients/web/package.json must declare a valid web version');
  }
  return version;
}

export async function pluginAppVersion() {
  try {
    const pubspec = await readFile(join(repositoryRoot, 'pubspec.yaml'), 'utf8');
    const match = /^version:\s*(\d+\.\d+\.\d+)(?:[-+][0-9A-Za-z.-]+)?\s*$/m.exec(pubspec);
    if (match?.[1]) return match[1];
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const appJson = JSON.parse(await readFile(join(webRoot, 'assets/application.json'), 'utf8'));
  if (typeof appJson.pluginAppVersion === 'string' && /^\d+\.\d+\.\d+$/.test(appJson.pluginAppVersion)) {
    return appJson.pluginAppVersion;
  }
  throw Error('pubspec.yaml must declare a valid three-part application version');
}

export async function prepareSharedAssets() {
  const output = join(webRoot, 'assets');
  const sources = join(output, 'sources');
  await mkdir(sources, { recursive: true });
  await mkdir(join(output, 'runtime'), { recursive: true });
  const names = (await readdir(join(repositoryRoot, 'assets/sources')))
    .filter((name) => name.endsWith('.js'))
    .sort();
  if (!names.length) throw Error('Shared official plugins are missing');
  for (const old of await readdir(sources)) {
    if (!names.includes(old)) await rm(join(sources, old));
  }
  for (const name of names) {
    await copyFile(join(repositoryRoot, 'assets/sources', name), join(sources, name));
  }
  await copyFile(join(repositoryRoot, 'assets/runtime/park_runtime.js'), join(output, 'runtime/park_runtime.js'));
  await writeFile(
    join(output, 'application.json'),
    JSON.stringify({
      version: await applicationVersion(),
      pluginAppVersion: await pluginAppVersion(),
    }) + '\n',
  );
}

export async function sharedAssetsCurrent() {
  try {
    const current = JSON.parse(await readFile(join(webRoot, 'assets/application.json'), 'utf8'));
    if (
      current.version !== (await applicationVersion()) ||
      current.pluginAppVersion !== (await pluginAppVersion())
    ) {
      return false;
    }
    const names = (await readdir(join(repositoryRoot, 'assets/sources')))
      .filter((name) => name.endsWith('.js'))
      .sort();
    if (JSON.stringify(names) !== JSON.stringify((await readdir(join(webRoot, 'assets/sources'))).sort())) {
      return false;
    }
    for (const name of [...names.map((item) => 'sources/' + item), 'runtime/park_runtime.js']) {
      if (!(await readFile(join(repositoryRoot, 'assets', name))).equals(await readFile(join(webRoot, 'assets', name)))) {
        return false;
      }
    }
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}
