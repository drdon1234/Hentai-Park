(function(){
 'use strict';
 const HOME='https://www.fanbox.cc',BASE='https://api.fanbox.cc';
 function normalize(input){let s=String(input||'').trim();if(/^https?:\/\//i.test(s)){const u=new URL(s);if(u.protocol!=='https:'||u.username||u.password)throw Park.error('CONFIG','订阅目标无效');if(u.hostname.endsWith('.fanbox.cc')&&!['www.fanbox.cc','api.fanbox.cc'].includes(u.hostname)&&u.pathname==='/')s=u.hostname.slice(0,-10);else if(u.hostname==='www.fanbox.cc'&&/^\/@[a-zA-Z0-9_-]+\/?$/.test(u.pathname))s=u.pathname.replace(/^\/@|\/$/g,'');else throw Park.error('CONFIG','订阅目标无效');}s=s.replace(/^@/,'');if(!/^[a-zA-Z0-9_-]{1,64}$/.test(s))throw Park.error('CONFIG','订阅目标无效');return {id:s,label:s};}
 async function api(source,url,params){const r=await source.http.get(url,{params,headers:{Origin:HOME,Referer:HOME+'/',Cookie:''}});if(!r.ok)throw Park.error('BLOCKED','访问受限，请在原站检查权限');return r.json().body;}
 async function postInfo(source,id){const p=(await api(source,BASE+'/post.info',{postId:id}))?.post;if(!p||String(p.id)!==String(id))throw Park.error('PARSE','站点接口已变化，请稍后重试');return p;}
 Park.register({i18n:{"zh-Hant": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "創作者目錄訂閱，支援公開封面預覽；會員正文尚未驗證", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "目前支援公開目錄及封面預覽；正文與會員登入尚未驗證。"}, "ja": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "クリエイター一覧の購読と公開表紙プレビュー。会員本文は未検証です", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "公開一覧と表紙プレビューに対応。本文と会員ログインは未検証です。"}, "ko": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "크리에이터 목록과 공개 표지 미리보기. 회원 본문은 아직 미검증", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "공개 목록 및 표지 미리보기를 지원합니다. 본문과 회원 로그인은 아직 미검증입니다."}, "en": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "Creator listings with public cover previews; member content not verified", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "Public listings and cover previews supported; post content and member sign-in are not verified yet."}, "es": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "Listados de creadores con portadas públicas; contenido de miembros sin verificar", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "Listados y portadas públicos disponibles; contenido e inicio de sesión de miembros aún sin verificar."}, "ru": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "Каталоги авторов с публичными обложками; платный контент не проверен", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "Доступны публичные каталоги и обложки; содержимое постов и вход не проверены."}, "ar": {"创作者目录订阅，支持公开封面预览；会员正文尚未验证": "قوائم المبدعين مع معاينات أغلفة عامة؛ محتوى الأعضاء غير متحقق منه", "当前支持公开目录和封面预览；正文与会员登录尚未验证。": "القوائم ومعاينات الأغلفة العامة مدعومة؛ المحتوى ودخول الأعضاء غير متحقق منهما بعد."}},key:'fanbox',name:'pixivFANBOX',version: '0.0.6', minAppVersion: '0.9.2',type:'comic',category:'other',homepage:HOME,domains:['fanbox.cc','pixiv.pximg.net'],network:{vpnHint:true},description:'创作者目录订阅，支持公开封面预览；会员正文尚未验证',idExample:'rosuuri',
 async comments(value,req={}) {
  const id=String(value||''),page=Math.max(1,Math.floor(Number(req.page)||1));
  if(!/^[1-9]\d{0,19}$/.test(id))throw Park.error('CONFIG','作品编号无效');
  if(req.parentId)return {items:[],page,hasNext:false};
  const post=await postInfo(this,id);
  if(post.isRestricted)throw Park.error('BLOCKED','访问受限，请在原站检查权限');
  const cursorUrl=(value)=>{
   let u;try{u=new URL(value);}catch(_){throw Park.error('CONFIG','分页参数无效');}
   if(u.origin!==BASE||u.username||u.password||u.hash||u.pathname!=='/post.getComments'||u.searchParams.get('postId')!==id||
      [...u.searchParams.keys()].some(k=>!['postId','limit','offset'].includes(k))||
      [...new Set(u.searchParams.keys())].some(k=>u.searchParams.getAll(k).length!==1)||
      !/^\d+$/.test(u.searchParams.get('offset')||'')||!/^\d+$/.test(u.searchParams.get('limit')||'')||
      !Number.isSafeInteger(Number(u.searchParams.get('offset')))||
      Number(u.searchParams.get('limit'))<1||Number(u.searchParams.get('limit'))>100)throw Park.error('CONFIG','分页参数无效');
   return u;
  };
  if(page>1&&!req.cursor)throw Park.error('CONFIG','分页参数无效');
  const current=req.cursor?cursorUrl(String(req.cursor)):null;
  const data=await api(this,current?.href||BASE+'/post.getComments',current?undefined:{postId:id,limit:10,offset:0});
  if(data?.viewMode==='PLEDGE_INSUFFICIENT')throw Park.error('BLOCKED','访问受限，请在原站检查权限');
  const list=data?.commentList;
  if(!list&&['COMMENTING_RESTRICTED','OWNER'].includes(data?.viewMode))throw Park.error('BLOCKED','访问受限，请在原站检查权限');
  if(!list||!Array.isArray(list.items))throw Park.error('PARSE','评论数据无效');
  const seen=new Set();
  const parseComment=(row,root)=>{
   const cid=String(row?.id||''),parent=String(row?.parentCommentId||'0'),rootId=String(row?.rootCommentId||'0');
   if(!/^[1-9]\d*$/.test(cid)||typeof row.body!=='string'||(root?rootId!==root:rootId!=='0'||parent!=='0'))throw Park.error('PARSE','评论数据无效');
   if(seen.has(cid))return null;
   seen.add(cid);
   const body=Park.comments.text(row.body),replies=[];
   if(!root){
    if(!Array.isArray(row.replies))throw Park.error('PARSE','评论数据无效');
    const nested=row.replies.map(r=>parseComment(r,cid)).filter(Boolean),byId=new Map(nested.map(r=>[r.id,r]));
    for(const reply of nested){
     const visited=new Set([reply.id]);let parent=reply.parentId;
     while(parent!==cid){if(visited.has(parent)||!byId.has(parent))throw Park.error('PARSE','评论数据无效');visited.add(parent);parent=byId.get(parent).parentId;}
     if(reply.parentId===cid)replies.push(reply);else byId.get(reply.parentId).replies.push(reply);
    }
    for(const reply of nested)reply.replyCount=reply.replies.length;
   }
   if(!body.length)return null;
   return {id:cid,parentId:root?parent:undefined,author:{name:String(row.user?.name||''),avatar:Park.comments.url(row.user?.iconUrl,HOME)||undefined},
    body,date:String(row.createdDatetime||''),likes:Math.max(0,Number(row.likeCount)||0),replies,replyCount:replies.length};
  };
  const items=list.items.map(row=>parseComment(row)).filter(Boolean);
  let cursor=null;
  if(list.nextUrl){
   const next=cursorUrl(String(list.nextUrl));
   if(Number(next.searchParams.get('offset'))<=Number(current?.searchParams.get('offset')||0))throw Park.error('PARSE','评论数据无效');
   cursor=next.href;
  }
  return {items,page,cursor,hasNext:!!cursor};
 },
 subscription:{hint:'当前支持公开目录和封面预览；正文与会员登录尚未验证。',normalize,
  async resolve(input){return normalize(input);},
  async posts(input,options){const t=normalize(input);const d=await api(this,BASE+'/post.paginateCreator',{creatorId:t.id});const urls=d.pageUrls||[];const index=Number(options?.cursor||0);if(!Number.isInteger(index)||index<0||index>100000)throw Park.error('CONFIG','分页参数无效');if(index>=urls.length)return {items:[],hasNext:false};const u=new URL(urls[index]);if(u.origin!==BASE||u.pathname!=='/post.listCreator'||u.searchParams.get('creatorId')!==t.id)throw Park.error('PARSE','站点接口已变化，请稍后重试');const page=await api(this,u.href);return {items:(page.posts||[]).map(p=>({id:p.id,title:p.title||'',text:p.excerpt||'',date:p.publishedDatetime||'',url:`https://${t.id}.fanbox.cc/posts/${p.id}`,locked:p.isRestricted===true,media:p.cover?.url?[{type:'image',url:p.cover.url,preview:p.cover.url,previewOnly:true}]:[]})),cursor:String(index+1),hasNext:index+1<urls.length};},
  async media(scope,options={}){
   const target=normalize(scope.target),result=await this.subscription.posts.call(this,target.id,options);
   const items=await Park.utils.mapLimit(result.items,3,async summary=>{
    if(summary.locked)return {...summary,id:String(summary.id),presentation:'post',media:summary.media.map((m,i)=>({...m,id:String(i)}))};
    const p=await postInfo(this,summary.id);
    const media=[];
    const add=(i,id)=>{if(i?.originalUrl)media.push({id:String(id),type:'image',url:i.originalUrl,preview:i.thumbnailUrl||i.originalUrl});};
    if(!p.isRestricted&&p.body){
     if(p.type==='image')for(let i=0;i<(p.body.images||[]).length;i++)add(p.body.images[i],String(i));
     if(p.type==='article')for(let i=0;i<(p.body.blocks||[]).length;i++){const block=p.body.blocks[i];if(block.type==='image')add(p.body.imageMap?.[block.imageId],String(i));}
    }else if(p.cover?.url)media.push({id:'cover',type:'image',url:p.cover.url,preview:p.cover.url,previewOnly:true});
    return {...summary,id:String(p.id),presentation:'post',title:p.title||summary.title,
      text:p.body?.text||(p.type==='article'?(p.body?.blocks||[]).map(b=>b.text||'').filter(Boolean).join('\n'):summary.text),locked:p.isRestricted===true,media};
   });
   return {...result,items};
  }
 }
 });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"}]});
