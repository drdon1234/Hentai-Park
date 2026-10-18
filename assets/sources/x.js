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
      if(/bundle\.(?:HomeTimeline|Tweet|Bookmark|UserProfile)/.test(m[2]))names[m[1]]=m[2];
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
    const res=['SearchTimeline','FavoriteTweet','UnfavoriteTweet','CreateBookmark','DeleteBookmark'].includes(name)
      ? await source.http.post(url,{json:payload,headers})
      : await source.http.get(url,{params:Object.fromEntries(Object.entries(payload).map(([k,v])=>[k,JSON.stringify(v)])),headers});
    if(res.status===404){bootstrap=null;throw Park.error('PARSE',FAIL);}
    if(res.status===429)throw Park.error('BLOCKED','请求过于频繁，请稍后重试');
    if(res.status===401){source.store.set('account',null);bootstrap=null;throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');}
    let data;try{data=res.json();}catch{throw Park.error('PARSE',FAIL);}
    if(res.status===401||data.errors?.some(e=>[32,89,239].includes(e.code))){source.store.set('account',null);bootstrap=null;throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');}
    if(res.status===429||data.errors?.some(e=>e.code===88))throw Park.error('BLOCKED','请求过于频繁，请稍后重试');
    if(!res.ok||!data.data||data.errors?.length)throw Park.error('BLOCKED','访问受限，请在原站检查权限或手动关注、加入');
    return data.data;
  }
  function tweetPost(tweet,userId){
    let t=tweet?.tweet||tweet;if(!t?.rest_id||!t.legacy)return null;
    if (t.legacy.retweeted_status_result) {
      if (userId) return null;
      const original=t.legacy.retweeted_status_result.result;
      t=original?.tweet||original;
      if(!t?.rest_id||!t.legacy)return null;
    }
    const author=t.core?.user_results?.result;
    if(userId && (author?.rest_id!==userId||t.legacy.retweeted_status_result))return null;
    const attachments=t.legacy.extended_entities?.media||[];
    const media=attachments.map(m=>{
      if(m.type==='photo')return {type:'image',url:m.media_url_https,preview:m.media_url_https};
      const v=(m.video_info?.variants||[]).filter(v=>v.content_type==='video/mp4').sort((a,b)=>(b.bitrate||0)-(a.bitrate||0))[0];
      return v?{type:'video',url:v.url,preview:m.media_url_https}:null;
    }).filter(Boolean);
    if(userId && !media.length)return null;
    const handle=author?.core?.screen_name||author?.legacy?.screen_name||'';
    const name=author?.core?.name||author?.legacy?.name||'';
    return {id:t.rest_id,title:name||'@'+handle,uploader:handle,authors:handle?[handle]:[],text:t.note_tweet?.note_tweet_results?.result?.text||t.legacy.full_text||'',date:t.legacy.created_at,url:HOME+'/i/status/'+t.rest_id,media};
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
  function workId(id) {
    id=String(id);
    if(!/^[1-9]\d{0,24}$/.test(id))throw Park.error('NOT_FOUND','内容不存在或已被删除');
    return id;
  }
  async function tweet(source,id) {
    const data=await api(source,'TweetResultByRestId',{tweetId:workId(id),withCommunity:true,includePromotedContent:false,withVoice:true});
    const result=walk(data,v=>v.rest_id===String(id)&&v.legacy)[0];
    if(!result)throw Park.error('NOT_FOUND','内容不存在或已被删除');
    return result;
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
  Park.register({i18n:{"zh-Hant": {"匿名访问受限，请登录后重试": "匿名存取受限，請登入後重試", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "可先訂閱；匿名存取可能受限。需要追蹤時請至原站手動操作。", "媒体类型": "媒體類型", "媒体类型无效": "媒體類型無效", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "搜尋貼文、使用者或話題；推薦與搜尋需要先登入 X", "搜索排序无效": "搜尋排序無效", "未知推荐列表": "未知推薦列表", "登录 X": "登入 X", "登录信息无效，请重新登录": "登入資訊無效，請重新登入", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "登入後瀏覽推薦、圖集、影片集及站內搜尋，支援公開使用者訂閱", "访问受限，请在原站检查权限或手动关注、加入": "存取受限，請在原站檢查權限或手動追蹤、加入", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "請使用 auth_token 與 ct0；敏感內容需至原站開啟顯示權限", "请先登录 X 后使用推荐和搜索": "請先登入 X 後使用推薦和搜尋", "请按顺序加载推荐": "請按順序載入推薦", "请按顺序加载搜索": "請按順序載入搜尋", "请求过于频繁，请稍后重试": "請求過於頻繁，請稍後重試"}, "ja": {"匿名访问受限，请登录后重试": "匿名アクセスが制限されています。ログインしてからお試しください", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "先に購読できます。匿名アクセスは制限される場合があります。必要に応じてサイトで手動フォローしてください。", "媒体类型": "メディアの種類", "媒体类型无效": "メディアの種類が無効です", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "投稿・ユーザー・話題を検索。おすすめと検索には X へのログインが必要です", "搜索排序无效": "検索の並び順が無効です", "未知推荐列表": "不明なおすすめリストです", "登录 X": "Xにログイン", "登录信息无效，请重新登录": "ログイン情報が無効です。もう一度ログインしてください", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "ログイン後におすすめ・画像・動画・検索を利用。公開ユーザーの購読にも対応", "访问受限，请在原站检查权限或手动关注、加入": "アクセスが制限されています。元のサイトで権限を確認するか、フォローや参加を手動で行ってください", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "auth_tokenとct0を使用してください。センシティブな内容の表示はサイトで有効にしてください", "请先登录 X 后使用推荐和搜索": "おすすめと検索を使うには X にログインしてください", "请按顺序加载推荐": "おすすめは順番に読み込んでください", "请按顺序加载搜索": "検索結果は順番に読み込んでください", "请求过于频繁，请稍后重试": "リクエストが多すぎます。しばらくしてからお試しください"}, "ko": {"匿名访问受限，请登录后重试": "익명 접근이 제한되었습니다. 로그인 후 다시 시도하세요", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "먼저 구독할 수 있습니다. 익명 접근은 제한될 수 있으며, 필요시 사이트에서 직접 팔로우하세요.", "媒体类型": "미디어 유형", "媒体类型无效": "미디어 형식이 잘못되었습니다", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "게시물, 사용자 또는 주제 검색. 추천과 검색은 X 로그인이 필요합니다", "搜索排序无效": "검색 정렬이 잘못되었습니다", "未知推荐列表": "알 수 없는 추천 목록입니다", "登录 X": "X에 로그인", "登录信息无效，请重新登录": "로그인 정보가 잘못되었습니다. 다시 로그인하세요", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "로그인 후 추천, 이미지와 동영상 모음, 검색 및 공개 사용자 구독", "访问受限，请在原站检查权限或手动关注、加入": "접근이 제한되었습니다. 원래 사이트에서 권한을 확인하거나 직접 팔로우·가입하세요", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "auth_token과 ct0를 사용하세요. 민감한 콘텐츠 표시는 원본 사이트에서 활성화하세요", "请先登录 X 后使用推荐和搜索": "추천과 검색을 쓰려면 X에 로그인하세요", "请按顺序加载推荐": "추천은 순서대로 불러와 주세요", "请按顺序加载搜索": "검색 결과는 순서대로 불러와 주세요", "请求过于频繁，请稍后重试": "요청이 너무 많습니다. 잠시 후 다시 시도하세요"}, "en": {"匿名访问受限，请登录后重试": "Anonymous access is limited. Sign in and try again.", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "Subscribe first; anonymous access may be restricted. Follow manually on the site when needed.", "媒体类型": "Media type", "媒体类型无效": "Invalid media type", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "Search posts, users or topics; recommendations and search require X sign-in", "搜索排序无效": "Invalid search order", "未知推荐列表": "Unknown recommendation list", "登录 X": "Sign in to X", "登录信息无效，请重新登录": "Your login is invalid. Sign in again.", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "Signed-in recommendations, image and video collections, search, and public user subscriptions", "访问受限，请在原站检查权限或手动关注、加入": "Access is restricted. Check permissions on the original site, or follow or join there.", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "Use auth_token and ct0; enable sensitive content on the site", "请先登录 X 后使用推荐和搜索": "Sign in to X to use recommendations and search", "请按顺序加载推荐": "Load recommendations in order", "请按顺序加载搜索": "Load search results in order", "请求过于频繁，请稍后重试": "Too many requests. Try again later."}, "es": {"匿名访问受限，请登录后重试": "El acceso anónimo está limitado. Inicia sesión e inténtalo de nuevo.", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "Puedes suscribirte primero; el acceso anónimo puede estar restringido. Sigue al usuario manualmente si es necesario.", "媒体类型": "Tipo de contenido", "媒体类型无效": "Tipo de contenido no válido", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "Busca publicaciones, usuarios o temas; inicia sesión en X para recomendaciones y búsqueda", "搜索排序无效": "Orden de búsqueda no válido", "未知推荐列表": "Lista de recomendaciones desconocida", "登录 X": "Iniciar sesión en X", "登录信息无效，请重新登录": "Tu sesión no es válida. Vuelve a iniciar sesión.", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "Recomendaciones, imágenes, videos y búsqueda al iniciar sesión; suscripciones públicas", "访问受限，请在原站检查权限或手动关注、加入": "Acceso restringido. Revisa los permisos en el sitio original o sigue o únete allí.", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "Usa auth_token y ct0; activa el contenido sensible en el sitio", "请先登录 X 后使用推荐和搜索": "Inicia sesión en X para usar recomendaciones y búsqueda", "请按顺序加载推荐": "Carga las recomendaciones en orden", "请按顺序加载搜索": "Carga los resultados en orden", "请求过于频繁，请稍后重试": "Demasiadas solicitudes. Inténtalo más tarde."}, "ru": {"匿名访问受限，请登录后重试": "Анонимный доступ ограничен. Войдите и повторите попытку.", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "Можно подписаться заранее; анонимный доступ может быть ограничен. При необходимости подпишитесь на сайте вручную.", "媒体类型": "Тип медиа", "媒体类型无效": "Недопустимый тип медиа", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "Поиск публикаций, пользователей и тем; для поиска и рекомендаций нужен вход в X", "搜索排序无效": "Недопустимый порядок поиска", "未知推荐列表": "Неизвестный список рекомендаций", "登录 X": "Войти в X", "登录信息无效，请重新登录": "Данные входа недействительны. Войдите снова.", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "Рекомендации, фото, видео и поиск после входа; подписки на открытые профили", "访问受限，请在原站检查权限或手动关注、加入": "Доступ ограничен. Проверьте права на исходном сайте или подпишитесь/вступите там вручную.", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "Используйте auth_token и ct0; включите показ чувствительного контента на сайте", "请先登录 X 后使用推荐和搜索": "Войдите в X, чтобы пользоваться рекомендациями и поиском", "请按顺序加载推荐": "Загружайте рекомендации по порядку", "请按顺序加载搜索": "Загружайте результаты поиска по порядку", "请求过于频繁，请稍后重试": "Слишком много запросов. Повторите позже."}, "ar": {"匿名访问受限，请登录后重试": "الوصول المجهول محدود. سجّل الدخول وحاول مجددًا.", "可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。": "يمكن الاشتراك أولاً؛ قد يكون الوصول المجهول مقيداً. تابع يدوياً على الموقع عند الحاجة.", "媒体类型": "نوع الوسائط", "媒体类型无效": "نوع وسائط غير صالح", "搜索帖子、用户或话题；推荐和搜索需要先登录 X": "ابحث عن المنشورات أو المستخدمين أو المواضيع؛ يلزم تسجيل الدخول إلى X", "搜索排序无效": "ترتيب بحث غير صالح", "未知推荐列表": "قائمة توصيات غير معروفة", "登录 X": "تسجيل الدخول إلى X", "登录信息无效，请重新登录": "بيانات تسجيل الدخول غير صالحة. سجّل الدخول مجددًا.", "登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅": "توصيات ومجموعات صور وفيديو وبحث بعد تسجيل الدخول واشتراكات عامة", "访问受限，请在原站检查权限或手动关注、加入": "الوصول مقيّد. تحقق من الأذونات في الموقع الأصلي أو تابع أو انضم يدويًا.", "请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限": "استخدم auth_token وct0؛ فعّل عرض المحتوى الحساس على الموقع", "请先登录 X 后使用推荐和搜索": "سجّل الدخول إلى X لاستخدام التوصيات والبحث", "请按顺序加载推荐": "حمّل التوصيات بالترتيب", "请按顺序加载搜索": "حمّل نتائج البحث بالترتيب", "请求过于频繁，请稍后重试": "طلبات كثيرة جدًا. حاول لاحقًا."}},key:'x',name:'X / Twitter',version: '0.0.8',type:'video',category:'other',homepage:HOME,domains:['x.com','twitter.com','abs.twimg.com','pbs.twimg.com','video.twimg.com','api.fxtwitter.com'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['video.twimg.com']},description:'登录后浏览推荐、图集、视频集和站内搜索，支持公开用户订阅',idExample:'NASA',
    linkPatterns:['(?:x|twitter)\\.com/(?:[A-Za-z0-9_]+/status|i/(?:web/)?status)/(\\d+)(?:[/?#]|$)'],
    idPattern:'^([1-9]\\d{14,24})$',
    defaultFeed:'recommend',feeds:[{key:'recommend',label:'推荐',options:[mediaFilter]},{key:'photos',label:'图集'},{key:'videos',label:'视频集'}],
    async detail(id) {
      const post=tweetPost(await tweet(this,id));
      const first=post.media[0];
      return {...post,description:post.text,subtitle:post.text,cover:first?.preview||'',mediaKind:first?.type==='video'?'video':'comic',
        pages:post.media.filter(m=>m.type==='image').length,chapters:post.media.length?null:[]};
    },
    async chapter(id) {
      const post=tweetPost(await tweet(this,id));
      return {pages:post.media.filter(m=>m.type==='image').map(m=>({url:m.url}))};
    },
    async videos(id) {
      const post=tweetPost(await tweet(this,id));
      return post.media.filter(m=>m.type==='video').map((m,i)=>({url:m.url,label:String(i+1),type:'mp4'}));
    },
    async interaction(id,req={}) {
      let result=await tweet(this,id);
      const states=()=> {
        if(typeof result.legacy.favorited!=='boolean'||typeof result.legacy.bookmarked!=='boolean')throw Park.error('PARSE','原站互动数据无效');
        return [{type:'like',value:result.legacy.favorited},{type:'favorite',value:result.legacy.bookmarked}];
      };
      if(req.value!==undefined){
        if(!['like','favorite'].includes(req.type)||typeof req.value!=='boolean')throw Park.error('CONFIG','原站互动数据无效');
        if(states().find(s=>s.type===req.type).value!==req.value){
          const name=req.type==='like'?(req.value?'FavoriteTweet':'UnfavoriteTweet'):(req.value?'CreateBookmark':'DeleteBookmark');
          await api(this,name,{tweet_id:workId(id)});
          result=await tweet(this,id);
          if(states().find(s=>s.type===req.type).value!==req.value)throw Park.error('AUTH','原站操作未成功，请重试');
        }
      }
      return states();
    },
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
    account:{type:'cookies',title:'登录 X',hint:'请使用 auth_token 和 ct0；敏感内容需在原站开启显示权限',loginUrl:HOME+'/i/flow/login',loginDomains:['accounts.google.com','appleid.apple.com','account.apple.com'],cookieUrl:HOME+'/',requiredCookies:['auth_token','ct0'],fields:[{key:'auth_token',label:'auth_token',secret:true},{key:'ct0',label:'ct0',secret:true}],
      async login(values){await this.cookies.set(HOME+'/',{auth_token:values.auth_token,ct0:values.ct0});bootstrap=null;this.store.set('account',null);try{const d=await api(this,'Viewer',{withCommunitiesMemberships:true,withSubscribedTab:true,withCommunitiesMetadata:true});const u=walk(d,x=>x.__typename==='User'&&x.rest_id)[0];if(!u)throw Park.error('LOGIN_REQUIRED','登录信息无效，请重新登录');const name=u.core?.screen_name||u.legacy?.screen_name||'X';this.store.set('account',{name});return {name};}catch(e){await this.cookies.clear(HOME+'/');throw e;}},
      async logout(){await this.cookies.clear(HOME+'/');this.store.set('account',null);bootstrap=null;},status(){const a=this.store.get('account');return {loggedIn:!!a,name:a?.name||''};}},
    subscription:{hint:'可先订阅；匿名访问可能受限。需要关注时请到原站手动操作。',normalize,
      async resolve(input){const target=normalize(input);if(!this.store.get('account'))return target;const d=await api(this,'UserByScreenName',{screen_name:target.id,withSafetyModeUserFields:true,withGrokTranslatedBio:false});const u=d.user?.result;if(!u?.rest_id)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {id:target.id,label:u.core?.name||u.legacy?.name||target.label};},
      async posts(input,options){const target=normalize(input),cursor=options?.cursor;
        if(!this.store.get('account')){
          const r=await this.http.get('https://api.fxtwitter.com/2/profile/'+target.id+'/media',{params:cursor?{cursor}:undefined,headers:{Cookie:'',Authorization:''}});
          if(!r.ok)throw Park.error('LOGIN_REQUIRED','匿名访问受限，请登录后重试');const d=r.json();if(d.code!==200)throw Park.error('LOGIN_REQUIRED','匿名访问受限，请登录后重试');
          const items=(d.results||[]).map(t=>({id:String(t.id),title:t.author?.name||t.author?.screen_name||'@'+target.id,uploader:t.author?.screen_name||'',authors:t.author?.screen_name?[t.author.screen_name]:[],text:t.text||'',url:t.url||HOME+'/'+target.id+'/status/'+t.id,date:t.created_at||'',media:[...(t.media?.photos||[]).map(p=>({type:'image',url:p.url,preview:p.url})),...(t.media?.videos||[]).map(v=>({type:'video',url:v.url,preview:v.thumbnail_url||''}))]})).filter(p=>p.media.length);
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
