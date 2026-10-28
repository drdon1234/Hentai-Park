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
  { platform: 'windows', os: 'windows-2022', arch: 'x64' },
  { platform: 'linux', os: 'ubuntu-24.04', arch: 'x64' },
  { platform: 'macos', os: 'macos-15', arch: 'universal' },
  { platform: 'ios', os: 'macos-15', arch: 'simulator-x64' },
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
    const shared = paths.some(p => /^(lib\/|assets\/(?!sources\/|i18n\/)|pubspec\.|tools\/platform_build|\.github\/workflows\/)/.test(p));
    if (!shared) selected = platforms.filter(p => paths.some(f => f.startsWith(`${p.platform}/`)));
  }
  output('build', selected.length > 0 ? 'true' : 'false');
  output('matrix', JSON.stringify({ include: selected }));
} else if (command === 'package') {
  const platform = process.argv[3];
  const arch = process.argv[4];
  if (!platforms.some(p => p.platform === platform && p.arch === arch)) throw Error('未知构建目标');
  const prefix = `HentaiPark-${name}-${number}-${platform}-${arch}`;
  function zip(source, target, apple = false) {
    if (!existsSync(source)) throw Error(`缺少构建产物: ${source}`);
    const dest = join(out, target);
    if (apple) {
      run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', source, dest]);
    } else {
      // 包内固定主目录，避免解压工具以带版本号的附件名作为安装目录。
      const staging = mkdtempSync(resolve(`test/package-${platform}-`));
      try {
        const bundle = join(staging, 'HentaiPark');
        cpSync(source, bundle, { recursive: true, preserveTimestamps: true, verbatimSymlinks: true });
        if (platform === 'windows') {
          const quote = value => `'${value.replace(/'/g, "''")}'`;
          run('powershell.exe', ['-NoProfile', '-Command', `Compress-Archive -LiteralPath ${quote(bundle)} -DestinationPath ${quote(dest)} -Force`]);
        } else {
          run('tar', ['-czf', dest, '-C', staging, 'HentaiPark']);
        }
      } finally {
        rmSync(staging, { recursive: true, force: true });
      }
    }
  }
  if (platform === 'windows') {
    const bundle = 'build/windows/x64/runner/Release';
    // 将可再分发的 MSVC CRT 随包提供，不依赖构建机预装环境。
    const vswhere = join(process.env['ProgramFiles(x86)'] ?? '', 'Microsoft Visual Studio/Installer/vswhere.exe');
    const found = spawnSync(vswhere, ['-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], { encoding: 'utf8' });
    if (found.status !== 0 || !found.stdout.trim()) throw Error('无法找到 MSVC 可再分发运行库');
    const root = join(found.stdout.trim(), 'VC/Redist/MSVC');
    const versions = readdirSync(root).filter(v => /^\d+\./.test(v)).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
    let crt;
    for (const version of versions) {
      const directory = join(root, version, 'x64');
      if (!existsSync(directory)) continue;
      const name = readdirSync(directory).find(n => /^Microsoft\.VC\d+\.CRT$/.test(n));
      if (name) { crt = join(directory, name); break; }
    }
    if (!crt) throw Error('缺少 x64 MSVC CRT 分发目录');
    for (const file of readdirSync(crt).filter(n => n.endsWith('.dll'))) copyFileSync(join(crt, file), join(bundle, file));
    for (const file of ['hentai_park.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'libEGL.dll', 'libGLESv2.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets/AssetManifest.bin']) {
      if (!existsSync(join(bundle, file))) throw Error(`分发目录缺少运行文件: ${file}`);
    }
    zip(bundle, `${prefix}.zip`);
    const compiler = process.env.ISCC_COMMAND ?? join(process.env['ProgramFiles(x86)'] ?? '', 'Inno Setup 6/ISCC.exe');
    run(compiler, [
      `/DAppVersion=${name}`, `/DBundleDir=${resolve(bundle)}`,
      `/DOutputDir=${out}`, `/DOutputName=${prefix}-setup`,
      'windows/installer.iss',
    ]);
  }
  if (platform === 'linux') {
    const bundle = resolve('build/linux/x64/release/bundle');
    zip(bundle, `${prefix}.tar.gz`);
    const staging = mkdtempSync(resolve('test/package-linux-'));
    try {
      const root = join(staging, 'debian/hentaipark');
      const application = join(root, 'opt/hentaipark');
      cpSync(bundle, application, { recursive: true, preserveTimestamps: true, verbatimSymlinks: true });
      mkdirSync(join(staging, 'debian'), { recursive: true });
      writeFileSync(join(staging, 'debian/control'), 'Source: hentaipark\n\nPackage: hentaipark\nArchitecture: amd64\nDescription: HentaiPark desktop client\n');
      // 从构建产物推导当前发行版的真实运行库依赖，不手写可能漂移的库包名。
      const binaries = [join(application, 'hentai_park'), ...readdirSync(join(application, 'lib'))
        .filter(file => /\.so(?:\.|$)/.test(file)).map(file => join(application, 'lib', file))];
      const dependencies = run('dpkg-shlibdeps', [
        '-O', '--ignore-missing-info', `-l${join(application, 'lib')}`,
        ...binaries.flatMap(file => ['-e', file]),
      ], { cwd: staging, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }).stdout
        .split('\n').find(line => line.startsWith('shlibs:Depends='))?.slice('shlibs:Depends='.length);
      if (!dependencies) throw Error('无法确定 Linux 安装包的运行库依赖');
      mkdirSync(join(root, 'DEBIAN'), { recursive: true });
      writeFileSync(join(root, 'DEBIAN/control'), [
        'Package: hentaipark', `Version: ${name}-${number}`, 'Architecture: amd64',
        'Maintainer: HentaiPark contributors <noreply@github.com>', 'Section: video', 'Priority: optional',
        `Depends: ${dependencies}, xdg-utils`, 'Description: HentaiPark desktop client', '',
      ].join('\n'));
      mkdirSync(join(root, 'usr/share/applications'), { recursive: true });
      writeFileSync(join(root, 'usr/share/applications/hentaipark.desktop'), [
        '[Desktop Entry]', 'Type=Application', 'Name=HentaiPark',
        'Exec=/opt/hentaipark/hentai_park', 'Icon=hentaipark', 'Terminal=false',
        'Categories=AudioVideo;', '',
      ].join('\n'));
      mkdirSync(join(root, 'usr/share/pixmaps'), { recursive: true });
      copyFileSync('assets/branding/app_icon.png', join(root, 'usr/share/pixmaps/hentaipark.png'));
      run('dpkg-deb', ['--build', '--root-owner-group', root, join(out, `${prefix}.deb`)]);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }
  if (platform === 'macos') {
    const app = 'build/macos/Build/Products/Release/HentaiPark.app';
    zip(app, `${prefix}.zip`, true);
    run('pkgbuild', ['--component', app, '--install-location', '/Applications',
      '--identifier', 'com.hentaipark.installer', '--version', name, join(out, `${prefix}.pkg`)]);
  }
  if (platform === 'ios') zip('build/ios/iphonesimulator/Runner.app', `${prefix}.zip`, true);
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
