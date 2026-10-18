// Data contracts shared between the JS source runtime and the UI.
// Everything crossing the bridge is plain JSON; these classes are thin typed views over it.

import 'dart:ui' show Color;

import 'localization.dart';
import 'plugin_copy.dart';

export 'plugin_copy.dart' show PluginCopy;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];
List<String> _strings(Object? v) => v is List
    ? v.where((e) => e != null).map((e) => e.toString()).toList()
    : const [];
String _str(Object? v) => v == null ? '' : v.toString();
int? _int(Object? v) => v is num ? v.toInt() : int.tryParse(_str(v));
double? _double(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(_str(v));

Color parseHexColor(String hex, [Color fallback = const Color(0xFF7C4DFF)]) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}

enum MediaKind {
  comic,
  video,
  novel,
  game;

  static MediaKind fromJson(Object? value) =>
      values.firstWhere((kind) => kind.name == value, orElse: () => comic);
}

extension MediaKindLabel on MediaKind {
  String get label => tr(switch (this) {
    MediaKind.comic => '漫画',
    MediaKind.video => '视频',
    MediaKind.novel => '小说',
    MediaKind.game => '游戏',
  });
}

/// Content grouping for browsing; media kind still controls reading and playback.
enum SourceCategory {
  doujin('本子'),
  anime('里番'),
  aiDrama('AI短剧'),
  jav('JAV'),
  adult('成人视频'),
  shortvideo('短视频'),
  gallery('美图'),
  novel('小说'),
  game('游戏'),
  other('其他');

  const SourceCategory(this._label);
  final String _label;
  String get label => tr(_label);

  static SourceCategory fromJson(Object? value) => SourceCategory.values
      .firstWhere((category) => category.name == value, orElse: () => other);
}

/// 反搜用途独立于作品分类，不影响发现页入口或阅读行为。
enum ReverseSearchCategory {
  general('通用'),
  anime('里番'),
  jav('JAV'),
  gallery('美图');

  const ReverseSearchCategory(this._label);
  final String _label;
  String get label => tr(_label);

  static ReverseSearchCategory fromJson(Object? value) => values.firstWhere(
    (category) => category.name == value,
    orElse: () => general,
  );
}

/// One selectable value of a feed option, search filter or setting.
class Choice {
  Choice(this.value, String label, {this.color, PluginCopy? copy})
    : _label = label,
      _copy = copy ?? PluginCopy.none;
  final Object? value;
  final String _label;
  final PluginCopy _copy;
  String get label => _copy.text(_label);
  final String? color;

  factory Choice.fromJson(Object? json, [PluginCopy? copy]) {
    if (json is Map) {
      return Choice(
        json['value'],
        _str(json['label'] ?? json['value']),
        color: json['color']?.toString(),
        copy: copy,
      );
    }
    return Choice(json, _str(json), copy: copy);
  }
}

/// A feed option, search filter or setting definition. `type` is select | multi | number | text | password | switch.
class OptionDef {
  OptionDef({
    required this.key,
    required this._label,
    required this.type,
    required this.values,
    this.defaultValue,
    this.dynamicValues = false,
    this._description = '',
    PluginCopy? copy,
  }) : _copy = copy ?? PluginCopy.none;
  final String key;
  final String _label;
  final PluginCopy _copy;
  String get label => _copy.text(_label);
  final String type;
  final List<Choice> values;
  final Object? defaultValue;
  final bool dynamicValues;
  final String _description;
  String get description => _copy.text(_description);

  factory OptionDef.fromJson(Map<String, dynamic> j, [PluginCopy? copy]) {
    final values = (j['values'] ?? j['options']) as List? ?? const [];
    return OptionDef(
      key: _str(j['key']),
      label: _str(j['label']),
      type: _str(j['type']).isEmpty
          ? (values.isEmpty && j['dynamic'] != true ? 'text' : 'select')
          : _str(j['type']),
      values: values
          .map(
            (v) => Choice.fromJson(
              v,
              j['dynamic'] == true ? PluginCopy.none : copy,
            ),
          )
          .toList(),
      dynamicValues: j['dynamic'] == true,
      defaultValue: j['default'],
      description: _str(j['description']),
      copy: copy,
    );
  }

  String labelOf(Object? value) {
    for (final c in values) {
      if (c.value == value) return c.label;
    }
    return _str(value);
  }
}

