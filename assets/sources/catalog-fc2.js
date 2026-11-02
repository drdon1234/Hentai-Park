Park.register({
  i18n: {
    "zh-Hant": {"上月": "上月", "官方卖家榜": "官方賣家榜"},
    ja: {"上月": "先月", "官方卖家榜": "公式販売者ランキング"},
    ko: {"上月": "지난달", "官方卖家榜": "공식 판매자 순위"},
    en: {"上月": "Last month", "官方卖家榜": "Official seller ranking"},
    es: {"上月": "Mes pasado", "官方卖家榜": "Ranking oficial de vendedores"},
    ru: {"上月": "Прошлый месяц", "官方卖家榜": "Официальный рейтинг продавцов"},
    ar: {"上月": "الشهر الماضي", "官方卖家榜": "ترتيب البائعين الرسمي"},
  },
  key: 'catalog-fc2', name: 'FC2', version: '0.0.12', minAppVersion: '0.11.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '排行榜与作品资料', homepage: 'https://adult.contents.fc2.com/',
  domains: ['fc2.com'],
  network: { mode: 'browser', origin: 'https://adult.contents.fc2.com', vpnHint: true,
    confirmation: { selector: '[data-modal="agecheck"][aria-hidden="false"]',
      readySelector: '[data-form="search"], form[action="/search/"], .items_article_headerInfo, .items_article_MainitemNameTitle',
      requiredCookies: ['wei6H'],
      auto: { clickSelector: '[data-modal="agecheck"] [data-button="yes"]' },
      message: '站点年龄确认未自动完成，请重试' },
  },
  account: {
    type: 'cookies', title: '登录', required: false, fields: [],
    loginUrl: 'https://adult.contents.fc2.com/lk/services/id/login',
    cookieUrl: 'https://adult.contents.fc2.com/',
    async login(values) {
      await this.cookies.set(this.homepage, values);
      const state=await this.account.status.call(this);
      if (!state.loggedIn) throw Park.error('LOGIN_REQUIRED','请先登录');
      return {name:state.name};
    },
    async logout() { await this.cookies.clear(this.homepage); },
    async status() {
      const doc=Park.html.parse(await this.http.text(this.homepage+'ranking/article/weekly'));
      if (doc.querySelector('a[data-tag="login"]')) return {loggedIn:false};
      const logout=doc.querySelector('a[href*="/logout"], a[data-tag="logout"]');
      if (!logout) throw Park.error('PARSE','账号状态无效');
      return {loggedIn:true,name:''};
    },
  },
  defaultFeed: 'sales',
  feeds: [{key:'sales',label:'官方销量榜',options:[{key:'period',label:'周期',default:'weekly',values:[
    {value:'realtime',label:'实时'},{value:'daily',label:'日榜'},{value:'weekly',label:'周榜'},
    {value:'monthly',label:'月榜'},{value:'yearly',label:'年榜'},
  ]}]}],
  searchFilters: [{key:'type',label:'类型',default:'',dynamic:true}],
  async filterOptions(req) {
    if (req.filter!=='type') throw Park.error('CONFIG','筛选参数无效');
    const doc=Park.html.parse(await this.http.text(this.homepage+'ranking/article/weekly'));
    const values=[...doc.querySelectorAll('form[action="/search/"] select[name="type"] option[value]')]
      .map(e=>({value:e.getAttribute('value'),label:Park.html.text(e)}));
    if (!values.length) throw Park.error('PARSE','动态筛选选项无效');
    return values;
  },
  async feed(_,req) {
    const page=await this.ranking('sales',req);
    return {...page,items:page.items.map(item=>({...item,workCode:item.keyword}))};
  },
  async contentPage(url) {
    const response=await this.http.get(url);
    const target=Park.url.parse(response.url,this.homepage,this.domains);
    if (target?.hostname==='fc2.com' && /\/login\.php$/.test(target.pathname)) throw Park.error('LOGIN_REQUIRED','请先登录');
    // 匿名状态不等于没有搜索权限，错误页也不能据此推断必须登录。
    this.http.ensureOk(response);
    return response;
  },
  async search(req) {
    const page=Math.max(1,Number(req.page)||1),url=new URL('search/',this.homepage);
    url.searchParams.set('q',String(req.keyword||'').trim());url.searchParams.set('page',page);
    if (req.filters?.type) url.searchParams.set('type',req.filters.type);
    const response=await this.contentPage(url.href),doc=Park.html.parse(response.body),seen=new Set();
    const items=[...doc.querySelectorAll('a[href*="/article/"],a[href*="/article_search.php?id="]')].map(a=>{
      const link=Park.url.parse(a.getAttribute('href'),this.homepage,this.domains);
      if (link?.hostname!=='adult.contents.fc2.com') return null;
      const id=link.pathname.match(/^\/article\/(\d{2,9})\/$/)?.[1] || (link.pathname==='/article_search.php'?link.searchParams.get('id'):'');
      if (!/^\d{2,9}$/.test(id||'') || seen.has(id)) return null;
      const img=a.querySelector('img'),title=Park.html.text(a.querySelector('h3,h4')) || img?.getAttribute('alt') || Park.html.text(a);
      if (!title) return null;seen.add(id);
      const image=img?.getAttribute('data-src') || img?.getAttribute('src');
      return {id,code:'FC2-PPV-'+id,workCode:'FC2-PPV-'+id,title,cover:image?new URL(image,this.homepage).href:'',url:this.homepage+'article/'+id+'/'};
    }).filter(Boolean);
    if (!items.length && !/検索結果[\s\S]{0,40}0件|没有找到|該当する商品はありません/.test(Park.html.text(doc.body))) throw Park.error('PARSE','作品资料无效');
    const hasNext=[...doc.querySelectorAll('a[href]')].some(a=>{
      const u=Park.url.parse(a.getAttribute('href'),this.homepage,this.domains);
      return u?.pathname===url.pathname && u.searchParams.get('q')===req.keyword && Number(u.searchParams.get('page'))===page+1;
    });
    return {items,page,hasNext};
  },
  async metadataSearch(keyword) {return (await this.search({keyword,page:1})).items;},
  rankings: [{ key: 'sales', label: 'FC2', category: 'jav', section: 'market', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'realtime', label: '实时' }, { value: 'daily', label: '日榜' },
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
      { value: 'yearly', label: '年榜' },
    ] }],
  }, { key: 'sellers', label: '卖家榜', kind: 'seller', category: 'jav', section: 'market', metric: '官方卖家榜',
    options: [{ key: 'period', label: '周期', default: 'monthly', values: [
      { value: 'monthly', label: '上月' }, { value: 'yearly', label: '年榜' },
    ] }],
  }],
  async comments(value, req = {}) {
    const id = String(value);
    if (req.context?.board === 'sellers' || req.parentId) throw Park.error('UNSUPPORTED', '此内容暂不支持评论');
    if (!/^\d{2,9}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    // The public server currently repeats its first page even when page=2 is requested.
    if (Number(req.page) > 1) return {items: [], hasNext: false};
    const url = this.homepage + 'article/' + id + '/review', doc = Park.html.parse(await this.http.text(url));
    if (!doc.querySelector('.items_comment_reviewComp')) throw Park.error('PARSE', '评论数据无效');
    const items = [...doc.querySelectorAll('.userIdreview')].map(author => {
      const row = author.closest('ul'), reviewer = row?.querySelector('[data-reviewer-id]')?.getAttribute('data-reviewer-id');
      const content = row?.children[0]?.cloneNode(true);
      if (!content || !/^\d+$/.test(reviewer || '')) throw Park.error('PARSE', '评论数据无效');
      // Rating-only reviews have an explicit empty-title placeholder; do not display it as a comment.
      for (const empty of content.querySelectorAll('.items_comment_notTitle')) empty.remove();
      const body = Park.comments.html(content.innerHTML, url);
      if (!body.length) return null;
      const star = row.querySelector('[class^="items_comment_Star"][class$="1"], [class^="items_comment_Star"][class$="2"], [class^="items_comment_Star"][class$="3"], [class^="items_comment_Star"][class$="4"], [class^="items_comment_Star"][class$="5"]');
      return {id: id + ':' + reviewer, author: {name: Park.html.text(author)}, body,
        date: Park.html.text(row.querySelector('.userDatareview')), rating: Number(star?.className.match(/(\d)$/)?.[1]) || undefined};
    }).filter(Boolean);
    return {items, hasNext: false};
  },

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^\d{2,9}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}article/${id}/`;
    if (context.url) {
      const supplied = Park.url.parse(context.url, this.homepage, this.domains);
      const expected = new URL(url);
      if (!supplied || !supplied.pathname.includes(id) ||
          supplied.pathname !== expected.pathname) throw Park.error('CONFIG', '作品编号无效');
      url = supplied.href;
    }
    const response = await this.contentPage(url);
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    const meta = key => doc.querySelector(`meta[property="${key}"]`)?.getAttribute('content') || '';
    const text = selector => selector ? Park.html.text(doc.querySelector(selector)) : '';
    const title = text(".items_article_headerInfo h3, .items_article_MainitemNameTitle");
    if (!title) {
      if (/age[_-]?(?:check|verify)|年齢認証|年齢確認/i.test(response.url + response.body.slice(0, 20000))) {
        throw Park.error('CONFIRM_REQUIRED', '站点验证暂未完成', { url });
      }
      throw Park.error('PARSE', '作品资料无效');
    }
    const image = value => {
      if (!value) return '';
      try { const u = new URL(value, url); return u.protocol === 'https:' && !u.username && !u.password && !u.port ? u.href : ''; }
      catch (_) { return ''; }
    };
    const fields = {};
    for (const row of doc.querySelectorAll(".items_article_headerInfo tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: meta('og:description'),
      studio: field(/販売者/), releaseDate: field(/販売日/) || text(".items_article_Releasedate"),
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll(".items_article_headerInfo a[href*=\"tag\"]")].map(Park.html.text).filter(Boolean))],
      images: [...doc.querySelectorAll('.items_article_SampleImages a[href], .items_article_modalAreaPict img[src], [data-pdp-sample-thumbnail][data-img]')].map(row => {
        const img = row.querySelector('img') || row;
        const thumbnail = image(img.getAttribute('data-src') || img.getAttribute('src'));
        const url = image(row.getAttribute('href') || row.getAttribute('data-img') || row.getAttribute('src'));
        return {url, thumbnail: thumbnail || url};
      }).filter(row => row.url).slice(0, 100) };
  },
  async ranking(board, req) {
    const page = Math.max(1, Number(req.page) || 1);
    if (page > 5) return { items: [], page, hasNext: false };
    const url = board === 'sellers'
      ? `${this.homepage}ranking/writer/${req.options?.period === 'yearly' ? 'yearly' : ''}?page=${page}`
      : `${this.homepage}ranking/article/${req.options?.period || 'weekly'}?page=${page}`;
    const doc = Park.html.parse(await this.http.text(url));
    const rows = [...doc.querySelectorAll(board === 'sellers'
      ? '.c-ranksell-110, .c-rankbox-100 > .c-ranklist-110'
      : '.c-rankbox-100 > .c-ranklist-110')];
    const items = rows.map((row) => {
      if (board === 'sellers') {
        const anchor = row.querySelector('.c-ranksell-110_inbox[href], .c-ranklist-130 h3 a[href]');
        const url = new URL(anchor?.getAttribute('href') || '', this.homepage);
        const author = row.querySelector('a[href*="author_id="]');
        const feed = row.querySelector('[data-feed-api*="author_id="]');
        const authorUrl = new URL(author?.getAttribute('href') || '', this.homepage);
        const feedUrl = new URL(feed?.getAttribute('data-feed-api') || '', this.homepage);
        const id = authorUrl.searchParams.get('author_id') || feedUrl.searchParams.get('author_id');
        const rank = Number(Park.html.text(row.querySelector('[class^="c-ranklabel-"]')).match(/^\d+/)?.[0]);
        const title = row.querySelector('.c-ranklist-120_info h3, .c-ranklist-130 h3');
        const image = row.querySelector('.c-ranklist-120_tmbimg img, .c-rankwriter-100 img');
        if (!id || !/^[A-Za-z0-9_-]{1,60}$/.test(id) || !rank || url.host !== 'adult.contents.fc2.com') return null;
        return { id, rank, title: Park.html.text(title || anchor),
          subtitle: Park.html.text(row.querySelector('.c-ranklist-120_dis, .c-ranklist-130_dis')),
          workCount: Number(Park.html.text(author).match(/\((\d+)\)/)?.[1]) || undefined,
          cover: new URL(image?.getAttribute('src') || '', this.homepage).href,
          url: url.href };
      }
      const title = row.querySelector('.c-ranklist-110_info h3');
      const anchor = row.matches('a[href]') ? row : title?.querySelector('a[href]');
      const match = /\/article_search\.php\?id=(\d{2,9})$/.exec(anchor?.getAttribute('href') || '');
      const rank = Number(Park.html.text(row.querySelector('[class^="c-ranklabel-"]')).match(/^\d+/)?.[0]);
      if (!match || !rank) return null;
      const id = match[1], image = row.querySelector('.c-ranklist-110_tmb img');
      return {
        id, rank, title: Park.html.text(title), keyword: `FC2-PPV-${id}`,
        subtitle: Park.html.text(row.querySelector('.c-ranklist-110_own')),
        cover: new URL(image?.getAttribute('src') || '', this.homepage).href,
        url: `${this.homepage}article/${id}/`,
      };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page, hasNext: page < 5 && rows.length === 20 };
  },
});
