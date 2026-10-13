/* X 推荐、搜索与只读订阅；匿名请求不携带 X 会话。 */
(function(){
  'use strict';
  const HOME='https://x.com';
  const FAIL='站点接口已变化，请稍后重试';
  let bootstrap;
  function normalize(input){
    let s=String(input||'').trim();
    if(/^https?:\/\//i.test(s)){
      const u=new URL(s);
      if(u.protocol!=='https:'||!['x.com','www.x.com','twitter.com','www.twitter.com'].includes(u.hostname)||u.username||u.password) throw Park.error('CONFIG','订阅目标无效');
      const parts=u.pathname.split('/').filter(Boolean);
      if(parts.length>2||(parts.length===2&&!['media','with_replies'].includes(parts[1])))throw Park.error('CONFIG','订阅目标无效');
      s=parts[0]||'';
    }
    s=s.replace(/^@/,'').toLowerCase();
    if(!/^[a-z0-9_]{1,15}$/.test(s)||['home','explore','i','settings','search'].includes(s)) throw Park.error('CONFIG','订阅目标无效');
    return {id:s,label:'@'+s};
  }
  function walk(v,p){let out=[];if(v&&typeof v==='object'){if(p(v))out.push(v);for(const x of Object.values(v))out.push(...walk(x,p));}return out;}
  function initialState(html){
    const marker=/(?:window\.)?__INITIAL_STATE__\s*=\s*/.exec(html);
    if(!marker)throw Park.error('PARSE',FAIL);
    const start=marker.index+marker[0].length;let depth=0,quote=false,escape=false;
    for(let i=start;i<html.length;i++){const c=html[i];if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c==='"')quote=false;}else{if(c==='"')quote=true;else if(c==='{')depth++;else if(c==='}'&&--depth===0)return JSON.parse(html.slice(start,i+1));}}
    throw Park.error('PARSE',FAIL);
  }
  async function prepare(source){
    if(bootstrap&&Date.now()-bootstrap.time<15*60*1000)return bootstrap;
    const r=await source.http.get(HOME+'/home');
    if(!r.ok)throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');
    const doc=Park.html.parse(r.body);
    const scripts=Array.from(doc.querySelectorAll('script[src]')).map(n=>n.getAttribute('src')).filter(s=>{try{const u=new URL(s);return u.protocol==='https:'&&u.hostname==='abs.twimg.com'&&u.pathname.includes('/main.');}catch{return false;}});
    if(scripts.length!==1)throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');
    const js=await source.http.text(scripts[0],{headers:{Cookie:''}});
    const bearer=/["'](AAAAAAAA[A-Za-z0-9%_-]{50,})["']/.exec(js);
    if(!bearer)throw Park.error('PARSE',FAIL);
    const state=initialState(r.body),features={};
    for(const d of walk(state.featureSwitch||{},()=>true))for(const [k,v]of Object.entries(d)){
      if(typeof v==='boolean')features[k]=v;else if(v&&typeof v.value==='boolean')features[k]=v.value;
    }
    const chunks=[];
    const runtime=Array.from(doc.querySelectorAll('script')).map(s=>s.textContent||'').find(s=>s.includes('.u='))||'';
    const names={},hashes={};
    for(const m of runtime.matchAll(/(?:\{|,)(\d+):"([A-Za-z0-9_.~-]+)"/g)){
      if(m[2].includes('bundle.HomeTimeline'))names[m[1]]=m[2];
      else if(/^[a-f0-9]{8,64}$/.test(m[2]))hashes[m[1]]=m[2];
    }
    const suffix=/\}\)\[[a-zA-Z]\]\+"([a-z]*\.js)"/.exec(runtime)?.[1];
    if(suffix)for(const [id,name]of Object.entries(names).sort((a,b)=>(a[1]==='bundle.HomeTimeline'?-1:1)-(b[1]==='bundle.HomeTimeline'?-1:1))){
      if(hashes[id])chunks.push(new URL(name+'.'+hashes[id]+suffix,new URL('.',scripts[0])).href);
    }
    bootstrap={time:Date.now(),js,bearer:decodeURIComponent(bearer[1]),features,chunks};return bootstrap;
  }
  async function api(source,name,variables){
    const cookies=await source.cookies.get(HOME+'/');
    if(!cookies.auth_token||!cookies.ct0)throw Park.error('LOGIN_REQUIRED','请先登录 X 后使用推荐和搜索');
    const b=await prepare(source);
    const pattern=new RegExp('queryId:"([A-Za-z0-9_-]+)",operationName:"'+name+'".{0,200}?featureSwitches:(\\[[^\\]]*\\])(?:,fieldToggles:(\\[[^\\]]*\\]))?');
    let m=pattern.exec(b.js);
    if(!m&&(b.chunks.length||b.chunkLoad)){
      if(!b.chunkLoad)b.chunkLoad=(async()=>{
        try {
          for(const url of b.chunks){
            const chunk=await source.http.text(url,{headers:{Cookie:'',Authorization:''}});
            if(chunk.length>4*1024*1024)throw Park.error('PARSE',FAIL);
            b.js+='\n'+chunk;
          }
          b.chunks=[];
        } catch(e){ bootstrap=null;throw e; }
      })();
      await b.chunkLoad;
      m=pattern.exec(b.js);
    }
    if(!m)throw Park.error('PARSE',FAIL);
    const payload={variables,features:Object.fromEntries(JSON.parse(m[2]).map(k=>[k,b.features[k]===true])),fieldToggles:Object.fromEntries((m[3]?JSON.parse(m[3]):[]).map(k=>[k,false]))};
    const url=HOME+'/i/api/graphql/'+m[1]+'/'+name;
    const headers={Authorization:'Bearer '+b.bearer,'X-CSRF-Token':cookies.ct0,'X-Twitter-Auth-Type':'OAuth2Session','X-Twitter-Active-User':'yes',Referer:HOME+'/'};
    const res=name==='SearchTimeline'
      ? await source.http.post(url,{json:payload,headers})
      : await source.http.get(url,{params:Object.fromEntries(Object.entries(payload).map(([k,v])=>[k,JSON.stringify(v)])),headers});
    if(res.status===404){bootstrap=null;throw Park.error('PARSE',FAIL);}
    if(res.status===429)throw Park.error('BLOCKED','请求过于频繁，请稍后重试');
    if(res.status===401){source.store.set('account',null);bootstrap=null;throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');}
    let data;try{data=res.json();}catch{throw Park.error('PARSE',FAIL);}
    if(res.status===401||data.errors?.some(e=>[32,89,239].includes(e.code))){source.store.set('account',null);bootstrap=null;throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');}
    if(res.status===429||data.errors?.some(e=>e.code===88))throw Park.error('BLOCKED','请求过于频繁，请稍后重试');
    if(!res.ok||!data.data)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
    return data.data;
  }
  function tweetPost(tweet,userId){
    const t=tweet?.tweet||tweet;if(!t?.rest_id||!t.legacy)return null;
    const author=t.core?.user_results?.result;
    if(userId && (author?.rest_id!==userId||t.legacy.retweeted_status_result))return null;
    const attachments=t.legacy.extended_entities?.media||[];
    const media=attachments.map(m=>{
      if(m.type==='photo')return {type:'image',url:m.media_url_https,preview:m.media_url_https};
      const v=(m.video_info?.variants||[]).filter(v=>v.content_type==='video/mp4').sort((a,b)=>(b.bitrate||0)-(a.bitrate||0))[0];
      return v?{type:'video',url:v.url,preview:m.media_url_https}:null;
    }).filter(Boolean);
    if(userId && !media.length)return null;
    return {id:t.rest_id,title:'@'+(author?.core?.screen_name||author?.legacy?.screen_name||''),text:t.note_tweet?.note_tweet_results?.result?.text||t.legacy.full_text||'',date:t.legacy.created_at,url:HOME+'/i/status/'+t.rest_id,media};
  }
  function timelinePosts(data,userId){
    const entries=walk(data,d=>d.entryId&&d.content);
    const tweets=[];
    for(const e of entries){if(/^promoted/.test(e.entryId))continue;
      const c=e.content;const direct=c.itemContent?.tweet_results?.result;if(direct)tweets.push(direct);
      for(const i of c.items||[]){const t=i.item?.itemContent?.tweet_results?.result;if(t)tweets.push(t);}
    }
    return [...new Map(tweets.map(t=>tweetPost(t,userId)).filter(Boolean).map(p=>[p.id,p])).values()];
  }
  const mediaFilter={key:'mediaType',label:'媒体类型',type:'select',default:'all',values:[{value:'all',label:'全部'},{value:'image',label:'图片'},{value:'video',label:'视频'}]};
  function workPage(data,req,mediaType='all'){
    if(!['all','image','video'].includes(mediaType))throw Park.error('CONFIG','媒体类型无效');
    const cursor=walk(data,x=>x.cursorType==='Bottom'&&x.value).at(-1)?.value;
    const items=timelinePosts(data).map(post=>{
      const media=post.media.filter(m=>mediaType==='all'||m.type===mediaType);
      if(mediaType!=='all'&&!media.length)return null;
      const first=media[0];
      return {...post,media,subtitle:post.text,cover:first?.preview||'',
        presentation:mediaType==='all'?'post':'media',
        mediaKind:first?.type==='video'?'video':'comic',coverAspect:first?.type==='video'?16/9:1,
        pages:media.length};
    }).filter(Boolean);
    return {items,page:Math.max(1,Number(req.page)||1),cursor,hasNext:!!cursor&&cursor!==req.cursor};
  }
  Park.register({key:'x',name:'X / Twitter',version:'0.0.3',type:'video',category:'other',homepage:HOME,domains:['x.com','twitter.com','abs.twimg.com','pbs.twimg.com','video.twimg.com','api.fxtwitter.com'],network:{vpnHint:true},description:'登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅',idExample:'NASA',
    defaultFeed:'recommend',feeds:[{key:'recommend',label:'推荐',options:[mediaFilter]},{key:'photos',label:'图集'},{key:'videos',label:'视频集'}],
    searchHint:'搜索帖子、用户或话题；推荐和搜索需要先登录 X',searchFilters:[mediaFilter,{key:'sort',label:'排序',type:'select',default:'Top',values:[{value:'Top',label:'热门'},{value:'Latest',label:'最新'}]}],
    async feed(key,req={}){
      if(!['recommend','photos','videos'].includes(key))throw Park.error('CONFIG','未知推荐列表');
      if(Number(req.page)>1&&!req.cursor)throw Park.error('CONFIG','请按顺序加载推荐');
      const data=await api(this,'HomeTimeline',{count:20,includePromotedContent:false,latestControlAvailable:true,requestContext:'launch',withCommunity:true,...(req.cursor?{cursor:req.cursor}:{})});
      return workPage(data,req,key==='photos'?'image':key==='videos'?'video':req.options?.mediaType||'all');
    },
    async search(req={}){
      const keyword=String(req.keyword||'').trim();
      if(!keyword)return {items:[],page:1,hasNext:false};
      if(Number(req.page)>1&&!req.cursor)throw Park.error('CONFIG','请按顺序加载搜索');
      const type=req.filters?.mediaType||'all';
      if(!['all','image','video'].includes(type))throw Park.error('CONFIG','媒体类型无效');
      const sort=req.filters?.sort||'Top';
      if(!['Top','Latest'].includes(sort))throw Park.error('CONFIG','搜索排序无效');
      const data=await api(this,'SearchTimeline',{rawQuery:keyword,count:20,querySource:'typed_query',product:type==='image'?'Photos':type==='video'?'Videos':sort,withGrokTranslatedBio:false,...(req.cursor?{cursor:req.cursor}:{})});
      return workPage(data,req,type);
    },
    account:{type:'cookies',title:'登录 X',hint:'请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限',loginUrl:HOME+'/i/flow/login',cookieUrl:HOME+'/',requiredCookies:['auth_token','ct0'],fields:[{key:'auth_token',label:'auth_token',secret:true},{key:'ct0',label:'ct0',secret:true}],
      async login(values){await this.cookies.set(HOME+'/',{auth_token:values.auth_token,ct0:values.ct0});bootstrap=null;this.store.set('account',null);try{const d=await api(this,'Viewer',{withCommunitiesMemberships:true,withSubscribedTab:true,withCommunitiesMetadata:true});const u=walk(d,x=>x.__typename==='User'&&x.rest_id)[0];if(!u)throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');const name=u.core?.screen_name||u.legacy?.screen_name||'X';this.store.set('account',{name});return {name};}catch(e){await this.cookies.clear(HOME+'/');throw e;}},
      async logout(){await this.cookies.clear(HOME+'/');this.store.set('account',null);bootstrap=null;},status(){const a=this.store.get('account');return {loggedIn:!!a,name:a?.name||''};}},
    subscription:{hint:'可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。',normalize,
      async resolve(input){const target=normalize(input);if(!this.store.get('account'))return target;const d=await api(this,'UserByScreenName',{screen_name:target.id,withSafetyModeUserFields:true,withGrokTranslatedBio:false});const u=d.user?.result;if(!u?.rest_id)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {id:target.id,label:u.core?.name||u.legacy?.name||target.label};},
      async posts(input,options){const target=normalize(input),cursor=options?.cursor;
        if(!this.store.get('account')){
          const r=await this.http.get('https://api.fxtwitter.com/2/profile/'+target.id+'/media',{params:cursor?{cursor}:undefined,headers:{Cookie:'',Authorization:''}});
          if(!r.ok)throw Park.error('LOGIN_REQUIRED','匿名访问受限，请登录后重试');const d=r.json();if(d.code!==200)throw Park.error('LOGIN_REQUIRED','匿名访问受限，请登录后重试');
          const items=(d.results||[]).map(t=>({id:String(t.id),title:'@'+target.id,text:t.text||'',url:t.url||HOME+'/'+target.id+'/status/'+t.id,date:t.created_at||'',media:[...(t.media?.photos||[]).map(p=>({type:'image',url:p.url,preview:p.url})),...(t.media?.videos||[]).map(v=>({type:'video',url:v.url,preview:v.thumbnail_url||''}))]})).filter(p=>p.media.length);
          return {items,cursor:d.cursor?.bottom,hasNext:!!d.cursor?.bottom};
        }
        const user=await api(this,'UserByScreenName',{screen_name:target.id,withSafetyModeUserFields:true,withGrokTranslatedBio:false});const u=user.user?.result;
        if(!u?.rest_id)throw Park.error('NOT_FOUND','内容不存在或已被删除');
        const data=await api(this,'UserTweets',{userId:u.rest_id,count:20,includePromotedContent:false,withQuickPromoteEligibilityTweetFields:true,withVoice:true,...(cursor?{cursor}:{})});
        const bottom=walk(data,x=>x.cursorType==='Bottom'&&x.value).at(-1)?.value;
        const items=timelinePosts(data,u.rest_id);
        if(!items.length&&!bottom&&u.privacy?.protected&&!u.relationship_perspectives?.following)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
        return {items,cursor:bottom,hasNext:!!bottom&&bottom!==cursor};
      }
    }
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"},{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}],"searchFilters":{"sort":"Latest"}});
