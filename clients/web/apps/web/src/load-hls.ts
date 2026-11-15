import {t} from './i18n.js';

export const playerModuleError = () => t('播放器组件加载失败，请刷新页面后重试。');
export async function loadHls() {
  try { return await import('./hls.js'); }
  catch { throw new Error(playerModuleError()); }
}
