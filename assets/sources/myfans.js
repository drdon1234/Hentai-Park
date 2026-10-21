(function(){
 'use strict';
 const HOME='https://myfans.jp',BASE='https://api.myfans.jp/api';
 function normalize(input){let s=String(input||'').trim();if(/^https?:\/\//i.test(s)){const u=new URL(s);if(u.protocol!=='https:'||!['myfans.jp','www.myfans.jp'].includes(u.hostname)||u.username||u.password)throw Park.error('CONFIG','订阅目标无效');const p=u.pathname.split('/').filter(Boolean);if(p.length!==1)throw Park.error('CONFIG','订阅目标无效');s=p[0];}s=s.replace(/^@/,'');if(!/^[a-zA-Z0-9_-]{1,64}$/.test(s))throw Park.error('CONFIG','订阅目标无效');return {id:s,label:s};}
 // 官网 General=全年龄、Woman=一般成人；统一应用到列表、搜索和详情。
 async function api(source,path,params){const r=await source.http.get(BASE+path,{params:{...params,sexual_orientation:'woman'},headers:{'Content-Type':'application/json','google-ga-data':'event328','x-vercel-env':'production','X-Mf-Locale':'ja',Origin:HOME,Referer:HOME+'/',Cookie:''}});if(!r.ok)throw Park.error(r.status===404?'NOT_FOUND':'BLOCKED','访问受限，请在原站检查权限');return r.json();}
 function post(p) {
   const media = [];
   // 源站播放器优先选择 main，否则播放 trial；visible 只表示全文权限。
   const main = Array.isArray(p.videos?.main)
     ? p.videos.main.filter(v => v.url) : [];
   const trial = Array.isArray(p.videos?.trial)
     ? p.videos.trial.filter(v => v.url) : [];
   const videos = main.length ? main : trial;
   for (const v of videos) {
     media.push({
       type: 'video', url: v.url,
       preview: v.image_url || p.thumbnail_url || '',
       format: new URL(v.url).pathname.endsWith('.m3u8') ? 'hls' : 'mp4',
       previewOnly: !main.length
     });
   }
   // 视频帖 images 是封面；有视频时不再将模糊封面当作图集展示。
   if (p.kind !== 'video' || !videos.length) {
     for (const i of Array.isArray(p.images) ? p.images : []) {
       if (i.url) media.push({
         type: 'image', url: i.url, preview: i.square_thumbnail_url || i.url,
         previewOnly: p.visible !== true, blurred: p.visible !== true
       });
     }
   }
   if (!media.length && p.thumbnail_url) media.push({
     type: 'image', url: p.thumbnail_url, preview: p.thumbnail_url, previewOnly: true,
     blurred: p.visible !== true
   });
   return {
     id: String(p.id), title: p.user?.name || '', text: p.body || '',
     url: HOME + '/posts/' + p.id, date: p.published_at || '',
     locked: p.visible !== true && !videos.length, media: media.map((m,i)=>({...m,id:String(i)})),
     coverBlurred: media[0]?.blurred === true
   };
 }
 async function workPage(source,d,req){
   if(!Array.isArray(d.data))throw Park.error('PARSE','站点接口已变化，请稍后重试');
   const page=Math.max(1,Number(req.page)||1);
   // 排行与推荐接口可能只给摘要；补全真实媒体，不能拿封面冒充写真。
   const posts=await Park.utils.mapLimit(d.data,3,async p=>{
     if(Array.isArray(p.images)||(p.videos&&typeof p.videos==='object'))return p;
     const detail=await api(source,'/v2/posts/'+encodeURIComponent(p.id));
     if(detail.id!==p.id||(!Array.isArray(detail.images)&&!detail.videos))throw Park.error('PARSE','站点接口已变化，请稍后重试');
     return {...p,...detail};
   });
   const items=posts.map(post).map(p=>({...p,subtitle:p.text,cover:p.media[0]?.preview||'',mediaKind:p.media[0]?.type==='video'?'video':'comic',presentation:'post'}));
   const next=d.pagination?.next;
   const hasNext=next!=null||(d.pagination?.next===undefined&&d.data.length===10&&(d.pagination?.total_pages==null||page<d.pagination.total_pages));
   return {items,page,cursor:hasNext?String(next||page+1):null,hasNext};
 }
 Park.register({i18n:{"zh-Hant": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "創作者訂閱，公開圖片、影片及影片預覽；會員內容需在原站授權", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "支援在應用程式內查看公開圖片、影片及影片預覽；完整會員內容取決於原站權限。", "精选": "精選"}, "ja": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "クリエイターの購読、公開画像・動画・動画プレビュー。会員向けコンテンツにはサイトの権限が必要です", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "公開画像、動画、動画プレビューをアプリ内で閲覧できます。会員向け完全版の閲覧はサイトの権限によります。", "精选": "ピックアップ"}, "ko": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "크리에이터 구독, 공개 이미지·동영상·미리보기. 회원 콘텐츠는 원본 사이트의 권한이 필요합니다", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "공개 이미지, 동영상 및 동영상 미리보기를 앱 내에서 볼 수 있습니다. 회원 전용 전체 콘텐츠는 원본 사이트의 권한에 따라 달라집니다.", "精选": "엄선"}, "en": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Creator subscriptions with public images, videos and video previews; member content requires site authorization", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "View public images, videos and video previews in the app. Full member content depends on site permissions.", "精选": "Pickup"}, "es": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Suscripciones a creadores, imágenes, vídeos y vistas previas públicas; el contenido para miembros requiere autorización del sitio", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "Puedes ver imágenes, vídeos y vistas previas públicas en la aplicación. El contenido completo para miembros depende de los permisos del sitio.", "精选": "Selección"}, "ru": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Подписки на авторов, общедоступные изображения, видео и предпросмотры; контент для участников требует разрешения сайта", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "Общедоступные изображения, видео и предпросмотры доступны в приложении. Полный контент для участников зависит от прав на сайте.", "精选": "Подборка"}, "ar": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "اشتراكات المبدعين والصور والفيديوهات والمعاينات العامة؛ يتطلب محتوى الأعضاء تفويض الموقع", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "يمكن عرض الصور والفيديوهات والمعاينات العامة داخل التطبيق. يعتمد محتوى الأعضاء الكامل على صلاحيات الموقع.", "精选": "مختارات"}},key:'myfans',name:'myfans.jp',version: '0.0.9', minAppVersion: '0.9.2',type:'comic',category:'other',homepage:HOME,domains:['myfans.jp','api.myfans.jp','mfcdn.jp'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['mfcdn.jp']},description:'创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权',idExample:'haruni',
  defaultFeed:'recommend',feeds:[{key:'recommend',label:'精选'},{key:'ranking',label:'排行榜',options:[{key:'category',label:'分类',default:'all',dynamic:true,values:[]},{key:'term',label:'周期',default:'daily',values:[{value:'daily',label:'每天'},{value:'weekly',label:'每周'}]}]}],
  async categories(){
   if(this.categoryCache&&Date.now()-this.categoryCache.time<300000)return this.categoryCache.values;
   const data=await api(this,'/genres');
   if(!Array.isArray(data))throw Park.error('PARSE','分类列表解析失败');
   const values=[{value:'all',label:'全部'}],seen=new Set(['all']);
   for(const row of data){
    if(!/^f-[a-z0-9-]{1,100}$/.test(row?.key||'')||typeof row.name!=='string'||!row.name.trim()||seen.has(row.key))continue;
    seen.add(row.key);values.push({value:row.key,label:row.name.trim()});
   }
   if(values.length<2||values.length>500)throw Park.error('PARSE','分类列表解析失败');
   this.categoryCache={time:Date.now(),values};return values;
  },
  async filterOptions(req){
   if(req.scope!=='feed'||req.feed!=='ranking'||req.filter!=='category')return [];
   return this.categories();
  },
  rankings:[{key:'ranking',label:'排行榜',category:'other',metric:'站内热度',feed:'ranking'}],
  async search(req={}){
   const keyword=String(req.keyword||'').trim();
   if(!keyword)return {items:[],page:1,hasNext:false};
   if(Number(req.page)>1&&!req.cursor)throw Park.error('CONFIG','分页参数无效');
   const d=await api(this,'/stream/posts',{query:keyword,sort_key:'publish_start_at',per_page:10,...(req.cursor?{cursor:req.cursor}:{page:1})});
   const result=await workPage(this,d,req);
   const cursor=d.cursor?.next;
   return {...result,cursor,hasNext:!!cursor&&cursor!==req.cursor};
  },
  async feed(key,req={}){
   if(!['recommend','ranking'].includes(key))throw Park.error('CONFIG','分页参数无效');
   const page=Number(req.cursor||req.page||1);
   if(!Number.isInteger(page)||page<1||page>100000)throw Park.error('CONFIG','分页参数无效');
   const term=req.options?.term||'daily';
   if(!['daily','weekly'].includes(term))throw Park.error('CONFIG','分页参数无效');
   const category=String(req.options?.category||'all');
   if(key==='ranking'&&category!=='all'&&!(await this.categories()).some(x=>x.value===category))throw Park.error('CONFIG','分类无效');
   let d;
   if(key==='ranking'&&page===1&&category==='all'){
    // /zh-CN/ranking/posts 默认日榜；只取综合榜，分类榜不能混入总名次。
    const groups=await api(this,'/ranking/posts',{term,all_posts_limit:10});
    const all=Array.isArray(groups)?groups.find(g=>g.genre?.key==='all'):null;
    if(!all||!Array.isArray(all.data))throw Park.error('PARSE','站点接口已变化，请稍后重试');
    d={data:all.data};
   }else{
    // 官网总览的“全部”入口提供同一榜单的后续分页。
    d=await api(this,key==='ranking'?'/ranking/posts/'+encodeURIComponent(category):'/stream/posts/pick',{page,per_page:10,...(key==='ranking'?{term}:{})});
   }
   return workPage(this,d,{page});
  },
  subscription:{hint:'支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。',normalize,
   async resolve(input){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {id:t.id,label:u.name||t.label};},
   async posts(input,options){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');const page=Number(options?.cursor||1);if(!Number.isInteger(page)||page<1||page>100000)throw Park.error('CONFIG','分页参数无效');const d=await api(this,'/stream/users/'+encodeURIComponent(u.id)+'/posts',{page,per_page:10});return workPage(this,d,{page});},
   async media(scope,options={}){
    return scope.target?this.subscription.posts.call(this,scope.target,options):this.feed(scope.feed,{...options,options:scope.options});
   }
  }
 });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"},{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"}]});
