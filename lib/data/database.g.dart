// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $WorksTable extends Works with TableInfo<$WorksTable, WorkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoritedAtMeta = const VerificationMeta(
    'favoritedAt',
  );
  @override
  late final GeneratedColumn<int> favoritedAt = GeneratedColumn<int>(
    'favorited_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUpdateCheckMeta = const VerificationMeta(
    'lastUpdateCheck',
  );
  @override
  late final GeneratedColumn<int> lastUpdateCheck = GeneratedColumn<int>(
    'last_update_check',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readerModeMeta = const VerificationMeta(
    'readerMode',
  );
  @override
  late final GeneratedColumn<int> readerMode = GeneratedColumn<int>(
    'reader_mode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _oneShotMeta = const VerificationMeta(
    'oneShot',
  );
  @override
  late final GeneratedColumn<bool> oneShot = GeneratedColumn<bool>(
    'one_shot',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("one_shot" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    id,
    title,
    cover,
    json,
    favorite,
    favoritedAt,
    lastUpdateCheck,
    readerMode,
    oneShot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'works';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('cover')) {
      context.handle(
        _coverMeta,
        cover.isAcceptableOrUnknown(data['cover']!, _coverMeta),
      );
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('favorited_at')) {
      context.handle(
        _favoritedAtMeta,
        favoritedAt.isAcceptableOrUnknown(
          data['favorited_at']!,
          _favoritedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_update_check')) {
      context.handle(
        _lastUpdateCheckMeta,
        lastUpdateCheck.isAcceptableOrUnknown(
          data['last_update_check']!,
          _lastUpdateCheckMeta,
        ),
      );
    }
    if (data.containsKey('reader_mode')) {
      context.handle(
        _readerModeMeta,
        readerMode.isAcceptableOrUnknown(data['reader_mode']!, _readerModeMeta),
      );
    }
    if (data.containsKey('one_shot')) {
      context.handle(
        _oneShotMeta,
        oneShot.isAcceptableOrUnknown(data['one_shot']!, _oneShotMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, id};
  @override
  WorkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      cover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      favoritedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorited_at'],
      ),
      lastUpdateCheck: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_update_check'],
      ),
      readerMode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reader_mode'],
      ),
      oneShot: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}one_shot'],
      )!,
    );
  }

  @override
  $WorksTable createAlias(String alias) {
    return $WorksTable(attachedDatabase, alias);
  }
}

class WorkRow extends DataClass implements Insertable<WorkRow> {
  final String source;
  final String id;
  final String title;
  final String cover;
  final String json;
  final bool favorite;
  final int? favoritedAt;
  final int? lastUpdateCheck;
  final int? readerMode;

  /// The site lists no chapters for this work (a single gallery), so library updates can skip it. Added in v2.
  final bool oneShot;
  const WorkRow({
    required this.source,
    required this.id,
    required this.title,
    required this.cover,
    required this.json,
    required this.favorite,
    this.favoritedAt,
    this.lastUpdateCheck,
    this.readerMode,
    required this.oneShot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['cover'] = Variable<String>(cover);
    map['json'] = Variable<String>(json);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || favoritedAt != null) {
      map['favorited_at'] = Variable<int>(favoritedAt);
    }
    if (!nullToAbsent || lastUpdateCheck != null) {
      map['last_update_check'] = Variable<int>(lastUpdateCheck);
    }
    if (!nullToAbsent || readerMode != null) {
      map['reader_mode'] = Variable<int>(readerMode);
    }
    map['one_shot'] = Variable<bool>(oneShot);
    return map;
  }

