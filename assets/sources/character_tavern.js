(function () {
  'use strict';
  const SITE = 'https://character-tavern.com';
  const CDN = 'ct-cards.storage.character-tavern.com';
  function path(id) {
    const value = String(id || '');
    if (!/^[A-Za-z0-9._~-]{1,80}\/[A-Za-z0-9._~-]{1,160}$/.test(value) ||
        value.split('/').some(x => x === '.' || x === '..')) throw Park.error('NOT_FOUND', '内容不存在');
    return value;
  }
  function detailUrl(id) { return SITE + '/character/' + path(id).split('/').map(encodeURIComponent).join('/'); }
  function safeImage(value, base) {
    try {
      const u = new URL(value, base);
      return u.protocol === 'https:' && u.hostname === CDN && !u.username && !u.password && !u.port ? u.href : '';
    } catch (_) { return ''; }
  }
  async function html(source, url) {
    const response = await source.http.get(url);
    source.http.ensureOk(response);
    if (response.body.length > 6 * 1024 * 1024) throw Park.error('PARSE', '站点返回了无效结果');
    return Park.html.parse(response.body);
  }
  function list(doc, base, number) {
    const seen = new Set(), items = [];
    for (const a of doc.querySelectorAll('a[href]')) {
      let url;
      try { url = new URL(a.getAttribute('href'), base); } catch (_) { continue; }
      if (url.hostname !== 'character-tavern.com') continue;
      const match = /^\/character\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname);
      if (!match || !a.querySelector('h3')) continue;
      let id;
      try { id = path(decodeURIComponent(match[1]) + '/' + decodeURIComponent(match[2])); } catch (_) { continue; }
      const title = Park.html.text(a.querySelector('h3'));
      if (!title || seen.has(id)) continue;
      seen.add(id);
      items.push({id, title, subtitle: Park.html.text(a.querySelector('p')),
        cover: safeImage(a.querySelector('img')?.getAttribute('src'), base),
        authors: [id.split('/')[0]], mediaKind: 'tavern', tavernKind: 'character'});
    }
    return {items, page: number, hasNext: items.length >= 30};
  }
  Park.register({
    key: 'character_tavern', name: 'Character Tavern', version: '0.0.2', minAppVersion: '0.14.0',
    type: 'tavern', category: 'tavern', color: '#805F9A', description: '角色卡',
    homepage: SITE, domains: ['character-tavern.com'], network: {vpnHint: true},
    defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}],
    async feed(key, {page = 1} = {}) { return this.search({keyword: '', page}); },
    async search({keyword = '', page = 1} = {}) {
      if (!Number.isInteger(page) || page < 1 || page > 1000 || String(keyword).length > 200) throw Park.error('CONFIG', '访问受限');
      const url = new URL('/search/cards', SITE);
      if (keyword) url.searchParams.set('query', keyword);
      if (page > 1) url.searchParams.set('page', String(page));
      return list(await html(this, url.href), url.href, page);
    },
    async detail(id) {
      const url = detailUrl(id), doc = await html(this, url);
      const title = Park.html.text(doc.querySelector('h1'));
      if (!title) throw Park.error('PARSE', '站点返回了无效结果');
      return {id: path(id), title, url, mediaKind: 'tavern', tavernKind: 'character',
        cover: safeImage(doc.querySelector('meta[property="og:image"]')?.getAttribute('content'), url),
        description: doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || '', authors: [id.split('/')[0]]};
    },
    async tavernAsset(id) {
      const url = detailUrl(id), doc = await html(this, url);
      for (const a of doc.querySelectorAll('a[href]')) {
        const candidate = safeImage(a.getAttribute('href'), url);
        if (candidate && new URL(candidate).searchParams.get('action') === 'download') {
          return {kind: 'character', format: 'png', url: candidate};
        }
      }
      throw Park.error('UNSUPPORTED', '此作品不提供下载');
    },
  });
})();
