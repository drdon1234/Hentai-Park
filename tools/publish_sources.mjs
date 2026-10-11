#!/usr/bin/env node
// Offline publisher for the official source index. Uses only Node built-ins.
import { createHash } from 'node:crypto';
import { lstat, readFile, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import vm from 'node:vm';

const defaultRoot = fileURLToPath(new URL('../', import.meta.url));
const rawBase = 'https://raw.githubusercontent.com/drdon1234/Hentai-Park';
const executionOptions = { timeout: 1000 };

function requiredText(value, label) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} 必须是非空字符串`);
  return value;
}

function versionParts(value) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) {
    throw new Error(`无效版本 ${JSON.stringify(value)}：version 必须是无前导零的三段非负整数`);
  }
  return value.split('.').map(BigInt);
}

function compareVersions(a, b) {
  const left = versionParts(a);
  const right = versionParts(b);
  for (let i = 0; i < 3; i++) {
    const difference = left[i] - right[i];
    if (difference !== 0n) return difference > 0n ? 1 : -1;
  }
  return 0;
}

async function readUtf8(filename) {
  const bytes = await readFile(filename);
  const text = bytes.toString('utf8');
  if (!bytes.equals(Buffer.from(text, 'utf8'))) throw new Error(`${filename} 不是有效 UTF-8 文件`);
  return text;
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
    if (typeof entry.sha256 !== 'string' || !/^[a-fA-F0-9]{64}$/.test(entry.sha256)) {
      throw new Error(`旧索引 ${key} 缺少有效 sha256`);
    }
    if (published.has(key)) throw new Error(`旧索引存在重复 key：${key}`);
    published.set(key, entry);
  }
  return published;
}

export async function generateIndex({ root = defaultRoot, commit, previousIndex } = {}) {
  if (typeof commit !== 'string' || !/^[a-f0-9]{40}$/.test(commit)) {
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
    if (!/^[A-Za-z0-9_-]+$/.test(key)) throw new Error(`无效 key：${key}`);
    if (keys.has(key)) throw new Error(`清单存在重复 key：${key}`);
    keys.add(key);
    requiredText(entry.name, `${key} name`);
    if (typeof entry.description !== 'string') throw new Error(`${key} description 必须是字符串`);
    versionParts(entry.version);
    if (entry.apiVersion !== undefined && entry.apiVersion !== runtimeApi) {
      throw new Error(`${key} 的清单 apiVersion 与运行时 API 不一致`);
    }
    const code = await readUtf8(await scriptPath(sourceRoot, entry.file));
    const { apiVersion, manifest } = probeScript(runtimeCode, code, entry.file);
    if (manifest.key !== key || manifest.version !== entry.version) {
      throw new Error(`${entry.file} 注册的 key/version 与清单不一致`);
    }
    if (apiVersion !== runtimeApi || manifest.apiVersion !== runtimeApi) {
      throw new Error(`${key} 的脚本 apiVersion ${manifest.apiVersion} 与运行时 API ${runtimeApi} 不一致`);
    }
    const sha256 = createHash('sha256').update(code, 'utf8').digest('hex');
    const previous = published.get(key);
    if (previous) {
      const comparison = compareVersions(entry.version, previous.version);
      if (comparison < 0) throw new Error(`${key} 禁止降版：${previous.version} → ${entry.version}`);
      if (comparison === 0 && sha256 !== previous.sha256.toLowerCase()) {
        throw new Error(`${key} 同版本 ${entry.version} 的脚本内容已改变，请同时提升脚本和清单版本`);
      }
    }
    sources.push({
      key, name: entry.name, version: entry.version, description: entry.description,
      url: `${rawBase}/${commit}/assets/sources/${entry.file}`,
      sha256, apiVersion: runtimeApi,
    });
  }
  return { name: index.name, apiVersion: runtimeApi, sources };
}

async function main() {
  const { values } = parseArgs({ options: {
    root: { type: 'string' }, commit: { type: 'string' },
    previous: { type: 'string' }, output: { type: 'string' },
  } });
  requiredText(values.output, '--output');
  const previousIndex = values.previous ? JSON.parse(await readUtf8(values.previous)) : undefined;
  const index = await generateIndex({ root: values.root, commit: values.commit, previousIndex });
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