  WorksCompanion toCompanion(bool nullToAbsent) {
    return WorksCompanion(
      source: Value(source),
      id: Value(id),
      title: Value(title),
      cover: Value(cover),
      json: Value(json),
      favorite: Value(favorite),
      favoritedAt: favoritedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(favoritedAt),
      lastUpdateCheck: lastUpdateCheck == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdateCheck),
      readerMode: readerMode == null && nullToAbsent
          ? const Value.absent()
          : Value(readerMode),
      oneShot: Value(oneShot),
    );
  }

  factory WorkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkRow(
      source: serializer.fromJson<String>(json['source']),
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      cover: serializer.fromJson<String>(json['cover']),
      json: serializer.fromJson<String>(json['json']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      favoritedAt: serializer.fromJson<int?>(json['favoritedAt']),
      lastUpdateCheck: serializer.fromJson<int?>(json['lastUpdateCheck']),
      readerMode: serializer.fromJson<int?>(json['readerMode']),
      oneShot: serializer.fromJson<bool>(json['oneShot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'cover': serializer.toJson<String>(cover),
      'json': serializer.toJson<String>(json),
      'favorite': serializer.toJson<bool>(favorite),
      'favoritedAt': serializer.toJson<int?>(favoritedAt),
      'lastUpdateCheck': serializer.toJson<int?>(lastUpdateCheck),
      'readerMode': serializer.toJson<int?>(readerMode),
      'oneShot': serializer.toJson<bool>(oneShot),
    };
  }

  WorkRow copyWith({
    String? source,
    String? id,
    String? title,
    String? cover,
    String? json,
    bool? favorite,
    Value<int?> favoritedAt = const Value.absent(),
    Value<int?> lastUpdateCheck = const Value.absent(),
    Value<int?> readerMode = const Value.absent(),
    bool? oneShot,
  }) => WorkRow(
    source: source ?? this.source,
    id: id ?? this.id,
    title: title ?? this.title,
    cover: cover ?? this.cover,
    json: json ?? this.json,
    favorite: favorite ?? this.favorite,
    favoritedAt: favoritedAt.present ? favoritedAt.value : this.favoritedAt,
    lastUpdateCheck: lastUpdateCheck.present
        ? lastUpdateCheck.value
        : this.lastUpdateCheck,
    readerMode: readerMode.present ? readerMode.value : this.readerMode,
    oneShot: oneShot ?? this.oneShot,
  );
  WorkRow copyWithCompanion(WorksCompanion data) {
    return WorkRow(
      source: data.source.present ? data.source.value : this.source,
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      cover: data.cover.present ? data.cover.value : this.cover,
      json: data.json.present ? data.json.value : this.json,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      favoritedAt: data.favoritedAt.present
          ? data.favoritedAt.value
          : this.favoritedAt,
      lastUpdateCheck: data.lastUpdateCheck.present
          ? data.lastUpdateCheck.value
          : this.lastUpdateCheck,
      readerMode: data.readerMode.present
          ? data.readerMode.value
          : this.readerMode,
      oneShot: data.oneShot.present ? data.oneShot.value : this.oneShot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkRow(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('cover: $cover, ')
          ..write('json: $json, ')
          ..write('favorite: $favorite, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('lastUpdateCheck: $lastUpdateCheck, ')
          ..write('readerMode: $readerMode, ')
          ..write('oneShot: $oneShot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    source,
    id,
    title,
    cover,
    json,
    favorite,
    favoritedAt,
    lastUpdateCheck,
    readerMode,
    oneShot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkRow &&
          other.source == this.source &&
          other.id == this.id &&
          other.title == this.title &&
          other.cover == this.cover &&
          other.json == this.json &&
          other.favorite == this.favorite &&
          other.favoritedAt == this.favoritedAt &&
          other.lastUpdateCheck == this.lastUpdateCheck &&
          other.readerMode == this.readerMode &&
          other.oneShot == this.oneShot);
}

class WorksCompanion extends UpdateCompanion<WorkRow> {
  final Value<String> source;
  final Value<String> id;
  final Value<String> title;
  final Value<String> cover;
  final Value<String> json;
  final Value<bool> favorite;
  final Value<int?> favoritedAt;
  final Value<int?> lastUpdateCheck;
  final Value<int?> readerMode;
  final Value<bool> oneShot;
  final Value<int> rowid;
  const WorksCompanion({
    this.source = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.cover = const Value.absent(),
    this.json = const Value.absent(),
    this.favorite = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.lastUpdateCheck = const Value.absent(),
    this.readerMode = const Value.absent(),
    this.oneShot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorksCompanion.insert({
    required String source,
    required String id,
    this.title = const Value.absent(),
    this.cover = const Value.absent(),
    this.json = const Value.absent(),
    this.favorite = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.lastUpdateCheck = const Value.absent(),
    this.readerMode = const Value.absent(),
    this.oneShot = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       id = Value(id);
  static Insertable<WorkRow> custom({
    Expression<String>? source,
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? cover,
    Expression<String>? json,
    Expression<bool>? favorite,
    Expression<int>? favoritedAt,
    Expression<int>? lastUpdateCheck,
    Expression<int>? readerMode,
    Expression<bool>? oneShot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (cover != null) 'cover': cover,
      if (json != null) 'json': json,
      if (favorite != null) 'favorite': favorite,
      if (favoritedAt != null) 'favorited_at': favoritedAt,
      if (lastUpdateCheck != null) 'last_update_check': lastUpdateCheck,
      if (readerMode != null) 'reader_mode': readerMode,
      if (oneShot != null) 'one_shot': oneShot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorksCompanion copyWith({
    Value<String>? source,
    Value<String>? id,
    Value<String>? title,
    Value<String>? cover,
    Value<String>? json,
    Value<bool>? favorite,
    Value<int?>? favoritedAt,
    Value<int?>? lastUpdateCheck,
    Value<int?>? readerMode,
    Value<bool>? oneShot,
    Value<int>? rowid,
  }) {
    return WorksCompanion(
      source: source ?? this.source,
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      json: json ?? this.json,
      favorite: favorite ?? this.favorite,
      favoritedAt: favoritedAt ?? this.favoritedAt,
      lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
      readerMode: readerMode ?? this.readerMode,
      oneShot: oneShot ?? this.oneShot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (favoritedAt.present) {
      map['favorited_at'] = Variable<int>(favoritedAt.value);
    }
    if (lastUpdateCheck.present) {
      map['last_update_check'] = Variable<int>(lastUpdateCheck.value);
    }
    if (readerMode.present) {
      map['reader_mode'] = Variable<int>(readerMode.value);
    }
    if (oneShot.present) {
      map['one_shot'] = Variable<bool>(oneShot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorksCompanion(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('cover: $cover, ')
          ..write('json: $json, ')
          ..write('favorite: $favorite, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('lastUpdateCheck: $lastUpdateCheck, ')
          ..write('readerMode: $readerMode, ')
          ..write('oneShot: $oneShot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, sort];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final int id;
  final String name;
  final int sort;
  const CategoryRow({required this.id, required this.name, required this.sort});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      sort: Value(sort),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sort': serializer.toJson<int>(sort),
    };
  }

  CategoryRow copyWith({int? id, String? name, int? sort}) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    sort: sort ?? this.sort,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.sort == this.sort);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> sort;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sort = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.sort = const Value.absent(),
  }) : name = Value(name);
  static Insertable<CategoryRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? sort,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sort != null) 'sort': sort,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? sort,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sort: sort ?? this.sort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }
}

class $WorkCategoriesTable extends WorkCategories
    with TableInfo<$WorkCategoriesTable, WorkCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [source, workId, categoryId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, workId, categoryId};
  @override
  WorkCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkCategoryRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      )!,
    );
  }

  @override
  $WorkCategoriesTable createAlias(String alias) {
    return $WorkCategoriesTable(attachedDatabase, alias);
  }
}

class WorkCategoryRow extends DataClass implements Insertable<WorkCategoryRow> {
  final String source;
  final String workId;
  final int categoryId;
  const WorkCategoryRow({
    required this.source,
    required this.workId,
    required this.categoryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['work_id'] = Variable<String>(workId);
    map['category_id'] = Variable<int>(categoryId);
    return map;
  }

  WorkCategoriesCompanion toCompanion(bool nullToAbsent) {
    return WorkCategoriesCompanion(
      source: Value(source),
      workId: Value(workId),
      categoryId: Value(categoryId),
    );
  }

  factory WorkCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkCategoryRow(
      source: serializer.fromJson<String>(json['source']),
      workId: serializer.fromJson<String>(json['workId']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'workId': serializer.toJson<String>(workId),
      'categoryId': serializer.toJson<int>(categoryId),
    };
  }

  WorkCategoryRow copyWith({String? source, String? workId, int? categoryId}) =>
      WorkCategoryRow(
        source: source ?? this.source,
        workId: workId ?? this.workId,
        categoryId: categoryId ?? this.categoryId,
      );
  WorkCategoryRow copyWithCompanion(WorkCategoriesCompanion data) {
    return WorkCategoryRow(
      source: data.source.present ? data.source.value : this.source,
      workId: data.workId.present ? data.workId.value : this.workId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkCategoryRow(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(source, workId, categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkCategoryRow &&
          other.source == this.source &&
          other.workId == this.workId &&
          other.categoryId == this.categoryId);
}

class WorkCategoriesCompanion extends UpdateCompanion<WorkCategoryRow> {
  final Value<String> source;
  final Value<String> workId;
  final Value<int> categoryId;
  final Value<int> rowid;
  const WorkCategoriesCompanion({
    this.source = const Value.absent(),
    this.workId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkCategoriesCompanion.insert({
    required String source,
    required String workId,
    required int categoryId,
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       workId = Value(workId),
       categoryId = Value(categoryId);
  static Insertable<WorkCategoryRow> custom({
    Expression<String>? source,
    Expression<String>? workId,
    Expression<int>? categoryId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (workId != null) 'work_id': workId,
      if (categoryId != null) 'category_id': categoryId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkCategoriesCompanion copyWith({
    Value<String>? source,
    Value<String>? workId,
    Value<int>? categoryId,
    Value<int>? rowid,
  }) {
    return WorkCategoriesCompanion(
      source: source ?? this.source,
      workId: workId ?? this.workId,
      categoryId: categoryId ?? this.categoryId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkCategoriesCompanion(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('categoryId: $categoryId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters
    with TableInfo<$ChaptersTable, ChapterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastPageMeta = const VerificationMeta(
    'lastPage',
  );
  @override
  late final GeneratedColumn<int> lastPage = GeneratedColumn<int>(
    'last_page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dateFetchMeta = const VerificationMeta(
    'dateFetch',
  );
  @override
  late final GeneratedColumn<int> dateFetch = GeneratedColumn<int>(
    'date_fetch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dateReadMeta = const VerificationMeta(
    'dateRead',
  );
  @override
  late final GeneratedColumn<int> dateRead = GeneratedColumn<int>(
    'date_read',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    workId,
    chapterId,
    title,
    sort,
    read,
    lastPage,
    pageCount,
    dateFetch,
    dateRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    if (data.containsKey('last_page')) {
      context.handle(
        _lastPageMeta,
        lastPage.isAcceptableOrUnknown(data['last_page']!, _lastPageMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('date_fetch')) {
      context.handle(
        _dateFetchMeta,
        dateFetch.isAcceptableOrUnknown(data['date_fetch']!, _dateFetchMeta),
      );
    }
    if (data.containsKey('date_read')) {
      context.handle(
        _dateReadMeta,
        dateRead.isAcceptableOrUnknown(data['date_read']!, _dateReadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, workId, chapterId};
  @override
  ChapterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
      lastPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_page'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      dateFetch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_fetch'],
      )!,
      dateRead: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_read'],
      ),
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class ChapterRow extends DataClass implements Insertable<ChapterRow> {
  final String source;
  final String workId;
  final String chapterId;
  final String title;
  final int sort;
  final bool read;
  final int lastPage;
  final int pageCount;
  final int dateFetch;
  final int? dateRead;
  const ChapterRow({
    required this.source,
    required this.workId,
    required this.chapterId,
    required this.title,
    required this.sort,
    required this.read,
    required this.lastPage,
    required this.pageCount,
    required this.dateFetch,
    this.dateRead,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['work_id'] = Variable<String>(workId);
    map['chapter_id'] = Variable<String>(chapterId);
    map['title'] = Variable<String>(title);
    map['sort'] = Variable<int>(sort);
    map['read'] = Variable<bool>(read);
    map['last_page'] = Variable<int>(lastPage);
    map['page_count'] = Variable<int>(pageCount);
    map['date_fetch'] = Variable<int>(dateFetch);
    if (!nullToAbsent || dateRead != null) {
      map['date_read'] = Variable<int>(dateRead);
    }
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      source: Value(source),
      workId: Value(workId),
      chapterId: Value(chapterId),
      title: Value(title),
      sort: Value(sort),
      read: Value(read),
      lastPage: Value(lastPage),
      pageCount: Value(pageCount),
      dateFetch: Value(dateFetch),
      dateRead: dateRead == null && nullToAbsent
          ? const Value.absent()
          : Value(dateRead),
    );
  }

  factory ChapterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterRow(
      source: serializer.fromJson<String>(json['source']),
      workId: serializer.fromJson<String>(json['workId']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      title: serializer.fromJson<String>(json['title']),
      sort: serializer.fromJson<int>(json['sort']),
      read: serializer.fromJson<bool>(json['read']),
      lastPage: serializer.fromJson<int>(json['lastPage']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      dateFetch: serializer.fromJson<int>(json['dateFetch']),
      dateRead: serializer.fromJson<int?>(json['dateRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'workId': serializer.toJson<String>(workId),
      'chapterId': serializer.toJson<String>(chapterId),
      'title': serializer.toJson<String>(title),
      'sort': serializer.toJson<int>(sort),
      'read': serializer.toJson<bool>(read),
      'lastPage': serializer.toJson<int>(lastPage),
      'pageCount': serializer.toJson<int>(pageCount),
      'dateFetch': serializer.toJson<int>(dateFetch),
      'dateRead': serializer.toJson<int?>(dateRead),
    };
  }

  ChapterRow copyWith({
    String? source,
    String? workId,
    String? chapterId,
    String? title,
    int? sort,
    bool? read,
    int? lastPage,
    int? pageCount,
    int? dateFetch,
    Value<int?> dateRead = const Value.absent(),
  }) => ChapterRow(
    source: source ?? this.source,
    workId: workId ?? this.workId,
    chapterId: chapterId ?? this.chapterId,
    title: title ?? this.title,
    sort: sort ?? this.sort,
    read: read ?? this.read,
    lastPage: lastPage ?? this.lastPage,
    pageCount: pageCount ?? this.pageCount,
    dateFetch: dateFetch ?? this.dateFetch,
    dateRead: dateRead.present ? dateRead.value : this.dateRead,
  );
  ChapterRow copyWithCompanion(ChaptersCompanion data) {
    return ChapterRow(
      source: data.source.present ? data.source.value : this.source,
      workId: data.workId.present ? data.workId.value : this.workId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      title: data.title.present ? data.title.value : this.title,
      sort: data.sort.present ? data.sort.value : this.sort,
      read: data.read.present ? data.read.value : this.read,
      lastPage: data.lastPage.present ? data.lastPage.value : this.lastPage,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      dateFetch: data.dateFetch.present ? data.dateFetch.value : this.dateFetch,
      dateRead: data.dateRead.present ? data.dateRead.value : this.dateRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterRow(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('chapterId: $chapterId, ')
          ..write('title: $title, ')
          ..write('sort: $sort, ')
          ..write('read: $read, ')
          ..write('lastPage: $lastPage, ')
          ..write('pageCount: $pageCount, ')
          ..write('dateFetch: $dateFetch, ')
          ..write('dateRead: $dateRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    source,
    workId,
    chapterId,
    title,
    sort,
    read,
    lastPage,
    pageCount,
    dateFetch,
    dateRead,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterRow &&
          other.source == this.source &&
          other.workId == this.workId &&
          other.chapterId == this.chapterId &&
          other.title == this.title &&
          other.sort == this.sort &&
          other.read == this.read &&
          other.lastPage == this.lastPage &&
          other.pageCount == this.pageCount &&
          other.dateFetch == this.dateFetch &&
          other.dateRead == this.dateRead);
}

class ChaptersCompanion extends UpdateCompanion<ChapterRow> {
  final Value<String> source;
  final Value<String> workId;
  final Value<String> chapterId;
  final Value<String> title;
  final Value<int> sort;
  final Value<bool> read;
  final Value<int> lastPage;
  final Value<int> pageCount;
  final Value<int> dateFetch;
  final Value<int?> dateRead;
  final Value<int> rowid;
  const ChaptersCompanion({
    this.source = const Value.absent(),
    this.workId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.title = const Value.absent(),
    this.sort = const Value.absent(),
    this.read = const Value.absent(),
    this.lastPage = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.dateFetch = const Value.absent(),
    this.dateRead = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String source,
    required String workId,
    required String chapterId,
    this.title = const Value.absent(),
    this.sort = const Value.absent(),
    this.read = const Value.absent(),
    this.lastPage = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.dateFetch = const Value.absent(),
    this.dateRead = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       workId = Value(workId),
       chapterId = Value(chapterId);
  static Insertable<ChapterRow> custom({
    Expression<String>? source,
    Expression<String>? workId,
    Expression<String>? chapterId,
    Expression<String>? title,
    Expression<int>? sort,
    Expression<bool>? read,
    Expression<int>? lastPage,
    Expression<int>? pageCount,
    Expression<int>? dateFetch,
    Expression<int>? dateRead,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (workId != null) 'work_id': workId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (title != null) 'title': title,
      if (sort != null) 'sort': sort,
      if (read != null) 'read': read,
      if (lastPage != null) 'last_page': lastPage,
      if (pageCount != null) 'page_count': pageCount,
      if (dateFetch != null) 'date_fetch': dateFetch,
      if (dateRead != null) 'date_read': dateRead,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChaptersCompanion copyWith({
    Value<String>? source,
    Value<String>? workId,
    Value<String>? chapterId,
    Value<String>? title,
    Value<int>? sort,
    Value<bool>? read,
    Value<int>? lastPage,
    Value<int>? pageCount,
    Value<int>? dateFetch,
    Value<int?>? dateRead,
    Value<int>? rowid,
  }) {
    return ChaptersCompanion(
      source: source ?? this.source,
      workId: workId ?? this.workId,
      chapterId: chapterId ?? this.chapterId,
      title: title ?? this.title,
      sort: sort ?? this.sort,
      read: read ?? this.read,
      lastPage: lastPage ?? this.lastPage,
      pageCount: pageCount ?? this.pageCount,
      dateFetch: dateFetch ?? this.dateFetch,
      dateRead: dateRead ?? this.dateRead,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (lastPage.present) {
      map['last_page'] = Variable<int>(lastPage.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (dateFetch.present) {
      map['date_fetch'] = Variable<int>(dateFetch.value);
    }
    if (dateRead.present) {
      map['date_read'] = Variable<int>(dateRead.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('chapterId: $chapterId, ')
          ..write('title: $title, ')
          ..write('sort: $sort, ')
          ..write('read: $read, ')
          ..write('lastPage: $lastPage, ')
          ..write('pageCount: $pageCount, ')
          ..write('dateFetch: $dateFetch, ')
          ..write('dateRead: $dateRead, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryTable extends History with TableInfo<$HistoryTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<int> time = GeneratedColumn<int>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    workId,
    time,
    chapterId,
    chapterTitle,
    page,
    pageCount,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, workId};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      ),
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      ),
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      ),
    );
  }

  @override
  $HistoryTable createAlias(String alias) {
    return $HistoryTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final String source;
  final String workId;
  final int time;
  final String? chapterId;
  final String? chapterTitle;
  final int page;
  final int pageCount;
  final int? position;
  const HistoryRow({
    required this.source,
    required this.workId,
    required this.time,
    this.chapterId,
    this.chapterTitle,
    required this.page,
    required this.pageCount,
    this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['work_id'] = Variable<String>(workId);
    map['time'] = Variable<int>(time);
    if (!nullToAbsent || chapterId != null) {
      map['chapter_id'] = Variable<String>(chapterId);
    }
    if (!nullToAbsent || chapterTitle != null) {
      map['chapter_title'] = Variable<String>(chapterTitle);
    }
    map['page'] = Variable<int>(page);
    map['page_count'] = Variable<int>(pageCount);
    if (!nullToAbsent || position != null) {
      map['position'] = Variable<int>(position);
    }
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      source: Value(source),
      workId: Value(workId),
      time: Value(time),
      chapterId: chapterId == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterId),
      chapterTitle: chapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterTitle),
      page: Value(page),
      pageCount: Value(pageCount),
      position: position == null && nullToAbsent
          ? const Value.absent()
          : Value(position),
    );
  }

  factory HistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      source: serializer.fromJson<String>(json['source']),
      workId: serializer.fromJson<String>(json['workId']),
      time: serializer.fromJson<int>(json['time']),
      chapterId: serializer.fromJson<String?>(json['chapterId']),
      chapterTitle: serializer.fromJson<String?>(json['chapterTitle']),
      page: serializer.fromJson<int>(json['page']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      position: serializer.fromJson<int?>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'workId': serializer.toJson<String>(workId),
      'time': serializer.toJson<int>(time),
      'chapterId': serializer.toJson<String?>(chapterId),
      'chapterTitle': serializer.toJson<String?>(chapterTitle),
      'page': serializer.toJson<int>(page),
      'pageCount': serializer.toJson<int>(pageCount),
      'position': serializer.toJson<int?>(position),
    };
  }

  HistoryRow copyWith({
    String? source,
    String? workId,
    int? time,
    Value<String?> chapterId = const Value.absent(),
    Value<String?> chapterTitle = const Value.absent(),
    int? page,
    int? pageCount,
    Value<int?> position = const Value.absent(),
  }) => HistoryRow(
    source: source ?? this.source,
    workId: workId ?? this.workId,
    time: time ?? this.time,
    chapterId: chapterId.present ? chapterId.value : this.chapterId,
    chapterTitle: chapterTitle.present ? chapterTitle.value : this.chapterTitle,
    page: page ?? this.page,
    pageCount: pageCount ?? this.pageCount,
    position: position.present ? position.value : this.position,
  );
  HistoryRow copyWithCompanion(HistoryCompanion data) {
    return HistoryRow(
      source: data.source.present ? data.source.value : this.source,
      workId: data.workId.present ? data.workId.value : this.workId,
      time: data.time.present ? data.time.value : this.time,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      page: data.page.present ? data.page.value : this.page,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('time: $time, ')
          ..write('chapterId: $chapterId, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('pageCount: $pageCount, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    source,
    workId,
    time,
    chapterId,
    chapterTitle,
    page,
    pageCount,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.source == this.source &&
          other.workId == this.workId &&
          other.time == this.time &&
          other.chapterId == this.chapterId &&
          other.chapterTitle == this.chapterTitle &&
          other.page == this.page &&
          other.pageCount == this.pageCount &&
          other.position == this.position);
}

class HistoryCompanion extends UpdateCompanion<HistoryRow> {
  final Value<String> source;
  final Value<String> workId;
  final Value<int> time;
  final Value<String?> chapterId;
  final Value<String?> chapterTitle;
  final Value<int> page;
  final Value<int> pageCount;
  final Value<int?> position;
  final Value<int> rowid;
  const HistoryCompanion({
    this.source = const Value.absent(),
    this.workId = const Value.absent(),
    this.time = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String source,
    required String workId,
    required int time,
    this.chapterId = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       workId = Value(workId),
       time = Value(time);
  static Insertable<HistoryRow> custom({
    Expression<String>? source,
    Expression<String>? workId,
    Expression<int>? time,
    Expression<String>? chapterId,
    Expression<String>? chapterTitle,
    Expression<int>? page,
    Expression<int>? pageCount,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (workId != null) 'work_id': workId,
      if (time != null) 'time': time,
      if (chapterId != null) 'chapter_id': chapterId,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (page != null) 'page': page,
      if (pageCount != null) 'page_count': pageCount,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryCompanion copyWith({
    Value<String>? source,
    Value<String>? workId,
    Value<int>? time,
    Value<String?>? chapterId,
    Value<String?>? chapterTitle,
    Value<int>? page,
    Value<int>? pageCount,
    Value<int?>? position,
    Value<int>? rowid,
  }) {
    return HistoryCompanion(
      source: source ?? this.source,
      workId: workId ?? this.workId,
      time: time ?? this.time,
      chapterId: chapterId ?? this.chapterId,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      page: page ?? this.page,
      pageCount: pageCount ?? this.pageCount,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (time.present) {
      map['time'] = Variable<int>(time.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('source: $source, ')
          ..write('workId: $workId, ')
          ..write('time: $time, ')
          ..write('chapterId: $chapterId, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('pageCount: $pageCount, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadTasksTable extends DownloadTasks
    with TableInfo<$DownloadTasksTable, DownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirMeta = const VerificationMeta('dir');
  @override
  late final GeneratedColumn<String> dir = GeneratedColumn<String>(
    'dir',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [uid, source, json, dir, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('dir')) {
      context.handle(
        _dirMeta,
        dir.isAcceptableOrUnknown(data['dir']!, _dirMeta),
      );
    } else if (isInserting) {
      context.missing(_dirMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uid};
  @override
  DownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRow(
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      dir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dir'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DownloadTasksTable createAlias(String alias) {
    return $DownloadTasksTable(attachedDatabase, alias);
  }
}

class DownloadRow extends DataClass implements Insertable<DownloadRow> {
  final String uid;
  final String source;
  final String json;
  final String dir;
  final int createdAt;
  const DownloadRow({
    required this.uid,
    required this.source,
    required this.json,
    required this.dir,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uid'] = Variable<String>(uid);
    map['source'] = Variable<String>(source);
    map['json'] = Variable<String>(json);
    map['dir'] = Variable<String>(dir);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  DownloadTasksCompanion toCompanion(bool nullToAbsent) {
    return DownloadTasksCompanion(
      uid: Value(uid),
      source: Value(source),
      json: Value(json),
      dir: Value(dir),
      createdAt: Value(createdAt),
    );
  }

  factory DownloadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRow(
      uid: serializer.fromJson<String>(json['uid']),
      source: serializer.fromJson<String>(json['source']),
      json: serializer.fromJson<String>(json['json']),
      dir: serializer.fromJson<String>(json['dir']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uid': serializer.toJson<String>(uid),
      'source': serializer.toJson<String>(source),
      'json': serializer.toJson<String>(json),
      'dir': serializer.toJson<String>(dir),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  DownloadRow copyWith({
    String? uid,
    String? source,
    String? json,
    String? dir,
    int? createdAt,
  }) => DownloadRow(
    uid: uid ?? this.uid,
    source: source ?? this.source,
    json: json ?? this.json,
    dir: dir ?? this.dir,
    createdAt: createdAt ?? this.createdAt,
  );
  DownloadRow copyWithCompanion(DownloadTasksCompanion data) {
    return DownloadRow(
      uid: data.uid.present ? data.uid.value : this.uid,
      source: data.source.present ? data.source.value : this.source,
      json: data.json.present ? data.json.value : this.json,
      dir: data.dir.present ? data.dir.value : this.dir,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRow(')
          ..write('uid: $uid, ')
          ..write('source: $source, ')
          ..write('json: $json, ')
          ..write('dir: $dir, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(uid, source, json, dir, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRow &&
          other.uid == this.uid &&
          other.source == this.source &&
          other.json == this.json &&
          other.dir == this.dir &&
          other.createdAt == this.createdAt);
}

class DownloadTasksCompanion extends UpdateCompanion<DownloadRow> {
  final Value<String> uid;
  final Value<String> source;
  final Value<String> json;
  final Value<String> dir;
  final Value<int> createdAt;
  final Value<int> rowid;
  const DownloadTasksCompanion({
    this.uid = const Value.absent(),
    this.source = const Value.absent(),
    this.json = const Value.absent(),
    this.dir = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadTasksCompanion.insert({
    required String uid,
    required String source,
    required String json,
    required String dir,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : uid = Value(uid),
       source = Value(source),
       json = Value(json),
       dir = Value(dir),
       createdAt = Value(createdAt);
  static Insertable<DownloadRow> custom({
    Expression<String>? uid,
    Expression<String>? source,
    Expression<String>? json,
    Expression<String>? dir,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uid != null) 'uid': uid,
      if (source != null) 'source': source,
      if (json != null) 'json': json,
      if (dir != null) 'dir': dir,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadTasksCompanion copyWith({
    Value<String>? uid,
    Value<String>? source,
    Value<String>? json,
    Value<String>? dir,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return DownloadTasksCompanion(
      uid: uid ?? this.uid,
      source: source ?? this.source,
      json: json ?? this.json,
      dir: dir ?? this.dir,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (dir.present) {
      map['dir'] = Variable<String>(dir.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTasksCompanion(')
          ..write('uid: $uid, ')
          ..write('source: $source, ')
          ..write('json: $json, ')
          ..write('dir: $dir, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WorksTable works = $WorksTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $WorkCategoriesTable workCategories = $WorkCategoriesTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $HistoryTable history = $HistoryTable(this);
  late final $DownloadTasksTable downloadTasks = $DownloadTasksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    works,
    categories,
    workCategories,
    chapters,
    history,
    downloadTasks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('work_categories', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WorksTableCreateCompanionBuilder = WorksCompanion Function({
  required String source,
  required String id,
  Value<String> title,
  Value<String> cover,
  Value<String> json,
  Value<bool> favorite,
  Value<int?> favoritedAt,
  Value<int?> lastUpdateCheck,
  Value<int?> readerMode,
  Value<bool> oneShot,
  Value<int> rowid,
});
typedef $$WorksTableUpdateCompanionBuilder = WorksCompanion Function({
  Value<String> source,
  Value<String> id,
  Value<String> title,
  Value<String> cover,
  Value<String> json,
  Value<bool> favorite,
  Value<int?> favoritedAt,
  Value<int?> lastUpdateCheck,
  Value<int?> readerMode,
  Value<bool> oneShot,
  Value<int> rowid,
});

class $$WorksTableFilterComposer extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readerMode => $composableBuilder(
    column: $table.readerMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get oneShot => $composableBuilder(
    column: $table.oneShot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorksTableOrderingComposer
    extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cover => $composableBuilder(
    column: $table.cover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readerMode => $composableBuilder(
    column: $table.readerMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get oneShot => $composableBuilder(
    column: $table.oneShot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorksTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get cover =>
      $composableBuilder(column: $table.cover, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readerMode => $composableBuilder(
    column: $table.readerMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get oneShot =>
      $composableBuilder(column: $table.oneShot, builder: (column) => column);
}

class $$WorksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorksTable,
          WorkRow,
          $$WorksTableFilterComposer,
          $$WorksTableOrderingComposer,
          $$WorksTableAnnotationComposer,
          $$WorksTableCreateCompanionBuilder,
          $$WorksTableUpdateCompanionBuilder,
          (WorkRow, BaseReferences<_$AppDatabase, $WorksTable, WorkRow>),
          WorkRow,
          PrefetchHooks Function()
        > {
  $$WorksTableTableManager(_$AppDatabase db, $WorksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> cover = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> favoritedAt = const Value.absent(),
                Value<int?> lastUpdateCheck = const Value.absent(),
                Value<int?> readerMode = const Value.absent(),
                Value<bool> oneShot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorksCompanion(
                source: source,
                id: id,
                title: title,
                cover: cover,
                json: json,
                favorite: favorite,
                favoritedAt: favoritedAt,
                lastUpdateCheck: lastUpdateCheck,
                readerMode: readerMode,
                oneShot: oneShot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> cover = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> favoritedAt = const Value.absent(),
                Value<int?> lastUpdateCheck = const Value.absent(),
                Value<int?> readerMode = const Value.absent(),
                Value<bool> oneShot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorksCompanion.insert(
                source: source,
                id: id,
                title: title,
                cover: cover,
                json: json,
                favorite: favorite,
                favoritedAt: favoritedAt,
                lastUpdateCheck: lastUpdateCheck,
                readerMode: readerMode,
                oneShot: oneShot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorksTable, WorkRow>(table),
                  BaseReferences<_$AppDatabase, $WorksTable, WorkRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorksTable,
      WorkRow,
      $$WorksTableFilterComposer,
      $$WorksTableOrderingComposer,
      $$WorksTableAnnotationComposer,
      $$WorksTableCreateCompanionBuilder,
      $$WorksTableUpdateCompanionBuilder,
      (WorkRow, BaseReferences<_$AppDatabase, $WorksTable, WorkRow>),
      WorkRow,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required String name,
  Value<int> sort,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> sort,
});

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$WorkCategoriesTable, List<WorkCategoryRow>>
  _workCategoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.workCategories,
    aliasName: 'categories__id__work_categories__category_id',
  );

  $$WorkCategoriesTableProcessedTableManager get workCategoriesRefs {
    final manager = $$WorkCategoriesTableTableManager(
      $_db,
      $_db.workCategories,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_workCategoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> workCategoriesRefs(
    Expression<bool> Function($$WorkCategoriesTableFilterComposer f) f,
  ) {
    final $$WorkCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.workCategories,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.workCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  Expression<T> workCategoriesRefs<T extends Object>(
    Expression<T> Function($$WorkCategoriesTableAnnotationComposer a) f,
  ) {
    final $$WorkCategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.workCategories,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkCategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.workCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({bool workCategoriesRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> sort = const Value.absent(),
          }) => CategoriesCompanion(id: id, name: name, sort: sort),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<int> sort = const Value.absent(),
          }) => CategoriesCompanion.insert(id: id, name: name, sort: sort),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, CategoryRow>(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workCategoriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (workCategoriesRefs) db.workCategories,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (workCategoriesRefs)
                    await $_getPrefetchedData<
                      CategoryRow,
                      $CategoriesTable,
                      WorkCategoryRow
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._workCategoriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).workCategoriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool workCategoriesRefs})
    >;
typedef $$WorkCategoriesTableCreateCompanionBuilder =
    WorkCategoriesCompanion Function({
      required String source,
      required String workId,
      required int categoryId,
      Value<int> rowid,
    });
typedef $$WorkCategoriesTableUpdateCompanionBuilder =
    WorkCategoriesCompanion Function({
      Value<String> source,
      Value<String> workId,
      Value<int> categoryId,
      Value<int> rowid,
    });

final class $$WorkCategoriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $WorkCategoriesTable, WorkCategoryRow> {
  $$WorkCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('work_categories__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WorkCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkCategoriesTable> {
  $$WorkCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkCategoriesTable> {
  $$WorkCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkCategoriesTable> {
  $$WorkCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkCategoriesTable,
          WorkCategoryRow,
          $$WorkCategoriesTableFilterComposer,
          $$WorkCategoriesTableOrderingComposer,
          $$WorkCategoriesTableAnnotationComposer,
          $$WorkCategoriesTableCreateCompanionBuilder,
          $$WorkCategoriesTableUpdateCompanionBuilder,
          (WorkCategoryRow, $$WorkCategoriesTableReferences),
          WorkCategoryRow,
          PrefetchHooks Function({bool categoryId})
        > {
  $$WorkCategoriesTableTableManager(
    _$AppDatabase db,
    $WorkCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkCategoriesCompanion(
                source: source,
                workId: workId,
                categoryId: categoryId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String workId,
                required int categoryId,
                Value<int> rowid = const Value.absent(),
              }) => WorkCategoriesCompanion.insert(
                source: source,
                workId: workId,
                categoryId: categoryId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkCategoriesTable, WorkCategoryRow>(table),
                  $$WorkCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$WorkCategoriesTableReferences
                            ._categoryIdTable(db),
                        referencedColumn: $$WorkCategoriesTableReferences
                            ._categoryIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WorkCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkCategoriesTable,
      WorkCategoryRow,
      $$WorkCategoriesTableFilterComposer,
      $$WorkCategoriesTableOrderingComposer,
      $$WorkCategoriesTableAnnotationComposer,
      $$WorkCategoriesTableCreateCompanionBuilder,
      $$WorkCategoriesTableUpdateCompanionBuilder,
      (WorkCategoryRow, $$WorkCategoriesTableReferences),
      WorkCategoryRow,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$ChaptersTableCreateCompanionBuilder = ChaptersCompanion Function({
  required String source,
  required String workId,
  required String chapterId,
  Value<String> title,
  Value<int> sort,
  Value<bool> read,
  Value<int> lastPage,
  Value<int> pageCount,
  Value<int> dateFetch,
  Value<int?> dateRead,
  Value<int> rowid,
});
typedef $$ChaptersTableUpdateCompanionBuilder = ChaptersCompanion Function({
  Value<String> source,
  Value<String> workId,
  Value<String> chapterId,
  Value<String> title,
  Value<int> sort,
  Value<bool> read,
  Value<int> lastPage,
  Value<int> pageCount,
  Value<int> dateFetch,
  Value<int?> dateRead,
  Value<int> rowid,
});

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPage => $composableBuilder(
    column: $table.lastPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateFetch => $composableBuilder(
    column: $table.dateFetch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateRead => $composableBuilder(
    column: $table.dateRead,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPage => $composableBuilder(
    column: $table.lastPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateFetch => $composableBuilder(
    column: $table.dateFetch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateRead => $composableBuilder(
    column: $table.dateRead,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<int> get lastPage =>
      $composableBuilder(column: $table.lastPage, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get dateFetch =>
      $composableBuilder(column: $table.dateFetch, builder: (column) => column);

  GeneratedColumn<int> get dateRead =>
      $composableBuilder(column: $table.dateRead, builder: (column) => column);
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          ChapterRow,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (
            ChapterRow,
            BaseReferences<_$AppDatabase, $ChaptersTable, ChapterRow>,
          ),
          ChapterRow,
          PrefetchHooks Function()
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<int> lastPage = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> dateFetch = const Value.absent(),
                Value<int?> dateRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion(
                source: source,
                workId: workId,
                chapterId: chapterId,
                title: title,
                sort: sort,
                read: read,
                lastPage: lastPage,
                pageCount: pageCount,
                dateFetch: dateFetch,
                dateRead: dateRead,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String workId,
                required String chapterId,
                Value<String> title = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<int> lastPage = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> dateFetch = const Value.absent(),
                Value<int?> dateRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion.insert(
                source: source,
                workId: workId,
                chapterId: chapterId,
                title: title,
                sort: sort,
                read: read,
                lastPage: lastPage,
                pageCount: pageCount,
                dateFetch: dateFetch,
                dateRead: dateRead,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChaptersTable, ChapterRow>(table),
                  BaseReferences<_$AppDatabase, $ChaptersTable, ChapterRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      ChapterRow,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (ChapterRow, BaseReferences<_$AppDatabase, $ChaptersTable, ChapterRow>),
      ChapterRow,
      PrefetchHooks Function()
    >;
typedef $$HistoryTableCreateCompanionBuilder = HistoryCompanion Function({
  required String source,
  required String workId,
  required int time,
  Value<String?> chapterId,
  Value<String?> chapterTitle,
  Value<int> page,
  Value<int> pageCount,
  Value<int?> position,
  Value<int> rowid,
});
typedef $$HistoryTableUpdateCompanionBuilder = HistoryCompanion Function({
  Value<String> source,
  Value<String> workId,
  Value<int> time,
  Value<String?> chapterId,
  Value<String?> chapterTitle,
  Value<int> page,
  Value<int> pageCount,
  Value<int?> position,
  Value<int> rowid,
});

class $$HistoryTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryTable> {
  $$HistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryTable> {
  $$HistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryTable> {
  $$HistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<int> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$HistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoryTable,
          HistoryRow,
          $$HistoryTableFilterComposer,
          $$HistoryTableOrderingComposer,
          $$HistoryTableAnnotationComposer,
          $$HistoryTableCreateCompanionBuilder,
          $$HistoryTableUpdateCompanionBuilder,
          (
            HistoryRow,
            BaseReferences<_$AppDatabase, $HistoryTable, HistoryRow>,
          ),
          HistoryRow,
          PrefetchHooks Function()
        > {
  $$HistoryTableTableManager(_$AppDatabase db, $HistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<int> time = const Value.absent(),
                Value<String?> chapterId = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int?> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion(
                source: source,
                workId: workId,
                time: time,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                page: page,
                pageCount: pageCount,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String workId,
                required int time,
                Value<String?> chapterId = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int?> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion.insert(
                source: source,
                workId: workId,
                time: time,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                page: page,
                pageCount: pageCount,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HistoryTable, HistoryRow>(table),
                  BaseReferences<_$AppDatabase, $HistoryTable, HistoryRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoryTable,
      HistoryRow,
      $$HistoryTableFilterComposer,
      $$HistoryTableOrderingComposer,
      $$HistoryTableAnnotationComposer,
      $$HistoryTableCreateCompanionBuilder,
      $$HistoryTableUpdateCompanionBuilder,
      (HistoryRow, BaseReferences<_$AppDatabase, $HistoryTable, HistoryRow>),
      HistoryRow,
      PrefetchHooks Function()
    >;
typedef $$DownloadTasksTableCreateCompanionBuilder =
    DownloadTasksCompanion Function({
      required String uid,
      required String source,
      required String json,
      required String dir,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$DownloadTasksTableUpdateCompanionBuilder =
    DownloadTasksCompanion Function({
      Value<String> uid,
      Value<String> source,
      Value<String> json,
      Value<String> dir,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$DownloadTasksTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dir => $composableBuilder(
    column: $table.dir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dir => $composableBuilder(
    column: $table.dir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get dir =>
      $composableBuilder(column: $table.dir, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DownloadTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadTasksTable,
          DownloadRow,
          $$DownloadTasksTableFilterComposer,
          $$DownloadTasksTableOrderingComposer,
          $$DownloadTasksTableAnnotationComposer,
          $$DownloadTasksTableCreateCompanionBuilder,
          $$DownloadTasksTableUpdateCompanionBuilder,
          (
            DownloadRow,
            BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadRow>,
          ),
          DownloadRow,
          PrefetchHooks Function()
        > {
  $$DownloadTasksTableTableManager(_$AppDatabase db, $DownloadTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uid = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<String> dir = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion(
                uid: uid,
                source: source,
                json: json,
                dir: dir,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String uid,
                required String source,
                required String json,
                required String dir,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion.insert(
                uid: uid,
                source: source,
                json: json,
                dir: dir,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadTasksTable, DownloadRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DownloadTasksTable,
                    DownloadRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadTasksTable,
      DownloadRow,
      $$DownloadTasksTableFilterComposer,
      $$DownloadTasksTableOrderingComposer,
      $$DownloadTasksTableAnnotationComposer,
      $$DownloadTasksTableCreateCompanionBuilder,
      $$DownloadTasksTableUpdateCompanionBuilder,
      (
        DownloadRow,
        BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadRow>,
      ),
      DownloadRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WorksTableTableManager get works =>
      $$WorksTableTableManager(_db, _db.works);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$WorkCategoriesTableTableManager get workCategories =>
      $$WorkCategoriesTableTableManager(_db, _db.workCategories);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$HistoryTableTableManager get history =>
      $$HistoryTableTableManager(_db, _db.history);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db, _db.downloadTasks);
}
