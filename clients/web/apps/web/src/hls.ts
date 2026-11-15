import {t} from './i18n.js';
import Hls from 'hls.js';
import workerPath from 'hls.js/dist/hls.worker.js?url';

export function attachHls(media: HTMLMediaElement, source: string, onError: (message: string) => void) {
  const initial=new URL(source,window.location.origin);
  const offline=/^\/api\/v1\/offline\/[^/]+\/files\/\d+$/.test(initial.pathname)?initial.pathname.slice(0,initial.pathname.lastIndexOf('/')+1):undefined;
  const allowed=(target:URL)=>target.origin===window.location.origin&&(offline?target.pathname.startsWith(offline)&&/^\d+$/.test(target.pathname.slice(offline.length)):target.pathname.startsWith('/api/v1/media/'));
  if(!allowed(initial))throw new Error(t("HLS资源不在实例授权链中"));
  if (!Hls.isSupported()) {
    if (media.canPlayType('application/vnd.apple.mpegurl')) { media.src = source; return () => undefined; }
    throw new Error(t("当前浏览器不支持HLS播放"));
  }
  const player = new Hls({ workerPath, maxBufferLength: 30, backBufferLength: 60, xhrSetup(xhr, url) { const target = new URL(url, window.location.origin); if (!allowed(target)) throw new Error(t("HLS资源不在实例授权链中")); xhr.withCredentials = true; } });
  player.on(Hls.Events.ERROR, (_event, data) => { if (data.fatal) onError(t("HLS播放失败：") + data.details + t("，可重取授权后重试。")); });
  player.attachMedia(media); player.loadSource(source);
  return () => player.destroy();
}
