/* 由 tools/build_feed_sources.mjs 生成；请修改模板与站点配置。 */
(function () {
  'use strict';
  const SITE = {"key":"feed51cg","name":"51吃瓜网","names":{"zh-Hant":"51吃瓜網","en":"51CG","ja":"51吃瓜網","ko":"51CG","es":"51CG","ru":"51CG","ar":"51CG"},"home":"https://51cg1.com","domain":"51cg1.com","imageDomain":"pic.gyezbp.cn","hostPattern":"^(?:www\\.)?51cg[0-9]+\\.com$","linkPattern":"(?:www\\.)?51cg[0-9]+\\.com"};
  const catalogCache = new Map();
  const option = (key, label) => ({key, label, type: 'multi', default: [], dynamic: true, values: []});
  const text = node => Park.html.text(node);
  const resolver = SITE.release ? Park.createDomainResolver({
    initialOrigin: SITE.home,
    accept: origin => new RegExp(SITE.hostPattern).test(new URL(origin).hostname),
    async discover(http) {
      const response = await http.get(SITE.release, {mode: 'native', followRedirects: false, timeout: 15000});
      http.ensureOk(response);
      if (response.url !== SITE.release || typeof response.body !== 'string' || response.body.length > 2097152) {
        throw Park.error('PARSE', '加载失败');
      }
      let html = response.body;
      if (SITE.encodedRelease) {
        const encoded = /document\.write\(Base64\.decode\(['"]([A-Za-z0-9+/=]+)['"]\)\)/.exec(html)?.[1];
        if (!encoded || encoded.length > 2097152) throw Park.error('PARSE', '加载失败');
        try {
          html = decodeURIComponent([...atob(encoded)].map(char => '%' + char.charCodeAt(0).toString(16).padStart(2, '0')).join(''));
        } catch (_) { throw Park.error('PARSE', '加载失败'); }
      }
      const doc = Park.html.parse(html), result = [];
      for (const node of doc.querySelectorAll(SITE.releaseSelector)) {
        try {
          const candidate = new URL(node.getAttribute('href'), SITE.release);
          if (candidate.protocol === 'https:' && !candidate.username && !candidate.password && !candidate.port &&
              candidate.pathname === '/' && !candidate.search && !candidate.hash &&
              new RegExp(SITE.hostPattern).test(candidate.hostname)) result.push(candidate.origin);
        } catch (_) { /* Ignore unrelated links on the publication page. */ }
      }
      return [...new Set(result)];
    },
    verify(body) {
      if (typeof body !== 'string' || body.length > 2097152) return false;
      const doc = Park.html.parse(body);
      return !!doc.querySelector(SITE.archive ? 'a.category-nav__link' : 'nav a[href*="/category/"]') &&
        !!doc.querySelector(SITE.archive ? '.video-item a[href*="/archives/"]' : 'article .post-card');
    },
  }) : null;

  function imageUrl(value, base) {
    try {
      if (!value) return '';
      const url = new URL(String(value || ''), base);
      return Park.url.parse(url.href, base, [url.hostname])?.href || '';
    } catch (_) { return ''; }
  }
  function idValue(value) {
    const id = String(value || '');
    if (!/^[1-9]\d{0,14}$/.test(id)) throw Park.error('NOT_FOUND', '内容不存在');
    return id;
  }
  const articlePath = id => '/archives/' + id + '/';
  function pageValue(value) {
    const page = Number(value ?? 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', '访问受限');
    return page;
  }
  function itemId(href, base) {
    try {
      const url = new URL(href, base);
      if (url.origin !== base || !Park.url.parse(url.href, base, [url.hostname])) return '';
      return /^\/archives\/([1-9]\d{0,14})(?:\.html|\/)$/i.exec(url.pathname)?.[1] || '';
    } catch (_) { return ''; }
  }
  function image(node, base) {
    if (!node) return '';
    const preferred = ['x-bg-loader-url', 'z-image-loader-url', 'data-src', 'data-original', 'src'];
    for (const name of preferred) {
      const value = node.getAttribute(name);
      if (value && !/\/(?:zw|placeholder)\.(?:png|gif)/i.test(value)) {
        const url = imageUrl(value, base);
        if (url) return url;
      }
    }
    for (const attr of node.attributes || []) {
      if (/^data-/i.test(attr.name) && /^https:\/\//i.test(attr.value)) {
        const url = imageUrl(attr.value, base);
        if (url) return url;
      }
    }
    return '';
  }
  function cover(card, base) {
    for (const node of card.querySelectorAll('[x-bg-loader-url], [z-image-loader-url], img')) {
      const direct = image(node, base);
      if (direct) return direct;
    }
    for (const script of card.querySelectorAll('script')) {
      const match = /loadBannerDirect\(\s*['"]([^'"]+)['"]/.exec(script.textContent || '');
      if (match) return imageUrl(match[1], base);
    }
    return '';
  }
  function coverImages(card, base) {
    const found = new Set();
    for (const node of card.querySelectorAll('[x-bg-loader-url], [z-image-loader-url], img')) {
      const url = image(node, base);
      if (url) found.add(url);
      if (found.size >= 6) break;
    }
    return [...found];
  }
  function player(node, base = SITE.home) {
    const id = node.getAttribute('data-video_id') || '';
    if (!/^[1-9]\d{0,20}(?:_\d{1,8})?$/.test(id)) return null;
    try {
      const data = JSON.parse(node.getAttribute('data-config') || node.getAttribute('config') || '{}');
      const url = imageUrl(data.video?.url, SITE.home);
      const parsed = url && new URL(url);
      if (!parsed || !/\.(?:m3u8|mp4)$/i.test(parsed.pathname)) return null;
      const preview = imageUrl(data.video?.pic || data.video?.poster || node.getAttribute('poster'), base);
      return {id, url, preview, format: /\.m3u8$/i.test(parsed.pathname) ? 'hls' : 'mp4'};
    } catch (_) { return null; }
  }
  function blocks(root, base) {
    const result = [];
    function walk(node) {
      if (!node || node.nodeType !== 1) return;
      const tag = node.tagName.toUpperCase();
      if (node.classList.contains('dplayer')) {
        const id = node.getAttribute('data-video_id') || '';
        if (!/^[1-9]\d{0,20}(?:_\d{1,8})?$/.test(id)) throw Park.error('PARSE', '加载失败');
        const video = player(node, base);
        result.push({type: 'video', id, preview: video?.preview || ''});
        return;
      }
      if (tag === 'IMG') {
        const url = image(node, base);
        if (url) result.push({type: 'image', url});
        return;
      }
      if (tag === 'UL' || tag === 'OL') {
        for (const child of node.children || []) walk(child);
        return;
      }
      if (/^(SCRIPT|STYLE|IFRAME|NAV|FORM)$/.test(tag)) return;
      if (/^(P|BLOCKQUOTE|H[1-6]|LI)$/.test(tag)) {
        let pending = '';
        const flush = () => {
          const value = pending.replace(/\s+/g, ' ').trim();
          if (value) result.push({type: 'text', text: value});
          pending = '';
        };
        function inline(child) {
          if (child.nodeType === 3) { pending += child.textContent || ''; return; }
          if (child.nodeType !== 1) return;
          if (child.tagName.toUpperCase() === 'IMG' || child.classList.contains('dplayer')) {
            flush(); walk(child); return;
          }
          if (child.tagName.toUpperCase() === 'BR') { pending += '\n'; return; }
          if (/^(SCRIPT|STYLE|IFRAME)$/.test(child.tagName.toUpperCase())) return;
          for (const nested of child.childNodes || []) inline(nested);
        }
        for (const child of node.childNodes || []) inline(child);
        flush();
      }
    }
    for (const child of root.children || []) {
      if (child.hasAttribute('data-reading-content-end')) break;
      if (child.tagName.toUpperCase() === 'BLOCKQUOTE' && child.querySelectorAll('a[href^="https://"]').length > 1) continue;
      walk(child);
    }
    return result;
  }
  Park.register({
    key: SITE.key, name: SITE.name, version: '0.0.8', minAppVersion: '0.11.0',
    type: 'article', category: 'feed', color: '#488A7B', language: 'zh',
    description: '吃瓜图文，支持分类、标签、搜索与视频',
    i18n: {
      'zh-Hant': {[SITE.name]: SITE.names['zh-Hant'],'吃瓜图文，支持分类、标签、搜索与视频':'吃瓜圖文，支援分類、標籤、搜尋與影片'},
      ja: {[SITE.name]: SITE.names['ja'],'吃瓜图文，支持分类、标签、搜索与视频':'画像付き記事。カテゴリ、タグ、検索、動画に対応'},
      ko: {[SITE.name]: SITE.names['ko'],'吃瓜图文，支持分类、标签、搜索与视频':'이미지 기사, 분류, 태그, 검색 및 동영상 지원'},
      en: {[SITE.name]: SITE.names['en'],'吃瓜图文，支持分类、标签、搜索与视频':'Gossip articles with images, categories, tags, search and video'},
      es: {[SITE.name]: SITE.names['es'],'吃瓜图文，支持分类、标签、搜索与视频':'Artículos con imágenes, categorías, etiquetas, búsqueda y vídeo'},
      ru: {[SITE.name]: SITE.names['ru'],'吃瓜图文，支持分类、标签、搜索与视频':'Статьи с изображениями, категориями, тегами, поиском и видео'},
      ar: {[SITE.name]: SITE.names['ar'],'吃瓜图文，支持分类、标签、搜索与视频':'مقالات مصورة مع تصنيفات ووسوم وبحث وفيديو'},
    },
    homepage: SITE.homepage || SITE.home, domains: [SITE.domain], network: {mode: 'native', vpnHint: true},
    imageDecrypt: {type: 'aes-cbc', key: 'f5d965df75336270', iv: '97b60394abc2fbe1', domains: [SITE.imageDomain]},
    media: {mode: 'native', scope: 'session', origin: SITE.home},
    linkPatterns: [SITE.linkPattern + '/archives/([1-9]\\d{0,14})(?:\\.html|/)(?:[?#]|$)'],
    idPattern: '^([1-9]\\d{0,14})$',
    defaultFeed: 'recommend',
    feeds: [
      {key: 'recommend', label: '推荐'},
      {key: 'category', label: '分类', options: [option('category', '分类')]},
      {key: 'tag', label: '标签', options: [
        {key: 'tagPage', label: '标签页', type: 'number', default: 1},
        {...option('tag', '标签'), dependsOn: ['tagPage']},
      ]},
    ],
    async document(path) {
      const {response: res, origin} = resolver
        ? await resolver.request(this, path, {method: 'GET', timeout: 20000})
        : {response: await this.http.get(new URL(path, SITE.home).href, {timeout: 20000}), origin: SITE.home};
      this.http.ensureOk(res);
      const doc = Park.html.parse(res.body);
      doc.__feedOrigin = origin;
      return doc;
    },
    async catalog(kind, page = 1) {
      const cacheKey = kind + ':' + page;
      const cached = catalogCache.get(cacheKey);
      if (cached && Date.now() - cached.at < 120000) return cached.values;
      const tagsPath = SITE.archive ? (page === 1 ? '/tags/' : '/tags/page/' + page + '/') : (page === 1 ? '/tags.html' : '/tags/' + page + '/');
      const doc = await this.document(kind === 'category' ? '/' : tagsPath);
      const base = doc.__feedOrigin;
      const selector = kind === 'category' ? (SITE.archive ? 'a.category-nav__link' : 'nav a[href*="/category/"]') : 'a[href*="/tag/"]';
      const found = new Map();
      for (const node of doc.querySelectorAll(selector)) {
        let url;
        try { url = new URL(node.getAttribute('href'), base); } catch (_) { continue; }
        if (url.origin !== base || url.search || url.hash) continue;
        const pattern = kind === 'category' ? (SITE.archive ? /^\/[a-z0-9_-]+\/$/i : /^\/category\/[a-z0-9_-]+\/$/i) : /^\/tag\/[^/]+\/$/i;
        if (!pattern.test(url.pathname)) continue;
        const label = text(node) || node.getAttribute('title') || '';
        if (label && label.length <= 256 && !/[\x00-\x1f\x7f]/.test(label)) found.set(url.pathname, label);
      }
      const values = [...found].map(([value, label]) => ({value, label}));
      if (!values.length || values.length > 500) throw Park.error('PARSE', '加载失败');
      catalogCache.set(cacheKey, {at: Date.now(), values});
      return values;
    },
    async filterOptions(request) {
      if (request.scope !== 'feed' || !['category', 'tag'].includes(request.filter) || request.feed !== request.filter) {
        throw Park.error('CONFIG', '访问受限');
      }
      return this.catalog(request.filter, request.filter === 'tag' ? pageValue(request.values.tagPage) : 1);
    },
    cards(doc, page) {
      const items = [], seen = new Set(), base = doc.__feedOrigin;
      if (SITE.archive) {
        for (const card of doc.querySelectorAll('.video-item, a.result-item[href*="/archives/"]')) {
          const link = card.matches('a[href]') ? card : card.querySelector('a[href*="/archives/"]');
          const id = itemId(link?.getAttribute('href'), base);
          const title = text(card.querySelector('.title, .result-title'));
          if (!id || !title || seen.has(id)) continue;
          seen.add(id);
          items.push({id, title, cover: image(card.querySelector('img'), base), mediaKind: 'article'});
        }
        if (!items.length && !doc.querySelector('.pagination, .tag-main-list, .video-list')) throw Park.error('PARSE', '加载失败');
        return {items, page, hasNext: !!doc.querySelector('link[rel="next"], .pagination a.next')};
      }
      for (const card of doc.querySelectorAll('article .post-card')) {
        const article = card.closest('article');
        const link = article?.querySelector('a[href*="/archives/"]');
        const id = itemId(link?.getAttribute('href'), base);
        const titleNode = card.querySelector('[itemprop="headline"], .post-card-bottom-title, h2');
        if (!id || !titleNode || seen.has(id)) continue;
        const clone = titleNode.cloneNode(true);
        for (const badge of clone.querySelectorAll('.wrap')) badge.remove();
        const title = text(clone);
        if (!title) continue;
        seen.add(id);
        items.push({id, title, cover: cover(card, base), coverImages: coverImages(card, base), mediaKind: 'article',
          uploaded: card.querySelector('[itemprop="datePublished"]')?.getAttribute('content') || ''});
      }
      if (!items.length && !doc.querySelector('#archive, .page-nav')) throw Park.error('PARSE', '加载失败');
      const next = doc.querySelector('link[rel="next"], .page-navigator .next a');
      return {items, page, hasNext: !!next};
    },
    async feed(key, {page = 1, cursor, options = {}} = {}) {
      page = pageValue(page);
      let path = '/';
      if (key === 'category' || key === 'tag') {
        const values = options[key] || [];
        if (!Array.isArray(values) || values.some(value => typeof value !== 'string')) throw Park.error('CONFIG', '访问受限');
        if (values.length) {
          const choices = await this.catalog(key, key === 'tag' ? pageValue(options.tagPage) : 1);
          if (values.some(value => !choices.some(choice => choice.value === value))) throw Park.error('CONFIG', '访问受限');
          const paths = [...new Set(values)];
          let state = {paths, pages: paths.map(() => 1), seen: []};
          if (cursor) {
            try { state = JSON.parse(cursor); } catch (_) { throw Park.error('CONFIG', '访问受限'); }
            if (JSON.stringify(state.paths) !== JSON.stringify(paths) ||
                !Array.isArray(state.pages) || state.pages.length !== paths.length ||
                state.pages.some(p => !Number.isSafeInteger(p) || p < 0 || p > 10000) ||
                !Array.isArray(state.seen) || state.seen.some(id => !/^[1-9]\d{0,14}$/.test(id))) throw Park.error('CONFIG', '访问受限');
          } else if (page !== 1) throw Park.error('CONFIG', '访问受限');
          const seen = new Set(state.seen), items = [];
          // One branch per request bounds both response size and simultaneous source connections.
          const nextPage = Math.min(...state.pages.filter(p => p > 0));
          const branch = state.pages.findIndex(p => p > 0 && p === nextPage);
          if (branch < 0) return {items, page, hasNext: false};
          const branchPage = state.pages[branch];
          path = paths[branch] + (branchPage === 1 ? '' : (SITE.archive ? 'page/' : '') + branchPage + '/');
          const result = this.cards(await this.document(path), page);
          for (const item of result.items) if (!seen.has(item.id)) { seen.add(item.id); items.push(item); }
          state.pages[branch] = result.hasNext ? branchPage + 1 : 0;
          state.seen = [...seen];
          const hasNext = state.pages.some(p => p > 0);
          return {items, page, hasNext, cursor: hasNext ? JSON.stringify(state) : undefined};
        }
      } else if (key !== 'recommend') throw Park.error('CONFIG', '访问受限');
      path = page === 1 ? path : path === '/' ? '/page/' + page + '/' : path + (SITE.archive ? 'page/' : '') + page + '/';
      return this.cards(await this.document(path), page);
    },
    async search({keyword, page = 1} = {}) {
      page = pageValue(page);
      const value = String(keyword || '').trim();
      if (!value || value.length > 200) throw Park.error('CONFIG', '访问受限');
      if (SITE.archive) {
        const {response: res, origin} = await resolver.request(this, '/index/search_article', {
          method: 'POST', form: {word: value, page, oauth_type: 'web'}, readOnly: true, allowDomainRetry: true,
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        });
        this.http.ensureOk(res);
        const body = res.json(), data = body?.data;
        if (body?.code !== 0 || !Array.isArray(data?.list)) throw Park.error('PARSE', '加载失败');
        const items = [];
        for (const row of data.list) {
          if (!row || Number(row.is_ad) === 1 || !/^[1-9]\d{0,14}$/.test(String(row.id)) || !row.title) continue;
          items.push({id: String(row.id), title: String(row.title), cover: imageUrl(row.thumb, origin), mediaKind: 'article'});
        }
        return {items, page, hasNext: page < Number(data.total_page || 0)};
      }
      const path = '/search/' + encodeURIComponent(value) + '/' + (page === 1 ? '' : page + '/');
      return this.cards(await this.document(path), page);
    },
    async detail(value) {
      const id = idValue(value), path = articlePath(id), doc = await this.document(path);
      const base = doc.__feedOrigin;
      const title = SITE.archive ? text(doc.querySelector('h1.detail-title'))
        : text(doc.querySelector('h1.post-title')) || String(doc.querySelector('article.post meta[itemprop="headline"]')?.getAttribute('content') || '').trim();
      const root = doc.querySelector(SITE.archive ? '.detail-page .editormd-preview' : '.post-content[itemprop="articleBody"]');
      if (!title || !root) throw Park.error('PARSE', '加载失败');
      const content = blocks(root, base);
      if (!content.length) throw Park.error('PARSE', '加载失败');
      const tagLinks = [];
      for (const node of root.querySelectorAll('.tags a[href*="/tag/"]')) {
        try {
          const tag = new URL(node.getAttribute('href'), base), name = text(node);
          if (tag.origin === base && /^\/tag\/[^/]+\/$/.test(tag.pathname) && name &&
              !tagLinks.some(item => item.url.endsWith(tag.pathname))) {
            tagLinks.push({name, url: SITE.home + tag.pathname});
          }
        } catch (_) { /* Ignore malformed tag links. */ }
      }
      const standardCover = imageUrl(doc.querySelector('meta[itemprop="image"]')?.getAttribute('content'), base);
      const bodyCover = content.find(block => block.type === 'image')?.url || '';
      let precedingImage = '';
      for (const block of content) {
        if (block.type === 'image') precedingImage = block.url;
        if (block.type === 'video' && !block.preview) block.preview = precedingImage || standardCover || bodyCover;
      }
      return {id, title, url: base + path, blocks: content, tags: tagLinks.map(tag => tag.name), tagLinks, mediaKind: 'article',
        uploaded: doc.querySelector('meta[itemprop="datePublished"]')?.getAttribute('content') || '',
        cover: standardCover || bodyCover,
        coverImages: content.filter(block => block.type === 'image').map(block => block.url).slice(0, 6)};
    },
    async searchLink(value, {page = 1} = {}) {
      page = pageValue(page);
      const parsed = Park.url.parse(value, SITE.home, [SITE.domain]);
      if (!parsed || parsed.search || !/^\/tag\/[^/]+\/$/.test(parsed.pathname)) throw Park.error('CONFIG', '访问受限');
      const path = parsed.pathname + (page === 1 ? '' : (SITE.archive ? 'page/' : '') + page + '/');
      return this.cards(await this.document(path), page);
    },
    async videos(value, episodeId) {
      const id = idValue(value), episode = String(episodeId || '');
      if (!/^[1-9]\d{0,20}(?:_\d{1,8})?$/.test(episode)) throw Park.error('NOT_FOUND', '内容不存在');
      const doc = await this.document(articlePath(id));
      const node = [...doc.querySelectorAll(SITE.archive ? '.editormd-preview .dplayer' : '.post-content[itemprop="articleBody"] .dplayer')]
        .find(element => element.getAttribute('data-video_id') === episode);
      const video = node && player(node);
      if (!video) throw Park.error('UNSUPPORTED', '该媒体暂不支持，请在原站打开');
      return [{quality: 0, label: '原画', url: video.url, format: video.format, preferred: true,
        ...(doc.__feedOrigin === SITE.home ? {headers: {Referer: SITE.home + articlePath(id)}} : {})}];
    },
  });
})();
