import {t} from './i18n.js';
import type { ImageTransform } from './api.js';

export function restoreImage(canvas: HTMLCanvasElement, image: HTMLImageElement, transform: ImageTransform) {
  const width = image.naturalWidth; const height = image.naturalHeight; const segments = transform.segments;
  if (transform.type !== 'unscramble-strips' || !Number.isInteger(segments) || segments < 1 || segments > 4096 || segments > height || width < 1 || height < 1 || width * height > 32_000_000) throw new Error(t("图片重排参数或尺寸超出支持范围。"));
  canvas.width = width; canvas.height = height;
  const context = canvas.getContext('2d'); if (!context) throw new Error(t("浏览器无法还原此图片。"));
  context.imageSmoothingEnabled = false;
  const base = Math.floor(height / segments); const remainder = height % segments;
  for (let index = 0; index < segments; index++) {
    const sourceY = height - base * (index + 1) - remainder;
    const targetY = base * index + (index === 0 ? 0 : remainder);
    const stripHeight = base + (index === 0 ? remainder : 0);
    context.drawImage(image, 0, sourceY, width, stripHeight, 0, targetY, width, stripHeight);
  }
}
