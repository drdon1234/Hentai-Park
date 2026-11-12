/// 游戏大资源使用独立浏览器配置内的 CacheStorage，避免超过 HTTP 缓存
/// 单文件限制后每次重新下载。每次复用先验证源站版本，不缓存网页或凭据。
const gameResourceCacheScript = r'''
(() => {
  if (!window.caches || !window.fetch || location.protocol !== 'https:') return;
  const fetchResource = window.fetch.bind(window);
  const cacheName = 'park-game-resources';
  const limit = 512 * 1024 * 1024;
  const pending = new Map();
  const reusable = response => response.status === 200 &&
    !/\b(?:no-store|private)\b/i.test(response.headers.get('cache-control') || '') &&
    !!(response.headers.get('etag') || response.headers.get('last-modified'));
  const size = response => Number(response.headers.get('content-length')) || 0;
  const sameVersion = (a, b) => size(a) === size(b) &&
    (a.headers.get('etag') ? a.headers.get('etag') === b.headers.get('etag') :
      a.headers.get('last-modified') === b.headers.get('last-modified'));
  let writes = Promise.resolve();
  window.fetch = async (input, init) => {
    let request;
    try { request = new Request(input, init); } catch (_) { return fetchResource(input, init); }
    const url = new URL(request.url);
    if (request.method !== 'GET' || url.origin !== location.origin ||
        !/\.(?:zip|wasm|data|pck|rpa|bundle)$/i.test(url.pathname) ||
        request.cache === 'no-store' || request.cache === 'reload' ||
        request.headers.has('authorization') || request.headers.has('range') ||
        ['if-match', 'if-none-match', 'if-modified-since', 'if-unmodified-since', 'if-range']
          .some(name => request.headers.has(name))) {
      return fetchResource(request);
    }
    let cache;
    try {
      cache = await caches.open(cacheName);
      const saved = await cache.match(request);
      if (saved) {
        const check = await fetchResource(new Request(request, {method: 'HEAD', cache: 'no-store'}));
        if (check.url === request.url && reusable(check) && sameVersion(saved, check)) {
          request.signal.throwIfAborted();
          return saved;
        }
        await cache.delete(request);
      }
    } catch (_) { /* 存储不可用或验证失败时仍由正常网络请求决定结果。 */ }
    const response = await fetchResource(request);
    const bytes = size(response);
    if (cache && response.url === request.url && reusable(response) &&
        bytes >= 1024 * 1024 && bytes <= limit && !pending.has(request.url)) {
      const copy = response.clone();
      const write = writes = writes.catch(() => {}).then(async () => {
        let used = 0;
        const entries = [];
        for (const key of await cache.keys()) {
          const entry = await cache.match(key);
          const length = entry ? size(entry) : 0;
          used += length; entries.push([key, length]);
        }
        while (entries.length && used + bytes > limit) {
          const [key, length] = entries.shift();
          await cache.delete(key); used -= length;
        }
        await cache.put(request, copy);
      }).catch(() => {}).finally(() => pending.delete(request.url));
      pending.set(request.url, write);
    }
    return response;
  };
})();
''';
