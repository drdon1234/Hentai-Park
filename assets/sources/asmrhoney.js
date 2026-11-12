(() => {
  const BASE = 'https://asmrhoney.com';
  const filters = [
    {key: 'region', label: '地区', default: 'zh', values: [
      {value: 'zh', label: '中文'}, {value: 'jp-kr', label: '日韩音声'},
      {value: 'western', label: '欧美'}, {value: 'all', label: '全部'},
    ]},
    {key: 'sort', label: '排序', default: 'views', values: [
      {value: 'views', label: '播放量'}, {value: 'recent', label: '最新'},
      {value: 'duration', label: '时长最长'}, {value: 'title', label: '标题'},
    ]},
    {key: 'creator', label: '创作者', default: 'all', dynamic: true, values: []},
    {key: 'tag', label: '标签', default: 'all', dynamic: true, values: []},
  ];
  const copy = {
    'zh-Hant': {'中文与多语 ASMR 音视频，支持创作者和标签筛选': '中文與多語 ASMR 音視訊，支援創作者和標籤篩選', '日韩音声': '日韓音聲', '欧美': '歐美', '时长最长': '時長最長', '地区': '地區', '播放量': '播放量', '创作者': '創作者'},
    ja: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': '中国語・多言語の ASMR 音声と動画。クリエイターとタグで検索', '日韩音声': '日本・韓国', '欧美': '欧米', '时长最长': '再生時間が長い順', '地区': '地域', '播放量': '再生数', '创作者': 'クリエイター'},
    ko: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': '중국어 및 다국어 ASMR 음성과 영상, 창작자와 태그 필터 지원', '日韩音声': '일본·한국', '欧美': '서양', '时长最长': '재생 시간순', '地区': '지역', '播放量': '재생 수', '创作者': '창작자'},
    en: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': 'Chinese and multilingual ASMR audio and video with creator and tag filters', '日韩音声': 'Japanese and Korean', '欧美': 'Western', '时长最长': 'Longest', '地区': 'Region', '播放量': 'Views', '创作者': 'Creator'},
    es: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': 'Audio y vídeo ASMR chino y multilingüe con filtros de creador y etiquetas', '日韩音声': 'Japonés y coreano', '欧美': 'Occidental', '时长最长': 'Más largos', '地区': 'Región', '播放量': 'Reproducciones', '创作者': 'Creador'},
    ru: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': 'Китайские и многоязычные ASMR аудио и видео с фильтрами авторов и тегов', '日韩音声': 'Японский и корейский', '欧美': 'Западные', '时长最长': 'Самые длинные', '地区': 'Регион', '播放量': 'Просмотры', '创作者': 'Автор'},
    ar: {'中文与多语 ASMR 音视频，支持创作者和标签筛选': 'صوت وفيديو ASMR صيني ومتعدد اللغات مع تصفية المبدعين والعلامات', '日韩音声': 'ياباني وكوري', '欧美': 'غربي', '时长最长': 'الأطول', '地区': 'المنطقة', '播放量': 'المشاهدات', '创作者': 'المبدع'},
  };
  const cache = new Map();

  Park.register({
    i18n: copy, key: 'asmrhoney', name: 'ASMRHoney', version: '0.0.3', minAppVersion: '0.13.2',
    type: 'voice', category: 'asmr', color: '#9A6572',
    description: '中文与多语 ASMR 音视频，支持创作者和标签筛选',
    homepage: BASE, domains: ['asmrhoney.com'], network: {mode: 'auto', vpnHint: true},
    media: {mode: 'native', origin: BASE, domains: ['asmrhoney.com']},
    imageHeaders: {Referer: BASE + '/'},
    defaultFeed: 'videos', feeds: [
      {key: 'videos', label: '视频', options: filters},
      {key: 'audio', label: '音频', options: filters.filter(option => option.key !== 'tag').map(option =>
        option.key === 'sort' ? {...option, default: 'recent', values: option.values.filter(value => value.value !== 'views')} : option)},
    ],
    searchFilters: [
      {key: 'kind', label: '类型', default: 'all', values: [
        {value: 'all', label: '全部'}, {value: 'video', label: '视频'}, {value: 'audio', label: '音频'},
      ]},
      ...filters.map(option => option.key === 'region' ? {...option, default: 'all'} : option),
    ],

    slug(value) {
      const result = String(value || '');
      if (!/^[a-z0-9][a-z0-9-]{0,180}$/.test(result)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return result;
    },
    parseId(value) {
      const match = /^([cat]):([a-z0-9][a-z0-9-]{0,180})(?:\/t\/([a-z0-9][a-z0-9-]{0,180}))?$/.exec(String(value || ''));
      if (!match || (match[3] && match[1] !== 'a')) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return {kind: match[1], slug: match[2], track: match[3] || ''};
    },
    safeUrl(raw) {
      let url;
      try { url = new URL(raw, BASE); } catch (_) {}
      if (!url || url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
          !(url.hostname === 'asmrhoney.com' || url.hostname.endsWith('.asmrhoney.com'))) throw Park.error('PARSE', '媒体数据无效');
      return url.href;
    },
    async data(name) {
      if (!['audio', 'clips-search', 'streamers', 'triggers'].includes(name)) throw Park.error('CONFIG', '媒体数据无效');
      const saved = cache.get(name);
      if (saved && Date.now() - saved.time < 10 * 60 * 1000) return saved.value;
      const response = await this.http.get(BASE + '/data/' + name + '.json');
      if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', {status: response.status, params: {status: response.status}});
      if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
      const value = response.json();
      if (!value || typeof value !== 'object') throw Park.error('PARSE', '媒体数据无效');
      cache.set(name, {time: Date.now(), value});
      return value;
    },
    async catalog() {
      const [audio, clips, streamers] = await Promise.all([this.data('audio'), this.data('clips-search'), this.data('streamers')]);
      if (!Array.isArray(audio.tracks) || !Array.isArray(audio.albums) || !Array.isArray(clips.clips) || !Array.isArray(streamers.streamers)) {
        throw Park.error('PARSE', '媒体数据无效');
      }
      return {audio, clips: clips.clips, creators: new Map(streamers.streamers.map(value => [value.slug, value]))};
    },
    language(creator) {
      const values = Array.isArray(creator?.language) ? creator.language : [];
      return values.length === 1 && ['zh', 'ja', 'ko', 'en'].includes(values[0]) ? values[0] : '';
    },
    item(entry, kind, creators) {
      const slug = this.slug(entry.slug), creator = creators.get(entry.creator);
      if (typeof entry.title !== 'string' || !entry.title.trim() || !creator) throw Park.error('PARSE', '媒体数据无效');
      const language = kind === 'clip'
        ? (['zh', 'ja', 'ko', 'en'].includes(entry.language) ? entry.language : '')
        : this.language(creator);
      const id = (kind === 'clip' ? 'c:' : kind === 'album' ? 'a:' : 't:') + slug;
      let cover = '';
      if (entry.coverWebpUrl || entry.coverUrl) cover = this.safeUrl(entry.coverWebpUrl || entry.coverUrl);
      return {id, title: entry.title, cover, coverAspect: kind === 'clip' ? 16 / 9 : 1,
        mediaKind: kind === 'clip' && entry.kind !== 'collection' ? 'video' : 'voice', authors: [creator.displayName || creator.name].filter(Boolean),
        ...(language ? {language} : {}),
        ...(language === 'zh' && kind !== 'clip' ? {voiceLanguageStatus: 'chineseSpoken'} : {}),
        ...(kind !== 'clip' ? {voiceMediaForm: 'audioOnly'} : entry.audioOnly === false ? {voiceMediaForm: 'videoOnly'} : {}),
        ...(Number(entry.duration || entry.totalDuration) > 0 ? {duration: String(entry.duration || entry.totalDuration)} : {})};
    },
    async listing(request, kind, keyword = '') {
      const selected = request.filters || request.options || {};
      const region = String(selected.region || (keyword ? 'all' : 'zh'));
      const sort = String(selected.sort || (kind === 'audio' ? 'recent' : 'views'));
      const creatorId = String(selected.creator || 'all');
      const tag = String(selected.tag || 'all');
      if (!['all', 'zh', 'jp-kr', 'western'].includes(region) || !['views', 'recent', 'duration', 'title'].includes(sort) ||
          (creatorId !== 'all' && !/^[a-z0-9][a-z0-9-]{0,180}$/.test(creatorId)) ||
      (tag !== 'all' && !/^[a-z0-9][a-z0-9_-]{0,180}$/.test(tag)) ||
          !['all', 'video', 'audio'].includes(kind)) throw Park.error('CONFIG', '筛选参数无效');
      const {audio, clips, creators} = await this.catalog();
      const rows = [
        ...(kind !== 'audio' ? clips.map(value => ({value, kind: 'clip'})) : []),
        ...(kind !== 'video' && tag === 'all' ? audio.albums.map(value => ({value, kind: 'album'})) : []),
        ...(kind !== 'video' && tag === 'all' ? audio.tracks.filter(value => !value.albumSlug).map(value => ({value, kind: 'track'})) : []),
      ];
      const query = keyword.toLocaleLowerCase();
      const filtered = rows.filter(({value, kind: rowKind}) => {
        const creator = creators.get(value.creator);
        if (!creator || value.status !== 'published') return false;
        if (region !== 'all' && creator.region !== region) return false;
        if (creatorId !== 'all' && value.creator !== creatorId) return false;
        if (tag !== 'all' && (rowKind !== 'clip' || !Array.isArray(value.tags) || !value.tags.includes(tag))) return false;
        if (!query) return true;
        return [value.title, value.title_en, value.title_ja, value.title_ko, creator.name, creator.displayName,
          ...(Array.isArray(creator.aliases) ? creator.aliases : []), ...(Array.isArray(value.tags) ? value.tags : [])]
          .some(text => typeof text === 'string' && text.toLocaleLowerCase().includes(query));
      });
      filtered.sort((a, b) => {
        const av = a.value, bv = b.value;
        const aViews = av.playCount == null ? null : Number(av.playCount);
        const bViews = bv.playCount == null ? null : Number(bv.playCount);
        const order = sort === 'views' ? (aViews == null ? (bViews == null ? 0 : 1) : bViews == null ? -1 : bViews - aViews)
          : sort === 'duration' ? Number(bv.duration || bv.totalDuration || 0) - Number(av.duration || av.totalDuration || 0)
          : sort === 'title' ? String(av.title).localeCompare(String(bv.title))
          : String(bv.publishedAt || '').localeCompare(String(av.publishedAt || ''));
        return order || String(av.slug).localeCompare(String(bv.slug));
      });
      const page = Math.max(1, Math.floor(Number(request.page) || 1)), size = 48;
      return {items: filtered.slice((page - 1) * size, page * size).map(row => this.item(row.value, row.kind, creators)),
        page, total: filtered.length, hasNext: page * size < filtered.length};
    },
    async feed(key, request) {
      if (key !== 'videos' && key !== 'audio') throw Park.error('CONFIG', '未知列表');
      return this.listing(request, key === 'videos' ? 'video' : 'audio');
    },
    async search(request) {
      const keyword = String(request.keyword || '').trim();
      if (!keyword) return {items: [], page: 1, hasNext: false};
      if (keyword.length > 200) throw Park.error('CONFIG', '筛选参数无效');
      return this.listing(request, String(request.filters?.kind || 'all'), keyword);
    },
    async filterOptions(request) {
      if (request.filter === 'creator') {
        const data = await this.data('streamers');
        if (!Array.isArray(data.streamers) || data.streamers.length > 499) throw Park.error('PARSE', '媒体数据无效');
        return [{value: 'all', label: '全部'}, ...data.streamers.map(value => ({value: this.slug(value.slug), label: String(value.displayName || value.name || '')}))];
      }
      if (request.filter === 'tag') {
        const data = await this.data('triggers');
        if (!Array.isArray(data.triggers) || data.triggers.length > 499) throw Park.error('PARSE', '媒体数据无效');
        return [{value: 'all', label: '全部'}, ...data.triggers.map(value => {
          const slug = String(value.slug || '');
          if (!/^[a-z0-9][a-z0-9_-]{0,180}$/.test(slug)) throw Park.error('PARSE', '媒体数据无效');
          return {value: slug, label: String(value.label_zh || slug)};
        })];
      }
      throw Park.error('CONFIG', '筛选参数无效');
    },
    async resolve(value) {
      const id = this.parseId(value), {audio, clips, creators} = await this.catalog();
      let entry;
      if (id.kind === 'c') entry = clips.find(row => row.slug === id.slug);
      else if (id.kind === 'a') entry = audio.albums.find(row => row.slug === id.slug);
      else entry = audio.tracks.find(row => row.slug === id.slug && !row.albumSlug);
      if (!entry || entry.status !== 'published') throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return {id, entry, audio, creators};
    },
    async clip(slug) {
      this.slug(slug);
      const response = await this.http.get(BASE + '/data/clips/' + slug + '.json');
      if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', {status: response.status, params: {status: response.status}});
      if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
      const clip = response.json()?.clip;
      if (!clip || clip.slug !== slug || clip.status !== 'published') throw Park.error('PARSE', '媒体数据无效');
      return clip;
    },
    async clipVideos(slug) {
      const clip = await this.clip(slug);
      if (!clip.videoUrl) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
      const url = this.safeUrl(clip.videoUrl), ext = new URL(url).pathname.split('.').pop().toLowerCase();
      if (!['mp4', 'm3u8'].includes(ext)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
      return [{url, format: ext === 'm3u8' ? 'hls' : ext, label: '原画', preferred: true, headers: {Referer: BASE + '/'}}];
    },
    async collection(slug) {
      this.slug(slug);
      const key = 'collection:' + slug, saved = cache.get(key);
      if (saved && Date.now() - saved.time < 10 * 60 * 1000) return saved.value;
      const response = await this.http.get(BASE + '/collection/' + slug + '/');
      if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', {status: response.status, params: {status: response.status}});
      if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
      const doc = Park.html.parse(response.body), rows = [], seen = new Set();
      for (const card of doc.querySelectorAll('main .clip-grid a.clip-card[href]')) {
        const url = new URL(card.getAttribute('href'), BASE);
        const match = /^\/(clip|collection)\/([a-z0-9][a-z0-9-]{0,180})\/$/.exec(url.pathname);
        if (url.origin !== BASE || !match || seen.has(match[2])) throw Park.error('PARSE', '媒体数据无效');
        seen.add(match[2]);
        rows.push({slug: match[2], kind: match[1] === 'collection' ? 'directory' : 'video',
          name: Park.html.text(card.querySelector('h3')) || match[2]});
      }
      const pictures = [...doc.querySelectorAll('main a.photo-gallery-item[href]')].map(card => this.safeUrl(card.getAttribute('href')));
      const hashes = pictures.length ? await Park.crypto.md5Hex(pictures) : [];
      pictures.forEach((url, index) => rows.push({slug: hashes[index], kind: 'image', url,
        name: decodeURIComponent(new URL(url).pathname.split('/').pop())}));
      if (!rows.length || rows.length > 5000) throw Park.error('PARSE', '媒体数据无效');
      cache.set(key, {time: Date.now(), value: rows});
      return rows;
    },
    async collectionFolder(value, directory, entry) {
      if (directory !== value && !String(directory).startsWith(value + '/d/')) throw Park.error('NOT_FOUND', '目录不存在');
      const path = directory === value ? [] : directory.slice(value.length + 3).split('/d/');
      if (path.length > 12) throw Park.error('PARSE', '媒体数据无效');
      let rows = await this.collection(entry.collectionSlug || this.parseId(value).slug);
      for (const slug of path) {
        if (!rows.some(row => row.kind === 'directory' && row.slug === slug)) throw Park.error('NOT_FOUND', '目录不存在');
        rows = await this.collection(slug);
      }
      return rows;
    },
    async collectionNode(value, nodeId, entry) {
      const match = /^(.*)\/(v|i)\/([a-z0-9-]+)(?:\/s\/([a-z0-9-]+))?$/.exec(String(nodeId));
      if (!match) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      const rows = await this.collectionFolder(value, match[1], entry);
      const row = rows.find(row => row.slug === match[3] && row.kind === (match[2] === 'v' ? 'video' : 'image'));
      if (!row || (row.kind === 'image' && match[4])) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return {row, language: match[4] || ''};
    },
    clipSubtitles(id, clip) {
      if (clip.subtitleTracks == null) return [];
      if (!Array.isArray(clip.subtitleTracks) || clip.subtitleTracks.length > 50) throw Park.error('PARSE', '媒体数据无效');
      const seen = new Set();
      return clip.subtitleTracks.map(value => {
        const language = String(value?.srclang || '').toLowerCase();
        if (!/^[a-z]{2,3}(?:-[a-z0-9]{2,8})?$/.test(language) || seen.has(language)) throw Park.error('PARSE', '媒体数据无效');
        seen.add(language);
        const url = this.safeUrl(value.src);
        if (!/\.vtt$/i.test(new URL(url).pathname)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
        return {id: 'c:' + id + '/s/' + language, language, url};
      }).sort((a, b) => Number(b.language === 'zh') - Number(a.language === 'zh'));
    },
    async detail(value) {
      const resolved = await this.resolve(value), {id, entry, creators} = resolved;
      if (id.track) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      const kind = id.kind === 'c' ? 'clip' : id.kind === 'a' ? 'album' : 'track';
      const item = this.item(entry, kind, creators);
      let description = '', subtitles = [];
      if (entry.kind === 'collection') {
        return {...item, url: BASE + '/collection/' + this.slug(entry.collectionSlug || id.slug) + '/',
          voiceRoot: {id: item.id, name: item.title, type: 'directory'}};
      }
      if (kind === 'clip') {
        const clip = await this.clip(id.slug);
        description = typeof clip.description === 'string' ? clip.description : '';
        subtitles = this.clipSubtitles(id.slug, clip);
      }
      return {...item, description, url: kind === 'clip' ? BASE + '/clip/' + id.slug + '/' : BASE + '/creator/' + entry.creator + '/?media=audio',
        ...(subtitles.length ? {voiceSubtitles: {'_': subtitles.map(subtitle => subtitle.id)}} : {}),
        ...(subtitles.some(subtitle => subtitle.language === 'zh') ? {voiceLanguageStatus: 'chineseSubtitled'} : {}),
        ...(kind === 'album' ? {voiceRoot: {id: item.id, name: item.title, type: 'directory'}} : {})};
    },
    async voiceDirectory(value, directory, options = {}) {
      const resolved = await this.resolve(value), {id, entry, audio} = resolved;
      if (entry.kind === 'collection') {
        const rows = await this.collectionFolder(value, directory, entry);
        const page = Math.max(1, Math.floor(Number(options.page) || 1)), nodes = [];
        const selected = rows.slice((page - 1) * 24, page * 24);
        // Resolve captions in small batches; large collections must not open
        // hundreds of detail requests before the first directory page appears.
        for (let offset = 0; offset < selected.length; offset += 4) {
          const batch = await Promise.all(selected.slice(offset, offset + 4).map(async row => {
            const nodeId = directory + '/' + (row.kind === 'directory' ? 'd' : row.kind === 'video' ? 'v' : 'i') + '/' + row.slug;
            if (row.kind !== 'video') return [{id: nodeId, name: row.name, type: row.kind}];
            const clip = await this.clip(row.slug);
            const captions = this.clipSubtitles(row.slug, clip).map(subtitle => ({...subtitle, id: nodeId + '/s/' + subtitle.language}));
            return [{id: nodeId, name: row.name + '.mp4', type: 'video', subtitleIds: captions.map(caption => caption.id)},
              ...captions.map(caption => ({id: caption.id, name: caption.language + '.vtt', type: 'subtitle', subtitleLanguage: caption.language}))];
          }));
          nodes.push(...batch.flat());
        }
        return {items: nodes, hasNext: page * 24 < rows.length};
      }
      if (id.kind !== 'a' || id.track || directory !== value) throw Park.error('NOT_FOUND', '目录不存在');
      const tracks = audio.tracks.filter(track => track.albumSlug === entry.slug && track.status === 'published');
      tracks.sort((a, b) => Number(a.trackNo || 0) - Number(b.trackNo || 0));
      const nodes = tracks.map((track, index) => {
        const extension = String(track.format || '').toLowerCase();
        if (!['mp3', 'm4a'].includes(extension)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
        return {id: value + '/t/' + this.slug(track.slug), name: String(track.title || 'Track ' + (index + 1)) + '.' + extension, type: 'audio'};
      });
      const page = Math.max(1, Math.floor(Number(options.page) || 1));
      return {items: nodes.slice((page - 1) * 100, page * 100), hasNext: page * 100 < nodes.length};
    },
    async track(value, nodeId) {
      const resolved = await this.resolve(value), {id, entry, audio} = resolved;
      if (id.kind === 't' && !id.track && (nodeId === '_' || nodeId === value)) return entry;
      const node = this.parseId(nodeId);
      if (id.kind !== 'a' || node.kind !== 'a' || node.slug !== id.slug || !node.track) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      const track = audio.tracks.find(row => row.slug === node.track && row.albumSlug === entry.slug && row.status === 'published');
      if (!track) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return track;
    },
    async voiceResource(id, nodeId) {
      const {entry} = await this.resolve(id);
      if (entry.kind === 'collection') {
        const {row, language} = await this.collectionNode(id, nodeId, entry);
        if (row.kind === 'image') return {url: row.url, format: new URL(row.url).pathname.split('.').pop().toLowerCase()};
        const subtitle = this.clipSubtitles(row.slug, await this.clip(row.slug)).find(subtitle => subtitle.language === language);
        if (!subtitle) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        return {url: subtitle.url, format: 'vtt'};
      }
      const root = this.parseId(id);
      if (root.kind === 'c' && !root.track) {
        const subtitle = this.clipSubtitles(root.slug, await this.clip(root.slug)).find(value => value.id === nodeId);
        if (!subtitle) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        return {url: subtitle.url, format: 'vtt'};
      }
      const track = await this.track(id, nodeId), format = String(track.format || '').toLowerCase();
      if (!['mp3', 'm4a'].includes(format)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
      return {url: this.safeUrl(track.audioUrl), format};
    },
    async videos(value, episodeId) {
      const id = this.parseId(value);
      const {entry} = await this.resolve(value);
      if (entry.kind === 'collection') {
        const {row, language} = await this.collectionNode(value, episodeId, entry);
        if (row.kind !== 'video' || language) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        return this.clipVideos(row.slug);
      }
      if (id.kind === 'c' && !id.track) {
        return this.clipVideos(id.slug);
      }
      const track = await this.track(value, episodeId), format = String(track.format || '').toLowerCase();
      if (!['mp3', 'm4a'].includes(format)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
      return [{url: this.safeUrl(track.audioUrl), format, label: '原画', preferred: true, headers: {Referer: BASE + '/'}}];
    },
  });
})();
