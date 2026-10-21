// Telegram 站点实现；telegram.js 由 tools/build_subscription_sources.mjs 打包。
import makeMTProto from '@mtproto/core/src/index.js';
import { EventEmitter } from 'events';
const HOME = 'https://t.me';
const dcNames = { 1: 'pluto', 2: 'venus', 3: 'aurora', 4: 'vesta', 5: 'flora' };
let client,
  entropy = new Uint8Array(),
  entropyIndex = 0;
let rpcQueue = Promise.resolve();
const peers = new Map();
function normalize(input) {
  let s = String(input || '').trim();
  if (/^https?:\/\//i.test(s)) {
    const u = new URL(s);
    if (
      u.protocol !== 'https:' ||
      !['t.me', 'www.t.me', 'telegram.me'].includes(u.hostname) ||
      u.username ||
      u.password
    )
      throw Park.error('CONFIG', '订阅目标无效');
    let parts = u.pathname.split('/').filter(Boolean);
    if (parts[0] === 's') parts.shift();
    if (parts.length !== 1) throw Park.error('CONFIG', '订阅目标无效');
    s = parts[0];
  }
  s = s.replace(/^@/, '');
  if (/^channel:\d{1,16}$/.test(s)) return { id: s, label: s };
  if (!/^[a-zA-Z][a-zA-Z0-9_]{3,31}$/.test(s))
    throw Park.error('CONFIG', '订阅目标无效');
  return { id: s.toLowerCase(), label: '@' + s };
}
function bytes64(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 8192)
    out += String.fromCharCode(...bytes.slice(i, i + 8192));
  return btoa(out);
}
function from64(text) {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}
async function seed() {
  if (entropy.length - entropyIndex < 8192) {
    entropy = Uint8Array.from(await Park.crypto.randomBytes(65536));
    entropyIndex = 0;
  }
}
class Transport extends EventEmitter {
  constructor(dc, source, onFailure) {
    super();
    this.dc = dc;
    this.source = source;
    this.onFailure = onFailure;
    this.isAvailable = true;
    setTimeout(() => {
      if (this.isAvailable) this.emit('open');
    }, 1);
  }
  async send(bytes) {
    if (!this.isAvailable) return;
    const http = this.source.http;
    try {
      const res = await http.post(
        `https://${dcNames[this.dc.id]}.web.telegram.org/apiw1`,
        {
          bodyBase64: bytes64(bytes),
          responseType: 'base64',
          headers: { 'Content-Type': 'application/octet-stream', Cookie: '' },
          timeout: 18000,
        },
      );
      if (!res.ok) throw new Error('HTTP');
      const body = from64(res.body);
      if (body.length === 4) {
        const code = Math.abs(new DataView(body.buffer).getInt32(0, true));
        this.fail(
          Park.error(
            code === 404
              ? 'LOGIN_REQUIRED'
              : code === 429
                ? 'BLOCKED'
                : 'NETWORK',
            code === 404
              ? '登录信息无效，请重新登录'
              : code === 429
                ? '请求过于频繁，请稍后重试'
                : '请求失败，请稍后重试',
          ),
        );
        return;
      }
      this.emit('message', body.buffer);
    } catch {
      this.fail(Park.error('NETWORK', '请求失败，请稍后重试'));
    }
  }
  fail(error) {
    this.isAvailable = false;
    this.onFailure(error);
  }
  close() {
    this.isAvailable = false;
    this.removeAllListeners();
  }
}
function stop() {
  if (client)
    for (const rpc of client.rpcs.values()) {
      rpc.sendAcks.cancel();
      rpc.transport.close();
    }
  client = null;
  peers.clear();
}
async function makeClient(source, session) {
  await seed();
  const binding = { source };
  const Client = makeMTProto({
    SHA1: async (bytes) =>
      Uint8Array.from(await Park.crypto.digestBytes('sha1', bytes)),
    SHA256: async (bytes) =>
      Uint8Array.from(await Park.crypto.digestBytes('sha256', bytes)),
    PBKDF2: () => {
      throw Park.error('UNSUPPORTED', '仅支持导入已有授权会话');
    },
    getRandomBytes: (length) => {
      if (entropyIndex + length > entropy.length)
        throw Park.error('CONFIG', '随机字节不足');
      const b = entropy.slice(entropyIndex, entropyIndex + length);
      entropyIndex += length;
      return b;
    },
    getLocalStorage: () => ({ get: async () => null, set: async () => {} }),
    createTransport: (dc) =>
      new Transport(dc, binding.source, (error) => {
        const r = binding.client?.rpcs.get(dc.id);
        if (!r) return;
        for (const waiting of r.messagesWaitAuth) waiting.reject(error);
        r.messagesWaitAuth = [];
        for (const waiting of r.messagesWaitResponse.values())
          waiting.reject(error);
        r.messagesWaitResponse.clear();
      }),
  });
  // 只恢复 Telegram WebK 的已有会话身份；不用于注册或发起第三方新登录。
  const c = new Client({ api_id: session.apiId || 2496, api_hash: '' });
  c.binding = binding;
  c.authorizedDcs = new Set(Object.keys(session.keys).map(Number));
  binding.client = c;
  c.updateInitConnectionParams({
    device_model: 'HentaiPark subscription',
    system_version: '1.0',
    app_version: '1.0',
  });
  await c.setDefaultDc(session.dc);
  for (const [dc, key] of Object.entries(session.keys)) {
    await c.storage.set(
      dc + 'authKey',
      Array.from(Uint8Array.from(key.match(/../g), (x) => parseInt(x, 16))),
    );
    await c.storage.set(dc + 'serverSalt', Array(8).fill(0));
  }
  return c;
}
function sessionValue(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = Object.fromEntries(
      [
        ...String(text).matchAll(
          /(dc\d+_auth_key|dc)\s*[:=]\s*["']?([a-fA-F0-9]+)/g,
        ),
      ].map((m) => [m[1], m[2]]),
    );
  }
  if (!data || typeof data !== 'object')
    throw Park.error('CONFIG', '授权会话格式无效');
  const dc = Number(data.dc),
    keys = {};
  for (let i = 1; i <= 5; i++) {
    let v = data['dc' + i + '_auth_key'];
    if (typeof v === 'string') {
      v = v.replace(/^["']|["']$/g, '');
      if (!/^[a-fA-F0-9]{512}$/.test(v))
        throw Park.error('CONFIG', '授权会话格式无效');
      keys[i] = v;
    }
  }
  if (![1, 2, 3, 4, 5].includes(dc) || !keys[dc])
    throw Park.error('CONFIG', '授权会话格式无效');
  return { dc, keys };
}
function rpc(source, method, params, options) {
  const pending = rpcQueue
    .catch(() => {})
    .then(() => executeRpc(source, method, params, options));
  rpcQueue = pending;
  return pending;
}
async function executeRpc(source, method, params, options) {
  await seed();
  if (!client) {
    const session = source.store.get('session');
    if (!session)
      throw Park.error('LOGIN_REQUIRED', '匿名访问受限，请登录后重试');
    client = await makeClient(source, session);
  }
  client.binding.source = source;
  if (options?.dcId && !client.authorizedDcs.has(options.dcId))
    throw Park.error('UNSUPPORTED', '该媒体暂不支持，请在原站打开');
  // 每次调用绑定自己的 invocation，禁止复用登录时已结束的取消令牌。
  for (const r of client.rpcs.values()) {
    r.transport.source = source;
    r.sendAcks.cancel();
  }
  let timer;
  try {
    return await Promise.race([
      client.call(method, params, options),
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(Park.error('NETWORK', '请求超时，请稍后重试')),
          23000,
        );
      }),
    ]);
  } catch (e) {
    const code = String(e.error_message || '');
    if (
      e.code === 'LOGIN_REQUIRED' ||
      /AUTH_KEY|SESSION_REVOKED|USER_DEACTIVATED/.test(code)
    ) {
      stop();
      source.store.set('account', null);
      throw Park.error('LOGIN_REQUIRED', '登录信息无效，请重新登录');
    }
    if (/FLOOD_WAIT/.test(code))
      throw Park.error('BLOCKED', '请求过于频繁，请稍后重试');
    if (/FILE_REFERENCE/.test(code))
      throw Park.error('FILE_REFERENCE', '媒体引用已过期');
    if (/CHANNEL_PRIVATE|CHAT_ADMIN_REQUIRED|USER_NOT_PARTICIPANT/.test(code))
      throw Park.error('BLOCKED', '访问受限，请在原站检查权限或手动关注、加入');
    if (e.code) {
      if (e.code === 'NETWORK') stop();
      throw e;
    }
    throw Park.error('NETWORK', '请求失败，请稍后重试');
  } finally {
    clearTimeout(timer);
    if (client) for (const r of client.rpcs.values()) r.sendAcks.cancel();
  }
}
function addPeer(ch) {
  if (ch._ !== 'channel' || !ch.access_hash) return;
  const p = {
    _: 'inputPeerChannel',
    channel_id: ch.id,
    access_hash: ch.access_hash,
  };
  peers.set('channel:' + ch.id, p);
  if (ch.username) peers.set(ch.username.toLowerCase(), p);
}
async function joined(source) {
  const d = await rpc(source, 'messages.getDialogs', {
    offset_date: 0,
    offset_id: 0,
    offset_peer: { _: 'inputPeerEmpty' },
    limit: 100,
    hash: '0',
  });
  for (const ch of d.chats || []) addPeer(ch);
  return (d.chats || [])
    .filter((ch) => ch._ === 'channel' && ch.access_hash)
    .map((ch) => ({
      id: ch.username ? ch.username.toLowerCase() : 'channel:' + ch.id,
      label: ch.title || ch.username || String(ch.id),
    }));
}
async function peer(source, id) {
  if (peers.has(id)) return peers.get(id);
  await joined(source);
  if (peers.has(id)) return peers.get(id);
  if (id.startsWith('channel:'))
    throw Park.error('BLOCKED', '访问受限，请在原站检查权限或手动关注、加入');
  const d = await rpc(source, 'contacts.resolveUsername', { username: id });
  for (const ch of d.chats || []) addPeer(ch);
  if (!peers.has(id)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
  return peers.get(id);
}
function mediaPost(m, p, target) {
  const media = [];
  const photo = m.media?.photo,
    doc = m.media?.document;
  if (photo) {
    const size = [...(photo.sizes || [])]
      .reverse()
      .find((s) => ['photoSize', 'photoSizeProgressive'].includes(s._));
    if (size) {
      const length = size.size || (size.sizes || []).at(-1);
      media.push({
        type: 'image',
        resource: {
          cacheKey: 'photo:' + photo.dc_id + ':' + photo.id + ':' + size.type,
          dc: photo.dc_id,
          size: Number(length),
          peer: p,
          messageId: m.id,
          location: {
            _: 'inputPhotoFileLocation',
            id: photo.id,
            access_hash: photo.access_hash,
            file_reference: Array.from(photo.file_reference),
            thumb_size: size.type,
          },
        },
      });
    }
  }
  if (doc && /^(video|image)\//.test(doc.mime_type || '')) {
    media.push({
      type: doc.mime_type.startsWith('video/') ? 'video' : 'image',
      resource: {
        cacheKey: 'document:' + doc.dc_id + ':' + doc.id,
        dc: doc.dc_id,
        size: Number(doc.size),
        peer: p,
        messageId: m.id,
        location: {
          _: 'inputDocumentFileLocation',
          id: doc.id,
          access_hash: doc.access_hash,
          file_reference: Array.from(doc.file_reference),
          thumb_size: '',
        },
      },
    });
  }
  if (!media.length) return null;
  for (const item of media) {
    item.id = String(m.id);
    item.order = m.id;
    const object = photo || doc;
    const sizes = photo?.sizes || doc?.thumbs || [];
    const thumb = sizes.filter(s => s._ === 'photoSize' && s.size > 0 && s.size <= 2097152)
      .sort((a,b) => Math.abs((a.w || 0) - 320) - Math.abs((b.w || 0) - 320))[0];
    if (thumb) item.previewResource = {
      ...item.resource,
      cacheKey: (photo ? 'photo:' : 'document:') + object.dc_id + ':' + object.id + ':' + thumb.type,
      size: thumb.size,
      location: {...item.resource.location, thumb_size: thumb.type},
    };
  }
  return {
    id: m.grouped_id ? 'group:' + m.grouped_id : String(m.id),
    presentation: 'post',
    title: target.label,
    text: m.message || '',
    date: new Date(m.date * 1000).toISOString(),
    url: target.id.startsWith('channel:')
      ? `https://t.me/c/${target.id.slice(8)}/${m.id}`
      : HOME + '/' + target.id + '/' + m.id,
    media,
  };
}
async function publicPosts(source, target, options) {
  if (target.id.startsWith('channel:'))
    throw Park.error('LOGIN_REQUIRED', '匿名访问受限，请登录后重试');
  const r = await source.http.get(HOME + '/s/' + target.id, {
    params: options?.cursor ? { before: options.cursor } : undefined,
    headers: { Cookie: '' },
  });
  if (!r.ok) throw Park.error('LOGIN_REQUIRED', '匿名访问受限，请登录后重试');
  const doc = Park.html.parse(r.body);
  if (!doc.querySelector('.tgme_channel_history'))
    throw Park.error('LOGIN_REQUIRED', '匿名访问受限，请登录后重试');
  const items = [];
  let before;
  for (const n of doc.querySelectorAll('[data-post]')) {
    const ref = n.getAttribute('data-post') || '';
    if (!ref.startsWith(target.id + '/')) continue;
    const id = ref.split('/')[1];
    if (!/^\d+$/.test(id)) continue;
    before = Math.min(before || Number(id), Number(id));
    const media = [];
    const background = node => /background-image:\s*url\(['"]?([^'"\)]+)['"]?\)/.exec(node?.getAttribute('style') || '')?.[1] || '';
    for (const node of n.querySelectorAll('.tgme_widget_message_photo_wrap, video[src]')) {
      const video = node.tagName.toLowerCase() === 'video';
      const url = video ? node.getAttribute('src') : background(node);
      if (!url) continue;
      const preview = video ? node.getAttribute('poster') || background(node.closest('.tgme_widget_message_video_wrap')?.querySelector('.tgme_widget_message_video_thumb')) : url;
      media.push({id: String(media.length), type: video ? 'video' : 'image', url, preview});
    }
    if (media.length)
      items.push({
        id,
        presentation: 'post',
        title: target.label,
        text: n.querySelector('.tgme_widget_message_text')?.textContent || '',
        date: n.querySelector('time')?.getAttribute('datetime') || '',
        url: HOME + '/' + ref,
        media,
      });
  }
  return {
    items,
    cursor: before ? String(before) : null,
    hasNext:
      !!doc.querySelector('a.tme_messages_more') &&
      !!before &&
      String(before) !== options?.cursor,
  };
}
Park.register({
  key: 'telegram',
  name: 'Telegram',
  version: '0.0.6', minAppVersion: '0.9.2',
  type: 'video',
  category: 'other',
  homepage: HOME,
  domains: ['t.me', 'telegram.me', 'web.telegram.org', 'telesco.pe'],
  network: { vpnHint: true },
  description: '频道订阅，公开预览与授权会话只读访问',
  idExample: 'telegram',
  account: {
    type: 'session',
    title: '导入授权会话',
    hint: '导入 Telegram WebK 本地存储（dc、dcN_auth_key）。这不是 Cookie；仅恢复已有会话，不会自动加入频道。',
    fields: [{ key: 'session', label: '授权会话', secret: true }],
    async login(values) {
      const session = sessionValue(values.session);
      stop();
      try {
        client = await makeClient(this, session);
        const u = await rpc(this, 'users.getUsers', {
          id: [{ _: 'inputUserSelf' }],
        });
        if (!u[0]?.self)
          throw Park.error('LOGIN_REQUIRED', '登录信息无效，请重新登录');
        const name = u[0].username || u[0].first_name || 'Telegram';
        this.store.set('session', session);
        this.store.set('account', { name });
        return { name };
      } catch (e) {
        stop();
        throw e;
      }
    },
    logout() {
      stop();
      this.store.set('session', null);
      this.store.set('account', null);
    },
    status() {
      const a = this.store.get('account');
      return { loggedIn: !!a, name: a?.name || '' };
    },
  },
  subscription: {
    async media(scope, options = {}) {
      const result = await this.subscription.posts.call(this, scope.target, options);
      const groups = new Map();
      for (const post of result.items) {
        const previous = groups.get(post.id);
        if (previous) {
          previous.media.push(...post.media);
          if (!previous.text) previous.text = post.text;
          if (post.date < previous.date) { previous.date = post.date; previous.url = post.url; }
        } else groups.set(post.id, {...post, media: [...post.media]});
      }
      for (const post of groups.values()) {
        if (post.media.every(m => Number.isFinite(m.order))) post.media.sort((a,b) => a.order-b.order);
      }
      return {...result, items: [...groups.values()]};
    },
    hint: '可先订阅；匿名访问可能受限。需要加入频道时请到原站手动操作。',
    normalize,
    async targets() {
      return joined(this);
    },
    async resolve(input) {
      const target = normalize(input);
      if (this.store.get('account')) await peer(this, target.id);
      return target;
    },
    async posts(input, options) {
      const target = normalize(input);
      if (!this.store.get('account')) return publicPosts(this, target, options);
      const p = await peer(this, target.id);
      const h = await rpc(this, 'messages.getHistory', {
        peer: p,
        offset_id: Number(options?.cursor) || 0,
        offset_date: 0,
        add_offset: 0,
        limit: 20,
        max_id: 0,
        min_id: 0,
        hash: '0',
      });
      const messages = (h.messages || []).filter((m) => m._ === 'message');
      const cursor = messages.length
        ? String(Math.min(...messages.map((m) => m.id)))
        : null;
      return {
        items: messages.map((m) => mediaPost(m, p, target)).filter(Boolean),
        cursor,
        hasNext:
          !!cursor && cursor !== options?.cursor && messages.length >= 20,
      };
    },
    async mediaChunk(resource, offset) {
      if (
        !resource ||
        !dcNames[resource.dc] ||
        !['inputPhotoFileLocation', 'inputDocumentFileLocation'].includes(
          resource.location?._,
        ) ||
        !Number.isSafeInteger(offset) ||
        offset < 0 ||
        offset % 131072
      )
        throw Park.error('CONFIG', '媒体参数无效');
      let location = {
        ...resource.location,
        file_reference: Uint8Array.from(resource.location.file_reference),
      };
      let file;
      try {
        file = await rpc(
          this,
          'upload.getFile',
          { location, offset: String(offset), limit: 131072 },
          { dcId: resource.dc },
        );
      } catch (e) {
        if (e.code !== 'FILE_REFERENCE') throw e;
        const data = await rpc(this, 'channels.getMessages', {
          channel: {
            _: 'inputChannel',
            channel_id: resource.peer.channel_id,
            access_hash: resource.peer.access_hash,
          },
          id: [{ _: 'inputMessageID', id: resource.messageId }],
        });
        const p = data.messages?.[0]?.media;
        const fresh =
          location._ === 'inputPhotoFileLocation' ? p?.photo : p?.document;
        if (!fresh || String(fresh.id) !== String(location.id))
          throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        location = {
          ...location,
          file_reference: Uint8Array.from(fresh.file_reference),
        };
        file = await rpc(
          this,
          'upload.getFile',
          { location, offset: String(offset), limit: 131072 },
          { dcId: resource.dc },
        );
      }
      if (file._ !== 'upload.file')
        throw Park.error('UNSUPPORTED', '该媒体暂不支持，请在原站打开');
      return { base64: bytes64(file.bytes), done: file.bytes.length < 131072 };
    },
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"posts","label":"频道或博主","hint":"用户名、频道名或主页链接"}]});
