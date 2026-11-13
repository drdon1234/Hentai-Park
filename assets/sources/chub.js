(function () {
  'use strict';
  const API = 'https://api.chub.ai';
  const GATEWAY = 'https://gateway.chub.ai';
  const SITE = 'https://chub.ai';
  const AVATARS = 'https://avatars.charhub.io';
  const pathPattern = /^[A-Za-z0-9._~-]{1,64}\/[A-Za-z0-9._~-]{1,160}$/;
  const kinds = new Set(['character', 'lorebook']);

  function identity(id) {
    const match = /^(character|lorebook):(.+)$/.exec(String(id || ''));
    if (!match || !pathPattern.test(match[2]) || match[2].split('/').some(x => x === '.' || x === '..')) {
      throw Park.error('NOT_FOUND', '内容不存在');
    }
    return {kind: match[1], path: match[2]};
  }
  function pathOf(node, kind) {
    const raw = String(node?.fullPath || '');
    const path = kind === 'lorebook' ? raw.replace(/^lorebooks\//, '') : raw;
    return pathPattern.test(path) && !path.split('/').some(x => x === '.' || x === '..') ? path : '';
  }
  function item(node, kind) {
    const path = pathOf(node, kind);
    if (!path || typeof node.name !== 'string' || !node.name.trim()) return null;
    return {
      id: kind + ':' + path,
      title: node.name,
      subtitle: typeof node.tagline === 'string' ? node.tagline : '',
      cover: kind === 'character' ? AVATARS + '/avatars/' + path + '/avatar.webp' : '',
      authors: [path.split('/')[0]],
      tags: Array.isArray(node.topics) ? node.topics.filter(x => typeof x === 'string') : [],
      mediaKind: 'tavern',
      tavernKind: kind,
    };
  }
  async function page(source, kind, keyword, number, sort) {
    if (!kinds.has(kind) || !Number.isInteger(number) || number < 1 || number > 1000) throw Park.error('CONFIG', '访问受限');
    const url = new URL('/search', GATEWAY);
    for (const [key, value] of Object.entries({
      search: String(keyword || '').slice(0, 200), namespace: kind === 'lorebook' ? 'lorebooks' : 'characters',
      first: '24', page: String(number), sort: sort === 'created_at' ? 'created_at' : 'default',
      asc: 'false', nsfw: 'true', nsfl: 'false', nsfw_only: 'false', include_forks: 'true', count: 'true',
    })) url.searchParams.set(key, value);
    const payload = await source.http.json(url.href);
    const data = payload && payload.data;
    if (!data || !Array.isArray(data.nodes)) throw Park.error('PARSE', '站点返回了无效结果');
    const items = data.nodes.map(node => item(node, kind)).filter(Boolean);
    const total = Number.isFinite(data.count) ? data.count : null;
    return {items, page: number, total, hasNext: items.length > 0 && (total == null ? items.length >= 24 : number * 24 < total)};
  }
  async function metadata(source, id) {
    const entry = identity(id);
    const path = entry.path.split('/').map(encodeURIComponent).join('/');
    const url = API + '/api/' + (entry.kind === 'lorebook' ? 'lorebooks/' : 'characters/') + path + '?full=true';
    const payload = await source.http.json(url);
    const node = payload && payload.node;
    if (!node || pathOf(node, entry.kind) !== entry.path) throw Park.error('PARSE', '站点返回了无效结果');
    return {entry, node};
  }
  function character(node) {
    const d = node.definition;
    if (!d || typeof d !== 'object' || typeof d.name !== 'string') throw Park.error('PARSE', '酒馆资源格式无效');
    return {spec: 'chara_card_v2', spec_version: '2.0', data: {
      name: d.name, description: d.personality || '', personality: d.tavern_personality || '',
      scenario: d.scenario || '', first_mes: d.first_message || '', mes_example: d.example_dialogs || '',
      creator_notes: d.description || '', system_prompt: d.system_prompt || '',
      post_history_instructions: d.post_history_instructions || '',
      alternate_greetings: Array.isArray(d.alternate_greetings) ? d.alternate_greetings : [],
      character_book: d.embedded_lorebook || null,
      extensions: {...(d.extensions && typeof d.extensions === 'object' ? d.extensions : {}), chub_original_definition: d},
      tags: Array.isArray(node.topics) ? node.topics : [],
      creator: String(node.fullPath || '').split('/')[0], character_version: '',
    }};
  }
  Park.register({
    key: 'chub', name: 'Chub AI', version: '0.0.2', minAppVersion: '0.14.0',
    type: 'tavern', category: 'tavern', color: '#9B5B78',
    description: '角色卡与世界书', homepage: SITE, domains: ['chub.ai', 'charhub.io'],
    network: {vpnHint: true},
    defaultFeed: 'characters',
    feeds: [{key: 'characters', label: '角色卡'}, {key: 'lorebooks', label: '世界书'}],
    searchFilters: [
      {key: 'kind', label: '类型', default: 'all', values: [{value: 'all', label: '全部'}, {value: 'character', label: '角色卡'}, {value: 'lorebook', label: '世界书'}]},
      {key: 'sort', label: '排序', default: 'default', values: [{value: 'default', label: '热门'}, {value: 'created_at', label: '最新'}]},
    ],
    async feed(key, {page: number = 1} = {}) {
      return page(this, key === 'lorebooks' ? 'lorebook' : 'character', '', number, 'default');
    },
    async search({keyword = '', page: number = 1, filters = {}} = {}) {
      if (filters.kind === 'character' || filters.kind === 'lorebook') {
        return page(this, filters.kind, keyword, number, filters.sort);
      }
      const [characters, books] = await Promise.all([
        page(this, 'character', keyword, number, filters.sort),
        page(this, 'lorebook', keyword, number, filters.sort),
      ]);
      const items = [];
      for (let i = 0; i < Math.max(characters.items.length, books.items.length); i++) {
        if (characters.items[i]) items.push(characters.items[i]);
        if (books.items[i]) items.push(books.items[i]);
      }
      const total = characters.total == null || books.total == null ? null : characters.total + books.total;
      return {items, page: number, total, hasNext: characters.hasNext || books.hasNext};
    },
    async detail(id) {
      const {entry, node} = await metadata(this, id);
      const base = item(node, entry.kind);
      if (!base) throw Park.error('PARSE', '站点返回了无效结果');
      return {...base, url: SITE + '/' + (entry.kind === 'lorebook' ? 'lorebooks/' : 'characters/') + entry.path,
        description: typeof node.description === 'string' ? node.description : ''};
    },
    async tavernAsset(id) {
      const {entry, node} = await metadata(this, id);
      if (entry.kind === 'character') return {kind: 'character', format: 'json', data: character(node)};
      if (!Number.isSafeInteger(node.id) || node.id < 1) throw Park.error('PARSE', '酒馆资源格式无效');
      const data = await this.http.json(API + '/api/v4/projects/' + node.id + '/repository/files/raw%252Fsillytavern_raw.json/raw');
      if (!data || typeof data !== 'object' || !data.entries) throw Park.error('PARSE', '酒馆资源格式无效');
      return {kind: 'lorebook', format: 'json', data};
    },
  });
})();
