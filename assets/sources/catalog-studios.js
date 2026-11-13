Park.register({
  i18n: {
    "zh-Hant": {"官方女优榜": "官方女優榜"},
    ja: {"官方女优榜": "公式女優ランキング"},
    ko: {"官方女优榜": "공식 배우 순위"},
    en: {"官方女优榜": "Official actress ranking"},
    es: {"官方女优榜": "Ranking oficial de actrices"},
    ru: {"官方女优榜": "Официальный рейтинг актрис"},
    ar: {"官方女优榜": "ترتيب الممثلات الرسمي"},
  },
  key: 'catalog-studios', name: '无码厂商', version: '0.0.11', minAppVersion: '0.13.6',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '排行榜与作品资料', homepage: 'https://www.1pondo.tv/',
  domains: ['1pondo.tv', '10musume.com', 'pacopacomama.com', 'caribbeancom.com'],
  network: { vpnHint: true },
  rankings: [
    ['10musume', '天然むすめ'],
    ['pacopacomama', 'パコパコママ'], ['caribbeancom', '加勒比'],
    ['caribbean-actresses', '加勒比'], ['1pondo', '一本道'],
  ].map(([key, label]) => ({ key, label, category: 'jav', section: 'market',
    ...(key === 'caribbean-actresses'
      ? { kind: 'actress', metric: '官方女优榜' }
      : { metric: '官方人气榜', options: [
        { key: 'period', label: '周期', default: 'weekly', values: [
          { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
        ] },
      ] }),
  })),

  defaultFeed: '1pondo',
  feeds: [['1pondo', '一本道'], ['10musume', '天然むすめ'], ['pacopacomama', 'パコパコママ'], ['caribbeancom', '加勒比']].map(([key,label]) => ({key,label,
    options: [
      {key:'category',label:'分类',dynamic:true,default:''},
      ...(key === 'caribbeancom' ? [] : [{key:'sort',label:'排序',default:'newest',values:[{value:'newest',label:'最新'},{value:'oldest',label:'从旧到新'}]}]),
    ]})),
  searchFilters: [{key:'site',label:'站点',default:'1pondo',values:[
    {value:'1pondo',label:'一本道'},{value:'10musume',label:'天然むすめ'},
    {value:'pacopacomama',label:'パコパコママ'},{value:'caribbeancom',label:'加勒比'},
  ]}, {key:'category',label:'分类',dynamic:true,dependsOn:['site'],default:''}],
  origin(site) {
    const base = {'1pondo':'https://www.1pondo.tv','10musume':'https://www.10musume.com',pacopacomama:'https://www.pacopacomama.com',caribbeancom:'https://www.caribbeancom.com'}[site];
    if (!base) throw Park.error('CONFIG', '未知列表');
    return base;
  },
  async caribbeanDocument(url) {
    const r = this.http.ensureOk(await this.http.get(url,{responseType:'base64'}));
    return Park.html.parse(new TextDecoder('euc-jp').decode(Uint8Array.from(atob(r.body),c=>c.charCodeAt(0))));
  },
  caribbeanQuery(value) {
    // 原站搜索表单采用 EUC-JP；URLSearchParams 的 UTF-8 编码会导致日文查询失效。
    if (!this._eucCharacters) {
      const map=new Map(),decoder=new TextDecoder('euc-jp');
      for(let a=0xa1;a<=0xfe;a++)for(let b=0xa1;b<=0xfe;b++) {
        const text=decoder.decode(new Uint8Array([a,b]));
        if (!text.includes('\ufffd')) map.set(text,[a,b]);
      }
      for(let b=0xa1;b<=0xdf;b++)map.set(decoder.decode(new Uint8Array([0x8e,b])),[0x8e,b]);
      this._eucCharacters=map;
    }
    return [...String(value).normalize('NFKC')].map(c=>{
      if(c.charCodeAt(0)<128)return encodeURIComponent(c);
      const bytes=this._eucCharacters.get(c);
      if(!bytes)throw Park.error('CONFIG','搜索关键词无效');
      return bytes.map(b=>'%'+b.toString(16).toUpperCase()).join('');
    }).join('');
  },
  async filterOptions(req) {
    if (req.filter !== 'category') throw Park.error('CONFIG','筛选参数无效');
    const site=req.scope==='search' ? req.values?.site || '1pondo' : req.feed;
    const base = this.origin(site);
    if (site === 'caribbeancom') {
      if (req.scope==='search') return [{value:'',label:'全部'}];
      const doc = await this.caribbeanDocument(base+'/listpages/all1.htm'), values = new Map([['',{value:'',label:'全部'}]]);
      for (const a of doc.querySelectorAll('a[href^="/listpages/"]')) {
        const path = a.getAttribute('href');
        if (!/^\/listpages\/[a-z_]+1\.htm$/.test(path) || path === '/listpages/all1.htm') continue;
        const label=Park.html.text(a).replace(/\s*\(\d+\)\s*$/,'');
        if (label) values.set(path,{value:path,label});
      }
      if (values.size < 2) throw Park.error('PARSE','动态筛选选项无效');
      return [...values.values()];
    }
    const data=await this.http.json(base+'/dyn/phpauto/category.json');
    const values=Object.values(data).filter(row=>/^\d+$/.test(String(row.category_id)) && row.name?.ja)
      .map(row=>({value:String(row.category_id),label:row.name.ja}));
    if (!values.length) throw Park.error('PARSE','动态筛选选项无效');
    return [{value:'',label:'全部'},...values];
  },
  catalogItem(site,row) {
    const id=String(row.MovieID || '');
    if (!/^\d{6}_\d{2,3}$/.test(id) || !row.Title) throw Park.error('PARSE','作品资料无效');
    return {id:site+':'+id,code:id,workCode:id,title:row.Title,cover:row.ThumbHigh || row.MovieThumb || '',
      url:this.origin(site)+'/movies/'+id+'/',authors:row.ActressesJa || [],tags:row.UCNAME || [],uploaded:row.Release || ''};
  },
  async catalogChunk(site,sort,offset) {
    // 目录分片为原站公开数据；内存缓存避免翻页重复下载，不持久化到账号配置。
    const cache=this._catalogChunks || (this._catalogChunks=new Map()),key=site+':'+sort+':'+offset;
    let entry=cache.get(key);
    if (!entry || Date.now()-entry.time>600000) {
      const data=await this.http.json(this.origin(site)+'/dyn/phpauto/movie_lists/list_'+sort+'_'+offset+'.json');
      if (!Array.isArray(data.Rows) || !Number.isInteger(data.SplitSize) || data.SplitSize<=0 || !Number.isInteger(data.TotalRows)) throw Park.error('PARSE','作品资料无效');
      entry={time:Date.now(),data:{TotalRows:data.TotalRows,SplitSize:data.SplitSize,Rows:data.Rows.map(row=>({
        MovieID:row.MovieID,Title:row.Title,Desc:row.Desc,ActressesJa:row.ActressesJa,UC:row.UC,UCNAME:row.UCNAME,
        ThumbHigh:row.ThumbHigh,MovieThumb:row.MovieThumb,Release:row.Release,
      }))}};
      if (cache.size>=120) cache.delete(cache.keys().next().value);
      cache.set(key,entry);
    }
    return entry.data;
  },
  async catalog(site,keyword,req) {
    const page=Math.max(1,Number(req.page)||1),options=req.filters || req.options || {},sort=options.sort || 'newest',category=options.category || '';
    if (!['newest','oldest'].includes(sort) || (category && !/^\d+$/.test(category))) throw Park.error('CONFIG','筛选参数无效');
    const words=String(keyword||'').normalize('NFKC').toLocaleLowerCase().split(/\s+/).filter(Boolean);
    const first=await this.catalogChunk(site,sort,0),size=first.SplitSize,total=first.TotalRows;
    let offset=0;
    if (req.cursor) {
      const c=JSON.parse(req.cursor);
      if (c.site!==site || c.sort!==sort || c.category!==category || c.keyword!==keyword || !Number.isInteger(c.offset) || c.offset<0 || c.offset>total) throw Park.error('CONFIG','分页游标无效');
      offset=c.offset;
    } else if (page>1) throw Park.error('CONFIG','分页游标无效');
    const items=[];
    while (offset<total && items.length<24) {
      const start=Math.floor(offset/size)*size;
      // 有限并发，按目录顺序消费；所有分片均可到达，不截断搜索范围。
      const starts=[start,start+size,start+2*size,start+3*size].filter(n=>n<total);
      const chunks=await Promise.all(starts.map(n=>this.catalogChunk(site,sort,n)));
      for (let i=0;i<chunks.length && items.length<24;i++) {
        const chunk=chunks[i];
        if (!chunk.Rows.length && starts[i]<total) throw Park.error('PARSE','作品资料无效');
        for (let j=Math.max(0,offset-starts[i]);j<chunk.Rows.length;j++) {
          const row=chunk.Rows[j];offset=starts[i]+j+1;
          if (category && !(row.UC||[]).some(v=>String(v)===category)) continue;
          const text=[row.MovieID,row.Title,row.Desc,...(row.ActressesJa||[]),...(row.UCNAME||[])].join(' ').normalize('NFKC').toLocaleLowerCase();
          if (words.every(word=>text.includes(word))) items.push(this.catalogItem(site,row));
          if (items.length===24) break;
        }
      }
    }
    const hasNext=offset<total;
    return {items,page,hasNext,...(hasNext?{cursor:JSON.stringify({site,sort,category,keyword,offset})}:{})};
  },
  async caribbean(keyword,req) {
    const base=this.origin('caribbeancom'),page=Math.max(1,Number(req.page)||1);
    let url;
    if (keyword) {
      if (req.cursor) {
        const next=Park.url.parse(req.cursor,base,['caribbeancom.com']);
        if (!next) throw Park.error('CONFIG','分页游标无效');
        url=next.href;
      } else {
        if (page>1) throw Park.error('CONFIG','分页游标无效');
        url=base+'/search/?q='+this.caribbeanQuery(keyword);
      }
    } else {
      const category=req.options?.category || '/listpages/all1.htm';
      if (!/^\/listpages\/[a-z_]+1\.htm$/.test(category)) throw Park.error('CONFIG','筛选参数无效');
      url=base+category.replace(/1\.htm$/,page+'.htm');
    }
    const doc=await this.caribbeanDocument(url),seen=new Set();
    const items=[...doc.querySelectorAll('.grid.is-movie .entry')].map(row=>{
      const a=row.querySelector('.meta-title a[href]'),link=Park.url.parse(a?.getAttribute('href'),base,['caribbeancom.com']);
      const id=link?.pathname.match(/^\/moviepages\/(\d{6}-\d{3})\/index\.html$/)?.[1];
      if (!id || seen.has(id)) return null;
      seen.add(id);
      const img=row.querySelector('.media-thum img');
      return {id:'caribbeancom:'+id,code:id,workCode:id,title:Park.html.text(a),url:link.href,
        cover:(img?.getAttribute('src')||'').trim()};
    }).filter(Boolean);
    if (!items.length && !/\(0件\)|見つかりません|該当する.*ありません/.test(Park.html.text(doc.body))) throw Park.error('PARSE','作品资料无效');
    const next=[...doc.querySelectorAll('.pagination a[href]')].map(a=>Park.url.parse(a.getAttribute('href'),base,['caribbeancom.com']))
      .find(u=>u && (keyword ? new RegExp('/'+(page+1)+'\\.html$').test(u.pathname) : u.pathname===new URL(url).pathname.replace(new RegExp(page+'\\.htm$'),(page+1)+'.htm')));
    return {items,page,hasNext:!!next,...(next?{cursor:next.href}:{})};
  },
  async feed(site,req) {this.origin(site);return site==='caribbeancom'?this.caribbean('',req):this.catalog(site,'',req);},
  async search(req) {
    const site=req.filters?.site || '1pondo';this.origin(site);
    const code=String(req.keyword||'').trim().match(/^(\d{6})[-_](\d{2,3})$/);
    if (code) {
      if (Number(req.page)>1) return {items:[],page:Number(req.page),hasNext:false};
      const id=code[1]+(site==='caribbeancom'?'-':'_')+code[2];
      try {
        const detail=await this.metadataDetail(site+':'+id);
        return {items:[{...detail,workCode:detail.code}],page:1,hasNext:false};
      } catch(e) {if (e.code==='NOT_FOUND' || e.code==='HTTP' && e.status===404) return {items:[],page:1,hasNext:false};throw e;}
    }
    return site==='caribbeancom'?this.caribbean(req.keyword,req):this.catalog(site,req.keyword,req);
  },
  async metadataSearch(keyword) {
    const pages=await Promise.all(['1pondo','10musume','pacopacomama','caribbeancom'].map(site=>this.search({keyword,page:1,filters:{site}})));
    return pages.flatMap(p=>p.items).slice(0,100);
  },

  async comments(value, req = {}) {
    const bases = {'1pondo': 'https://www.1pondo.tv', '10musume': 'https://www.10musume.com', pacopacomama: 'https://www.pacopacomama.com'};
    let board = req.context?.board, id = String(value);
    if (id.includes(':')) [board,id]=id.split(':');
    if (!board && req.context?.url) {
      const url = Park.comments.url(req.context.url);
      if (url) board = Object.keys(bases).find(key => new URL(url).origin === bases[key]);
    }
    if (!bases[board]) throw Park.error('UNSUPPORTED', '此内容暂不支持评论');
    if (!/^\d{6}_\d{2,3}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    if (req.parentId || Number(req.page) > 1) return {items: [], hasNext: false};
    const data = await this.http.json(bases[board] + '/dyn/phpauto/new_movie_reviews/movie_id/' + id + '.json');
    if (!Array.isArray(data.Rows)) throw Park.error('PARSE', '评论数据无效');
    const items = data.Rows.map(c => {
      if (!c.ReviewID || String(c.MovieID) !== id || typeof c.UserComment !== 'string') throw Park.error('PARSE', '评论数据无效');
      return {id: String(c.ReviewID), author: {name: String(c.Nickname || '')}, body: Park.comments.text(c.UserComment),
        date: c.Created, rating: Number(c.UserRating) || undefined};
    }).filter(c => c.body.length);
    return {items, hasNext: false};
  },

  async metadataDetail(value, context = {}) {
    const identity=String(value), scoped=identity.split(':');
    const id=scoped.length===2?scoped[1]:identity;
    if (!/^\d{6}[_-]\d{2,3}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    const origins = { '1pondo': 'https://www.1pondo.tv', '10musume': 'https://www.10musume.com',
      pacopacomama: 'https://www.pacopacomama.com', caribbeancom: 'https://www.caribbeancom.com' };
    const board = (scoped.length===2?scoped[0]:'') || context.board || Object.keys(origins).find(key => {
      try { return new URL(context.url).origin === origins[key]; } catch (_) { return false; }
    });
    const base = origins[board];
    if (!base) throw Park.error('CONFIG', '作品编号无效');
    const expected=board==='caribbeancom'?base+'/moviepages/'+id+'/index.html':base+'/movies/'+id+'/';
    if (context.url && context.url!==expected) throw Park.error('CONFIG','作品编号无效');
    if (board === 'caribbeancom') {
      const url = `${base}/moviepages/${id}/index.html`;
      const response = this.http.ensureOk(await this.http.get(url, {responseType: 'base64'}));
      const bytes = Uint8Array.from(atob(response.body), c => c.charCodeAt(0));
      const doc = Park.html.parse(new TextDecoder('euc-jp').decode(bytes));
      const title = Park.html.text(doc.querySelector('.heading .heading-title, h1[itemprop="name"], #movie-info h1'));
      if (!title) throw Park.error('PARSE', '作品资料无效');
      const text = selector => Park.html.text(doc.querySelector(selector));
      // 仅读取明确标为公开样张的链接，不包含会员图片或猜测图片地址。
      const publicImage = value => {
        if (!value) return '';
        try {
          const image = new URL(value, base);
          return image.origin === base && !image.username && !image.password &&
            image.pathname.startsWith(`/moviepages/${id}/images/`) ? image.href : '';
        } catch (_) { return ''; }
      };
      const images = [...doc.querySelectorAll('.gallery-item[data-is_sample="1"]')].map(row => {
        const thumbnail = publicImage(row.querySelector('img')?.getAttribute('src'));
        const url = publicImage(row.getAttribute('href')) || thumbnail;
        return {url, thumbnail: thumbnail || url};
      }).filter(row => row.url);
      return { id:identity, code: id, title, url, images,
        cover: doc.querySelector('script') && /var image = '\/moviepages\/'\+movie_id\+'\/images\/l_l\.jpg'/.test(doc.toString()) ? base+'/moviepages/'+id+'/images/l_l.jpg' : '',
        duration: text('.movie-info [itemprop="duration"]'),
        description: text('.movie-info [itemprop="description"]'),
        releaseDate: text('.movie-info [itemprop="uploadDate"]'),
        actors: [...doc.querySelectorAll('.movie-info [itemprop="actor"]')].map(Park.html.text),
        tags: [...doc.querySelectorAll('.movie-info a[href*="/listpages/"]')].map(Park.html.text) };

    }
    const work = await this.http.json(`${base}/dyn/phpauto/movie_details/movie_id/${id}.json`);
    if (work.MovieID !== id || !work.Title) throw Park.error('PARSE', '作品资料无效');
    return { id:identity, code: id, title: work.Title, url: `${base}/movies/${id}/`,
      cover: work.ThumbHigh || work.MovieThumb || '', description: work.Desc || '',
      releaseDate: work.Release || '', duration: work.Duration == null ? '' : String(work.Duration),
      series: work.Series || '', rating: work.AvgRating == null ? '' : String(work.AvgRating),
      actors: (work.ActressesJa || []).filter(name => typeof name === 'string'),
      tags: Object.values(work.UcNameList || {}).map(row => typeof row === 'string' ? row : row?.NameJa || row?.NameEn).filter(Boolean) };
  },
  async ranking(studio, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const period = req.options?.period || 'weekly';
    let items;
    if (studio === 'caribbeancom' || studio === 'caribbean-actresses') {
      const base = 'https://www.caribbeancom.com';
      const actress = studio === 'caribbean-actresses';
      const response = this.http.ensureOk(await this.http.get(`${base}/ranking/${actress ? 'actress.htm' : period + '.html'}`, { responseType: 'base64' }));
      const bytes = Uint8Array.from(atob(response.body), c => c.charCodeAt(0));
      const doc = Park.html.parse(new TextDecoder('euc-jp').decode(bytes));
      items = [...doc.querySelectorAll(actress ? '.is-actress-ranking a.entry[href]' : '.is-movie-ranking a.entry[href]')].map((row) => {
        if (actress) {
          const match = /^\/search_act\/(\d+)\/1\.html$/.exec(row.getAttribute('href') || '');
          if (!match) return null;
          const title = Park.html.text(row.querySelector('.meta-title'));
          return { id: match[1], title, keyword: title,
            rank: Number(Park.html.text(row.querySelector('.ranking-number'))),
            workCount: Number(Park.html.text(row).match(/出演作品数:\s*(\d+)/)?.[1]) || undefined,
            cover: new URL(row.querySelector('img.media-image')?.getAttribute('src') || '', base).href,
            url: base + row.getAttribute('href') };
        }
        const match = /^\/moviepages\/(\d{6}-\d{3})\/index\.html$/.exec(row.getAttribute('href') || '');
        if (!match) return null;
        return { id: match[1], keyword: match[1],
          rank: Number(Park.html.text(row.querySelector('.ranking-number'))),
          title: Park.html.text(row.querySelector('.meta-title')),
          cover: new URL(row.querySelector('img.media-image')?.getAttribute('src') || '', base).href,
          url: base + row.getAttribute('href') };
      }).filter(Boolean);
    } else {
      const base = { '1pondo': 'https://www.1pondo.tv', '10musume': 'https://www.10musume.com', 'pacopacomama': 'https://www.pacopacomama.com' }[studio];
      if (!base) throw Park.error('CONFIG', '未知列表');
      const data = await this.http.json(`${base}/dyn/phpauto/movie_lists/list_${period}_0.json`);
      if (!Array.isArray(data.Rows)) throw Park.error('PARSE', '排行榜解析失败');
      items = data.Rows.map((row, index) => {
        const id = String(row.MovieID || '');
        if (!/^\d{6}_\d{2,3}$/.test(id)) return null;
        return { id, rank: index + 1, title: row.Title, keyword: id,
          subtitle: row.Actor || '', cover: row.ThumbHigh || row.MovieThumb || '',
          url: `${base}/movies/${id}/` };
      }).filter(Boolean);
    }
    items = items.filter(row => row.title && row.rank > 0);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
