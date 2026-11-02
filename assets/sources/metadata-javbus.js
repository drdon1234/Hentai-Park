Park.register({
  key: 'metadata-javbus', name: 'JavBus', version: '0.0.4', minAppVersion: '0.11.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '作品资料与磁链', homepage: 'https://www.javbus.com/',
  domains: ['javbus.com'], network: {
    mode: 'browser', origin: 'https://www.javbus.com', vpnHint: true,
    confirmation: {
      selector: '#ageVerify, form:has(input[name^="userAnswers"])',
      readySelector: '#waterfall, .info, .alert, .not-found',
      requiredCookies: ['age'],
      auto: {
        checkSelector: '#ageVerify #form1 input[type="checkbox"]',
        clickSelector: '#ageVerify #form1 input[type="submit"]',
        questionnaire: {
          rowSelector: 'form:has(input[name^="userAnswers"]) li',
          submitSelector: 'form:has(input[name^="userAnswers"]) button[type="submit"]',
          answers: [
            { question: '年龄在70周岁以上的驾驶人多长时间要提交一次身体条件证明？', answer: 'B. 每1年' },
            {
              "question": "造成致人轻伤以上或者死亡的交通事故后逃逸，尚不构成犯罪的，一次记几分？",
              "answer": "B. 12分"
            },
            {
              "question": "机动车驾驶人逾期不参加审验仍然驾驶机动车的，会受到什么处罚？",
              "answer": "A. 200元以上500元以下"
            },
            {
              "question": "隐瞒有关情况或提供虚假材料申请机动车驾驶证，申请人在多少年内不得再次申领机动车驾驶证？",
              "answer": "B. 1年"
            },
            {
              "question": "申请轻型牵引挂车准驾车型的，年龄不得超过多少岁？",
              "answer": "C. 60周岁"
            },
            {
              "question": "机动车购买后尚未注册登记，需要临时上道路行驶的，应当凭什么临时上道路行驶？",
              "answer": "A. 临时行驶车号牌"
            },
            {
              "question": "在考试过程中有贿赂.舞弊行为的，申请人在多少年内不得再次申领机动车驾驶证？",
              "answer": "D. 3年"
            },
            {
              "question": "初次申领机动车驾驶证的，可以申请以下哪种准驾车型？",
              "answer": "A. 普通三轮摩托车"
            },
            {
              "question": "驾驶机动车行经人行横道，不按规定减速.停车.避让行人，一次记多少分？",
              "answer": "C. 3分"
            },
            {
              "question": "机动车驾驶人户籍迁出原车辆管理所需要向什么地方的车辆管理所提出申请？",
              "answer": "D. 迁入地"
            },
            {
              "question": "机动车驾驶人在驾驶证有效期满前多长时间申请换证？",
              "answer": "C. 90日内"
            },
            {
              "question": "机动车驾驶证记载的驾驶人信息发生变化的要在多长时间内申请换证？",
              "answer": "C. 30日"
            },
            {
              "question": "当事人有以下哪种行为，要承担交通事故全部责任？",
              "answer": "C. 发生事故后故意损坏、伪造现场、毁灭证据的"
            },
            {
              "question": "驾驶机动车发生交通事故后当事人故意破坏、伪造现场、毁灭证据的，应承担什么责任？",
              "answer": "A. 全部责任"
            },
            {
              "question": "申请人存在以下哪种行为，在一年内不得再次申领机动车驾驶证？",
              "answer": "B. 在考试过程中有舞弊行为"
            },
            {
              "question": "超过机动车驾驶证有效期一年以上未换证被注销，但未超过二年的，机动车驾驶人应当如何恢复驾驶资格？",
              "answer": "B. 参加道路交通安全法律、法规和相关知识考试合格后"
            },
            {
              "question": "驾驶机动车在高速公路或城市快速路上不按规定车道行驶的，一次记几分？",
              "answer": "D. 3分"
            },
            {
              "question": "机动车驾驶人请他人代为接受交通违法行为处罚和记分并支付经济利益的，由公安机关交通管理部门处所支付经济利益多少倍以下罚款，但最高不得超过多少万元？",
              "answer": "B. 三，三"
            },
            {
              "question": "实习期内驾驶人驾驶机动车上高速公路行驶，以下做法正确的是什么？",
              "answer": "C. 需要持有相应或者更高准驾车型驾驶证三年以上的驾驶人陪同"
            },
            {
              "question": "驾驶机动车在高速公路上倒车的，一次记几分？",
              "answer": "B. 12分"
            }
          ],
        },
      },
      message: '站点年龄确认未自动完成，请重试',
    },
  },
  imageHeaders: { Referer: 'https://www.javbus.com/' },
  i18n: {
    'zh-Hant': { '作品资料与磁链': '作品資料與磁鏈' },
    ja: { '作品资料与磁链': '作品情報とマグネットリンク' },
    ko: { '作品资料与磁链': '작품 정보 및 마그넷 링크' },
    en: { '作品资料与磁链': 'Work information and magnet links' },
    es: { '作品资料与磁链': 'Información de obras y enlaces magnet' },
    ru: { '作品资料与磁链': 'Сведения о произведениях и magnet-ссылки' },
    ar: { '作品资料与磁链': 'معلومات الأعمال وروابط ماغنت' },
  },

  defaultFeed: 'censored',
  feeds: ['censored', 'uncensored'].map(key => ({ key,
    label: key === 'censored' ? '有码' : '无码',
    options: [
      { key: 'genre', label: '分类', dynamic: true, default: '' },
      { key: 'magnet', label: '磁链资源', default: 'all', values: [
        { value: 'all', label: '全部' }, { value: 'yes', label: '含磁链' },
      ] },
    ],
  })),
  searchFilters: [
    { key: 'scope', label: '分类', default: 'censored', values: [
      { value: 'censored', label: '有码' }, { value: 'uncensored', label: '无码' },
    ] },
    { key: 'magnet', label: '磁链资源', default: 'all', values: [
      { value: 'all', label: '全部' }, { value: 'yes', label: '含磁链' },
    ] },
  ],
  async filterOptions(req) {
    const base = req.feed === 'uncensored' ? 'uncensored/' : '';
    const {doc} = await this.page(`${this.homepage}${base}genre`);
    const values = new Map([['', {value: '', label: '全部'}]]);
    for (const row of doc.querySelectorAll(`a[href*="/${base}genre/"]`)) {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const match = url?.pathname.match(/^\/(?:uncensored\/)?genre\/([a-z0-9_-]+)\/?$/i);
      const label = Park.html.text(row);
      if (match && label) values.set(match[1], {value: match[1], label});
    }
    if (values.size < 2) throw Park.error('PARSE', '动态筛选选项无效');
    return [...values.values()];
  },
  listItems(doc) {
    const seen = new Set();
    return [...doc.querySelectorAll('a.movie-box, .movie-box a[href]')].map(row => {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const id = url?.pathname.replace(/^\/+|\/+$/g, '');
      const image = row.querySelector('img');
      const title = image?.getAttribute('title') || image?.getAttribute('alt') || '';
      if (!id || !/^[a-z0-9][a-z0-9_-]{1,100}$/i.test(id) || !title || seen.has(id)) return null;
      seen.add(id);
      return {id, code: Park.html.text(row.querySelector('date')) || id, title, url: url.href,
        cover: this.image(image?.getAttribute('data-src') || image?.getAttribute('src'))};
    }).filter(Boolean);
  },
  async list(url) {
    const page = await this.page(url, {empty404: true});
    if (!page) return {items: [], hasNext: false};
    const items = this.listItems(page.doc);
    if (!items.length && !page.doc.querySelector('#waterfall, .alert, .not-found')) throw Park.error('PARSE', '作品资料无效');
    return {items, hasNext: !!page.doc.querySelector('#next, a[name="nextpage"], .pagination li.active + li a')};
  },
  async feed(key, req = {}) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = key === 'uncensored' ? 'uncensored/' : '';
    const genre = String(req.options?.genre || '');
    if (genre && !/^[a-z0-9_-]+$/i.test(genre)) throw Park.error('CONFIG', '筛选条件无效');
    const path = genre ? `${base}genre/${encodeURIComponent(genre)}${page > 1 ? `/${page}` : ''}` : `${base}${page > 1 ? `page/${page}` : ''}`;
    const url = new URL(path, this.homepage);
    url.searchParams.set('magnet', req.options?.magnet === 'yes' ? 'exist' : 'all');
    return {...await this.list(url.href), page};
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = req.filters?.scope === 'uncensored' ? 'uncensored/' : '';
    const url = new URL(`${base}search/${encodeURIComponent(keyword)}${page > 1 ? `/${page}` : ''}`, this.homepage);
    url.searchParams.set('magnet', req.filters?.magnet === 'yes' ? 'exist' : 'all');
    return {...await this.list(url.href), page};
  },
  image(value) {
    if (!value) return '';
    try {
      const url = new URL(value, this.homepage);
      return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
        /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i.test(url.hostname) &&
        !/\.(?:local|localhost)$/i.test(url.hostname) ? url.href : '';
    } catch (_) { return ''; }
  },
  identity(value) {
    const id = String(value || '').trim();
    if (!/^[a-z0-9][a-z0-9_-]{1,100}$/i.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    return id;
  },
  async page(url, { empty404 = false, headers = {} } = {}) {
    const response = await this.http.get(url, { headers });
    if (empty404 && response.status === 404) return null;
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    if (doc.querySelector('#ageVerify, input[name^="userAnswers"]') ||
        /\/doc\/driver-verify/.test(response.url || '') ||
        /Age Verification JavBus/i.test(Park.html.text(doc.querySelector('title')))) {
      throw Park.error('CONFIRM_REQUIRED', '站点验证暂未完成', { url: response.url || url });
    }
    return { doc, body: response.body };
  },
  async metadataSearch(value) {
    const keyword = String(value || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    const page = await this.page(`${this.homepage}search/${encodeURIComponent(keyword)}`, { empty404: true });
    if (!page) return [];
    const items = this.listItems(page.doc);
    if (!items.length && !page.doc.querySelector('#waterfall, .alert, .not-found')) {
      throw Park.error('PARSE', '作品资料无效');
    }
    return items.slice(0, 100);
  },
  async metadataDetail(value) {
    const id = this.identity(value), url = this.homepage + encodeURIComponent(id);
    const { doc, body } = await this.page(url);
    const title = Park.html.text(doc.querySelector('.container h3'));
    const cover = this.image(doc.querySelector('a.bigImage')?.getAttribute('href'));
    if (!title || !doc.querySelector('.info') || !cover) throw Park.error('PARSE', '作品资料无效');
    const fields = {};
    for (const row of doc.querySelectorAll('.info p')) {
      const header = row.querySelector('.header');
      if (!header) continue;
      const label = Park.html.text(header).replace(/[:：\s]/g, '');
      const copy = row.cloneNode(true);
      copy.querySelector('.header')?.remove();
      fields[label] = Park.html.text(copy);
    }
    const names = selector => [...new Set([...doc.querySelectorAll(selector)].map(Park.html.text).filter(Boolean))];
    const images = [...doc.querySelectorAll('a.sample-box')].map(row => ({
      url: this.image(row.getAttribute('href')),
      thumbnail: this.image(row.querySelector('img')?.getAttribute('data-src') || row.querySelector('img')?.getAttribute('src')),
    })).filter(row => row.url);
    const vars = {};
    for (const match of body.matchAll(/\bvar\s+(gid|uc|img|lang)\s*=\s*(?:'([^']*)'|"([^"]*)"|(\d+))\s*;/g)) {
      vars[match[1]] = match[2] ?? match[3] ?? match[4];
    }
    this.magnetPages ??= new Map();
    this.magnetPages.set(id, { vars, body });
    while (this.magnetPages.size > 10) this.magnetPages.delete(this.magnetPages.keys().next().value);
    const code = fields['識別碼'] || fields['识别码'];
    if (!code) throw Park.error('PARSE', '作品资料无效');
    return { id, code, title, cover, url,
      releaseDate: fields['發行日期'] || fields['发行日期'] || '',
      duration: fields['長度'] || fields['长度'] || '',
      director: fields['導演'] || fields['导演'] || '',
      studio: fields['製作商'] || fields['制作商'] || '',
      publisher: fields['發行商'] || fields['发行商'] || '',
      series: fields['系列'] || '',
      actors: names('.star-name a, .info a[href*="/star/"]'),
      tags: names('.genre a[href*="/genre/"]'), images };
  },
  parseMagnets(body) {
    const doc = Park.html.parse('<!doctype html><html><body><table>' + body + '</table></body></html>'), unique = new Map();
    for (const row of doc.querySelectorAll('tr')) {
      const link = row.querySelector('a[href^="magnet:?"]');
      if (!link) continue;
      let url;
      try { url = new URL(link.getAttribute('href')); } catch (_) { continue; }
      const topic = url.searchParams.get('xt') || '';
      if (url.protocol !== 'magnet:' || !/^urn:btih:(?:[a-f0-9]{40}|[a-z2-7]{32})$/i.test(topic)) continue;
      const cells = [...row.querySelectorAll('td')];
      const name = Park.html.text(link), key = topic.toUpperCase();
      if (!name) continue;
      const labels = [...row.querySelectorAll('.label, .badge, .btn')]
        .map(Park.html.text).filter(value => value && value.length < 40);
      const quality = [name, ...labels, ...[...row.querySelectorAll('[title]')].map(e => e.getAttribute('title'))].join(' ');
      if (/\b(?:8k|4320p)\b/i.test(quality)) labels.push('8K');
      if (/\b(?:4k|2160p|uhd)\b/i.test(quality)) labels.push('4K');
      if (/超清/.test(quality)) labels.push('超清');
      if (/\b1080[pi]?\b|full\s*hd|fhd/i.test(quality)) labels.push('1080p');
      if (/\b720p?\b/i.test(quality)) labels.push('720p');
      if (/高清|高[畫画]質|\bhd\b/i.test(quality)) labels.push('高清');
      if (/字幕|中字|中文|\b(?:chs|cht)\b/i.test(quality)) labels.push('字幕');
      if (unique.has(key)) labels.push(...unique.get(key).tags);
      unique.set(key, { url: url.href, name, size: Park.html.text(cells[1]), date: Park.html.text(cells[2]), tags: [...new Set(labels)] });
    }
    return [...unique.values()].slice(0, 500);
  },
  async metadataMagnets(value) {
    const id = this.identity(value);
    if (!this.magnetPages?.has(id)) await this.metadataDetail(id);
    const { vars, body } = this.magnetPages.get(id), initial = this.parseMagnets(body);
    if (!/^\d{1,18}$/.test(vars.gid || '') || !vars.img || !/^[01]$/.test(vars.uc || '0')) {
      if (initial.length) return initial;
      throw Park.error('PARSE', '作品资料无效');
    }
    const url = new URL('ajax/uncledatoolsbyajax.php', this.homepage);
    for (const [key, value] of Object.entries({ gid: vars.gid, lang: 'zh', img: vars.img, uc: vars.uc || '0', floor: '1' })) {
      url.searchParams.set(key, value);
    }
    const page = await this.page(url.href, { headers: { Referer: this.homepage + encodeURIComponent(id), 'X-Requested-With': 'XMLHttpRequest' } });
    if (!/<tr\b/i.test(page.body) && !/暫時沒有|暂时没有|No\s+(?:magnet|data|result)/i.test(page.body)) {
      throw Park.error('PARSE', '作品资料无效');
    }
    const results = new Map([...initial, ...this.parseMagnets(page.body)].map(row => [new URL(row.url).searchParams.get('xt').toUpperCase(), row]));
    return [...results.values()].slice(0, 500);
  },
});