class FeedDef {
  FeedDef({
    required this.key,
    required this._label,
    required this.options,
    PluginCopy? copy,
  }) : _copy = copy ?? PluginCopy.none;
  final String key;
  final String _label;
  final PluginCopy _copy;
  String get label => _copy.text(_label);
  final List<OptionDef> options;

  factory FeedDef.fromJson(Map<String, dynamic> j, [PluginCopy? copy]) =>
      FeedDef(
        key: _str(j['key']),
        label: _str(j['label']),
        options: _maps(j['options'])
            .map((o) => OptionDef.fromJson(o, copy))
            .toList(),
        copy: copy,
      );

  Map<String, Object?> defaultOptions() => {
    for (final o in options) o.key: o.defaultValue,
  };
}

/// 榜单声明不改变源的媒体类型；一个商业站可同时提供 JAV 和动画榜。
class RankingDef {
  RankingDef.fromJson(Map<String, dynamic> json, PluginCopy copy)
    : key = _str(json['key']),
      _label = _str(json['label']),
      _metric = _str(json['metric']),
      category = SourceCategory.fromJson(json['category']),
      feed = _str(json['feed']),
      kind = _str(json['kind']).isEmpty ? 'work' : _str(json['kind']),
      section = _str(json['section']),
      options = _maps(json['options'])
          .map((value) => OptionDef.fromJson(value, copy))
          .toList(),
      _copy = copy;

  final String key;
  final String _label;
  final String _metric;
  final PluginCopy _copy;
  final SourceCategory category;
  final String feed;
  final String kind;
  final String section;
  final List<OptionDef> options;
  String get label => _copy.text(_label);
  String get metric => _copy.text(_metric);
  bool get opensWork => feed.isNotEmpty && kind == 'work';
  Map<String, Object?> defaultOptions() => {
    for (final option in options) option.key: option.defaultValue,
  };
}

/// 人物榜条目不会进入作品详情、收藏或阅读链路。
class RankingEntry {
  RankingEntry(this.json, this.source);
  final Map<String, dynamic> json;
  final String source;
  String get id => _str(json['id']);
  String get kind => _str(json['kind']).isEmpty ? 'work' : _str(json['kind']);
  String get uid => '$source:$kind:$id';
  String get title => _str(json['title']);
  String get subtitle => _str(json['subtitle']);
  String get cover => _str(json['cover']);
  WorkItem? get work => kind == 'work' ? WorkItem(json, source) : null;
}

class RankingPage {
  RankingPage({
    required this.items,
    required this.page,
    this.hasNext = false,
    this.cursor,
  });
  final List<RankingEntry> items;
  final int page;
  final bool hasNext;
  final String? cursor;
  factory RankingPage.fromJson(Map<String, dynamic> json, String source) =>
      RankingPage(
        items: _maps(json['items'])
            .map((row) => RankingEntry(row, source))
            .toList(),
        page: _int(json['page']) ?? 1,
        hasNext: json['hasNext'] == true,
        cursor: json['cursor']?.toString(),
      );
}

class AccountDef {
  AccountDef({
    required this.type,
    required this._title,
    required this._hint,
    required this.fields,
    required this.loginUrl,
    required this.cookieUrl,
    required this.requiredCookies,
    required this.required,
    this.managedAccount = false,
    this.loginDomains = const [],
    PluginCopy? copy,
  }) : _copy = copy ?? PluginCopy.none;
  final String type; // password | cookies | session
  final String _title;
  final String _hint;
  final PluginCopy _copy;
  String get title => _copy.text(_title);
  String get hint => _copy.text(_hint);

  /// Translates a field label or hint the plugin declared.
  String text(String value) => _copy.text(value);
  final List<Map<String, dynamic>> fields;
  final String loginUrl;

  /// 仅放行第三方授权导航，不授予 Cookie 访问权限。
  final List<String> loginDomains;
  final String cookieUrl;
  final List<String> requiredCookies;
  final bool required;
  final bool managedAccount;

  static AccountDef? fromJson(Object? json, [PluginCopy? copy]) {
    if (json is! Map) return null;
    final j = json.cast<String, dynamic>();
    return AccountDef(
      type: _str(j['type']),
      title: _str(j['title']),
      hint: _str(j['hint']),
      fields: _maps(j['fields']),
      loginUrl: _str(j['loginUrl']),
      loginDomains: _strings(j['loginDomains']),
      cookieUrl: _str(j['cookieUrl']),
      requiredCookies: _strings(j['requiredCookies']),
      required: j['required'] == true,
      managedAccount: j['managedAccount'] == true,
      copy: copy,
    );
  }
}

