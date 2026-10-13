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
 Park.register({key:'myfans',name:'myfans.jp',version:'0.0.3',type:'comic',category:'other',homepage:HOME,domains:['myfans.jp','api.myfans.jp','mfcdn.jp'],network:{vpnHint:true},media:{mode:'native',origin:HOME,domains:['mfcdn.jp']},description:'创作者订阅，公开图片、视频及视频预览；会员内容需在原站授权',idExample:'haruni',
  subscription:{hint:'支持应用内查看公开图片、视频及视频预览；完整会员内容取决于原站权限。',normalize,
   async resolve(input){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');return {id:t.id,label:u.name||t.label};},
   async posts(input,options){const t=normalize(input),u=await api(this,'/v2/users/show_by_username',{username:t.id});if(!u.id)throw Park.error('NOT_FOUND','内容不存在或已被删除');const page=Number(options?.cursor||1);if(!Number.isInteger(page)||page<1||page>100000)throw Park.error('CONFIG','分页参数无效');const d=await api(this,'/stream/users/'+encodeURIComponent(u.id)+'/posts',{page,per_page:10});const items=Array.isArray(d.data)?d.data:[];const hasNext=items.length===10&&(d.pagination?.total_pages==null||page<d.pagination.total_pages);return {items:items.map(post),cursor:hasNext?String(page+1):null,hasNext};}
  }
 });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"}]});
