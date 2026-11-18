// Windows 构建、签名与分发包生成脚本；所有构建与签名临时文件仅写入被忽略的 test/。
import {
  appendFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const windowsRoot = resolve(scriptDir, '..');
const repoRoot = resolve(windowsRoot, '../..');

const pubspec = readFileSync(join(repoRoot, 'pubspec.yaml'), 'utf8');
const versionMatch = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(pubspec);
if (!versionMatch) {
  throw new Error('pubspec.yaml 必须声明应用版本和构建号');
}
const [, appVersion, buildNumber] = versionMatch;

function output(key, value) {
  console.log(`${key}=${value}`);
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
  }
}

function run(command, args, options = {}) {
  const res = spawnSync(command, args, { stdio: 'inherit', cwd: repoRoot, ...options });
  if (res.error || res.status !== 0) {
    throw res.error ?? new Error(`${command} failed with exit code ${res.status}`);
  }
}

function findSignTool() {
  const kitsRoot = join(process.env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)', 'Windows Kits', '10', 'bin');
  if (!existsSync(kitsRoot)) return null;
  const versions = readdirSync(kitsRoot).filter((d) => /^10\./.test(d)).sort().reverse();
  for (const ver of versions) {
    const candidate = join(kitsRoot, ver, 'x64', 'signtool.exe');
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

function findIscc() {
  const check = spawnSync('powershell', ['-NoProfile', '-Command', '(Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source'], {
    encoding: 'utf8',
  });
  const fromPath = check.stdout?.trim();
  if (fromPath && existsSync(fromPath)) return fromPath;

  const candidates = [
    join(process.env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)', 'Inno Setup 6', 'ISCC.exe'),
    join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Inno Setup 6', 'ISCC.exe'),
    join(process.env.LOCALAPPDATA ?? '', 'Programs', 'Inno Setup 6', 'ISCC.exe'),
  ];
  return candidates.find((p) => p && existsSync(p)) ?? null;
}

function prepareSigning() {
  const pfxBase64 = (process.env.WINDOWS_PFX_BASE64 ?? '').trim();
  const pfxPassword = process.env.WINDOWS_PFX_PASSWORD ?? '';
  if (!pfxBase64 && !pfxPassword) {
    return null;
  }
  if (!pfxBase64 || !pfxPassword) {
    throw new Error('WINDOWS_PFX_BASE64 与 WINDOWS_PFX_PASSWORD 必须同时提供，不允许部分缺失');
  }
  const signingDir = resolve(repoRoot, 'test/signing');
  mkdirSync(signingDir, { recursive: true });
  const pfxPath = join(signingDir, 'windows-release.pfx');
  writeFileSync(pfxPath, Buffer.from(pfxBase64, 'base64'));

  const signtool = findSignTool();
  if (!signtool) {
    throw new Error('未找到 Windows SDK signtool.exe，无法完成请求的代码签名');
  }
  return { pfxPath, pfxPassword, signtool, timestampUrl: (process.env.WINDOWS_TIMESTAMP_URL ?? '').trim() };
}

function signBinary(signing, filePath) {
  if (!signing) return;
  const args = ['sign', '/fd', 'SHA256', '/f', signing.pfxPath, '/p', signing.pfxPassword];
  if (signing.timestampUrl) {
    args.push('/tr', signing.timestampUrl, '/td', 'SHA256');
  }
  args.push(filePath);
  // Avoid printing args containing password; spawn directly with stdio inherit for tool output only
  const res = spawnSync(signing.signtool, args, { stdio: 'pipe', encoding: 'utf8' });
  if (res.status !== 0) {
    throw new Error(`signtool 签名失败 (${basename(filePath)}): ${res.stderr || res.stdout}`);
  }
  run(signing.signtool, ['verify', '/pa', filePath]);
}

function createZipFromDirectory(sourceDir, destinationZip) {
  if (existsSync(destinationZip)) rmSync(destinationZip, { force: true });
  const psScript = `Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::CreateFromDirectory($env:ZIP_SRC, $env:ZIP_DST, [System.IO.Compression.CompressionLevel]::Optimal, $false)`;
  run('powershell', ['-NoProfile', '-Command', psScript], {
    env: { ...process.env, ZIP_SRC: sourceDir, ZIP_DST: destinationZip },
  });
}

function writeSha256Files(distDir, files) {
  for (const file of files) {
    const fullPath = join(distDir, file);
    const digest = createHash('sha256').update(readFileSync(fullPath)).digest('hex');
    writeFileSync(`${fullPath}.sha256`, `${digest}  ${basename(file)}\n`, 'utf8');
  }
}

const command = process.argv[2];

if (command === 'metadata') {
  const refTag = process.env.GITHUB_REF_TYPE === 'tag' ? process.env.GITHUB_REF_NAME : '';
  if (refTag && refTag !== `v${appVersion}`) {
    throw new Error(`标签 (${refTag}) 必须与 pubspec.yaml 版本 (v${appVersion}) 一致`);
  }
  const archChoice = (process.env.WINDOWS_ARCH ?? 'all').trim();
  const archList = archChoice === 'x64' ? ['x64'] : archChoice === 'arm64' ? ['arm64'] : ['x64', 'arm64'];
  output('version', appVersion);
  output('build_number', buildNumber);
  output('tag', `v${appVersion}`);
  output('matrix', JSON.stringify({ include: archList.map((arch) => ({ arch })) }));
} else if (command === 'package') {
  const arch = process.argv[3];
  const flags = new Set(process.argv.slice(4));
  if (arch !== 'x64' && arch !== 'arm64') {
    throw new Error('用法: package <x64|arm64> [--skip-installer] [--single-node]');
  }

  const distDir = resolve(repoRoot, 'test/distribution');
  const stageRoot = resolve(repoRoot, `test/windows-stage-${arch}`);
  const publishDir = join(stageRoot, 'app');
  const portableDir = join(stageRoot, 'portable');

  rmSync(stageRoot, { recursive: true, force: true });
  mkdirSync(distDir, { recursive: true });
  mkdirSync(publishDir, { recursive: true });

  const signing = prepareSigning();
  try {
    run(process.execPath, ['clients/windows/scripts/sync-assets.mjs']);
    run(process.execPath, ['clients/windows/scripts/check-localizations.mjs']);

    const publishArgs = [
      'publish',
      'clients/windows/src/Park.App/Park.App.csproj',
      '-c',
      'Release',
      '-r',
      `win-${arch}`,
      '--self-contained',
      'true',
      '-o',
      publishDir,
    ];
    if (flags.has('--single-node')) {
      publishArgs.push('-m:1', '-nr:false');
    }
    if (process.env.NUGET_LOCAL_SOURCE) {
      publishArgs.push('--source', process.env.NUGET_LOCAL_SOURCE);
    }
    run('dotnet', publishArgs);

    const exePath = join(publishDir, 'HentaiPark.exe');
    if (!existsSync(exePath)) {
      throw new Error(`缺少发布可执行文件: ${exePath}`);
    }

    // Bundle synced shared assets (runtime, 101+ sources, i18n, tag_translations, worldbook_terms, licenses)
    const syncedAssets = join(windowsRoot, 'assets');
    if (!existsSync(join(syncedAssets, 'runtime/park_runtime.js')) || !existsSync(join(syncedAssets, 'sources/index.json'))) {
      throw new Error('缺少已同步的共享插件或运行时资产');
    }
    cpSync(syncedAssets, join(publishDir, 'assets'), { recursive: true });

    signBinary(signing, exePath);

    const suffix = signing ? '' : '-unsigned';
    const basePrefix = `HentaiPark-${appVersion}-${buildNumber}-windows-${arch}`;
    const generatedFiles = [];

    // 1. Portable ZIP (includes portable.flag so data stays self-contained in ./data)
    cpSync(publishDir, portableDir, { recursive: true });
    writeFileSync(join(portableDir, 'portable.flag'), '', 'utf8');
    const portableZipName = `${basePrefix}-portable${suffix}.zip`;
    createZipFromDirectory(portableDir, join(distDir, portableZipName));
    generatedFiles.push(portableZipName);

    // 2. Standard User-Mode Installer EXE (Inno Setup 6)
    if (!flags.has('--skip-installer')) {
      const iscc = findIscc();
      if (!iscc) {
        throw new Error('未找到 Inno Setup 6 (ISCC.exe)；本地仅验证便携包时可传入 --skip-installer');
      }
      const setupBaseName = `${basePrefix}-setup${suffix}`;
      const issPath = join(windowsRoot, 'installer/HentaiPark.iss');
      run(iscc, [
        `/DAppVersion=${appVersion}`,
        `/DAppArch=${arch}`,
        `/DSourceDir=${publishDir}`,
        `/DOutputDir=${distDir}`,
        `/DOutputBaseFilename=${setupBaseName}`,
        issPath,
      ]);
      const setupExeName = `${setupBaseName}.exe`;
      signBinary(signing, join(distDir, setupExeName));
      generatedFiles.push(setupExeName);
    }

    writeSha256Files(distDir, generatedFiles);
    console.log(`Packaged Windows (${arch}): ${generatedFiles.join(', ')}`);
  } finally {
    rmSync(resolve(repoRoot, 'test/signing'), { recursive: true, force: true });
    rmSync(stageRoot, { recursive: true, force: true });
  }
} else {
  throw new Error('用法: metadata | package <x64|arm64> [--skip-installer]');
}
