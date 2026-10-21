  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = __CATALOG_CONFIG__, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
    const values = new Map(), indexes = new Set(), origin = new URL(this.BASE).origin;
    const page = path => this[config.pageMethod || 'getPage']((config.absolute ? this.BASE : '') + path);
    const collect = doc => {
      for (const a of doc.querySelectorAll(config.selector || 'a[href]')) {
        let u;
        try { u = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
        if (u.origin !== origin || u.username || u.password || u.search || u.hash ||
            /%2f|%5c|%2e|%00/i.test(u.pathname)) continue;
        try { if (/[\x00-\x1f\x7f\\]/.test(decodeURIComponent(u.pathname))) continue; } catch (_) { continue; }
        const label = Park.html.text(a).replace(/\s+/g, ' ').trim();
        if (leaf.test(u.pathname) && label && label.length <= 256 && !values.has(u.pathname)) values.set(u.pathname, label);
        else if (index?.test(u.pathname)) indexes.add(u.pathname);
      }
    };
    collect((await page(config.home)).doc);
    for (const path of [...indexes].slice(0, 1)) collect((await page(path)).doc);
    if (!values.size || values.size > (config.ranges ? 10000 : 499)) throw Park.error('PARSE', '分类列表解析失败');
    const rows = [...values].map(([value, label]) => ({value, label}));
    this._categoryDirectory = {time: Date.now(), values: rows};
    return rows;
  },
  async filterOptions(request) {
    const config = __CATALOG_CONFIG__;
    const rows = await this.categoryDirectory();
    if (config.ranges && request.filter === 'range') {
      return Array.from({length: Math.ceil(rows.length / 200)}, (_, i) => ({
        value: String(i), label: (i * 200 + 1) + '–' + Math.min((i + 1) * 200, rows.length),
      }));
    }
    if (request.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
    let choices = rows;
    if (config.ranges) {
      const range = String(request.values?.range ?? '0');
      if (!/^(?:0|[1-9]\d{0,2})$/.test(range) || Number(range) * 200 >= rows.length) throw Park.error('CONFIG', '筛选参数无效');
      choices = rows.slice(Number(range) * 200, (Number(range) + 1) * 200);
    }
    return [{value: '', label: '全部'}, ...choices];
  },
  async categoryFeed(request) {
    const category = String(request.options?.category || '');
    if (!category) return this.feed(this.defaultFeed, request);
    const choices = await this.filterOptions({filter: 'category', values: request.options || {}});
    if (!choices.some(option => option.value === category)) {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    const config = __CATALOG_CONFIG__;
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