class SourceManifest {
  SourceManifest(Map<String, dynamic> json)
    : this._(json, PluginCopy(json['i18n']));

  SourceManifest._(this.json, this.copy)
    : key = _str(json['key']),
      _name = _str(json['name']),
      version = _str(json['version']),
      kind = MediaKind.values.firstWhere(
        (kind) => kind.name == json['type'],
        orElse: () => MediaKind.comic,
      ),
      category = SourceCategory.fromJson(json['category']),
      color = parseHexColor(_str(json['color'])),
      icon = _str(json['icon']),
      _description = _str(json['description']),
      homepage = _str(json['homepage']),
      language = _str(json['language']),
      linkPatterns = _strings(json['linkPatterns'])
          .map((p) => RegExp(p))
          .toList(),
      idPattern = _str(json['idPattern']).isEmpty
          ? null
          : RegExp(_str(json['idPattern'])),
      idExample = _str(json['idExample']),
      imageHeaders = _map(json['imageHeaders'])
          .map((k, v) => MapEntry(k, v.toString())),
      network = _map(json['network']),
      media = _map(json['media']),
      settings = _maps(json['settings'])
          .map((o) => OptionDef.fromJson(o, copy))
          .toList(),
      account = AccountDef.fromJson(json['account'], copy),
      feeds = _maps(json['feeds'])
          .map((f) => FeedDef.fromJson(f, copy))
          .toList(),
      rankings = _maps(json['rankings'])
          .map((f) => RankingDef.fromJson(f, copy))
          .toList(),
      defaultFeed = _str(json['defaultFeed']),
      anonymousDefaultFeed = _str(json['anonymousDefaultFeed']),
      searchFilters = _maps(json['searchFilters'])
          .map((o) => OptionDef.fromJson(o, copy))
          .toList(),
      _searchHint = _str(json['searchHint']),
      capabilities = _map(json['capabilities']);

  final Map<String, dynamic> json;

  /// The plugin's own translations; see [PluginCopy].
  final PluginCopy copy;
  final String key;
  final String _name;
  String get name => copy.text(_name);
  final String version;
  final MediaKind kind;
  final SourceCategory category;
  final Color color;
  final String icon;
  final String _description;
  String get description => copy.text(_description);
  final String homepage;
  final String language;
  final List<RegExp> linkPatterns;
  final RegExp? idPattern;
  final String idExample;
  final Map<String, String> imageHeaders;
  final Map<String, dynamic> network;
  final Map<String, dynamic> media;
  final List<OptionDef> settings;
  final AccountDef? account;
  final List<FeedDef> feeds;
  final List<RankingDef> rankings;
  bool get rankingOnly => json['rankingOnly'] == true;
  bool get reverseSearchOnly =>
      can('reverseSearch') && feeds.isEmpty && !can('search');
  ReverseSearchCategory get reverseSearchCategory =>
      ReverseSearchCategory.fromJson(json['reverseSearchCategory']);

  /// Key of the feed the source page opens on (manifest `defaultFeed`).
  final String defaultFeed;
  final String anonymousDefaultFeed;

  int entryFeedIndex({required bool loggedIn}) {
    if (!loggedIn && anonymousDefaultFeed.isNotEmpty) {
      final index = feeds.indexWhere(
        (feed) => feed.key == anonymousDefaultFeed,
      );
      if (index >= 0) return index;
    }
    return defaultFeedIndex;
  }

  /// The feed to open first: the manifest's `defaultFeed`, otherwise recommended > ranking > popular.
  int get defaultFeedIndex {
    if (defaultFeed.isNotEmpty) {
      final i = feeds.indexWhere((f) => f.key == defaultFeed);
      if (i >= 0) return i;
    }
    for (final keys in const [
      ['promote', 'recommend', 'featured'],
      ['rank', 'toplist'],
      ['popular', 'hot', 'trending'],
    ]) {
      final i = feeds.indexWhere(
        (f) => keys.any((k) => f.key.toLowerCase().contains(k)),
      );
      if (i >= 0) return i;
    }
    return 0;
  }

  final List<OptionDef> searchFilters;
  final String _searchHint;
  String get searchHint => copy.text(_searchHint);
  final Map<String, dynamic> capabilities;

