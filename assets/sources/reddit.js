(function(){
  'use strict';
  const HOME='https://www.reddit.com';
  const API=HOME;
  const FAIL='Reddit 接口已变化，请稍后重试';
  let embeddedToken, embeddedAuth;
  function redgifsId(value){
    const url=Park.url.parse(value,HOME,['redgifs.com']);
    return url&&/^\/(?:watch|ifr)\/([a-z0-9]{4,80})\/?$/i.exec(url.pathname)?.[1].toLowerCase();
  }
  async function redgifsVideo(source,id,retry=true){
    const headers={Cookie:'',Authorization:''};
    if(!embeddedToken){
      if(!embeddedAuth)embeddedAuth=(async()=>{
        const r=await source.http.get('https://api.redgifs.com/v2/auth/temporary',{mode:'native',headers});
        if(!r.ok)throw Park.error('HTTP',FAIL,{status:r.status});
        const token=r.json()?.token;
        if(typeof token!=='string'||!token)throw Park.error('PARSE',FAIL);
        return embeddedToken=token;
      })().finally(()=>{embeddedAuth=null;});
      await embeddedAuth;
    }
    const r=await source.http.get('https://api.redgifs.com/v2/gifs/'+id,{mode:'native',headers:{...headers,Authorization:'Bearer '+embeddedToken}});
    if(r.status===401&&retry){embeddedToken=null;return redgifsVideo(source,id,false);}
    if(!r.ok)throw Park.error('HTTP',FAIL,{status:r.status});
    const urls=r.json()?.gif?.urls;
    const media=Park.url.parse(urls?.hd||urls?.sd,HOME,['redgifs.com']);
    if(!media)throw Park.error('UNSUPPORTED','此影片暂无可用播放地址');
    return [{url:media.href,format:'mp4',preferred:true,headers:{Referer:'https://www.redgifs.com/'}}];
  }
  const banned=new Set(['about','account','admin','api','comments','login','message','mod','prefs','search','settings','submit','user','users']);
  function normalize(input){
    let s=String(input||'').trim();
    if(/^https?:\/\//i.test(s)){
      const u=new URL(s);
      if(u.protocol!=='https:'||!['reddit.com','www.reddit.com','old.reddit.com'].includes(u.hostname)||u.username||u.password)throw Park.error('CONFIG','订阅目标无效');
      const p=u.pathname.split('/').filter(Boolean); if(p[0]?.toLowerCase()!=='r'||p.length!==2)throw Park.error('CONFIG','订阅目标无效'); s=p[1];
    }
    s=s.replace(/^r\//i,'').replace(/^u\//i,'').trim();
    if(!/^[A-Za-z0-9][A-Za-z0-9_-]{2,20}$/.test(s)||banned.has(s.toLowerCase()))throw Park.error('CONFIG','订阅目标无效');
    return {id:s.toLowerCase(),label:'r/'+s};
  }
  function logged(source){if(!source.store.get('account'))throw Park.error('LOGIN_REQUIRED','请先登录 Reddit');}
  async function json(source,path,options={}){
    const r=await source.http.get(API+path,{headers:{Accept:'application/json',...options.headers},params:options.params});
    if(r.status===401){source.store.set('account',null);throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');}
    if(r.status===403)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
    if(r.status===429)throw Park.error('BLOCKED','请求过于频繁，请稍后重试');
    if(!r.ok)throw Park.error('HTTP',FAIL,{status:r.status});
    try{return r.json();}catch{throw Park.error('PARSE',FAIL);}
  }
  // Cookie 会话只能用 /api/me.json 识别账号；/api/v1/me 仅接受 OAuth 令牌。
  async function me(source){const d=await json(source,'/api/me.json');return d?.data?.name?d.data:null;}
  async function post(source,path,form){
    const account=await me(source);
    if(!account?.modhash)throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');
    const r=await source.http.post(API+path,{form:{...form,uh:account.modhash},headers:{Accept:'application/json','X-Modhash':account.modhash}});
    if(r.status===401){source.store.set('account',null);throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');}
    if(r.status===403)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
    if(!r.ok)throw Park.error('AUTH','Reddit 操作未成功，请重试');
    return r;
  }
  function media(item, depth=0){
    if(!item||depth>2)return [];
    const out=[], clean=u=>String(u||'').replace(/&amp;/g,'&');
    for(const row of item.gallery_data?.items||[]){
      const id=String(row.media_id),m=item.media_metadata?.[id];
      if(m?.status!=='valid')continue;
      const preview=clean(m.p?.at(-1)?.u||m.s?.u||m.s?.gif);
      if(m.e==='Image'&&m.s?.u)out.push({id,type:'image',url:clean(m.s.u),preview});
      else if(m.e==='AnimatedImage'&&(m.s?.mp4||m.s?.gif))out.push({id,type:m.s.mp4?'video':'image',url:clean(m.s.mp4||m.s.gif),preview});
      else if(m.e==='RedditVideo'&&(m.s?.hlsUrl||m.s?.mp4))out.push({id,type:'video',url:clean(m.s.hlsUrl||m.s.mp4),preview});
    }
    const u=clean(item.url_overridden_by_dest||item.url);
    if(!out.length&&item.post_hint==='image'&&u)out.push({id:'image',type:'image',url:u,preview:u});
    const video=item.secure_media?.reddit_video||item.media?.reddit_video;
    const preview=clean(item.preview?.images?.[0]?.source?.url||(/^https?:/.test(item.thumbnail||'')?item.thumbnail:''));
    if(item.is_video&&(video?.hls_url||video?.fallback_url))out.push({id:'video',type:'video',url:clean(video.hls_url||video.fallback_url),format:video.hls_url?'hls':'mp4',preview});
    if(!out.length){
      const id=redgifsId(u);
      if(id)out.push({id:'video',type:'video',episodeId:'redgifs:'+id,preview});
      else {
        const clip=item.preview?.reddit_video_preview;
        if(clip?.hls_url||clip?.fallback_url)out.push({id:'video',type:'video',url:clean(clip.hls_url||clip.fallback_url),format:clip.hls_url?'hls':'mp4',preview});
        else {
          const mp4=item.preview?.images?.[0]?.variants?.mp4?.source?.url;
          if(mp4)out.push({id:'video',type:'video',url:clean(mp4),format:'mp4',preview});
        }
      }
    }
    if(!out.length&&item.crosspost_parent_list?.length)return media(item.crosspost_parent_list[0],depth+1);
    return out;
  }
  function work(item,target){
    const m=media(item); if(!m.length)return null;
    const community=item?.subreddit_name_prefixed||((item?.subreddit&&'r/'+item.subreddit)||target.label||'');
    return {id:String(item.id),title:community+' · '+String(item.title||''),subtitle:item.selftext||'',text:item.selftext||'',uploader:item.author||'',authors:item.author?[item.author]:[],url:HOME+String(item.permalink||''),date:item.created_utc?new Date(item.created_utc*1000).toISOString():'',media:m,cover:m[0].preview||m[0].url,mediaKind:m[0].type==='video'?'video':'comic',pages:m.filter(x=>x.type==='image').length};
  }
  function listing(data,target){const children=data?.data?.children||[];const items=children.map(x=>work(x.data,target)).filter(Boolean);const after=data?.data?.after;return {items,cursor:after||null,hasNext:!!after};}
  function communityPage(html,target) {
    const doc=Park.html.parse(html), nodes=[...doc.querySelectorAll('shreddit-post')];
    if(!nodes.length)throw Park.error('PARSE',FAIL);
    const items=[],seen=new Set();
    for(const node of nodes){
      if((node.getAttribute('subreddit-name')||'').toLowerCase()!==target.id)continue;
      const id=(node.getAttribute('id')||'').replace(/^t3_/, '');
      if(!/^[a-z0-9]+$/.test(id)||seen.has(id))continue;
      seen.add(id);
      const media=[],urls=new Set(), content=node.getAttribute('content-href')||'';
      const gif=redgifsId(content);
      if(gif)media.push({id:'video',type:'video',episodeId:'redgifs:'+gif,
        preview:node.querySelector('img[src*="preview.redd.it"]')?.getAttribute('src')||''});
      for(const video of node.querySelectorAll('shreddit-player[src],video[src],source[src]')){
        const url=video.getAttribute('src')||'';
        if(!/^https:\/\/(?:v\.redd\.it|preview\.redd\.it)\//.test(url)||urls.has(url))continue;
        urls.add(url);media.push({id:String(media.length),type:'video',url,
          format:/\.m3u8(?:\?|$)/.test(url)?'hls':'mp4',preview:video.getAttribute('poster')||''});
      }
      for(const image of node.querySelectorAll('img[src]')){
        if(media.some(m=>m.type==='video')&&node.getAttribute('post-type')!=='gallery')continue;
        const url=image.getAttribute('src')||'';
        if(!/^https:\/\/(?:i|preview)\.redd\.it\//.test(url))continue;
        const key=new URL(url).pathname.split('/').at(-1).replace(/^.*-v0-/, '');
        if(urls.has(key))continue;
        urls.add(key);media.push({id:String(media.length),type:'image',url,preview:url});
      }
      const text=node.querySelector('[slot="text-body"]')?.textContent?.trim()||'';
      items.push({id,title:node.getAttribute('post-title')||'',text,subtitle:text,
        uploader:node.getAttribute('author')||'',url:HOME+(node.getAttribute('permalink')||''),
        date:node.getAttribute('created-timestamp')||'',media,
        cover:media[0]?.preview||'',mediaKind:media[0]?.type==='video'?'video':'comic',
        pages:media.filter(x=>x.type==='image').length});
    }
    if(!items.length)throw Park.error('PARSE',FAIL);
    const next=[...doc.querySelectorAll('faceplate-partial[src]')].map(x=>x.getAttribute('src'))
      .find(value=>value.startsWith('/svc/shreddit/community-more-posts/')&&new URL(value,HOME).searchParams.get('name')?.toLowerCase()===target.id);
    return {items,cursor:next||null,hasNext:!!next};
  }
  async function communityPosts(source,target,options={}) {
    let path='/r/'+target.id+'/';
    if(options.cursor){
      const next=Park.url.parse(options.cursor,HOME,['reddit.com']);
      if(!next||next.origin!==HOME||!next.pathname.startsWith('/svc/shreddit/community-more-posts/')||next.searchParams.get('name')?.toLowerCase()!==target.id)throw Park.error('CONFIG','Reddit 分页数据无效');
      path=next.pathname+next.search;
    }
    const r=await source.http.get(HOME+path,{mode:'browser'});
    if(r.status===401)throw Park.error('LOGIN_REQUIRED','请先登录 Reddit');
    if(r.status===403||r.status===429)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
    if(!r.ok)throw Park.error('HTTP',FAIL,{status:r.status});
    const page=communityPage(r.body,target);
    if(page.cursor===options.cursor)return {...page,cursor:null,hasNext:false};
    return page;
  }
  const commentId = /^[a-z0-9]{1,32}$/;
  const commentSnapshots = new Map();
  let commentSequence = 0;
  function commentChildren(node) {
    const value = node?.data?.replies;
    if (!value) return [];
    if (!Array.isArray(value.data?.children)) throw Park.error('PARSE', '评论数据无效');
    return value.data.children;
  }
  function commentCount(nodes) {
    return nodes.reduce((total, node) => total + (node.kind === 'more'
      ? Math.max(0, Number(node.data?.count) || 0)
      : 1 + commentCount(commentChildren(node))), 0);
  }
  function commentItem(node, workId, depth = 0) {
    if (node.kind !== 't1') return null;
    const row = node.data;
    if (!row || !commentId.test(row.id) || row.link_id !== 't3_' + workId ||
        !/^t[13]_[a-z0-9]{1,32}$/.test(row.parent_id || '')) throw Park.error('PARSE', '评论数据无效');
    const children = commentChildren(node), name = String(row.author || '');
    const replies = depth < 3 ? children.map(child => commentItem(child, workId, depth + 1)).filter(Boolean) : [];
    return {id: row.id, parentId: row.parent_id.startsWith('t1_') ? row.parent_id.slice(3) : undefined,
      author: {name}, body: row.body_html ? Park.comments.html(row.body_html, HOME) : Park.comments.text(String(row.body || '')),
      date: Number.isFinite(row.created_utc) ? new Date(row.created_utc * 1000).toISOString() : '',
      likes: Number.isFinite(row.score) && row.score >= 0 ? row.score : undefined,
      replyCount: commentCount(children), repliesAvailable: children.length > 0, replies};
  }
  function commentPending(nodes, parent) {
    return [...new Set(nodes.filter(node => node.kind === 'more' && node.data?.parent_id === parent)
      .flatMap(node => Array.isArray(node.data.children) ? node.data.children : [])
      .filter(id => typeof id === 'string' && commentId.test(id)))];
  }
  async function commentThread(source, id, focus, limit) {
    const value = await json(source, '/comments/' + id + '.json', {params: {
      raw_json: 1, sort: 'confidence', limit, depth: 4, ...(focus ? {comment: focus, context: 0} : {})}});
    if (value?.[0]?.data?.children?.[0]?.data?.id !== id || !Array.isArray(value?.[1]?.data?.children)) {
      throw Park.error('PARSE', '评论数据无效');
    }
    return {nodes: value[1].data.children, total: value[0].data.children[0].data.num_comments};
  }
  async function joined(source){
    logged(source);
    const targets=[],seen=new Set(),cursors=new Set();
    let after;
    do{
      const d=await json(source,'/subreddits/mine/subscriber.json',{params:{limit:100,after}});
      for(const row of d?.data?.children||[]){
        const name=String(row.data?.display_name||''),id=name.toLowerCase();
        if(id&&!seen.has(id)){seen.add(id);targets.push({id,label:'r/'+name,kind:'community'});}
      }
      after=d?.data?.after||null;
      if(after){if(cursors.has(after))throw Park.error('PARSE','Reddit 分页数据无效');cursors.add(after);}
    }while(after);
    return targets;
  }
  async function joinedPage(source,options={}){
    logged(source);
    const query=String(options.query||'').trim();
    const endpoint=query?'/subreddits/search.json':'/subreddits/mine/subscriber.json';
    const d=await json(source,endpoint,{params:{limit:100,after:options.cursor||undefined,...(query?{q:query,include_over_18:'on'}:{})}});
    const targets=(d?.data?.children||[]).filter(row=>!query||row.data?.user_is_subscriber===true).map(row=>{
      const name=String(row.data?.display_name||'');
      return name?{id:name.toLowerCase(),label:'r/'+name,kind:'community'}:null;
    }).filter(Boolean);
    const cursor=d?.data?.after||null;
    return {targets,queryApplied:!!query,cursor,hasNext:!!cursor&&cursor!==options.cursor};
  }
  Park.register({
    i18n:{'zh-Hant':{"红迪":"Reddit",'请先登录 Reddit':'請先登入 Reddit','Reddit 登录信息无效，请重新登录':'Reddit 登入資訊無效，請重新登入','Reddit 推荐、社区浏览与已加入社区':'Reddit 推薦、社群瀏覽與已加入社群'},ja:{"红迪":"Reddit",'请先登录 Reddit':'Reddit にログインしてください'},ko:{"红迪":"레딧",'请先登录 Reddit':'Reddit에 로그인하세요'},en:{"红迪":"Reddit",'请先登录 Reddit':'Sign in to Reddit first'},es:{"红迪":"Reddit",'请先登录 Reddit':'Inicia sesión en Reddit primero'},ru:{"红迪":"Reddit",'请先登录 Reddit':'Сначала войдите в Reddit'},ar:{"红迪":"ريديت",'请先登录 Reddit':'سجّل الدخول إلى Reddit أولاً'}},
    key:'reddit',name:'红迪',version: '0.0.16', minAppVersion: '0.9.2',postShortVideos:true,type:'comic',category:'other',homepage:HOME,domains:['reddit.com','www.reddit.com','old.reddit.com','accounts.reddit.com','oauth.reddit.com'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['v.redd.it','external-preview.redd.it','preview.redd.it','i.redd.it','redgifs.com'],referrerDomains:['redgifs.com']},description:'Reddit 推荐、社区浏览与已加入社区',idExample:'r/AskReddit',defaultFeed:'recommended',feeds:[{key:'recommended',label:'推荐'},{key:'popular',label:'热门'}],
    async comments(value, req = {}) {
      logged(this);
      const id = String(value), parent = req.parentId == null ? null : String(req.parentId);
      if (!commentId.test(id) || (parent && !commentId.test(parent)) ||
          !['default', 'confidence'].includes(req.sort || 'default')) throw Park.error('CONFIG', '评论数据无效');
      const parentKey = parent ? 't1_' + parent : 't3_' + id;
      let nodes, pending, total, snapshotKey, offset = 0;
      if (req.cursor) {
        let cursor;
        try { cursor = JSON.parse(String(req.cursor)); } catch { throw Park.error('CONFIG', '评论数据无效'); }
        if (String(req.cursor).length > 512 || cursor?.id !== id || cursor.parent !== parent ||
            typeof cursor.snapshot !== 'string' || !/^[a-z0-9]+-[a-z0-9]+$/.test(cursor.snapshot) ||
            !Number.isSafeInteger(cursor.offset) || cursor.offset < 0) throw Park.error('CONFIG', '评论数据无效');
        const snapshot = commentSnapshots.get(cursor.snapshot);
        if (!snapshot || Date.now() - snapshot.time > 600000) {
          return {...await this.comments(value, {...req, cursor: null, page: 1}), reset: true, page: 1};
        }
        if (snapshot.id !== id || snapshot.parent !== parent || cursor.offset > snapshot.pending.length) throw Park.error('CONFIG', '评论数据无效');
        snapshotKey = cursor.snapshot;
        pending = snapshot.pending;
        offset = cursor.offset;
        // 每次只展开原站明确返回的五个线程；不把首页重拉当成下一页。
        const batch = pending.slice(offset, offset + 5);
        offset += batch.length;
        nodes = [];
        for (const focus of batch) {
          const result = await commentThread(this, id, focus, 20);
          const node = result.nodes.find(item => item.kind === 't1' && item.data?.id === focus);
          if (!node || node.data.parent_id !== parentKey) throw Park.error('PARSE', '评论数据无效');
          nodes.push(node);
        }
      } else {
        if (Number(req.page || 1) !== 1) throw Park.error('CONFIG', '评论数据无效');
        const result = await commentThread(this, id, parent, 100);
        if (parent) {
          const node = result.nodes.find(item => item.kind === 't1' && item.data?.id === parent);
          if (!node) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
          nodes = commentChildren(node);
        } else { nodes = result.nodes; total = result.total; }
        pending = commentPending(nodes, parentKey);
        const returned = new Set(nodes.filter(node => node.kind === 't1').map(node => node.data.id));
        pending = pending.filter(item => !returned.has(item));
        snapshotKey = Date.now().toString(36) + '-' + (++commentSequence).toString(36);
        if (pending.length) {
          commentSnapshots.set(snapshotKey, {id, parent, pending, time: Date.now()});
          while (commentSnapshots.size > 8) commentSnapshots.delete(commentSnapshots.keys().next().value);
        }
      }
      const items = nodes.filter(node => node.kind === 't1' && node.data?.parent_id === parentKey)
        .map(node => commentItem(node, id));
      const hasNext = offset < pending.length;
      const cursor = hasNext ? JSON.stringify({id, parent, snapshot: snapshotKey, offset}) : null;
      return {items, total: Number.isSafeInteger(total) && total >= 0 ? total : undefined,
        hasNext, cursor};
    },
    async feed(key,req={}){logged(this);if(!['recommended','popular'].includes(key))throw Park.error('CONFIG','未知推荐列表');const path=key==='popular'?'/r/popular/hot.json':'/best.json';return listing(await json(this,path,{params:{limit:25,after:req.cursor||undefined}}),{id:'推荐'});},
    searchFilters:[{key:'sort',label:'排序',type:'select',default:'relevance',values:[{value:'relevance',label:'相关度'},{value:'new',label:'最新'}]}],
    async search(req={}){logged(this);const q=String(req.keyword||'').trim();if(!q)return {items:[],page:1,hasNext:false};return listing(await json(this,'/search.json',{params:{q,limit:25,after:req.cursor||undefined,sort:req.filters?.sort==='new'?'new':'relevance',restrict_sr:false}}),{id:'搜索'});},
    async detail(id){logged(this);const d=await json(this,'/comments/'+encodeURIComponent(String(id))+'.json',{params:{limit:1}});const p=d?.[0]?.data?.children?.[0]?.data;const target=normalize(p?.subreddit_name_prefixed||'r/unknown');const w=work(p,target);if(!w)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {...w,description:w.text,chapters:[]};},
    async chapter(id){const d=await this.detail(id);return {pages:d.media.filter(x=>x.type==='image').map(x=>({url:x.url}))};},
    async videos(id,episodeId){
      logged(this);
      if(episodeId&&episodeId!=='_'){
        if(!/^redgifs:[a-z0-9]{4,80}$/.test(episodeId))throw Park.error('CONFIG','媒体数据无效');
        return redgifsVideo(this,episodeId.slice('redgifs:'.length));
      }
      const detail=await this.detail(id),video=detail.media.find(m=>m.type==='video');
      if(video?.episodeId)return this.videos(id,video.episodeId);
      if(!video?.url)throw Park.error('UNSUPPORTED','此影片暂无可用播放地址');
      return [{url:video.url,format:video.format||'mp4',preferred:true}];
    },
    account:{type:'cookies',title:'登录 Reddit',hint:'请在 Reddit 页面完成登录；需允许第三方 OAuth 页面和回调。',loginUrl:HOME+'/login/',loginDomains:['reddit.com','www.reddit.com','old.reddit.com','accounts.reddit.com','oauth.reddit.com','accounts.google.com','appleid.apple.com','account.apple.com'],cookieUrl:HOME+'/',required:true,requiredCookies:['reddit_session'],fields:[{key:'reddit_session',label:'reddit_session',secret:true}],async login(values){await this.cookies.set(HOME+'/',{reddit_session:values.reddit_session});try{const d=await me(this);if(!d)throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');this.store.set('account',{name:d.name});return {name:d.name};}catch(e){await this.cookies.clear(HOME+'/');throw e;}},async logout(){await this.cookies.clear(HOME+'/');this.store.set('account',null);},async status(){const cookies=await this.cookies.get(HOME+'/');if(!cookies.reddit_session){this.store.set('account',null);return {loggedIn:false};}const a=await me(this);this.store.set('account',a?{name:a.name}:null);return {loggedIn:!!a,name:a?.name||''};}},
    subscription:{communities:true,hint:'可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。',normalize,async targets(options={}){return options.mode==='page'?joinedPage(this,options):joined(this);},async resolve(input){const t=normalize(input);await communityPosts(this,t);return t;},async posts(input,options){return communityPosts(this,normalize(input),options);},async media(scope,options={}){
      const result=scope.search?await this.search({...options,...scope.search}):scope.target
        ?await this.subscription.posts.call(this,scope.target,options)
        :await this.feed(scope.feed,{...options,options:scope.options});
      return {...result,items:result.items.map(p=>({...p,presentation:'post'}))};
    }}
  });
})();

Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"},{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}],"searchFilters":{"sort":"new"}});
