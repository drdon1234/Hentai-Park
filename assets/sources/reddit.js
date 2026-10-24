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
    if(r.status===401||r.status===403)throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');
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
    if(r.status===401||r.status===403)throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');
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
  async function subreddit(source,target){const d=await json(source,'/r/'+target.id+'/about.json');const s=d?.data;if(!s?.display_name)throw Park.error('NOT_FOUND','社区不存在或已被删除');return s;}
  async function joined(source){logged(source);const d=await json(source,'/subreddits/mine/subscriber.json',{params:{limit:100}});return (d?.data?.children||[]).map(x=>({id:String(x.data?.display_name||'').toLowerCase(),label:'r/'+(x.data?.display_name||'')})).filter(x=>x.id);}
  Park.register({
    i18n:{'zh-Hant':{'请先登录 Reddit':'請先登入 Reddit','Reddit 登录信息无效，请重新登录':'Reddit 登入資訊無效，請重新登入','Reddit 推荐、社区浏览与已加入社区':'Reddit 推薦、社群瀏覽與已加入社群'},ja:{'请先登录 Reddit':'Reddit にログインしてください'},ko:{'请先登录 Reddit':'Reddit에 로그인하세요'},en:{'请先登录 Reddit':'Sign in to Reddit first'},es:{'请先登录 Reddit':'Inicia sesión en Reddit primero'},ru:{'请先登录 Reddit':'Сначала войдите в Reddit'},ar:{'请先登录 Reddit':'سجّل الدخول إلى Reddit أولاً'}},
    key:'reddit',name:'Reddit',version: '0.0.7', minAppVersion: '0.9.2',postShortVideos:true,type:'comic',category:'other',homepage:HOME,domains:['reddit.com','www.reddit.com','old.reddit.com','accounts.reddit.com','oauth.reddit.com'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['v.redd.it','external-preview.redd.it','preview.redd.it','i.redd.it','redgifs.com'],referrerDomains:['redgifs.com']},description:'Reddit 推荐、社区浏览与已加入社区',idExample:'r/AskReddit',defaultFeed:'recommended',feeds:[{key:'recommended',label:'推荐'},{key:'popular',label:'热门'}],
    async feed(key,req={}){logged(this);if(!['recommended','popular'].includes(key))throw Park.error('CONFIG','未知推荐列表');const path=key==='popular'?'/r/popular/hot.json':'/best.json';return listing(await json(this,path,{params:{limit:25,after:req.cursor||undefined}}),{id:'推荐'});},
    async search(req={}){logged(this);const q=String(req.keyword||'').trim();if(!q)return {items:[],page:1,hasNext:false};return listing(await json(this,'/search.json',{params:{q,limit:25,after:req.cursor||undefined,sort:'relevance',restrict_sr:false}}),{id:'搜索'});},
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
    account:{type:'cookies',title:'登录 Reddit',hint:'请在 Reddit 页面完成登录；需允许第三方 OAuth 页面和回调。',loginUrl:HOME+'/login/',loginDomains:['reddit.com','www.reddit.com','old.reddit.com','accounts.reddit.com','oauth.reddit.com','accounts.google.com','appleid.apple.com','account.apple.com'],cookieUrl:HOME+'/',required:true,requiredCookies:['reddit_session'],fields:[{key:'reddit_session',label:'reddit_session',secret:true}],async login(values){await this.cookies.set(HOME+'/',{reddit_session:values.reddit_session});try{const d=await me(this);if(!d)throw Park.error('LOGIN_REQUIRED','Reddit 登录信息无效，请重新登录');this.store.set('account',{name:d.name});return {name:d.name};}catch(e){await this.cookies.clear(HOME+'/');throw e;}},async logout(){await this.cookies.clear(HOME+'/');this.store.set('account',null);},status(){const a=this.store.get('account');return {loggedIn:!!a,name:a?.name||''};}},
    subscription:{hint:'必须先登录 Reddit；输入 r/xxx 后会加入该社区。',normalize,async targets(){return joined(this);},async resolve(input){logged(this);const t=normalize(input);const s=await subreddit(this,t);await post(this,'/api/subscribe',{action:'sub',skip_initial_defaults:'true',sr:s.name||s.id});return {id:t.id,label:'r/'+(s.display_name||t.id)};},async posts(input,options){logged(this);const t=normalize(input);await subreddit(this,t);return listing(await json(this,'/r/'+t.id+'/new.json',{params:{limit:25,after:options?.cursor||undefined}}),t);},async media(scope,options={}){
      const result=scope.target
        ?await this.subscription.posts.call(this,scope.target,options)
        :await this.feed(scope.feed,{...options,options:scope.options});
      return {...result,items:result.items.map(p=>({...p,presentation:'post'}))};
    }}
  });
})();