  bool can(String capability) => capabilities[capability] == true;
  bool get isVideo => kind == MediaKind.video;

  /// 聚合视频索引不提供媒体时，作品通过系统浏览器打开。
  bool get opensExternally => isVideo && !can('videos') && !can('webVideo');
  bool get usesWebVideo => isVideo && !can('videos') && can('webVideo');
  bool get isNovel => kind == MediaKind.novel;
  bool get isGame => kind == MediaKind.game;
  bool get usesBrowserNetwork => network['mode'] == 'browser';
  String get origin =>
      _str(network['origin']).isNotEmpty ? _str(network['origin']) : homepage;

  Map<String, Object?> defaultFilters() => {
    for (final f in searchFilters) f.key: f.defaultValue,
  };

  /// Extracts work ids from free text (links or explicit ids).
  List<String> extractIds(String text) {
    final found = <(int, String)>[];
    for (final p in linkPatterns) {
      for (final m in p.allMatches(text)) {
        final id = m.groupCount >= 1 ? m.group(1) : m.group(0);
        if (id != null) found.add((m.start, id));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return {for (final f in found) f.$2}.toList();
  }

  String? matchExplicitId(String text) {
    final m = idPattern?.firstMatch(text.trim());
    if (m == null) return null;
    if (m.groupCount >= 2 && m.group(2) != null) {
      return '${m.group(1)}/${m.group(2)}';
    }
    return m.groupCount >= 1 ? m.group(1) : m.group(0);
  }
}

class WorkItem {
  WorkItem(this.json, this.source)
    : id = _str(json['id']),
      title = _str(json['title']),
      subtitle = _str(json['subtitle']),
      cover = _str(json['cover']),
      coverAspect = _double(json['coverAspect']),
      pages = _int(json['pages']),
      rating = _double(json['rating']),
      likes = _int(json['likes']),
      views = _int(json['views']),
      language = _str(json['language']),
      category = _str(json['category']),
      badge = _str(json['badge']),
      badgeColor = _str(json['badgeColor']),
      duration = _str(json['duration']),
      uploaded = _str(json['uploaded']),
      authors = [..._strings(json['authors'])],
      tags = _strings(json['tags']),
      workCode = _str(json['workCode']),
      editions = _strings(json['editions']),
      mediaKind = MediaKind.values
          .where((kind) => kind.name == json['mediaKind'])
          .firstOrNull;

  final Map<String, dynamic> json;
  final String source;

  /// The kind declared on the item itself (sources that mix kinds); null means the source's.
  final MediaKind? mediaKind;
  bool get isNovel => mediaKind == MediaKind.novel;
  bool get isGame => mediaKind == MediaKind.game;

  /// Update-subscription posts carry their media instead of having a detail page.
  bool get isSubscriptionPost => json['media'] is List;
  final String id;
  final String title;
  final String subtitle;
  final String cover;
  final double? coverAspect;
  final int? pages;
  final double? rating;
  final int? likes;
  final int? views;
  final String language;
  final String category;
  final String badge;
  final String badgeColor;
  final String duration;
  final String uploaded;

  /// 源提供的作者，以及浏览时从详情补充的真实作者。
  final List<String> authors;
  final List<String> tags;

  /// A source-declared work identity for searching; never replaces the source ID.
  final String workCode;
  final List<String> editions;

  String get uid => '$source:$id';

  Map<String, dynamic> toJson() => {
    ...json,
    if (authors.isNotEmpty) 'authors': authors,
    'id': id,
    'source': source,
  };

  factory WorkItem.fromStored(Map<String, dynamic> j) =>
      WorkItem(j, _str(j['source']));
}

class WorkPage {
  WorkPage({
    required this.items,
    required this.page,
    this.totalPages,
    this.hasNext = false,
    this.cursor,
    this.total,
    this.sections,
    this.staleCache = false,
  });
  final List<WorkItem> items;
  final int page;
  final int? totalPages;
  final bool hasNext;
  final String? cursor;
  final int? total;
  final List<WorkSection>? sections;
  final bool staleCache;

  factory WorkPage.fromJson(Map<String, dynamic> j, String source) => WorkPage(
    items: _maps(j['items']).map((e) => WorkItem(e, source)).toList(),
    page: _int(j['page']) ?? 1,
    totalPages: _int(j['totalPages']),
    hasNext: j['hasNext'] == true,
    cursor: j['cursor']?.toString(),
    total: _int(j['total']),
    staleCache: j['_staleCache'] == true,
    sections: j['sections'] is List
        ? _maps(j['sections'])
              .map(
                (s) => WorkSection(
                  _str(s['title']),
                  _maps(s['items']).map((e) => WorkItem(e, source)).toList(),
                ),
              )
              .toList()
        : null,
  );
}

class WorkSection {
  WorkSection(this.title, this.items);
  final String title;
  final List<WorkItem> items;
}

class TagRef {
  TagRef(this.name, this.keyword, this.filters, this.count);
  final String name;
  final String keyword;
  final Map<String, dynamic> filters;
  final int? count;
}

class TagGroup {
  TagGroup(this.namespace, this.label, this.tags);
  final String namespace;
  final String label;
  final List<TagRef> tags;
}

class Chapter {
  Chapter(this.id, this.title);
  final String id;
  final String title;
}

/// Sprite-aware thumbnail (E-Hentai packs several thumbnails into one image).
class PreviewThumb {
  PreviewThumb(this.json)
    : url = _str(json['url']),
      index = _int(json['index']),
      width = _double(json['width']),
      height = _double(json['height']),
      offsetX = _double(json['offsetX']) ?? 0,
      offsetY = _double(json['offsetY']) ?? 0;
  final Map<String, dynamic> json;
  final String url;
  final int? index;
  final double? width;
  final double? height;
  final double offsetX;
  final double offsetY;
  bool get isSprite =>
      width != null &&
      height != null &&
      (offsetX != 0 || offsetY != 0 || json.containsKey('offsetX'));
}

class WorkDetail extends WorkItem {
  WorkDetail(super.json, super.source)
    : url = _str(json['url']),
      description = _str(json['description']),
      uploader = _str(json['uploader']),
      size = _str(json['size']),
      comments = _int(json['comments']),
      tagGroups = _maps(json['tags'])
          .map(
            (g) => TagGroup(
              _str(g['namespace']),
              _str(g['label']).isEmpty
                  ? _str(g['namespace'])
                  : _str(g['label']),
              _maps(g['tags'])
                  .map(
                    (t) => TagRef(
                      _str(t['name']),
                      _str(t['keyword']),
                      _map(t['filters']),
                      _int(t['count']),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      chapters = json['chapters'] is List
          ? _maps(json['chapters'])
                .map((c) => Chapter(_str(c['id']), _str(c['title'])))
                .toList()
          : null,
      singleChapterId = json['singleChapterId']?.toString(),
      related = _maps(json['related']).map((e) => WorkItem(e, source)).toList(),
      series = _maps(json['series']).map((e) => WorkItem(e, source)).toList(),
      variants = _maps(json['variants'])
          .where(
            (e) =>
                _str(e['id']).isNotEmpty && _str(e['id']) != _str(json['id']),
          )
          .map((e) => WorkItem(e, source))
          .toList(),
      thumbnails = (json['thumbnails'] as List? ?? const [])
          .map(
            (t) => t is Map
                ? PreviewThumb(t.cast<String, dynamic>())
                : PreviewThumb({'url': _str(t)}),
          )
          .where((t) => t.url.isNotEmpty)
          .toList(),
      thumbnailsTotal = _int(json['thumbnailsTotal']),
      authorSearch = json['authorSearch'] is Map
          ? _map(json['authorSearch'])
          : null;

  final String url;
  final String description;
  final String uploader;
  final String size;
  final int? comments;
  final List<TagGroup> tagGroups;
  final List<Chapter>? chapters;
  final String? singleChapterId;
  final List<WorkItem> related;
  final List<WorkItem> series;
  final List<WorkItem> variants;
  final List<PreviewThumb> thumbnails;
  final int? thumbnailsTotal;
  final Map<String, dynamic>? authorSearch;

  /// Offline and stored chapter subsets must not replace a complete source directory.
  bool get chaptersComplete => json['chaptersComplete'] != false;
  bool get hasVideoEpisodes => chapters?.isNotEmpty == true;

  /// The site lists the work as having chapters but returned none (nothing to open yet).
  bool get hasNoChapters => chapters != null && chapters!.isEmpty;

  /// The chapter to open: the one last read when it still exists, otherwise the first.
  /// Null for single-chapter works and when the chapter list is empty.
  Chapter? chapterToOpen([String? lastChapterId]) {
    final list = chapters;
    if (list == null || list.isEmpty) return null;
    return list.firstWhere(
      (c) => c.id == lastChapterId,
      orElse: () => list.first,
    );
  }

  /// Video episodes share the library's stable chapter identities.
  List<Chapter> get videoEpisodes => hasVideoEpisodes
      ? chapters!
      : [
          Chapter(
            singleChapterId?.isNotEmpty == true ? singleChapterId! : '_',
            tr('正片'),
          ),
        ];

  WorkItem toItem() => WorkItem.fromStored({
    ...toJson(),
    'source': source,
    'tags': tagGroups.expand((g) => g.tags.map((t) => t.name)).take(8).toList(),
  });
}

/// One page of a chapter. Either a direct [url] or a [token] resolved lazily through `resolveImage`.
class PageImage {
  PageImage(Map<String, dynamic> json)
    : url = _str(json['url']),
      token = json['token']?.toString(),
      fallbacks = _strings(json['fallbacks']),
      headers = _map(json['headers']).map((k, v) => MapEntry(k, v.toString())),
      width = _double(json['width']),
      height = _double(json['height']),
      transform = json['transform'] is Map ? _map(json['transform']) : null,
      cacheKey = json['cacheKey']?.toString();

  final String url;
  final String? token;
  final List<String> fallbacks;
  final Map<String, String> headers;
  final double? width;
  final double? height;
  final Map<String, dynamic>? transform;
  final String? cacheKey;

  bool get needsResolve => url.isEmpty;
  double? get aspect =>
      width != null && height != null && height! > 0 ? width! / height! : null;
}

class ChapterImages {
  ChapterImages(this.pages);
  final List<PageImage> pages;

  factory ChapterImages.fromJson(Map<String, dynamic> j) =>
      ChapterImages(_maps(j['pages']).map(PageImage.new).toList());
}

/// 小说正文只接受纯文本，段落顺序同时作为阅读位置与离线契约。
class TextChapter {
  TextChapter({required this.title, required List<String> paragraphs})
    : paragraphs = List.unmodifiable(paragraphs);
  final String title;
  final List<String> paragraphs;

  factory TextChapter.fromJson(Map<String, dynamic> json) {
    final raw = json['paragraphs'];
    if (raw is! List || raw.any((p) => p is! String)) {
      throw SourceError('PARSE', '小说正文格式无效');
    }
    final paragraphs = raw
        .cast<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) throw SourceError('PARSE', '小说正文为空或受限');
    return TextChapter(title: _str(json['title']), paragraphs: paragraphs);
  }

  Map<String, dynamic> toJson() => {'title': title, 'paragraphs': paragraphs};
}

enum GameChannelKind { direct, external }

class GameChannel {
  GameChannel.fromJson(Map<String, dynamic> json)
    : id = _str(json['id']),
      label = _str(json['label']),
      size = _str(json['size']),
      requiresReply = json['requiresReply'] == true,
      replyText = _str(json['replyText']),
      kind = json['kind'] == 'direct'
          ? GameChannelKind.direct
          : GameChannelKind.external;
  final String id, label, size, replyText;
  final bool requiresReply;
  final GameChannelKind kind;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'size': size,
    'requiresReply': requiresReply,
    if (requiresReply) 'replyText': replyText,
    'kind': kind.name,
  };
}

/// Stable resource metadata only. Resolved links never enter library snapshots.
class GameResource {
  GameResource.fromJson(Map<String, dynamic> json)
    : id = _str(json['id']),
      title = _str(json['title']),
      version = _str(json['version']),
      size = _str(json['size']),
      notes = _str(json['notes']),
      status = _str(json['status']),
      testStatus = _str(json['testStatus']),
      platforms = _strings(json['platforms']),
      languages = _strings(json['languages']),
      channels = _maps(json['channels']).map(GameChannel.fromJson).toList();
  final String id, title, version, size, notes, status, testStatus;
  final List<String> platforms, languages;
  final List<GameChannel> channels;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'version': version,
    'size': size,
    'notes': notes,
    'status': status,
    'testStatus': testStatus,
    'platforms': platforms,
    'languages': languages,
    'channels': channels.map((c) => c.toJson()).toList(),
  };
}

/// Ephemeral click result, deliberately has no persistence method.
class GameResourceLink {
  GameResourceLink.fromJson(Map<String, dynamic> json)
    : url = _str(json['url']),
      filename = _str(json['filename']),
      urls = json['urls'] is List
          ? _strings(json['urls'])
          : [_str(json['url'])],
      extractionCode = _str(json['extractionCode']),
      extractionCodes = _strings(json['extractionCodes']),
      archivePassword = _str(json['archivePassword']),
      kind = json['kind'] == 'direct'
          ? GameChannelKind.direct
          : GameChannelKind.external {
    if (urls.isEmpty || urls.first != url || urls.length > 100) {
      throw SourceError('PARSE', '游戏下载地址无效');
    }
    if (extractionCodes.isNotEmpty && extractionCodes.length != urls.length) {
      throw SourceError('PARSE', '游戏下载地址无效');
    }
    for (final value in urls) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !{
            'https',
            'http',
            'ftp',
            'ftps',
            'magnet',
            'ed2k',
            'thunder',
          }.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          ({'https', 'http', 'ftp', 'ftps'}.contains(uri.scheme) &&
              uri.host.isEmpty) ||
          (kind == GameChannelKind.direct && uri.scheme != 'https')) {
        throw SourceError('PARSE', '游戏下载地址无效');
      }
    }
  }
  final String url, filename, extractionCode, archivePassword;
  final List<String> urls, extractionCodes;
  final GameChannelKind kind;
}

class VideoSource {
  VideoSource(Map<String, dynamic> j)
    : quality = _int(j['quality']) ?? 0,
      _label = _str(j['label']).isEmpty
          ? '${_int(j['quality']) ?? ''}P'
          : _str(j['label']),
      url = _str(j['url']),
      headers = _map(j['headers']).map((k, v) => MapEntry(k, v.toString())),
      format = _str(j['format']),
      preferred = j['preferred'] == true;
  final int quality;
  final String _label;
  String get label => tr(_label);
  final String url;
  final Map<String, String> headers;
  final String format;
  final bool preferred;
}

class AccountStatus {
  AccountStatus(this.loggedIn, this.name, {this.configured = false});
  final bool loggedIn;
  final String name;
  final bool configured;
}

/// Error codes produced by sources (see park_runtime.js).
class SourceError implements Exception {
  SourceError(
    this.code,
    String message, {
    this.status,
    this.url,
    this.diagnostics = const <String, String>{},
    this.params = const {},
    PluginCopy? copy,
  }) : _message = message,
       _copy = copy ?? PluginCopy.none;

