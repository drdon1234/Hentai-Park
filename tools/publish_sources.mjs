#!/usr/bin/env node
// Offline publisher for the official source index. Uses only Node built-ins.
import { lstat, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import vm from 'node:vm';

const defaultRoot = fileURLToPath(new URL('../', import.meta.url));
import { versionParts, compareVersions, readUtf8, isSourceKey, isSha256, isCommit, sha256, officialAssetUrl } from './publish_common.mjs';
const executionOptions = { timeout: 1000 };

function requiredText(value, label) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} 必须是非空字符串`);
  return value;
}

const multiLabelSuffixes = new Set(['co.jp', 'ne.jp', 'or.jp', 'com.cn', 'net.cn', 'org.cn', 'com.tw', 'net.tw', 'com.hk', 'co.kr', 'co.uk', 'com.au', 'com.br']);
const publicHost = host => typeof host === 'string' &&
  /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$/.test(host) &&
  !host.split('.').some(label => !label || label.startsWith('-') || label.endsWith('-')) &&
  host !== 'localhost' && !host.endsWith('.localhost') && !host.endsWith('.local');
const hostInDomains = (host, domains) => domains.some(domain =>
  host === domain.toLowerCase() || host.endsWith('.' + domain.toLowerCase()));

function declaredDomains(manifest) {
  if (manifest.domains.length) return manifest.domains.map(domain => domain.toLowerCase().trim()).filter(Boolean);
  const domains = [];
  for (const value of [manifest.homepage, manifest.network?.origin, manifest.account?.cookieUrl, manifest.account?.loginUrl]) {
    let host;
    try { host = new URL(value).hostname; } catch { continue; }
    const labels = host.split('.');
    domains.push(labels.slice(multiLabelSuffixes.has(labels.slice(-2).join('.')) ? -3 : -2).join('.'));
  }
  return domains;
}

// 发布前对照 MediaPolicy 和 createImageTransport 检查，避免播放时才发现权限缺失。
function validateMedia(manifest) {
  const siteDomains = declaredDomains(manifest);
  function check(media, image = false) {
    const fail = () => { throw new Error(`${manifest.key} 的${image ? '图片' : '媒体'}权限无效，请检查 mode、origin、scope 和 domains`); };
    if (!media || typeof media !== 'object' || Array.isArray(media)) fail();
    const session = media.scope === 'session';
    const referrers = media.referrerDomains;
    if (referrers != null && (!Array.isArray(referrers) || image || media.mode !== 'native' ||
        referrers.length > 16 || referrers.some(domain => !publicHost(domain)))) fail();
    if (!['native', 'browser'].includes(media.mode) ||
        (media.scope != null && !session) || (session && media.mode !== 'native') ||
        typeof media.origin !== 'string' || !/^https:\/\/[^/]/i.test(media.origin) || /[?#\\\s]/.test(media.origin)) fail();
    let origin;
    try { origin = new URL(media.origin); } catch { fail(); }
    if (origin.protocol !== 'https:' || origin.port || origin.username || origin.password ||
        !publicHost(origin.hostname)) fail();
    const domains = media.domains ?? [];
    if (!Array.isArray(domains) || (!domains.length && !session) ||
        domains.some(domain => typeof domain !== 'string' || !publicHost(domain.toLowerCase()))) fail();
    if (!hostInDomains(origin.hostname, siteDomains) &&
        !(image && hostInDomains(origin.hostname, domains))) fail();
    if (image && (media.mode !== 'browser' || session || !domains.length)) fail();
  }
  if (manifest.capabilities.videos || Array.isArray(manifest.media) ||
      typeof manifest.media !== 'object' || Object.keys(manifest.media).length) check(manifest.media);
  if (manifest.imageNetwork != null) check(manifest.imageNetwork, true);
}

function createProbe(runtimeCode) {
  // No host functions/objects, network, storage, process, or module loader are exposed.
  // This evaluates reviewed repository scripts; node:vm is not a hostile-code security boundary.
  const context = vm.createContext(Object.create(null), {
    codeGeneration: { strings: false, wasm: false },
    microtaskMode: 'afterEvaluate',
  });
  vm.runInContext(runtimeCode, context, { ...executionOptions, filename: 'park_runtime.js' });
  return context;
}

function validateChat(manifest) {
  const chat = manifest.chat;
  if (!manifest.capabilities.liveChat && chat && !Object.keys(chat).length) return;
  const domains = chat?.domains;
  if (!chat || typeof chat !== 'object' || Array.isArray(chat) ||
      !Array.isArray(domains) || !domains.length || domains.length > 64 ||
      domains.some(domain => {
        if (typeof domain !== 'string') return true;
        const endpoint = domain.startsWith('*.') ? domain.slice(2) : domain;
        try {
          const url = new URL('https://' + endpoint), port = Number(url.port || 443);
          return url.host !== endpoint || !publicHost(url.hostname) || url.username || url.password ||
            url.pathname !== '/' || url.search || url.hash || (port !== 443 && (port < 1024 || port > 65535));
        } catch { return true; }
      }) || new Set(domains).size !== domains.length) {
    throw new Error(`${manifest.key} 的聊天权限无效，请声明独立的 TLS 主机与端口，通配符只能位于首个子域`);
  }
}

function probeScript(runtimeCode, code, filename) {
  const context = createProbe(runtimeCode);
  const apiVersion = vm.runInContext('Park.API_VERSION', context, executionOptions);
  vm.runInContext('Park.__pending = null', context, executionOptions);
  vm.runInContext(code, context, { ...executionOptions, filename });
  // Match the application's installation probe: read the last registered definition, without setup/init.
  const json = vm.runInContext(
    'JSON.stringify(Park.__pending ? Park.manifest(Park.__pending.key) : null)',
    context,
    executionOptions,
  );
  const manifest = JSON.parse(json);
  if (!manifest) throw new Error(`${filename} 没有调用 Park.register 注册源`);
  return { apiVersion, manifest };
}

async function scriptPath(sourceRoot, file) {
  if (typeof file !== 'string' || !/^[A-Za-z0-9_-]+\.js$/.test(file)) {
    throw new Error(`无效源文件路径 ${JSON.stringify(file)}：必须是 sources 根目录下的 [A-Za-z0-9_-]+.js 文件`);
  }
  const filename = await realpath(path.join(sourceRoot, file));
  const relative = path.relative(sourceRoot, filename);
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`源文件路径越过 sources 目录边界：${file}`);
  }
  const info = await lstat(path.join(sourceRoot, file));
  if (info.isSymbolicLink()) throw new Error(`源文件路径不允许符号链接：${file}`);
  if (!info.isFile()) throw new Error(`源文件不是普通文件：${file}`);
  return filename;
}

function publishedSources(previousIndex) {
  const published = new Map();
  if (previousIndex === undefined) return published;
  if (!previousIndex || !Array.isArray(previousIndex.sources)) throw new Error('旧索引缺少 sources 数组');
  for (const entry of previousIndex.sources) {
    const key = requiredText(entry?.key, '旧索引 key');
    versionParts(entry.version);
    if (!isSha256(entry.sha256)) {
      throw new Error(`旧索引 ${key} 缺少有效 sha256`);
    }
    if (published.has(key)) throw new Error(`旧索引存在重复 key：${key}`);
    published.set(key, entry);
  }
  return published;
}

export async function generateIndex({ root = defaultRoot, commit, previousIndex, channel = 'sources' } = {}) {
  if (!['sources', 'rankings', 'reverse-search'].includes(channel)) throw new Error('无效发布频道');
  if (!isCommit(commit)) {
    throw new Error('commit 必须是源码提交的完整 40 位小写十六进制 SHA');
  }
  const sourceRoot = await realpath(path.resolve(root, 'assets', 'sources'));
  const index = JSON.parse(await readUtf8(path.join(sourceRoot, 'index.json')));
  requiredText(index.name, '清单 name');
  if (!Array.isArray(index.sources) || index.sources.length === 0) throw new Error('清单 sources 必须是非空数组');
  const runtimeCode = await readUtf8(path.resolve(root, 'assets', 'runtime', 'park_runtime.js'));
  const runtimeApi = vm.runInContext('Park.API_VERSION', createProbe(runtimeCode), executionOptions);
  if (!Number.isSafeInteger(runtimeApi) || runtimeApi < 1 || index.apiVersion !== runtimeApi) {
    throw new Error(`清单 apiVersion ${index.apiVersion} 与运行时 API ${runtimeApi} 不一致`);
  }
  const published = publishedSources(previousIndex);
  const keys = new Set();
  const sources = [];
  for (const entry of index.sources) {
    const key = requiredText(entry?.key, '清单 key');
    if (!isSourceKey(key)) throw new Error(`无效 key：${key}`);
    if (keys.has(key)) throw new Error(`清单存在重复 key：${key}`);
    keys.add(key);
    requiredText(entry.name, `${key} name`);
    if (typeof entry.description !== 'string') throw new Error(`${key} description 必须是字符串`);
    if (!['doujin', 'anime', 'aiDrama', 'jav', 'adult', 'shortvideo', 'recording', 'gallery', 'illustration', 'novel', 'game', 'other', 'live'].includes(entry.category)) {
      throw new Error(`${key} category 必须是有效的内容分类`);
    }
    versionParts(entry.version);
    if (entry.apiVersion !== undefined && entry.apiVersion !== runtimeApi) {
      throw new Error(`${key} 的清单 apiVersion 与运行时 API 不一致`);
    }
    versionParts(entry.minAppVersion);
    const code = await readUtf8(await scriptPath(sourceRoot, entry.file));
    if (entry.file !== `${key}.js`) throw new Error(`${key} 的文件路径必须匹配 key`);
    const { apiVersion, manifest } = probeScript(runtimeCode, code, entry.file);
    if (manifest.key !== key || manifest.version !== entry.version) {
      throw new Error(`${entry.file} 注册的 key/version 与清单不一致`);
    }
    if (manifest.minAppVersion !== entry.minAppVersion) {
      throw new Error(`${entry.file} 注册的 minAppVersion 与清单不一致`);
    }
    if (manifest.category !== entry.category) {
      throw new Error(`${entry.file} 注册的 category 与清单不一致`);
    }
    validateMedia(manifest);
    validateChat(manifest);
    if (manifest.capabilities.reverseSearch) {
      if (!['general', 'anime', 'jav', 'gallery'].includes(manifest.reverseSearchCategory) ||
          manifest.reverseSearchCategory !== (entry.reverseSearchCategory || 'general')) {
        throw new Error(`${key} 的反搜分类无效或与清单不一致`);
      }
    }
    if (manifest.rankingOnly !== (entry.rankingOnly === true)) {
      throw new Error(`${key} 的排行榜标记与清单不一致`);
    }
    if (manifest.rankingOnly && (!manifest.rankings.length || manifest.feeds.length)) {
      throw new Error(`${key} 必须仅声明排行榜，不得混入普通列表`);
    }
    if (manifest.rankingOnly && manifest.reverseSearchOnly) {
      throw new Error(`${key} 不得同时属于排行榜与反搜频道`);
    }
    if (apiVersion !== runtimeApi || manifest.apiVersion !== runtimeApi) {
      throw new Error(`${key} 的脚本 apiVersion ${manifest.apiVersion} 与运行时 API ${runtimeApi} 不一致`);
    }
    const digest = sha256(code);
    const sourceChannel = manifest.rankingOnly ? 'rankings' : manifest.reverseSearchOnly ? 'reverse-search' : 'sources';
    if (channel !== sourceChannel) continue;
    const previous = published.get(key);
    if (previous) {
      const comparison = compareVersions(entry.version, previous.version);
      if (comparison < 0) throw new Error(`${key} 禁止降版：${previous.version} → ${entry.version}`);
      if (comparison === 0 && digest !== previous.sha256.toLowerCase()) {
        throw new Error(`${key} 同版本 ${entry.version} 的脚本内容已改变，请同时提升脚本和清单版本`);
      }
    }
    sources.push({
      key, name: entry.name, version: entry.version, description: entry.description,
      category: entry.category,
      ...(manifest.capabilities.reverseSearch ? {reverseSearchCategory: manifest.reverseSearchCategory} : {}),
      rankingOnly: manifest.rankingOnly,
      reverseSearchOnly: manifest.reverseSearchOnly,
      url: officialAssetUrl(commit, `assets/sources/${entry.file}`),
      sha256: digest, apiVersion: runtimeApi, minAppVersion: manifest.minAppVersion,
    });
  }
  const name = channel === 'rankings' ? 'HentaiPark Rankings' : channel === 'reverse-search' ? 'HentaiPark Reverse Search' : index.name;
  return { name, apiVersion: runtimeApi, sources };
}

async function main() {
  const { values } = parseArgs({ options: {
    root: { type: 'string' }, commit: { type: 'string' },
    previous: { type: 'string' }, output: { type: 'string' },
    channel: { type: 'string', default: 'sources' },
  } });
  requiredText(values.output, '--output');
  const previousIndex = values.previous ? JSON.parse(await readUtf8(values.previous)) : undefined;
  const index = await generateIndex({ root: values.root, commit: values.commit, previousIndex, channel: values.channel });
  // Do not touch an existing output until every script and the previous publication have passed.
  await writeFile(values.output, JSON.stringify(index, null, 2) + '\n', 'utf8');
  console.log(`已离线验证并生成 ${index.sources.length} 个官方源：${values.output}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(`发布校验失败：${error.message}`);
    process.exitCode = 1;
  });
}
