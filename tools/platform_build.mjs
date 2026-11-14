// 构建元数据与完整分发包；生成文件仅写入被忽略的 test/。
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, appendFileSync, copyFileSync, cpSync, mkdtempSync, rmSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const version = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(readFileSync('pubspec.yaml', 'utf8'));
if (!version) throw Error('pubspec.yaml 必须声明应用版本和构建号');
const [, name, number] = version;
const out = resolve('test/distribution');
mkdirSync(out, { recursive: true });
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (result.error || result.status !== 0) throw result.error ?? Error(`${command} failed: ${result.status}`);
  return result;
}
function output(key, value) {
  console.log(`${key}=${value}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
}
const platforms = [
  { platform: 'android', os: 'ubuntu-24.04', arch: 'arm64-armv7-x64' },
];
const command = process.argv[2];
if (command === 'metadata') {
  const tag = process.env.GITHUB_REF_TYPE === 'tag' ? process.env.GITHUB_REF_NAME : '';
  if (tag && tag !== `v${name}`) throw Error('标签必须与 pubspec.yaml 版本一致');
  output('version', name);
  output('build_number', number);
  output('tag', `v${name}`);
} else if (command === 'plan') {
  let selected = platforms;
  const base = process.env.CHANGE_BASE;
  if (base && !/^0+$/.test(base)) {
    const diff = spawnSync('git', ['diff', '--name-only', base, 'HEAD'], { encoding: 'utf8' });
    if (diff.status !== 0) throw Error('无法确定变动范围');
    const paths = diff.stdout.trim().split(/\r?\n/);
    const shared = paths.some(p => /^(lib\/|assets\/(?!sources\/)|LICENSE$|docs\/licenses\/|pubspec\.|tools\/platform_build|\.github\/workflows\/)/.test(p));
    if (!shared) selected = platforms.filter(p => paths.some(f => f.startsWith(`${p.platform}/`)));
  }
  output('build', selected.length > 0 ? 'true' : 'false');
  output('matrix', JSON.stringify({ include: selected }));
} else if (command === 'package') {
  const platform = process.argv[3];
  const arch = process.argv[4];
  if (!platforms.some(p => p.platform === platform && p.arch === arch)) throw Error('未知构建目标');
  const prefix = `HentaiPark-${name}-${number}-${platform}-${arch}`;
  function zip(source, target) {
    if (!existsSync(source)) throw Error(`缺少构建产物: ${source}`);
    const dest = join(out, target);
    // 包内固定主目录，避免解压工具以带版本号的附件名作为安装目录。
    const staging = mkdtempSync(resolve('test/package-android-'));
    try {
      const bundle = join(staging, 'HentaiPark');
      cpSync(source, bundle, { recursive: true, preserveTimestamps: true, verbatimSymlinks: true });
      const quote = value => `'${value.replace(/'/g, "''")}'`;
      run('powershell.exe', ['-NoProfile', '-Command', `Compress-Archive -LiteralPath ${quote(bundle)} -DestinationPath ${quote(dest)} -Force`]);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }
  if (platform === 'android') {
    // 无签名 APK 只用于编译检查，不进入分发目录。
    if (process.env.ANDROID_SIGNED === 'true') {
      const { copyFileSync } = await import('node:fs');
      for (const abi of ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        copyFileSync(`build/app/outputs/flutter-apk/app-${abi}-release.apk`, join(out, `HentaiPark-${name}-${number}-android-${abi}.apk`));
      }
    } else console.log('Android 未配置发布密钥：仅完成无签名编译，不提供安装包。');
  }
  for (const file of readdirSync(out).filter(f => !f.endsWith('.sha256'))) {
    const digest = createHash('sha256').update(readFileSync(join(out, file))).digest('hex');
    writeFileSync(join(out, `${file}.sha256`), `${digest}  ${basename(file)}\n`);
  }
} else if (command === 'notes') {
  const path = process.argv[3];
  const notes = readFileSync(path, 'utf8').trim();
  const sections = [...notes.matchAll(/^## (.+)$/gm)].map(m => m[1]);
  if (sections.join('|') !== '中文|English') throw Error('发布说明必须只有中文、English 两节');
  const allowed = new Set(['新功能', '改进', '修复', '插件更新', '注意事项', 'New', 'Improvements', 'Fixes', 'Plugin updates', 'Notes']);
  for (const line of notes.split(/\r?\n/)) {
    if (!line.trim() || /^## (中文|English)$/.test(line) || line.startsWith('- ')) continue;
    if (line.startsWith('### ') && allowed.has(line.slice(4))) continue;
    throw Error('发布说明包含不支持的格式');
  }
  const [zh, en] = notes.split('## English');
  if ((zh.match(/^- /gm) ?? []).length !== (en.match(/^- /gm) ?? []).length) throw Error('中英文条目数不一致');
  writeFileSync('test/release-notes.md', `${notes}\n`);
} else throw Error('用法: metadata | plan | package <platform> <arch> | notes <path>');
