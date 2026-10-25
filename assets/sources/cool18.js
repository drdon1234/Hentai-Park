(function () {
  'use strict';
  const HOME = 'https://www.cool18.com',
    BOARD = HOME + '/bbs4/index.php';
  function idValue(id) {
    if (!/^[1-9]\d{0,12}$/.test(String(id)))
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  function thread(id) {
    return BOARD + '?app=forum&act=threadview&tid=' + idValue(id);
  }
  async function doc(source, url) {
    return Park.html.parse(
      source.http.ensureOk(await source.http.get(url)).body,
    );
  }
  function titleInfo(raw) {
    const author = raw.match(/\s*作\s*者[：:]\s*([^\s()[\]【】（）]+)/);
    let title = author
      ? raw.slice(0, author.index).replace(/[（(【[]\s*$/, '').trim()
      : raw;
    const number = '[0-9０-９零〇一二两兩三四五六七八九十百千]+(?:[.．][0-9０-９]+)*',
      range = number + '(?:[-－—–~～至到]' + number + ')?',
      episode = new RegExp(
        '^第?' + range + '[章节節回集篇部卷]?(?:完[结結本]?|全)?(?:[+＋]番外)?$',
      );
    // 只收紧明确的集数；书名、英文分词和普通说明中的空格保留。
    title = title
      .replace(
        /\s*([(（\[【])([^()（）\[\]【】]+)([)）\]】])/g,
        (match, open, inner, close) => {
          if ('(（[【'.indexOf(open) !== ')）]】'.indexOf(close)) return match;
          const compact = inner.replace(/\s+/g, '');
          return episode.test(compact) ? open + compact + close : match;
        },
      )
      .replace(
        /第[\s0-9０-９零〇一二两兩三四五六七八九十百千.．\-－—–~～至到]+[章节節回集篇部卷]/g,
        (match) => {
          const compact = match.replace(/\s+/g, '');
          return episode.test(compact) ? compact : match;
        },
      )
      .trim();
    return { title: title || raw, authors: author ? [author[1]] : [] };
  }
  function entries(d, search) {
    const items = [],
      seen = new Set();
    for (const a of d.querySelectorAll(
      search
        ? '.thread-list a[href*="threadview"]'
        : '.post-item a[href],.title-col a[href],li a[href*="threadview"]',
    )) {
      const u = new URL(a.getAttribute('href'), BOARD);
      if (u.hostname !== 'www.cool18.com' || u.pathname !== '/bbs4/index.php')
        continue;
      const id = u.searchParams.get('tid'),
        text = Park.html.text(a),
        bytes = text.match(/\((\d+) bytes\)/i);
      if (
        !id ||
        !/^\d+$/.test(id) ||
        seen.has(id) ||
        (bytes && +bytes[1] < 500) ||
        /^(?:[.\s]*Re[:：]|[.\s]*回复|[.\s]*点赞)/i.test(text)
      )
        continue;
      seen.add(id);
      const rawTitle = text
        .replace(/^\.\s*/, '')
        .replace(/\s+-\s+[^]*?\(\d+ bytes\)[^]*$/, '')
        .trim();
      items.push({
        id,
        ...titleInfo(rawTitle),
        subtitle: '',
        category: '',
        tags: [],
        uploaded: '',
        cover: '',
        language: 'zh',
        mediaKind: 'novel',
      });
    }
    return items;
  }
  async function list(source, req, params) {
    const page = Math.max(1, Number(req.page) || 1),
      u = new URL(BOARD);
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    if (page > 1) u.searchParams.set('p', page);
    const d = await doc(source, u.href),
      next = [...d.querySelectorAll('a[href]')].find((a) =>
        /下一页/.test(Park.html.text(a)),
      );
    return { items: entries(d, params.act === 'threadsearch'), page, hasNext: !!next };
  }
  Park.register({
    i18n: {
      "zh-Hant": {"小说不存在或受限": "小說不存在或受限", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "禁忌書屋小說版，支援精華、熱門文章、搜尋與正文閱讀", "精华": "精華"},
      "ja": {"小说不存在或受限": "小説が存在しないか制限されています", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "禁忌書屋の小説掲示板。厳選作品、人気投稿、検索、本文の閲覧に対応", "精华": "厳選"},
      "ko": {"小说不存在或受限": "소설이 없거나 제한됩니다", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "금기서옥 소설 게시판. 엄선 작품, 인기 글, 검색 및 본문 읽기 지원", "精华": "엄선"},
      "en": {"小说不存在或受限": "Novel not found or restricted", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "Cool18 fiction board with curated posts, popular posts, search and text reading", "精华": "Featured"},
      "es": {"小说不存在或受限": "Novela no encontrada o restringida", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "Foro de ficción de Cool18 con selección, publicaciones populares, búsqueda y lectura", "精华": "Destacados"},
      "ru": {"小说不存在或受限": "Роман не найден или доступ ограничен", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "Раздел прозы Cool18: избранные и популярные публикации, поиск и чтение", "精华": "Избранное"},
      "ar": {"小说不存在或受限": "الرواية غير موجودة أو مقيدة", "禁忌书屋小说版，支持精华、热帖、搜索与正文阅读": "منتدى روايات Cool18 مع مشاركات مختارة وشائعة وبحث وقراءة النص", "精华": "مختارات"},
    },
    key: 'cool18',
    name: 'Cool18',
    version: '0.0.9', minAppVersion: '0.9.2',
    type: 'novel',
    category: 'novel',
    language: 'zh',
    color: '#A83E40',
    homepage: BOARD,
    domains: ['www.cool18.com'],
    description: '禁忌书屋小说版，支持精华、热帖、搜索与正文阅读',
    network: { mode: 'native', vpnHint: true },
    account: {
      type: 'cookies',
      title: '站点账号',
      required: false,
      loginUrl: BOARD,
      cookieUrl: HOME + '/',
      requiredCookies: [],
    },
    linkPatterns: ['cool18\\.com/bbs4/index\\.php\\?[^\\s#]*?tid=([0-9]+)'],
    idPattern: '^[1-9]\\d+$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '精华' },
      { key: 'popular', label: '热门' },
      {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]},
    ],
    async filterOptions(req) {
      if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') return [];
      const d = await doc(this, BOARD), options = [{value: '', label: '全部'}], seen = new Set();
      for (const a of d.querySelectorAll('a[href]')) {
        const u = new URL(a.getAttribute('href'), BOARD), value = u.searchParams.get('type');
        if (u.origin !== HOME || u.pathname !== '/bbs4/index.php' || u.searchParams.get('act') !== 'threadsearch' || !value || value.length > 20 || seen.has(value)) continue;
        seen.add(value); options.push({value, label: Park.html.text(a) || value});
      }
      if (!seen.size) throw Park.error('PARSE', '未找到分类');
      return options;
    },
    async feed(key, req) {
      if (key === 'categories') {
        const category = String(req.options?.category || '');
        if (!category) return list(this, req, {app: 'forum', act: 'gold'});
        if (!/^[\u3400-\u9fff]{1,20}$/.test(category)) throw Park.error('CONFIG', '分类无效');
        return list(this, req, {action: 'search', act: 'threadsearch', app: 'forum', type: category, submit: '查询'});
      }
      if (!['recommend', 'popular'].includes(key))
        throw Park.error('CONFIG', '未知列表');
      return list(this, req, {
        app: 'forum',
        act: key === 'recommend' ? 'gold' : 'hot',
      });
    },
    async search(req) {
      return list(this, req, {
        action: 'search',
        bbsdr: 'bbs4',
        act: 'threadsearch',
        app: 'forum',
        keywords: String(req.keyword || ''),
        submit: '查询',
      });
    },
    async comments(value, req = {}) {
      const id = idValue(value), parentId = req.parentId == null ? id : idValue(req.parentId);
      const page = Math.max(1, Math.floor(Number(req.page) || 1)), size = 20;
      const response = this.http.ensureOk(await this.http.get(BOARD, {params: {app: 'forum', act: 'achildlist', tid: id}}));
      let rows;
      try { rows = response.json(); } catch (_) { throw Park.error('PARSE', '评论数据无效'); }
      if (!Array.isArray(rows)) throw Park.error('PARSE', '评论数据无效');
      const index = new Map();
      for (const row of rows) {
        if (!row || !/^[1-9]\d{0,12}$/.test(String(row.tid || '')) ||
            String(row.rootid) !== id || !/^[1-9]\d{0,12}$/.test(String(row.uptid || '')) ||
            typeof row.subject !== 'string') throw Park.error('PARSE', '评论数据无效');
        if (String(row.tid) !== id) index.set(String(row.tid), row);
      }
      if (parentId !== id && !index.has(parentId)) throw Park.error('NOT_FOUND', '内容不存在');
      const children = new Map();
      for (const row of index.values()) {
        const parent = String(row.uptid);
        if (parent === String(row.tid) || parent !== id && !index.has(parent)) throw Park.error('PARSE', '评论数据无效');
        const visited = new Set([String(row.tid)]);
        let ancestor = parent;
        while (ancestor !== id) {
          if (visited.has(ancestor) || !index.has(ancestor)) throw Park.error('PARSE', '评论数据无效');
          visited.add(ancestor);
          ancestor = String(index.get(ancestor).uptid);
        }
        if (!children.has(parent)) children.set(parent, []);
        children.get(parent).push(row);
      }
      const selected = children.get(parentId) || [], offset = (page - 1) * size;
      const items = await Park.utils.mapLimit(selected.slice(offset, offset + size), 3, async row => {
        const cid = String(row.tid), url = thread(cid), body = Park.comments.html(row.subject, url);
        if (Number(row.size) > 0) {
          const d = await doc(this, url), content = d.querySelector('#content-section > pre');
          if (!content) {
            if (/登录后|login to|购买/.test(Park.html.text(d.querySelector('.post-content')))) throw Park.error('LOGIN_REQUIRED', '访问受限，请在原站检查权限');
            throw Park.error('PARSE', '评论数据无效');
          }
          const full = Park.comments.html(content.innerHTML, url);
          if (!full.length) throw Park.error('PARSE', '评论数据无效');
          body.push({type: 'text', text: '\n'}, ...full);
        }
        const replyCount = children.get(cid)?.length || 0, seconds = Number(row.dateline);
        return {id: cid, parentId: parentId === id ? undefined : parentId,
          author: {name: String(row.username || '')}, body,
          date: Number.isFinite(seconds) && seconds > 0 && seconds < 8640000000000 ? new Date(seconds * 1000).toISOString() : String(row.dateline || ''),
          replyCount, repliesAvailable: replyCount > 0};
      });
      return {items: items.filter(row => row.body.length), page, total: selected.length, hasNext: offset + size < selected.length};
    },
    async detail(value) {
      const id = idValue(value),
        url = thread(id),
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('.main-title'));
      if (!title) throw Park.error('NOT_FOUND', '小说不存在或受限');
      return {
        id,
        ...titleInfo(title),
        cover: '',
        url,
        language: 'zh',
        mediaKind: 'novel',
        chapters: null,
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (chapterId && chapterId !== '_' && idValue(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const d = await doc(this, thread(id)),
        body = d.querySelector('#content-section'),
        paragraphs = Park.html.paragraphs(body);
      if (!body || paragraphs.join('').length < 200) {
        if (
          /金币|登录后|login to|购买/.test(
            Park.html.text(d.querySelector('.post-content')),
          )
        )
          throw Park.error('LOGIN_REQUIRED', '小说正文需要账号或站点权限');
        throw Park.error('PARSE', '小说正文为空或受限');
      }
      return {
        title: titleInfo(Park.html.text(d.querySelector('.main-title'))).title,
        paragraphs,
      };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