  final String code;
  final String _message;
  final PluginCopy _copy;
  String get rawMessage => _message;
  PluginCopy get copy => _copy;

  /// Plugin errors are translated with the plugin's own copy, then the app's.
  String get message => _copy.text(_message, params);

  /// The same error, translated with [copy] (the source that raised it).
  SourceError withCopy(PluginCopy copy) => SourceError(
    code,
    _message,
    status: status,
    url: url,
    diagnostics: diagnostics,
    params: params,
    copy: copy,
  );
  final int? status;
  final String? url;
  final Map<String, String> diagnostics;

  /// Values for the placeholders in the message template; the template is the translation key.
  final Map<String, Object?> params;

  bool get isCloudflare => code == 'CLOUDFLARE';
  bool get needsConfirmation => code == 'CONFIRM_REQUIRED';
  bool get needsLogin => code == 'LOGIN_REQUIRED';
  bool get isNetwork => code == 'NETWORK';

  factory SourceError.fromJson(Object? j) {
    final m = _map(j);
    return SourceError(
      _str(m['code']).isEmpty ? 'UNKNOWN' : _str(m['code']),
      _str(m['message']),
      status: _int(m['status']),
      url: m['url']?.toString(),
      diagnostics: _map(m['diagnostics'])
          .map((key, value) => MapEntry(key, value.toString())),
      params: _map(m['params']),
    );
  }

  String get friendly {
    switch (code) {
      case 'CLOUDFLARE':
        return tr('站点开启了人机验证，需要在内置浏览器中通过一次');
      case 'LOGIN_REQUIRED':
        return message.isEmpty ? tr('需要登录') : message;
      case 'NETWORK':
        return tr('网络连接失败，请检查网络或代理设置\n{error}', {'error': message});
      default:
        return message.isEmpty ? code : message;
    }
  }

  @override
  String toString() => '$code: $message';
}
