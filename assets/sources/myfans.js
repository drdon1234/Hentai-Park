(function(){
 'use strict';
 const HOME='https://myfans.jp',BASE='https://api.myfans.jp/api';
 function normalize(input){let s=String(input||'').trim();if(/^https?:\/\//i.test(s)){const u=new URL(s);if(u.protocol!=='https:'||!['myfans.jp','www.myfans.jp'].includes(u.hostname)||u.username||u.password)throw Park.error('CONFIG','订阅目标无效');const p=u.pathname.split('/').filter(Boolean);if(p.length!==1)throw Park.error('CONFIG','订阅目标无效');s=p[0];}s=s.replace(/^@/,'');if(!/^[a-zA-Z0-9_-]{1,64}$/.test(s))throw Park.error('CONFIG','订阅目标无效');return {id:s,label:s};}
 async function api(source,path,params){const r=await source.http.get(BASE+path,{params,headers:{'Content-Type':'application/json','google-ga-data':'event328','x-vercel-env':'production','X-Mf-Locale':'ja',Origin:HOME,Referer:HOME+'/',Cookie:''}});if(!r.ok)throw Park.error(r.status===404?'NOT_FOUND':'BLOCKED','访问受限，请在原站检查权限');return r.json();}
 function post(p) {
   const media = [];
   // 源站播放器优先选择 main，否则播放 trial；visible 只表示全文权限。
   const main = p.visible === true && Array.isArray(p.videos?.main)
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
         previewOnly: p.visible !== true
       });
     }
   }
   if (!media.length && p.thumbnail_url) media.push({
     type: 'image', url: p.thumbnail_url, preview: p.thumbnail_url, previewOnly: true
   });
   return {
     id: p.id, title: p.user?.name || '', text: p.body || '',
     url: HOME + '/posts/' + p.id, date: p.published_at || '',
     locked: p.visible !== true && !videos.length, media
   };
 }
 Park.register({i18n:{"zh-Hant": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "創作者訂閱，公開圖片、影片及影片預覽；會員內容需在原站授權", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "支援在應用程式內查看公開圖片、影片及影片預覽；完整會員內容取決於原站權限。"}, "ja": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "クリエイターの購読、公開画像・動画・動画プレビュー。会員向けコンテンツにはサイトの権限が必要です", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "公開画像、動画、動画プレビューをアプリ内で閲覧できます。会員向け完全版の閲覧はサイトの権限によります。"}, "ko": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "크리에이터 구독, 공개 이미지·동영상·미리보기. 회원 콘텐츠는 원본 사이트의 권한이 필요합니다", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "공개 이미지, 동영상 및 동영상 미리보기를 앱 내에서 볼 수 있습니다. 회원 전용 전체 콘텐츠는 원본 사이트의 권한에 따라 달라집니다."}, "en": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Creator subscriptions with public images, videos and video previews; member content requires site authorization", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "View public images, videos and video previews in the app. Full member content depends on site permissions."}, "es": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Suscripciones a creadores, imágenes, vídeos y vistas previas públicas; el contenido para miembros requiere autorización del sitio", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "Puedes ver imágenes, vídeos y vistas previas públicas en la aplicación. El contenido completo para miembros depende de los permisos del sitio."}, "ru": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "Подписки на авторов, общедоступные изображения, видео и предпросмотры; контент для участников требует разрешения сайта", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "Общедоступные изображения, видео и предпросмотры доступны в приложении. Полный контент для участников зависит от прав на сайте."}, "ar": {"创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权": "اشتراكات المبدعين والصور والفيديوهات والمعاينات العامة؛ يتطلب محتوى الأعضاء تفويض الموقع", "支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。": "يمكن عرض الصور والفيديوهات والمعاينات العامة داخل التطبيق. يعتمد محتوى الأعضاء الكامل على صلاحيات الموقع."}},key:'myfans',name:'myfans.jp',version:'0.0.4',type:'comic',category:'other',homepage:HOME,domains:['myfans.jp','api.myfans.jp','mfcdn.jp'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['mfcdn.jp']},description:'创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权',idExample:'haruni',
  subscription:{hint:'支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。',normalize,
   async resolve(input){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {id:t.id,label:u.name||t.label};},
   async posts(input,options){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');const page=Number(options?.cursor||1);if(!Number.isInteger(page)||page<1||page>100000)throw Park.error('CONFIG','分页参数无效');const d=await api(this,'/stream/users/'+encodeURIComponent(u.id)+'/posts',{page,per_page:10});const items=Array.isArray(d.data)?d.data:[];const hasNext=items.length===10&&(d.pagination?.total_pages==null||page<d.pagination.total_pages);return {items:items.map(post),cursor:hasNext?String(page+1):null,hasNext};}
  }
 });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"}]});
