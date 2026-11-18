import { t } from './i18n.js';
import type { ImageTransform } from './api.js';

export function restoreImage(canvas: HTMLCanvasElement, image: HTMLImageElement, transform: ImageTransform) {
  const width = image.naturalWidth;
  const height = image.naturalHeight;
  const segments = transform.segments;
  if (
    transform.type !== 'unscramble-strips' ||
    !Number.isInteger(segments) ||
    segments < 1 ||
    segments > 4096 ||
    segments > height ||
    width < 1 ||
    height < 1 ||
    width * height > 32_000_000
  ) {
    throw new Error(t('图片重排参数或尺寸超出支持范围。'));
  }
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  if (!context) throw new Error(t('浏览器无法还原此图片。'));
  context.imageSmoothingEnabled = false;
  const base = Math.floor(height / segments);
  const remainder = height % segments;
  for (let index = 0; index < segments; index++) {
    const sourceY = height - base * (index + 1) - remainder;
    const targetY = base * index + (index === 0 ? 0 : remainder);
    const stripHeight = base + (index === 0 ? remainder : 0);
    context.drawImage(image, 0, sourceY, width, stripHeight, 0, targetY, width, stripHeight);
  }
}

/**
 * Lossless pixel-sampled comic margin trimmer (aligned with Android `cropWhiteBorders`).
 * Detects uniform white/near-black borders up to 18% per edge and draws only the content rect,
 * never clipping comic panels with `object-fit: cover`.
 */
export function cropComicMargins(canvas: HTMLCanvasElement, source: HTMLImageElement | HTMLCanvasElement) {
  const width = source instanceof HTMLImageElement ? source.naturalWidth : source.width;
  const height = source instanceof HTMLImageElement ? source.naturalHeight : source.height;
  if (width < 32 || height < 32 || width * height > 32_000_000) return false;

  const sampleScale = Math.min(1, 512 / Math.max(width, height));
  const sw = Math.max(16, Math.round(width * sampleScale));
  const sh = Math.max(16, Math.round(height * sampleScale));
  const probe = document.createElement('canvas');
  probe.width = sw;
  probe.height = sh;
  const pctx = probe.getContext('2d', { willReadFrequently: true });
  if (!pctx) return false;
  pctx.drawImage(source, 0, 0, sw, sh);
  const data = pctx.getImageData(0, 0, sw, sh).data;

  const pixelAt = (x: number, y: number) => {
    const idx = (y * sw + x) * 4;
    return [data[idx]!, data[idx + 1]!, data[idx + 2]!] as const;
  };
  const corners = [pixelAt(0, 0), pixelAt(sw - 1, 0), pixelAt(0, sh - 1), pixelAt(sw - 1, sh - 1)];
  const ref = corners[0]!;
  const isBorderPixel = (x: number, y: number) => {
    const [r, g, b] = pixelAt(x, y);
    const brightWhite = r > 238 && g > 238 && b > 238;
    const deepBlack = r < 16 && g < 16 && b < 16;
    const matchesCorner = Math.abs(r - ref[0]) <= 14 && Math.abs(g - ref[1]) <= 14 && Math.abs(b - ref[2]) <= 14;
    return brightWhite || deepBlack || matchesCorner;
  };

  const maxX = Math.floor(sw * 0.18);
  const maxY = Math.floor(sh * 0.18);
  let top = 0;
  while (top < maxY) {
    let uniform = 0;
    for (let x = 0; x < sw; x += 2) if (isBorderPixel(x, top)) uniform++;
    if (uniform / Math.ceil(sw / 2) < 0.96) break;
    top++;
  }
  let bottom = sh - 1;
  while (sh - 1 - bottom < maxY && bottom > top + 8) {
    let uniform = 0;
    for (let x = 0; x < sw; x += 2) if (isBorderPixel(x, bottom)) uniform++;
    if (uniform / Math.ceil(sw / 2) < 0.96) break;
    bottom--;
  }
  let left = 0;
  while (left < maxX) {
    let uniform = 0;
    for (let y = top; y <= bottom; y += 2) if (isBorderPixel(left, y)) uniform++;
    if (uniform / Math.max(1, Math.ceil((bottom - top + 1) / 2)) < 0.96) break;
    left++;
  }
  let right = sw - 1;
  while (sw - 1 - right < maxX && right > left + 8) {
    let uniform = 0;
    for (let y = top; y <= bottom; y += 2) if (isBorderPixel(right, y)) uniform++;
    if (uniform / Math.max(1, Math.ceil((bottom - top + 1) / 2)) < 0.96) break;
    right--;
  }

  probe.width = 0;
  probe.height = 0;
  if (top === 0 && left === 0 && right === sw - 1 && bottom === sh - 1) return false;

  const sx = Math.floor(left / sampleScale);
  const sy = Math.floor(top / sampleScale);
  const cw = Math.max(1, Math.ceil((right - left + 1) / sampleScale));
  const ch = Math.max(1, Math.ceil((bottom - top + 1) / sampleScale));
  canvas.width = cw;
  canvas.height = ch;
  const ctx = canvas.getContext('2d');
  if (!ctx) return false;
  ctx.drawImage(source, sx, sy, cw, ch, 0, 0, cw, ch);
  return true;
}
