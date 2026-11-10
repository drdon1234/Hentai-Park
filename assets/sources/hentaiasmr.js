(() => {
  const BASE = 'https://hentaiasmr.moe';
  const CATEGORIES = {
    all: '', subtitled: 'category/' + encodeURIComponent('中文字幕'),
    chinese: 'category/chinese', english: 'category/english',
    otome: 'category/otome', erovoice: 'category/erovoice',
  };
  const options = [
    {key: 'category', label: '分类', default: 'subtitled', values: [
      {value: 'subtitled', label: '中文字幕'}, {value: 'chinese', label: '中文配音'},
      {value: 'english', label: '英语'}, {value: 'otome', label: '乙女向'},
      {value: 'erovoice', label: '音声'}, {value: 'all', label: '全部'},
    ]},
    {key: 'sort', label: '排序', default: 'latest', values: [
      {value: 'latest', label: '最新'}, {value: 'popular', label: '热门'},
      {value: 'most-viewed', label: '播放量'}, {value: 'longest', label: '时长最长'},
      {value: 'random', label: '随机'},
    ]},
    {key: 'tag', label: '标签', type: 'text', default: ''},
  ];

  Park.register({
    i18n: {
      'zh-Hant': {'中文配音与汉化同人音声，支持多轨字幕': '中文配音與漢化同人音聲，支援多軌字幕', '乙女向': '乙女向', '时长最长': '時長最長', '浏览': '瀏覽', '播放量': '播放量', '随机': '隨機'},
      ja: {'中文配音与汉化同人音声，支持多轨字幕': '中国語音声と中国語字幕付き同人音声。複数トラックと字幕に対応', '乙女向': '乙女向け', '时长最长': '再生時間が長い順', '浏览': '閲覧', '播放量': '再生数', '随机': 'ランダム'},
      ko: {'中文配音与汉化同人音声，支持多轨字幕': '중국어 음성과 중국어 자막 동인 음성, 여러 트랙과 자막 지원', '乙女向': '여성향', '时长最长': '재생 시간순', '浏览': '둘러보기', '播放量': '재생 수', '随机': '무작위'},
      en: {'中文配音与汉化同人音声，支持多轨字幕': 'Chinese voice works and translated doujin audio with multi-track subtitles', '乙女向': 'Otome', '时长最长': 'Longest', '浏览': 'Browse', '播放量': 'Views', '随机': 'Random'},
      es: {'中文配音与汉化同人音声，支持多轨字幕': 'Audios chinos y doujin traducidos con subtítulos por pista', '乙女向': 'Otome', '时长最长': 'Más largos', '浏览': 'Explorar', '播放量': 'Reproducciones', '随机': 'Aleatorio'},
      ru: {'中文配音与汉化同人音声，支持多轨字幕': 'Китайские и переведённые додзин-аудио с субтитрами для дорожек', '乙女向': 'Отомэ', '时长最长': 'Самые длинные', '浏览': 'Обзор', '播放量': 'Просмотры', '随机': 'Случайно'},
      ar: {'中文配音与汉化同人音声，支持多轨字幕': 'أعمال صوتية صينية ومترجمة مع ترجمة للمقاطع المتعددة', '乙女向': 'أوتومي', '时长最长': 'الأطول', '浏览': 'تصفح', '播放量': 'المشاهدات', '随机': 'عشوائي'},
    },
    key: 'hentaiasmr', name: 'Hentai ASMR', version: '0.0.2', minAppVersion: '0.13.0',
    type: 'voice', category: 'asmr', color: '#765A80',
    description: '中文配音与汉化同人音声，支持多轨字幕',
    homepage: BASE, domains: ['hentaiasmr.moe'], network: {mode: 'auto', vpnHint: true},
    media: {mode: 'native', origin: BASE, domains: ['hentaiasmr.moe', 'kiko-play-niptan.one']},
    imageHeaders: {Referer: BASE + '/'},
    defaultFeed: 'browse', feeds: [{key: 'browse', label: '浏览', options}],
    searchFilters: options.map(option => option.key === 'category' ? {...option, default: 'all'} : option),
    linkPatterns: ['hentaiasmr\\.moe/([^/?#]{1,600})\\.html'],
    idPattern: '^[Rr][Jj][0-9]{5,12}$', idExample: 'RJ01319555',

    validId(value) {
      const id = String(value || '');
      if (!/^(?:[a-z0-9._~-]|%[0-9a-f]{2}){1,600}$/i.test(id)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      let decoded;
      try { decoded = decodeURIComponent(id); } catch (_) { throw Park.error('NOT_FOUND', '内容不存在或已被删除'); }
      if (!decoded || decoded === '.' || decoded === '..' || /[\x00-\x1f\x7f/\\?#]/.test(decoded)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return /^rj[0-9]+$/i.test(id) ? id.toLowerCase() : id;
    },
    safeMedia(raw, extensions) {
      let url;
      try { url = new URL(raw, BASE); } catch (_) {}
      if (!url || url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
          !['hentaiasmr.moe', 'kiko-play-niptan.one'].some(host => url.hostname === host || url.hostname.endsWith('.' + host))) {
        throw Park.error('PARSE', '媒体数据无效');
      }
      const extension = url.pathname.split('.').pop().toLowerCase();
      if (!extensions.includes(extension)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
      return {url: url.href, extension, identity: url.hostname + url.pathname};
    },
    cover(raw) {
      try {
        const url = new URL(raw, BASE);
        if (url.protocol === 'https:' && !url.username && !url.password && !url.port && !url.hash &&
            (url.hostname === 'hentaiasmr.moe' || url.hostname.endsWith('.hentaiasmr.moe') || url.hostname === 'blogger.googleusercontent.com')) return url.href;
      } catch (_) {}
      return '';
    },
    async page(path, params = {}) {
      const response = await this.http.get(BASE + path, {params});
      if (response.status === 404) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', {status: response.status, params: {status: response.status}});
      if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
      return response.body;
    },
    async listing(request, keyword = '') {
      const page = Math.max(1, Math.floor(Number(request.page) || 1));
      const selected = request.filters || request.options || {};
      const category = String(selected.category || (keyword ? 'all' : 'subtitled'));
      const sort = String(selected.sort || 'latest');
      const tag = String(selected.tag || '').trim();
      if (!Object.prototype.hasOwnProperty.call(CATEGORIES, category) ||
          !['latest', 'popular', 'most-viewed', 'longest', 'random'].includes(sort) ||
          tag.length > 120 || /[\x00-\x1f\x7f/\\]/.test(tag)) throw Park.error('CONFIG', '筛选参数无效');
      const section = tag && category === 'all' ? 'tag/' + encodeURIComponent(tag) : CATEGORIES[category];
      const path = '/' + (section ? section + '/' : '') + (page > 1 ? 'page/' + page + '/' : '');
      const doc = Park.html.parse(await this.page(path, {
        ...(keyword ? {s: keyword} : {}), ...(sort !== 'latest' ? {filter: sort} : {}),
        ...(tag && category !== 'all' ? {tag} : {}),
      }));
      const items = [], seen = new Set();
      for (const card of doc.querySelectorAll('article.loop-video')) {
        const link = card.querySelector('a[href][title]') || card.querySelector('a[href]');
        let url;
        try { url = new URL(link?.getAttribute('href') || '', BASE); } catch (_) { continue; }
        const match = /^\/((?:[a-z0-9._~-]|%[0-9a-f]{2}){1,600})\.html\/?$/i.exec(url.pathname);
        const title = link?.getAttribute('title') || Park.html.text(card.querySelector('.entry-header'));
        if (url.origin !== BASE || !match || !title) continue;
        let id;
        try { id = this.validId(match[1]); } catch (_) { continue; }
        if (seen.has(id)) continue;
        seen.add(id);
        const code = /\bRJ[0-9]{5,12}\b/i.exec(title)?.[0] || (/^rj[0-9]{5,12}$/i.test(id) ? id : '');
        const image = card.querySelector('img');
        items.push({id, title, cover: this.cover(image?.getAttribute('data-src') || image?.getAttribute('src') || ''),
          coverAspect: 1, mediaKind: 'voice', ...(code ? {workCode: code.toUpperCase()} : {}),
          duration: Park.html.text(card.querySelector('.duration')),
          ...(category === 'chinese' ? {voiceLanguageStatus: 'chineseSpoken'} : {}),
          ...(category === 'subtitled' ? {voiceLanguageStatus: 'chineseSubtitled'} : {})});
      }
      let hasNext = false;
      for (const a of doc.querySelectorAll('a[href]')) {
        let next;
        try { next = new URL(a.getAttribute('href'), BASE); } catch (_) { continue; }
        if (next.origin !== BASE) continue;
        const number = Number(/\/page\/(\d+)\/?$/.exec(next.pathname)?.[1] || next.searchParams.get('paged') || 0);
        let nextSection, expected;
        try {
          nextSection = decodeURIComponent(next.pathname.replace(/\/page\/\d+\/?$/, '').replace(/\/$/, '') || '/');
          expected = decodeURIComponent(section ? '/' + section : '/');
        } catch (_) { continue; }
        if (number > page && nextSection === expected) hasNext = true;
      }
      return {items, page, hasNext};
    },
    async feed(key, request) {
      if (key !== 'browse') throw Park.error('CONFIG', '未知列表');
      return this.listing(request);
    },
    async search(request) {
      const keyword = String(request.keyword || '').trim();
      if (!keyword) return {items: [], page: 1, hasNext: false};
      if (keyword.length > 200) throw Park.error('CONFIG', '筛选参数无效');
      return this.listing(request, keyword);
    },
    async readWork(value, preview) {
      const id = this.validId(value), html = await this.page('/' + id + '.html');
      const doc = Park.html.parse(html);
      const title = Park.html.text(doc.querySelector('h1.entry-title, h2.entry-title, h1, h2')) || preview?.title || '';
      if (!title) throw Park.error('PARSE', '媒体数据无效');
      let language = preview?.id === id ? preview.voiceLanguageStatus : undefined;
      for (const a of doc.querySelectorAll('#video-about .tags-list a[href]')) {
        let path;
        try { path = decodeURIComponent(new URL(a.getAttribute('href'), BASE).pathname).toLowerCase(); } catch (_) { continue; }
        if (path === '/category/chinese' || path === '/category/chinese/') language = 'chineseSpoken';
        if (path === '/category/中文字幕' || path === '/category/中文字幕/') language = 'chineseSubtitled';
      }
      const cover = this.cover(doc.querySelector('meta[property="og:image"]')?.getAttribute('content') || preview?.cover || '');
      const description = doc.querySelector('meta[name="description"]')?.getAttribute('content') || '';
      const parsed = [];
      const blocks = [...html.matchAll(/playlist\.push\(\s*\{([\s\S]*?)\}\s*\);/g)].map(match => match[1]);
      if (!blocks.length) {
        const single = /jwplayer\(\s*["']player["']\s*\)\.setup\(\s*\{([\s\S]*?)\}\s*\);/.exec(html);
        if (single) blocks.push(single[1]);
      }
      for (const block of blocks) {
        const files = [...block.matchAll(/\bfile\s*:\s*("(?:\\.|[^"\\])*")/g)].map(value => {
          try { return JSON.parse(value[1]); } catch (_) { throw Park.error('PARSE', '媒体数据无效'); }
        });
        if (!files.length) throw Park.error('PARSE', '媒体数据无效');
        const source = this.safeMedia(files[0], ['mp3', 'm4a', 'wav', 'flac', 'mp4', 'm3u8']);
        const captions = files.slice(1).map(file => this.safeMedia(file, ['vtt', 'srt', 'lrc']));
        const foundTitle = /\btitle\s*:\s*("(?:\\.|[^"\\])*")/.exec(block);
        let name = '';
        if (foundTitle) try { name = JSON.parse(foundTitle[1]); } catch (_) { throw Park.error('PARSE', '媒体数据无效'); }
        parsed.push({source, captions, name: String(name || 'Track ' + (parsed.length + 1))});
      }
      if (parsed.length > 500) throw Park.error('PARSE', '媒体数据无效');
      const identities = parsed.flatMap(track => [track.source.identity, ...track.captions.map(caption => caption.identity)]);
      const hashes = identities.length ? await Park.crypto.md5Hex(identities) : [];
      let offset = 0;
      const tracks = parsed.map(track => {
        const idPart = hashes[offset++];
        const subtitles = track.captions.map(caption => ({...caption, id: id + '/s/' + hashes[offset++]}));
        return {...track, id: id + '/t/' + idPart, subtitles};
      });
      return {id, title, cover, description, language, tracks};
    },
    async detail(id, preview) {
      const work = await this.readWork(id, preview);
      return {id: work.id, title: work.title, cover: work.cover, description: work.description,
        url: BASE + '/' + work.id + '.html', mediaKind: 'voice',
        ...(/^rj[0-9]{5,12}$/i.test(work.id) ? {workCode: work.id.toUpperCase()} : {}),
        ...(work.language ? {voiceLanguageStatus: work.language} : {}),
        voiceRoot: {id: work.id, name: work.title, type: 'directory'}};
    },
    async voiceDirectory(id, directory, options = {}) {
      id = this.validId(id);
      if (directory !== id) throw Park.error('NOT_FOUND', '目录不存在');
      const work = await this.readWork(id);
      if (!work.tracks.length) throw Park.error('UNSUPPORTED', '此作品暂无可用播放地址');
      const seen = new Set(), items = [];
      for (const track of work.tracks) {
        if (seen.has(track.id)) throw Park.error('PARSE', '媒体数据无效');
        seen.add(track.id);
        const kind = ['mp4', 'm3u8'].includes(track.source.extension) ? 'video' : 'audio';
        items.push({id: track.id, name: track.name + '.' + track.source.extension, type: kind,
          subtitleIds: track.subtitles.map(subtitle => subtitle.id)});
        for (const subtitle of track.subtitles) {
          if (seen.has(subtitle.id)) continue;
          seen.add(subtitle.id);
          items.push({id: subtitle.id, name: subtitle.id.split('/').pop() + '.' + subtitle.extension, type: 'subtitle',
            ...(work.language === 'chineseSubtitled' ? {subtitleLanguage: 'zh'} : {})});
        }
      }
      const page = Math.max(1, Math.floor(Number(options.page) || 1));
      return {items: items.slice((page - 1) * 100, page * 100), hasNext: page * 100 < items.length};
    },
    async voiceResource(id, nodeId) {
      const work = await this.readWork(id);
      for (const track of work.tracks) for (const subtitle of track.subtitles) {
        if (subtitle.id === nodeId) return {url: subtitle.url, format: subtitle.extension};
      }
      throw Park.error('NOT_FOUND', '内容不存在或已被删除');
    },
    async videos(id, episodeId) {
      const work = await this.readWork(id);
      const track = work.tracks.find(value => value.id === episodeId);
      if (!track) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return [{url: track.source.url, format: track.source.extension === 'm3u8' ? 'hls' : track.source.extension,
        label: '原画', preferred: true, headers: {Referer: BASE + '/'}}];
    },
  });
})();
