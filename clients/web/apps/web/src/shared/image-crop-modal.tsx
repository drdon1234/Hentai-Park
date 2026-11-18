import { useEffect, useRef, useState } from 'react';
import { AdaptiveSheet } from '@hentai-park/design-system';
import { t } from '../i18n.js';
import { useBackDismissable } from '../native.js';

type CropRect = { x: number; y: number; w: number; h: number };

export function ImageCropModal({
  file,
  open,
  onCancel,
  onConfirm,
}: {
  file: File | undefined;
  open: boolean;
  onCancel: () => void;
  onConfirm: (cropped: File) => void;
}) {
  const [previewUrl, setPreviewUrl] = useState<string>();
  const [rect, setRect] = useState<CropRect>({ x: 0, y: 0, w: 1, h: 1 });
  const [aspect, setAspect] = useState<'free' | '1:1' | '4:3' | '16:9'>('free');
  const stageRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const dragStart = useRef<{ x: number; y: number } | null>(null);

  useBackDismissable(open, onCancel);

  useEffect(() => {
    if (!file || !open) {
      setPreviewUrl(undefined);
      return;
    }
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
    setRect({ x: 0, y: 0, w: 1, h: 1 });
    return () => URL.revokeObjectURL(url);
  }, [file, open]);

  const applyAspect = (next: 'free' | '1:1' | '4:3' | '16:9') => {
    setAspect(next);
    if (next === 'free') {
      setRect({ x: 0, y: 0, w: 1, h: 1 });
      return;
    }
    const img = imgRef.current;
    const imgRatio = img && img.naturalHeight ? img.naturalWidth / img.naturalHeight : 1;
    const targetRatio = next === '1:1' ? 1 : next === '4:3' ? 4 / 3 : 16 / 9;
    if (imgRatio > targetRatio) {
      const w = targetRatio / imgRatio;
      setRect({ x: (1 - w) / 2, y: 0, w, h: 1 });
    } else {
      const h = imgRatio / targetRatio;
      setRect({ x: 0, y: (1 - h) / 2, w: 1, h });
    }
  };

  const commitCrop = async () => {
    if (!file) return;
    if (rect.x <= 0.005 && rect.y <= 0.005 && rect.w >= 0.99 && rect.h >= 0.99) {
      onConfirm(file);
      return;
    }
    const bitmap = await createImageBitmap(file);
    try {
      const sx = Math.max(0, Math.round(rect.x * bitmap.width));
      const sy = Math.max(0, Math.round(rect.y * bitmap.height));
      const sw = Math.max(8, Math.min(bitmap.width - sx, Math.round(rect.w * bitmap.width)));
      const sh = Math.max(8, Math.min(bitmap.height - sy, Math.round(rect.h * bitmap.height)));
      const canvas = document.createElement('canvas');
      canvas.width = sw;
      canvas.height = sh;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        onConfirm(file);
        return;
      }
      ctx.drawImage(bitmap, sx, sy, sw, sh, 0, 0, sw, sh);
      const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
      if (!blob) {
        onConfirm(file);
        return;
      }
      onConfirm(new File([blob], file.name.replace(/\.[^.]+$/, '') + '-crop.png', { type: 'image/png' }));
    } finally {
      bitmap.close();
    }
  };

  if (!open || !file) return null;

  return (
    <AdaptiveSheet
      open={open}
      title={t('裁剪搜索区域')}
      closeLabel={t('取消')}
      onClose={onCancel}
      footer={
        <>
          <button type="button" className="chip" onClick={() => onConfirm(file)}>
            {t('使用原图')}
          </button>
          <button type="button" className="primary-link" onClick={() => void commitCrop()}>
            {t('确认裁剪')}
          </button>
        </>
      }
    >
      <p className="muted" style={{ marginTop: 0 }}>
        {t('在画面上拖拽框选需要检索的主体，去除多余黑边或拼图背景可显著提升反搜准确度。')}
      </p>
      <div className="action-row">
        {(
          [
            ['free', '自由框选'],
            ['1:1', '1:1'],
            ['4:3', '4:3'],
            ['16:9', '16:9'],
          ] as const
        ).map(([key, label]) => (
          <button
            key={key}
            type="button"
            className={`chip ${aspect === key ? 'active' : ''}`}
            onClick={() => applyAspect(key)}
          >
            {key === 'free' ? t(label) : label}
          </button>
        ))}
      </div>
      {previewUrl ? (
        <div
          ref={stageRef}
          className="crop-canvas-stage"
          onPointerDown={(e) => {
            const bounds = e.currentTarget.getBoundingClientRect();
            const x = Math.max(0, Math.min(1, (e.clientX - bounds.left) / bounds.width));
            const y = Math.max(0, Math.min(1, (e.clientY - bounds.top) / bounds.height));
            e.currentTarget.setPointerCapture(e.pointerId);
            dragStart.current = { x, y };
            setAspect('free');
            setRect({ x, y, w: 0.02, h: 0.02 });
          }}
          onPointerMove={(e) => {
            if (!dragStart.current) return;
            const bounds = e.currentTarget.getBoundingClientRect();
            const cx = Math.max(0, Math.min(1, (e.clientX - bounds.left) / bounds.width));
            const cy = Math.max(0, Math.min(1, (e.clientY - bounds.top) / bounds.height));
            const x = Math.min(dragStart.current.x, cx);
            const y = Math.min(dragStart.current.y, cy);
            const w = Math.max(0.05, Math.abs(cx - dragStart.current.x));
            const h = Math.max(0.05, Math.abs(cy - dragStart.current.y));
            setRect({ x, y, w: Math.min(1 - x, w), h: Math.min(1 - y, h) });
          }}
          onPointerUp={() => {
            dragStart.current = null;
          }}
        >
          <img ref={imgRef} src={previewUrl} alt={t('本次反搜图片预览')} />
          <div
            className="crop-selection-box"
            style={{
              left: `${rect.x * 100}%`,
              top: `${rect.y * 100}%`,
              width: `${rect.w * 100}%`,
              height: `${rect.h * 100}%`,
            }}
          />
        </div>
      ) : null}
    </AdaptiveSheet>
  );
}
