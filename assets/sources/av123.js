/* 123AV: read declared player data and JSON; never execute remote scripts. */
Park.register({
  key: 'av123', name: '123AV', version: '0.0.3', type: 'video', category: 'jav', color: '#EF4444',
  description: 'JAV 视频，支持推荐、热门、搜索与 HLS 播放',
  homepage: 'https://123av.com', domains: ['123av.com', 'sadie-shop.site'], language: 'zh-Hans',
  network: {mode: 'browser', origin: 'https://123av.com', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://sadie-shop.site', domains: ['freeboldspirit.site', 'truefreespirit.site']},
  imageHeaders: {Referer: 'https://123av.com/'},
  linkPatterns: ['123av\\.com/(?:en|cn|tw|ja|ko|th|ms|id|fil|hi|vi|de|fr)/v/([a-z0-9][a-z0-9_-]{1,120})(?:[/?#]|$)'],
  idPattern: '^[a-z0-9][a-z0-9_-]{1,120}$', idExample: 'ipzz-964',
  defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'}, {key: 'hot', label: '热门'},
    {key: 'new', label: '最新上市'}, {key: 'recent', label: '最近更新'}],
  searchHint: '搜索番号、作品名或演员',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}]}],
  BASE: 'https://123av.com',
  validId(id) {
    const value = String(id).toLowerCase();
    if (!/^[a-z0-9][a-z0-9_-]{1,120}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  literal(value) {
    return value.replace(/\\(u[0-9a-f]{4}|x[0-9a-f]{2}|[\\/'"nrt])/gi, (_, e) =>
      e[0] === 'u' || e[0] === 'x' ? String.fromCharCode(parseInt(e.slice(1),16)) : ({n:'\n',r:'\r',t:'\t'})[e] || e);
  },
  duration(value) {
    if (!/^\d+$/.test(String(value))) return String(value || '');
    const n=Number(value);
    return `${Math.floor(n/3600)}:${String(Math.floor(n/60)%60).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`;
  },
  async getPage(path, params = {}) {
    const r=await this.http.get(this.BASE + path,{params});
    if (r.status===404) throw Park.error('NOT_FOUND','影片不存在');
    if (!r.ok) throw Park.error('HTTP',`123AV HTTP ${r.status}`,{status:r.status});
    if (r.body.length>4*1024*1024) throw Park.error('PARSE','影片页面过大');
    return Park.html.parse(r.body);
  },
  cards(doc) {
    const items=[];
    for (const card of doc.querySelectorAll('.card')) {
      const a=card.querySelector('.card__title a[href]'), img=card.querySelector('img.card__img');
      const m=a && /^\/cn\/v\/([a-z0-9][a-z0-9_-]{1,120})(?:[?#]|$)/.exec(a.getAttribute('href') || '');
      const title=Park.html.text(a), cover=img && img.getAttribute('src');
      if (!m || !title || !/^https:\/\/icdn\.123av\.me\//.test(cover || '') || items.some(i=>i.id===m[1])) continue;
      items.push({id:m[1],title,cover,coverAspect:16/9,duration:this.duration(Park.html.text(card.querySelector('.card__dur')))});
    }
    return items;
  },
  async listing(path, req, params = {}) {
    const page=Math.max(1,Math.floor(Number(req.page)||1));
    const doc=await this.getPage(path,{...params,...(page>1?{page}:{})});
    let totalPages=page;
    for (const a of doc.querySelectorAll('a[href]')) {
      const m=/[?&]page=(\d+)(?:&|$)/.exec(a.getAttribute('href') || '');
      if (m) totalPages=Math.max(totalPages,Number(m[1]));
    }
    return {items:this.cards(doc),page,totalPages,hasNext:page<totalPages};
  },
  async recommendations(req) {
    const page=Math.max(1,Math.floor(Number(req.page)||1));
    if (page===1 || !this.recConfig) {
      const doc=await this.getPage('/cn');
      const node=doc.querySelector('[x-data^="recSections("]');
      const config=node && node.getAttribute('x-data') || '';
      const key=/\bkey:\s*'([a-f0-9-]{36})'/.exec(config);
      if (!key || !config.includes("base: 'https://rec2.123av.com'")) throw Park.error('PARSE','推荐配置暂不可用');
      this.recConfig={key:key[1],user:await Park.crypto.uuid()};
      this.recPages=new Map();
    }
    const previous=page>1 && this.recPages.get(page-1);
    if (page>1 && !previous) throw Park.error('CONFIG','请刷新推荐列表后重试');
    // Use an explicit request UA so the site's public signature uses the same value.
    const ua='Mozilla/5.0', timestamp=String(Math.floor(Date.now()/1000));
    let hash=0;
    for (const c of this.recConfig.key+timestamp+ua) hash=((hash<<5)-hash+c.charCodeAt(0))|0;
    const path=previous?'/next/items/'+encodeURIComponent(previous):'/users/'+this.recConfig.user+'/items';
    const r=await this.http.post('https://rec2.123av.com'+path,{mode:'native',headers:{'User-Agent':ua},
      params:{timestamp,signature:(hash>>>0).toString(16)},json:previous?{count:12}:{count:12,scenario:'home-recommended',included_properties:['code','title_cn','duration']}});
    if (!r.ok || r.body.length>1024*1024) throw Park.error('HTTP','推荐列表暂不可用');
    let data;
    try {data=JSON.parse(r.body);} catch (_) {throw Park.error('PARSE','推荐列表暂不可用');}
    const entries=Array.isArray(data.recomms)?data.recomms.slice(0,100):[];
    const codes=entries.filter(i=>i && /^[a-z0-9][a-z0-9_-]{1,120}$/i.test(i.code || ''));
    const hashes=await Park.crypto.md5Hex(codes.map(i=>i.code.toLowerCase()));
    const items=codes.map((i,n)=>({id:i.code.toLowerCase(),title:i.code+(i.title_cn?' — '+i.title_cn:''),
      cover:'https://icdn.123av.me/img2/s360/'+hashes[n].slice(0,2)+'/'+i.code.toLowerCase()+'/cover.jpg',coverAspect:16/9,duration:this.duration(i.duration)}));
    const cursor=/^[a-f0-9]{16,128}$/.test(data.recomm_id || '')?data.recomm_id:'';
    if (cursor) this.recPages.set(page,cursor);
    if (this.recPages.size>100) this.recPages.delete(this.recPages.keys().next().value);
    return {items,page,hasNext:items.length>0 && !!cursor};
  },
  async feed(key, req) {
    if (key==='recommended') return this.recommendations(req);
    if (!['hot','new','recent'].includes(key)) throw Park.error('CONFIG','未知视频列表');
    return this.listing('/cn/'+key,req);
  },
  async search(req) {
    const category=(req.filters || {}).category;
    if (typeof category==='string' && /^\/cn\/(?:genres|actresses|makers|series|tags)\/[a-z0-9_%+-]+$/i.test(category)) return this.listing(category,req);
    const keyword=String(req.keyword || '').trim();
    if (!keyword) return {items:[],page:1,totalPages:1,hasNext:false};
    return this.listing('/cn/search',req,{keyword});
  },
  episodes(doc) {
    const node=doc.querySelector('.watch__main[x-data]');
    const m=node && /^player\(JSON\.parse\('((?:\\.|[^'\\])*)'\)/.exec(node.getAttribute('x-data') || '');
    if (!m) throw Park.error('UNSUPPORTED','播放线路暂不可用');
    let data;
    try {data=JSON.parse(this.literal(m[1]));} catch (_) {throw Park.error('PARSE','播放线路暂不可用');}
    if (!Array.isArray(data) || data.length>100) throw Park.error('PARSE','播放线路暂不可用');
    return data.filter(e=>e && /^https:\/\/sadie-shop\.site\/e\/[a-z0-9_]+(?:\?[^\s#]*)?$/i.test(e.url || ''));
  },
  async detail(id) {
    id=this.validId(id);
    const doc=await this.getPage('/cn/v/'+id), title=Park.html.text(doc.querySelector('h1'));
    if (!title) throw Park.error('NOT_FOUND','影片不存在');
    const episode=this.episodes(doc)[0];
    const poster=episode && /[?&]poster=([^&]+)/.exec(episode.url);
    let cover='';
    try {cover=poster?decodeURIComponent(poster[1]):'';} catch (_) {}
    if (!/^https:\/\/icdn\.123av\.me\//.test(cover)) cover='';
    const authors=[],tags=[]; let duration='',uploaded='';
    for (const row of doc.querySelectorAll('.watch__info-row')) {
      const name=Park.html.text(row.querySelector('dt')), value=Park.html.text(row.querySelector('dd'));
      if (name==='时长') duration=value;
      if (name==='发布日期') uploaded=value;
      for (const a of row.querySelectorAll('a[href]')) {
        const path=a.getAttribute('href') || '', label=Park.html.text(a);
        if (!/^\/cn\/(?:genres|actresses|makers|series|tags)\/[a-z0-9_%+-]+$/i.test(path) || !label) continue;
        if (path.startsWith('/cn/actresses/')) authors.push(label);
        tags.push({name:label,keyword:'',filters:{category:path}});
      }
    }
    return {id,title,cover,coverAspect:16/9,url:this.BASE+'/cn/v/'+id,authors,duration,uploaded,
      description:Park.html.text(doc.querySelector('.watch__desc-text')),tags:tags.length?[{namespace:'tag',label:'标签',tags}]:[],related:this.cards(doc).filter(i=>i.id!==id)};
  },
  async videos(id) {
    const doc=await this.getPage('/cn/v/'+this.validId(id));
    const episode=this.episodes(doc)[0];
    if (!episode) throw Park.error('UNSUPPORTED','播放线路暂不可用');
    const token=/\/e\/([a-z0-9_]+)/i.exec(episode.url)[1];
    const origin='https://sadie-shop.site', referer=origin+'/e/'+token;
    const r=await this.http.get(origin+'/stream',{mode:'native',params:{id:token},headers:{Referer:referer}});
    if (!r.ok || r.body.length>1024*1024) throw Park.error('UNSUPPORTED','播放线路暂不可用');
    let data;
    try {data=JSON.parse(r.body);} catch (_) {throw Park.error('PARSE','播放线路暂不可用');}
    const url=data && data.media && data.media.stream;
    if (typeof url!=='string' || !/^https:\/\/[^\s#]+\.m3u8(?:\?[^\s#]*)?$/.test(url)) throw Park.error('UNSUPPORTED','此影片没有可用的 HLS 清晰度');
    return [{url,quality:Number(this.config.quality)||1080,label:'原画',format:'hls',preferred:true,headers:{Referer:referer,Origin:origin}}];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"code","label":"完整番号","hint":"请输入完整番号，例如 ABP-123"},{"key":"series","label":"站点系列","hint":"请使用详情页的系列链接"}],"seriesPattern":"^/cn/series/[a-z0-9_%+-]+$"});
