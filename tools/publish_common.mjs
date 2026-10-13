import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const rawBase = 'https://raw.githubusercontent.com/drdon1234/Hentai-Park';
const matches = (pattern, value) => typeof value === 'string' && pattern.exec(value)?.[0] === value;
export const isSourceKey = value => matches(/^[A-Za-z0-9_-]+$/, value) && value.length <= 100 && value !== '_app';
export const isSha256 = value => matches(/^[a-fA-F0-9]{64}$/, value);
export const isCommit = value => matches(/^[a-f0-9]{40}$/, value);
export const isReleaseVersion = value => matches(/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/, value)
  && value.split('.').every(part => BigInt(part) <= 9223372036854775807n);
export function versionParts(value) {
  if (!isReleaseVersion(value)) throw new Error('version 必须是无前导零的三段非负整数');
  return value.split('.').map(BigInt);
}
export function compareVersions(a, b) {
  const left = versionParts(a), right = versionParts(b);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] > right[i] ? 1 : -1;
  }
  return 0;
}
export async function readUtf8(filename) {
  const bytes = await readFile(filename);
  const text = bytes.toString('utf8');
  if (!bytes.equals(Buffer.from(text, 'utf8'))) throw new Error(`${filename} 不是有效 UTF-8 文件`);
  return text;
}
export const sha256 = value => createHash('sha256').update(value).digest('hex');
export function officialAssetUrl(commit, relative) {
  if (!isCommit(commit)) throw new Error('commit 必须是源码提交的完整 40 位小写十六进制 SHA');
  if (!matches(/^assets\/(sources\/[A-Za-z0-9_-]+\.js|tag_translations\/[A-Za-z0-9_-]+\/[A-Za-z-]+\.json)$/, relative)) {
    throw new Error('官方资产路径无效');
  }
  return `${rawBase}/${commit}/${relative}`;
}
