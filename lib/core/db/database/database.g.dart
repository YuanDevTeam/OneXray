// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CoreConfigTable extends CoreConfig
    with TableInfo<$CoreConfigTable, CoreConfigData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoreConfigTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _delayMeta = const VerificationMeta('delay');
  @override
  late final GeneratedColumn<int> delay = GeneratedColumn<int>(
    'delay',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subIdMeta = const VerificationMeta('subId');
  @override
  late final GeneratedColumn<int> subId = GeneratedColumn<int>(
    'sub_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    tags,
    data,
    delay,
    subId,
    favorite,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'core_config';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoreConfigData> instance, {
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
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    } else if (isInserting) {
      context.missing(_tagsMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    if (data.containsKey('delay')) {
      context.handle(
        _delayMeta,
        delay.isAcceptableOrUnknown(data['delay']!, _delayMeta),
      );
    } else if (isInserting) {
      context.missing(_delayMeta);
    }
    if (data.containsKey('sub_id')) {
      context.handle(
        _subIdMeta,
        subId.isAcceptableOrUnknown(data['sub_id']!, _subIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subIdMeta);
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoreConfigData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoreConfigData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      ),
      delay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delay'],
      )!,
      subId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sub_id'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
    );
  }

  @override
  $CoreConfigTable createAlias(String alias) {
    return $CoreConfigTable(attachedDatabase, alias);
  }
}

class CoreConfigData extends DataClass implements Insertable<CoreConfigData> {
  final int id;
  final String name;
  final String type;
  final String tags;
  final String? data;
  final int delay;
  final int subId;
  final bool favorite;
  const CoreConfigData({
    required this.id,
    required this.name,
    required this.type,
    required this.tags,
    this.data,
    required this.delay,
    required this.subId,
    required this.favorite,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['tags'] = Variable<String>(tags);
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    map['delay'] = Variable<int>(delay);
    map['sub_id'] = Variable<int>(subId);
    map['favorite'] = Variable<bool>(favorite);
    return map;
  }

  CoreConfigCompanion toCompanion(bool nullToAbsent) {
    return CoreConfigCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      tags: Value(tags),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      delay: Value(delay),
      subId: Value(subId),
      favorite: Value(favorite),
    );
  }

  factory CoreConfigData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoreConfigData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      tags: serializer.fromJson<String>(json['tags']),
      data: serializer.fromJson<String?>(json['data']),
      delay: serializer.fromJson<int>(json['delay']),
      subId: serializer.fromJson<int>(json['subId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'tags': serializer.toJson<String>(tags),
      'data': serializer.toJson<String?>(data),
      'delay': serializer.toJson<int>(delay),
      'subId': serializer.toJson<int>(subId),
      'favorite': serializer.toJson<bool>(favorite),
    };
  }

  CoreConfigData copyWith({
    int? id,
    String? name,
    String? type,
    String? tags,
    Value<String?> data = const Value.absent(),
    int? delay,
    int? subId,
    bool? favorite,
  }) => CoreConfigData(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    tags: tags ?? this.tags,
    data: data.present ? data.value : this.data,
    delay: delay ?? this.delay,
    subId: subId ?? this.subId,
    favorite: favorite ?? this.favorite,
  );
  CoreConfigData copyWithCompanion(CoreConfigCompanion data) {
    return CoreConfigData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      tags: data.tags.present ? data.tags.value : this.tags,
      data: data.data.present ? data.data.value : this.data,
      delay: data.delay.present ? data.delay.value : this.delay,
      subId: data.subId.present ? data.subId.value : this.subId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoreConfigData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('tags: $tags, ')
          ..write('data: $data, ')
          ..write('delay: $delay, ')
          ..write('subId: $subId, ')
          ..write('favorite: $favorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, tags, data, delay, subId, favorite);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoreConfigData &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.tags == this.tags &&
          other.data == this.data &&
          other.delay == this.delay &&
          other.subId == this.subId &&
          other.favorite == this.favorite);
}

class CoreConfigCompanion extends UpdateCompanion<CoreConfigData> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> tags;
  final Value<String?> data;
  final Value<int> delay;
  final Value<int> subId;
  final Value<bool> favorite;
  const CoreConfigCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.tags = const Value.absent(),
    this.data = const Value.absent(),
    this.delay = const Value.absent(),
    this.subId = const Value.absent(),
    this.favorite = const Value.absent(),
  });
  CoreConfigCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String type,
    required String tags,
    this.data = const Value.absent(),
    required int delay,
    required int subId,
    this.favorite = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       tags = Value(tags),
       delay = Value(delay),
       subId = Value(subId);
  static Insertable<CoreConfigData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? tags,
    Expression<String>? data,
    Expression<int>? delay,
    Expression<int>? subId,
    Expression<bool>? favorite,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (tags != null) 'tags': tags,
      if (data != null) 'data': data,
      if (delay != null) 'delay': delay,
      if (subId != null) 'sub_id': subId,
      if (favorite != null) 'favorite': favorite,
    });
  }

  CoreConfigCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? tags,
    Value<String?>? data,
    Value<int>? delay,
    Value<int>? subId,
    Value<bool>? favorite,
  }) {
    return CoreConfigCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      data: data ?? this.data,
      delay: delay ?? this.delay,
      subId: subId ?? this.subId,
      favorite: favorite ?? this.favorite,
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
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (delay.present) {
      map['delay'] = Variable<int>(delay.value);
    }
    if (subId.present) {
      map['sub_id'] = Variable<int>(subId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoreConfigCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('tags: $tags, ')
          ..write('data: $data, ')
          ..write('delay: $delay, ')
          ..write('subId: $subId, ')
          ..write('favorite: $favorite')
          ..write(')'))
        .toString();
  }
}

class $SubscriptionTable extends Subscription
    with TableInfo<$SubscriptionTable, SubscriptionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubscriptionTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userAgentMeta = const VerificationMeta(
    'userAgent',
  );
  @override
  late final GeneratedColumn<String> userAgent = GeneratedColumn<String>(
    'user_agent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _panelMeta = const VerificationMeta('panel');
  @override
  late final GeneratedColumn<String> panel = GeneratedColumn<String>(
    'panel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('generic'),
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('appManaged'),
  );
  static const VerificationMeta _ageSecretKeyMeta = const VerificationMeta(
    'ageSecretKey',
  );
  @override
  late final GeneratedColumn<String> ageSecretKey = GeneratedColumn<String>(
    'age_secret_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agePublicKeyMeta = const VerificationMeta(
    'agePublicKey',
  );
  @override
  late final GeneratedColumn<String> agePublicKey = GeneratedColumn<String>(
    'age_public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hwidEnabledMeta = const VerificationMeta(
    'hwidEnabled',
  );
  @override
  late final GeneratedColumn<bool> hwidEnabled = GeneratedColumn<bool>(
    'hwid_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hwid_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hwidMeta = const VerificationMeta('hwid');
  @override
  late final GeneratedColumn<String> hwid = GeneratedColumn<String>(
    'hwid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadBytesMeta = const VerificationMeta(
    'uploadBytes',
  );
  @override
  late final GeneratedColumn<int> uploadBytes = GeneratedColumn<int>(
    'upload_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadBytesMeta = const VerificationMeta(
    'downloadBytes',
  );
  @override
  late final GeneratedColumn<int> downloadBytes = GeneratedColumn<int>(
    'download_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expireTimestampMeta = const VerificationMeta(
    'expireTimestamp',
  );
  @override
  late final GeneratedColumn<int> expireTimestamp = GeneratedColumn<int>(
    'expire_timestamp',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userInfoUpdatedAtMeta = const VerificationMeta(
    'userInfoUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> userInfoUpdatedAt =
      GeneratedColumn<DateTime>(
        'user_info_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    url,
    userAgent,
    panel,
    mode,
    ageSecretKey,
    agePublicKey,
    hwidEnabled,
    hwid,
    timestamp,
    uploadBytes,
    downloadBytes,
    totalBytes,
    expireTimestamp,
    userInfoUpdatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subscription';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubscriptionData> instance, {
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
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('user_agent')) {
      context.handle(
        _userAgentMeta,
        userAgent.isAcceptableOrUnknown(data['user_agent']!, _userAgentMeta),
      );
    }
    if (data.containsKey('panel')) {
      context.handle(
        _panelMeta,
        panel.isAcceptableOrUnknown(data['panel']!, _panelMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('age_secret_key')) {
      context.handle(
        _ageSecretKeyMeta,
        ageSecretKey.isAcceptableOrUnknown(
          data['age_secret_key']!,
          _ageSecretKeyMeta,
        ),
      );
    }
    if (data.containsKey('age_public_key')) {
      context.handle(
        _agePublicKeyMeta,
        agePublicKey.isAcceptableOrUnknown(
          data['age_public_key']!,
          _agePublicKeyMeta,
        ),
      );
    }
    if (data.containsKey('hwid_enabled')) {
      context.handle(
        _hwidEnabledMeta,
        hwidEnabled.isAcceptableOrUnknown(
          data['hwid_enabled']!,
          _hwidEnabledMeta,
        ),
      );
    }
    if (data.containsKey('hwid')) {
      context.handle(
        _hwidMeta,
        hwid.isAcceptableOrUnknown(data['hwid']!, _hwidMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('upload_bytes')) {
      context.handle(
        _uploadBytesMeta,
        uploadBytes.isAcceptableOrUnknown(
          data['upload_bytes']!,
          _uploadBytesMeta,
        ),
      );
    }
    if (data.containsKey('download_bytes')) {
      context.handle(
        _downloadBytesMeta,
        downloadBytes.isAcceptableOrUnknown(
          data['download_bytes']!,
          _downloadBytesMeta,
        ),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('expire_timestamp')) {
      context.handle(
        _expireTimestampMeta,
        expireTimestamp.isAcceptableOrUnknown(
          data['expire_timestamp']!,
          _expireTimestampMeta,
        ),
      );
    }
    if (data.containsKey('user_info_updated_at')) {
      context.handle(
        _userInfoUpdatedAtMeta,
        userInfoUpdatedAt.isAcceptableOrUnknown(
          data['user_info_updated_at']!,
          _userInfoUpdatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubscriptionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubscriptionData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      userAgent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_agent'],
      ),
      panel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      ageSecretKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_secret_key'],
      ),
      agePublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_public_key'],
      ),
      hwidEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hwid_enabled'],
      )!,
      hwid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hwid'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      uploadBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upload_bytes'],
      ),
      downloadBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}download_bytes'],
      ),
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      expireTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expire_timestamp'],
      ),
      userInfoUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}user_info_updated_at'],
      ),
    );
  }

  @override
  $SubscriptionTable createAlias(String alias) {
    return $SubscriptionTable(attachedDatabase, alias);
  }
}

class SubscriptionData extends DataClass
    implements Insertable<SubscriptionData> {
  final int id;
  final String name;
  final String url;
  final String? userAgent;
  final String panel;
  final String mode;
  final String? ageSecretKey;
  final String? agePublicKey;
  final bool hwidEnabled;
  final String? hwid;
  final DateTime timestamp;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final int? expireTimestamp;
  final DateTime? userInfoUpdatedAt;
  const SubscriptionData({
    required this.id,
    required this.name,
    required this.url,
    this.userAgent,
    required this.panel,
    required this.mode,
    this.ageSecretKey,
    this.agePublicKey,
    required this.hwidEnabled,
    this.hwid,
    required this.timestamp,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireTimestamp,
    this.userInfoUpdatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || userAgent != null) {
      map['user_agent'] = Variable<String>(userAgent);
    }
    map['panel'] = Variable<String>(panel);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || ageSecretKey != null) {
      map['age_secret_key'] = Variable<String>(ageSecretKey);
    }
    if (!nullToAbsent || agePublicKey != null) {
      map['age_public_key'] = Variable<String>(agePublicKey);
    }
    map['hwid_enabled'] = Variable<bool>(hwidEnabled);
    if (!nullToAbsent || hwid != null) {
      map['hwid'] = Variable<String>(hwid);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || uploadBytes != null) {
      map['upload_bytes'] = Variable<int>(uploadBytes);
    }
    if (!nullToAbsent || downloadBytes != null) {
      map['download_bytes'] = Variable<int>(downloadBytes);
    }
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    if (!nullToAbsent || expireTimestamp != null) {
      map['expire_timestamp'] = Variable<int>(expireTimestamp);
    }
    if (!nullToAbsent || userInfoUpdatedAt != null) {
      map['user_info_updated_at'] = Variable<DateTime>(userInfoUpdatedAt);
    }
    return map;
  }

  SubscriptionCompanion toCompanion(bool nullToAbsent) {
    return SubscriptionCompanion(
      id: Value(id),
      name: Value(name),
      url: Value(url),
      userAgent: userAgent == null && nullToAbsent
          ? const Value.absent()
          : Value(userAgent),
      panel: Value(panel),
      mode: Value(mode),
      ageSecretKey: ageSecretKey == null && nullToAbsent
          ? const Value.absent()
          : Value(ageSecretKey),
      agePublicKey: agePublicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(agePublicKey),
      hwidEnabled: Value(hwidEnabled),
      hwid: hwid == null && nullToAbsent ? const Value.absent() : Value(hwid),
      timestamp: Value(timestamp),
      uploadBytes: uploadBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadBytes),
      downloadBytes: downloadBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadBytes),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      expireTimestamp: expireTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(expireTimestamp),
      userInfoUpdatedAt: userInfoUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(userInfoUpdatedAt),
    );
  }

  factory SubscriptionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubscriptionData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      userAgent: serializer.fromJson<String?>(json['userAgent']),
      panel: serializer.fromJson<String>(json['panel']),
      mode: serializer.fromJson<String>(json['mode']),
      ageSecretKey: serializer.fromJson<String?>(json['ageSecretKey']),
      agePublicKey: serializer.fromJson<String?>(json['agePublicKey']),
      hwidEnabled: serializer.fromJson<bool>(json['hwidEnabled']),
      hwid: serializer.fromJson<String?>(json['hwid']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      uploadBytes: serializer.fromJson<int?>(json['uploadBytes']),
      downloadBytes: serializer.fromJson<int?>(json['downloadBytes']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      expireTimestamp: serializer.fromJson<int?>(json['expireTimestamp']),
      userInfoUpdatedAt: serializer.fromJson<DateTime?>(
        json['userInfoUpdatedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'userAgent': serializer.toJson<String?>(userAgent),
      'panel': serializer.toJson<String>(panel),
      'mode': serializer.toJson<String>(mode),
      'ageSecretKey': serializer.toJson<String?>(ageSecretKey),
      'agePublicKey': serializer.toJson<String?>(agePublicKey),
      'hwidEnabled': serializer.toJson<bool>(hwidEnabled),
      'hwid': serializer.toJson<String?>(hwid),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'uploadBytes': serializer.toJson<int?>(uploadBytes),
      'downloadBytes': serializer.toJson<int?>(downloadBytes),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'expireTimestamp': serializer.toJson<int?>(expireTimestamp),
      'userInfoUpdatedAt': serializer.toJson<DateTime?>(userInfoUpdatedAt),
    };
  }

  SubscriptionData copyWith({
    int? id,
    String? name,
    String? url,
    Value<String?> userAgent = const Value.absent(),
    String? panel,
    String? mode,
    Value<String?> ageSecretKey = const Value.absent(),
    Value<String?> agePublicKey = const Value.absent(),
    bool? hwidEnabled,
    Value<String?> hwid = const Value.absent(),
    DateTime? timestamp,
    Value<int?> uploadBytes = const Value.absent(),
    Value<int?> downloadBytes = const Value.absent(),
    Value<int?> totalBytes = const Value.absent(),
    Value<int?> expireTimestamp = const Value.absent(),
    Value<DateTime?> userInfoUpdatedAt = const Value.absent(),
  }) => SubscriptionData(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    userAgent: userAgent.present ? userAgent.value : this.userAgent,
    panel: panel ?? this.panel,
    mode: mode ?? this.mode,
    ageSecretKey: ageSecretKey.present ? ageSecretKey.value : this.ageSecretKey,
    agePublicKey: agePublicKey.present ? agePublicKey.value : this.agePublicKey,
    hwidEnabled: hwidEnabled ?? this.hwidEnabled,
    hwid: hwid.present ? hwid.value : this.hwid,
    timestamp: timestamp ?? this.timestamp,
    uploadBytes: uploadBytes.present ? uploadBytes.value : this.uploadBytes,
    downloadBytes: downloadBytes.present
        ? downloadBytes.value
        : this.downloadBytes,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    expireTimestamp: expireTimestamp.present
        ? expireTimestamp.value
        : this.expireTimestamp,
    userInfoUpdatedAt: userInfoUpdatedAt.present
        ? userInfoUpdatedAt.value
        : this.userInfoUpdatedAt,
  );
  SubscriptionData copyWithCompanion(SubscriptionCompanion data) {
    return SubscriptionData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      userAgent: data.userAgent.present ? data.userAgent.value : this.userAgent,
      panel: data.panel.present ? data.panel.value : this.panel,
      mode: data.mode.present ? data.mode.value : this.mode,
      ageSecretKey: data.ageSecretKey.present
          ? data.ageSecretKey.value
          : this.ageSecretKey,
      agePublicKey: data.agePublicKey.present
          ? data.agePublicKey.value
          : this.agePublicKey,
      hwidEnabled: data.hwidEnabled.present
          ? data.hwidEnabled.value
          : this.hwidEnabled,
      hwid: data.hwid.present ? data.hwid.value : this.hwid,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      uploadBytes: data.uploadBytes.present
          ? data.uploadBytes.value
          : this.uploadBytes,
      downloadBytes: data.downloadBytes.present
          ? data.downloadBytes.value
          : this.downloadBytes,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      expireTimestamp: data.expireTimestamp.present
          ? data.expireTimestamp.value
          : this.expireTimestamp,
      userInfoUpdatedAt: data.userInfoUpdatedAt.present
          ? data.userInfoUpdatedAt.value
          : this.userInfoUpdatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubscriptionData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('userAgent: $userAgent, ')
          ..write('panel: $panel, ')
          ..write('mode: $mode, ')
          ..write('ageSecretKey: $ageSecretKey, ')
          ..write('agePublicKey: $agePublicKey, ')
          ..write('hwidEnabled: $hwidEnabled, ')
          ..write('hwid: $hwid, ')
          ..write('timestamp: $timestamp, ')
          ..write('uploadBytes: $uploadBytes, ')
          ..write('downloadBytes: $downloadBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('expireTimestamp: $expireTimestamp, ')
          ..write('userInfoUpdatedAt: $userInfoUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    url,
    userAgent,
    panel,
    mode,
    ageSecretKey,
    agePublicKey,
    hwidEnabled,
    hwid,
    timestamp,
    uploadBytes,
    downloadBytes,
    totalBytes,
    expireTimestamp,
    userInfoUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubscriptionData &&
          other.id == this.id &&
          other.name == this.name &&
          other.url == this.url &&
          other.userAgent == this.userAgent &&
          other.panel == this.panel &&
          other.mode == this.mode &&
          other.ageSecretKey == this.ageSecretKey &&
          other.agePublicKey == this.agePublicKey &&
          other.hwidEnabled == this.hwidEnabled &&
          other.hwid == this.hwid &&
          other.timestamp == this.timestamp &&
          other.uploadBytes == this.uploadBytes &&
          other.downloadBytes == this.downloadBytes &&
          other.totalBytes == this.totalBytes &&
          other.expireTimestamp == this.expireTimestamp &&
          other.userInfoUpdatedAt == this.userInfoUpdatedAt);
}

class SubscriptionCompanion extends UpdateCompanion<SubscriptionData> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> url;
  final Value<String?> userAgent;
  final Value<String> panel;
  final Value<String> mode;
  final Value<String?> ageSecretKey;
  final Value<String?> agePublicKey;
  final Value<bool> hwidEnabled;
  final Value<String?> hwid;
  final Value<DateTime> timestamp;
  final Value<int?> uploadBytes;
  final Value<int?> downloadBytes;
  final Value<int?> totalBytes;
  final Value<int?> expireTimestamp;
  final Value<DateTime?> userInfoUpdatedAt;
  const SubscriptionCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.userAgent = const Value.absent(),
    this.panel = const Value.absent(),
    this.mode = const Value.absent(),
    this.ageSecretKey = const Value.absent(),
    this.agePublicKey = const Value.absent(),
    this.hwidEnabled = const Value.absent(),
    this.hwid = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.uploadBytes = const Value.absent(),
    this.downloadBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.expireTimestamp = const Value.absent(),
    this.userInfoUpdatedAt = const Value.absent(),
  });
  SubscriptionCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String url,
    this.userAgent = const Value.absent(),
    this.panel = const Value.absent(),
    this.mode = const Value.absent(),
    this.ageSecretKey = const Value.absent(),
    this.agePublicKey = const Value.absent(),
    this.hwidEnabled = const Value.absent(),
    this.hwid = const Value.absent(),
    required DateTime timestamp,
    this.uploadBytes = const Value.absent(),
    this.downloadBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.expireTimestamp = const Value.absent(),
    this.userInfoUpdatedAt = const Value.absent(),
  }) : name = Value(name),
       url = Value(url),
       timestamp = Value(timestamp);
  static Insertable<SubscriptionData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? userAgent,
    Expression<String>? panel,
    Expression<String>? mode,
    Expression<String>? ageSecretKey,
    Expression<String>? agePublicKey,
    Expression<bool>? hwidEnabled,
    Expression<String>? hwid,
    Expression<DateTime>? timestamp,
    Expression<int>? uploadBytes,
    Expression<int>? downloadBytes,
    Expression<int>? totalBytes,
    Expression<int>? expireTimestamp,
    Expression<DateTime>? userInfoUpdatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (userAgent != null) 'user_agent': userAgent,
      if (panel != null) 'panel': panel,
      if (mode != null) 'mode': mode,
      if (ageSecretKey != null) 'age_secret_key': ageSecretKey,
      if (agePublicKey != null) 'age_public_key': agePublicKey,
      if (hwidEnabled != null) 'hwid_enabled': hwidEnabled,
      if (hwid != null) 'hwid': hwid,
      if (timestamp != null) 'timestamp': timestamp,
      if (uploadBytes != null) 'upload_bytes': uploadBytes,
      if (downloadBytes != null) 'download_bytes': downloadBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (expireTimestamp != null) 'expire_timestamp': expireTimestamp,
      if (userInfoUpdatedAt != null) 'user_info_updated_at': userInfoUpdatedAt,
    });
  }

  SubscriptionCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? url,
    Value<String?>? userAgent,
    Value<String>? panel,
    Value<String>? mode,
    Value<String?>? ageSecretKey,
    Value<String?>? agePublicKey,
    Value<bool>? hwidEnabled,
    Value<String?>? hwid,
    Value<DateTime>? timestamp,
    Value<int?>? uploadBytes,
    Value<int?>? downloadBytes,
    Value<int?>? totalBytes,
    Value<int?>? expireTimestamp,
    Value<DateTime?>? userInfoUpdatedAt,
  }) {
    return SubscriptionCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      userAgent: userAgent ?? this.userAgent,
      panel: panel ?? this.panel,
      mode: mode ?? this.mode,
      ageSecretKey: ageSecretKey ?? this.ageSecretKey,
      agePublicKey: agePublicKey ?? this.agePublicKey,
      hwidEnabled: hwidEnabled ?? this.hwidEnabled,
      hwid: hwid ?? this.hwid,
      timestamp: timestamp ?? this.timestamp,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      expireTimestamp: expireTimestamp ?? this.expireTimestamp,
      userInfoUpdatedAt: userInfoUpdatedAt ?? this.userInfoUpdatedAt,
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
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (userAgent.present) {
      map['user_agent'] = Variable<String>(userAgent.value);
    }
    if (panel.present) {
      map['panel'] = Variable<String>(panel.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (ageSecretKey.present) {
      map['age_secret_key'] = Variable<String>(ageSecretKey.value);
    }
    if (agePublicKey.present) {
      map['age_public_key'] = Variable<String>(agePublicKey.value);
    }
    if (hwidEnabled.present) {
      map['hwid_enabled'] = Variable<bool>(hwidEnabled.value);
    }
    if (hwid.present) {
      map['hwid'] = Variable<String>(hwid.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (uploadBytes.present) {
      map['upload_bytes'] = Variable<int>(uploadBytes.value);
    }
    if (downloadBytes.present) {
      map['download_bytes'] = Variable<int>(downloadBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (expireTimestamp.present) {
      map['expire_timestamp'] = Variable<int>(expireTimestamp.value);
    }
    if (userInfoUpdatedAt.present) {
      map['user_info_updated_at'] = Variable<DateTime>(userInfoUpdatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubscriptionCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('userAgent: $userAgent, ')
          ..write('panel: $panel, ')
          ..write('mode: $mode, ')
          ..write('ageSecretKey: $ageSecretKey, ')
          ..write('agePublicKey: $agePublicKey, ')
          ..write('hwidEnabled: $hwidEnabled, ')
          ..write('hwid: $hwid, ')
          ..write('timestamp: $timestamp, ')
          ..write('uploadBytes: $uploadBytes, ')
          ..write('downloadBytes: $downloadBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('expireTimestamp: $expireTimestamp, ')
          ..write('userInfoUpdatedAt: $userInfoUpdatedAt')
          ..write(')'))
        .toString();
  }
}

class $GeoDataTable extends GeoData with TableInfo<$GeoDataTable, GeoDataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GeoDataTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryCountMeta = const VerificationMeta(
    'categoryCount',
  );
  @override
  late final GeneratedColumn<int> categoryCount = GeneratedColumn<int>(
    'category_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleCountMeta = const VerificationMeta(
    'ruleCount',
  );
  @override
  late final GeneratedColumn<int> ruleCount = GeneratedColumn<int>(
    'rule_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedMeta = const VerificationMeta(
    'installed',
  );
  @override
  late final GeneratedColumn<bool> installed = GeneratedColumn<bool>(
    'installed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("installed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    url,
    timestamp,
    categoryCount,
    ruleCount,
    installed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'geo_data';
  @override
  VerificationContext validateIntegrity(
    Insertable<GeoDataData> instance, {
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
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('category_count')) {
      context.handle(
        _categoryCountMeta,
        categoryCount.isAcceptableOrUnknown(
          data['category_count']!,
          _categoryCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_categoryCountMeta);
    }
    if (data.containsKey('rule_count')) {
      context.handle(
        _ruleCountMeta,
        ruleCount.isAcceptableOrUnknown(data['rule_count']!, _ruleCountMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleCountMeta);
    }
    if (data.containsKey('installed')) {
      context.handle(
        _installedMeta,
        installed.isAcceptableOrUnknown(data['installed']!, _installedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GeoDataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GeoDataData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      categoryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_count'],
      )!,
      ruleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rule_count'],
      )!,
      installed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}installed'],
      )!,
    );
  }

  @override
  $GeoDataTable createAlias(String alias) {
    return $GeoDataTable(attachedDatabase, alias);
  }
}

class GeoDataData extends DataClass implements Insertable<GeoDataData> {
  final int id;
  final String name;
  final String type;
  final String url;
  final DateTime timestamp;
  final int categoryCount;
  final int ruleCount;
  final bool installed;
  const GeoDataData({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.timestamp,
    required this.categoryCount,
    required this.ruleCount,
    required this.installed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['url'] = Variable<String>(url);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['category_count'] = Variable<int>(categoryCount);
    map['rule_count'] = Variable<int>(ruleCount);
    map['installed'] = Variable<bool>(installed);
    return map;
  }

  GeoDataCompanion toCompanion(bool nullToAbsent) {
    return GeoDataCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      url: Value(url),
      timestamp: Value(timestamp),
      categoryCount: Value(categoryCount),
      ruleCount: Value(ruleCount),
      installed: Value(installed),
    );
  }

  factory GeoDataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GeoDataData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      url: serializer.fromJson<String>(json['url']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      categoryCount: serializer.fromJson<int>(json['categoryCount']),
      ruleCount: serializer.fromJson<int>(json['ruleCount']),
      installed: serializer.fromJson<bool>(json['installed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'url': serializer.toJson<String>(url),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'categoryCount': serializer.toJson<int>(categoryCount),
      'ruleCount': serializer.toJson<int>(ruleCount),
      'installed': serializer.toJson<bool>(installed),
    };
  }

  GeoDataData copyWith({
    int? id,
    String? name,
    String? type,
    String? url,
    DateTime? timestamp,
    int? categoryCount,
    int? ruleCount,
    bool? installed,
  }) => GeoDataData(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    url: url ?? this.url,
    timestamp: timestamp ?? this.timestamp,
    categoryCount: categoryCount ?? this.categoryCount,
    ruleCount: ruleCount ?? this.ruleCount,
    installed: installed ?? this.installed,
  );
  GeoDataData copyWithCompanion(GeoDataCompanion data) {
    return GeoDataData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      url: data.url.present ? data.url.value : this.url,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      categoryCount: data.categoryCount.present
          ? data.categoryCount.value
          : this.categoryCount,
      ruleCount: data.ruleCount.present ? data.ruleCount.value : this.ruleCount,
      installed: data.installed.present ? data.installed.value : this.installed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GeoDataData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('timestamp: $timestamp, ')
          ..write('categoryCount: $categoryCount, ')
          ..write('ruleCount: $ruleCount, ')
          ..write('installed: $installed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    url,
    timestamp,
    categoryCount,
    ruleCount,
    installed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GeoDataData &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.url == this.url &&
          other.timestamp == this.timestamp &&
          other.categoryCount == this.categoryCount &&
          other.ruleCount == this.ruleCount &&
          other.installed == this.installed);
}

class GeoDataCompanion extends UpdateCompanion<GeoDataData> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> url;
  final Value<DateTime> timestamp;
  final Value<int> categoryCount;
  final Value<int> ruleCount;
  final Value<bool> installed;
  const GeoDataCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.url = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.categoryCount = const Value.absent(),
    this.ruleCount = const Value.absent(),
    this.installed = const Value.absent(),
  });
  GeoDataCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String type,
    required String url,
    required DateTime timestamp,
    required int categoryCount,
    required int ruleCount,
    this.installed = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       url = Value(url),
       timestamp = Value(timestamp),
       categoryCount = Value(categoryCount),
       ruleCount = Value(ruleCount);
  static Insertable<GeoDataData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? url,
    Expression<DateTime>? timestamp,
    Expression<int>? categoryCount,
    Expression<int>? ruleCount,
    Expression<bool>? installed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (url != null) 'url': url,
      if (timestamp != null) 'timestamp': timestamp,
      if (categoryCount != null) 'category_count': categoryCount,
      if (ruleCount != null) 'rule_count': ruleCount,
      if (installed != null) 'installed': installed,
    });
  }

  GeoDataCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? url,
    Value<DateTime>? timestamp,
    Value<int>? categoryCount,
    Value<int>? ruleCount,
    Value<bool>? installed,
  }) {
    return GeoDataCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      timestamp: timestamp ?? this.timestamp,
      categoryCount: categoryCount ?? this.categoryCount,
      ruleCount: ruleCount ?? this.ruleCount,
      installed: installed ?? this.installed,
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
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (categoryCount.present) {
      map['category_count'] = Variable<int>(categoryCount.value);
    }
    if (ruleCount.present) {
      map['rule_count'] = Variable<int>(ruleCount.value);
    }
    if (installed.present) {
      map['installed'] = Variable<bool>(installed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GeoDataCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('timestamp: $timestamp, ')
          ..write('categoryCount: $categoryCount, ')
          ..write('ruleCount: $ruleCount, ')
          ..write('installed: $installed')
          ..write(')'))
        .toString();
  }
}

class $RoutingProfileTable extends RoutingProfile
    with TableInfo<$RoutingProfileTable, RoutingProfileData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutingProfileTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _advancedMeta = const VerificationMeta(
    'advanced',
  );
  @override
  late final GeneratedColumn<bool> advanced = GeneratedColumn<bool>(
    'advanced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("advanced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, advanced, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routing_profile';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoutingProfileData> instance, {
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
    if (data.containsKey('advanced')) {
      context.handle(
        _advancedMeta,
        advanced.isAcceptableOrUnknown(data['advanced']!, _advancedMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoutingProfileData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutingProfileData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      advanced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}advanced'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $RoutingProfileTable createAlias(String alias) {
    return $RoutingProfileTable(attachedDatabase, alias);
  }
}

class RoutingProfileData extends DataClass
    implements Insertable<RoutingProfileData> {
  final int id;
  final String name;
  final bool advanced;
  final String data;
  const RoutingProfileData({
    required this.id,
    required this.name,
    required this.advanced,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['advanced'] = Variable<bool>(advanced);
    map['data'] = Variable<String>(data);
    return map;
  }

  RoutingProfileCompanion toCompanion(bool nullToAbsent) {
    return RoutingProfileCompanion(
      id: Value(id),
      name: Value(name),
      advanced: Value(advanced),
      data: Value(data),
    );
  }

  factory RoutingProfileData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutingProfileData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      advanced: serializer.fromJson<bool>(json['advanced']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'advanced': serializer.toJson<bool>(advanced),
      'data': serializer.toJson<String>(data),
    };
  }

  RoutingProfileData copyWith({
    int? id,
    String? name,
    bool? advanced,
    String? data,
  }) => RoutingProfileData(
    id: id ?? this.id,
    name: name ?? this.name,
    advanced: advanced ?? this.advanced,
    data: data ?? this.data,
  );
  RoutingProfileData copyWithCompanion(RoutingProfileCompanion data) {
    return RoutingProfileData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      advanced: data.advanced.present ? data.advanced.value : this.advanced,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutingProfileData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('advanced: $advanced, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, advanced, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutingProfileData &&
          other.id == this.id &&
          other.name == this.name &&
          other.advanced == this.advanced &&
          other.data == this.data);
}

class RoutingProfileCompanion extends UpdateCompanion<RoutingProfileData> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> advanced;
  final Value<String> data;
  const RoutingProfileCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.advanced = const Value.absent(),
    this.data = const Value.absent(),
  });
  RoutingProfileCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.advanced = const Value.absent(),
    required String data,
  }) : name = Value(name),
       data = Value(data);
  static Insertable<RoutingProfileData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? advanced,
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (advanced != null) 'advanced': advanced,
      if (data != null) 'data': data,
    });
  }

  RoutingProfileCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? advanced,
    Value<String>? data,
  }) {
    return RoutingProfileCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      advanced: advanced ?? this.advanced,
      data: data ?? this.data,
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
    if (advanced.present) {
      map['advanced'] = Variable<bool>(advanced.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutingProfileCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('advanced: $advanced, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

class $ConnectionConfigTable extends ConnectionConfig
    with TableInfo<$ConnectionConfigTable, ConnectionConfigData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectionConfigTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _configurationJsonMeta = const VerificationMeta(
    'configurationJson',
  );
  @override
  late final GeneratedColumn<String> configurationJson =
      GeneratedColumn<String>(
        'configuration_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  @override
  List<GeneratedColumn> get $columns => [id, configurationJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connection_config';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConnectionConfigData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('configuration_json')) {
      context.handle(
        _configurationJsonMeta,
        configurationJson.isAcceptableOrUnknown(
          data['configuration_json']!,
          _configurationJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConnectionConfigData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConnectionConfigData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      configurationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}configuration_json'],
      )!,
    );
  }

  @override
  $ConnectionConfigTable createAlias(String alias) {
    return $ConnectionConfigTable(attachedDatabase, alias);
  }
}

class ConnectionConfigData extends DataClass
    implements Insertable<ConnectionConfigData> {
  final int id;
  final String configurationJson;
  const ConnectionConfigData({
    required this.id,
    required this.configurationJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['configuration_json'] = Variable<String>(configurationJson);
    return map;
  }

  ConnectionConfigCompanion toCompanion(bool nullToAbsent) {
    return ConnectionConfigCompanion(
      id: Value(id),
      configurationJson: Value(configurationJson),
    );
  }

  factory ConnectionConfigData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConnectionConfigData(
      id: serializer.fromJson<int>(json['id']),
      configurationJson: serializer.fromJson<String>(json['configurationJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'configurationJson': serializer.toJson<String>(configurationJson),
    };
  }

  ConnectionConfigData copyWith({int? id, String? configurationJson}) =>
      ConnectionConfigData(
        id: id ?? this.id,
        configurationJson: configurationJson ?? this.configurationJson,
      );
  ConnectionConfigData copyWithCompanion(ConnectionConfigCompanion data) {
    return ConnectionConfigData(
      id: data.id.present ? data.id.value : this.id,
      configurationJson: data.configurationJson.present
          ? data.configurationJson.value
          : this.configurationJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionConfigData(')
          ..write('id: $id, ')
          ..write('configurationJson: $configurationJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, configurationJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectionConfigData &&
          other.id == this.id &&
          other.configurationJson == this.configurationJson);
}

class ConnectionConfigCompanion extends UpdateCompanion<ConnectionConfigData> {
  final Value<int> id;
  final Value<String> configurationJson;
  const ConnectionConfigCompanion({
    this.id = const Value.absent(),
    this.configurationJson = const Value.absent(),
  });
  ConnectionConfigCompanion.insert({
    this.id = const Value.absent(),
    this.configurationJson = const Value.absent(),
  });
  static Insertable<ConnectionConfigData> custom({
    Expression<int>? id,
    Expression<String>? configurationJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (configurationJson != null) 'configuration_json': configurationJson,
    });
  }

  ConnectionConfigCompanion copyWith({
    Value<int>? id,
    Value<String>? configurationJson,
  }) {
    return ConnectionConfigCompanion(
      id: id ?? this.id,
      configurationJson: configurationJson ?? this.configurationJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (configurationJson.present) {
      map['configuration_json'] = Variable<String>(configurationJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionConfigCompanion(')
          ..write('id: $id, ')
          ..write('configurationJson: $configurationJson')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CoreConfigTable coreConfig = $CoreConfigTable(this);
  late final $SubscriptionTable subscription = $SubscriptionTable(this);
  late final $GeoDataTable geoData = $GeoDataTable(this);
  late final $RoutingProfileTable routingProfile = $RoutingProfileTable(this);
  late final $ConnectionConfigTable connectionConfig = $ConnectionConfigTable(
    this,
  );
  late final CoreConfigDao coreConfigDao = CoreConfigDao(this as AppDatabase);
  late final SubscriptionDao subscriptionDao = SubscriptionDao(
    this as AppDatabase,
  );
  late final GeoDataDao geoDataDao = GeoDataDao(this as AppDatabase);
  late final RoutingProfileDao routingProfileDao = RoutingProfileDao(
    this as AppDatabase,
  );
  late final ConnectionConfigDao connectionConfigDao = ConnectionConfigDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    coreConfig,
    subscription,
    geoData,
    routingProfile,
    connectionConfig,
  ];
}

typedef $$CoreConfigTableCreateCompanionBuilder = CoreConfigCompanion Function({
  Value<int> id,
  required String name,
  required String type,
  required String tags,
  Value<String?> data,
  required int delay,
  required int subId,
  Value<bool> favorite,
});
typedef $$CoreConfigTableUpdateCompanionBuilder = CoreConfigCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> type,
  Value<String> tags,
  Value<String?> data,
  Value<int> delay,
  Value<int> subId,
  Value<bool> favorite,
});

class $$CoreConfigTableFilterComposer
    extends Composer<_$AppDatabase, $CoreConfigTable> {
  $$CoreConfigTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get delay => $composableBuilder(
    column: $table.delay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subId => $composableBuilder(
    column: $table.subId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoreConfigTableOrderingComposer
    extends Composer<_$AppDatabase, $CoreConfigTable> {
  $$CoreConfigTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get delay => $composableBuilder(
    column: $table.delay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subId => $composableBuilder(
    column: $table.subId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoreConfigTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoreConfigTable> {
  $$CoreConfigTableAnnotationComposer({
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

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<int> get delay =>
      $composableBuilder(column: $table.delay, builder: (column) => column);

  GeneratedColumn<int> get subId =>
      $composableBuilder(column: $table.subId, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);
}

class $$CoreConfigTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoreConfigTable,
          CoreConfigData,
          $$CoreConfigTableFilterComposer,
          $$CoreConfigTableOrderingComposer,
          $$CoreConfigTableAnnotationComposer,
          $$CoreConfigTableCreateCompanionBuilder,
          $$CoreConfigTableUpdateCompanionBuilder,
          (
            CoreConfigData,
            BaseReferences<_$AppDatabase, $CoreConfigTable, CoreConfigData>,
          ),
          CoreConfigData,
          PrefetchHooks Function()
        > {
  $$CoreConfigTableTableManager(_$AppDatabase db, $CoreConfigTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoreConfigTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoreConfigTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoreConfigTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> data = const Value.absent(),
                Value<int> delay = const Value.absent(),
                Value<int> subId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
              }) => CoreConfigCompanion(
                id: id,
                name: name,
                type: type,
                tags: tags,
                data: data,
                delay: delay,
                subId: subId,
                favorite: favorite,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String type,
                required String tags,
                Value<String?> data = const Value.absent(),
                required int delay,
                required int subId,
                Value<bool> favorite = const Value.absent(),
              }) => CoreConfigCompanion.insert(
                id: id,
                name: name,
                type: type,
                tags: tags,
                data: data,
                delay: delay,
                subId: subId,
                favorite: favorite,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CoreConfigTable, CoreConfigData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CoreConfigTable,
                    CoreConfigData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoreConfigTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoreConfigTable,
      CoreConfigData,
      $$CoreConfigTableFilterComposer,
      $$CoreConfigTableOrderingComposer,
      $$CoreConfigTableAnnotationComposer,
      $$CoreConfigTableCreateCompanionBuilder,
      $$CoreConfigTableUpdateCompanionBuilder,
      (
        CoreConfigData,
        BaseReferences<_$AppDatabase, $CoreConfigTable, CoreConfigData>,
      ),
      CoreConfigData,
      PrefetchHooks Function()
    >;
typedef $$SubscriptionTableCreateCompanionBuilder =
    SubscriptionCompanion Function({
      Value<int> id,
      required String name,
      required String url,
      Value<String?> userAgent,
      Value<String> panel,
      Value<String> mode,
      Value<String?> ageSecretKey,
      Value<String?> agePublicKey,
      Value<bool> hwidEnabled,
      Value<String?> hwid,
      required DateTime timestamp,
      Value<int?> uploadBytes,
      Value<int?> downloadBytes,
      Value<int?> totalBytes,
      Value<int?> expireTimestamp,
      Value<DateTime?> userInfoUpdatedAt,
    });
typedef $$SubscriptionTableUpdateCompanionBuilder =
    SubscriptionCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> url,
      Value<String?> userAgent,
      Value<String> panel,
      Value<String> mode,
      Value<String?> ageSecretKey,
      Value<String?> agePublicKey,
      Value<bool> hwidEnabled,
      Value<String?> hwid,
      Value<DateTime> timestamp,
      Value<int?> uploadBytes,
      Value<int?> downloadBytes,
      Value<int?> totalBytes,
      Value<int?> expireTimestamp,
      Value<DateTime?> userInfoUpdatedAt,
    });

class $$SubscriptionTableFilterComposer
    extends Composer<_$AppDatabase, $SubscriptionTable> {
  $$SubscriptionTableFilterComposer({
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

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userAgent => $composableBuilder(
    column: $table.userAgent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get panel => $composableBuilder(
    column: $table.panel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ageSecretKey => $composableBuilder(
    column: $table.ageSecretKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agePublicKey => $composableBuilder(
    column: $table.agePublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hwidEnabled => $composableBuilder(
    column: $table.hwidEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hwid => $composableBuilder(
    column: $table.hwid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadBytes => $composableBuilder(
    column: $table.uploadBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downloadBytes => $composableBuilder(
    column: $table.downloadBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expireTimestamp => $composableBuilder(
    column: $table.expireTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get userInfoUpdatedAt => $composableBuilder(
    column: $table.userInfoUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SubscriptionTableOrderingComposer
    extends Composer<_$AppDatabase, $SubscriptionTable> {
  $$SubscriptionTableOrderingComposer({
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

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userAgent => $composableBuilder(
    column: $table.userAgent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get panel => $composableBuilder(
    column: $table.panel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ageSecretKey => $composableBuilder(
    column: $table.ageSecretKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agePublicKey => $composableBuilder(
    column: $table.agePublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hwidEnabled => $composableBuilder(
    column: $table.hwidEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hwid => $composableBuilder(
    column: $table.hwid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadBytes => $composableBuilder(
    column: $table.uploadBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downloadBytes => $composableBuilder(
    column: $table.downloadBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expireTimestamp => $composableBuilder(
    column: $table.expireTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get userInfoUpdatedAt => $composableBuilder(
    column: $table.userInfoUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SubscriptionTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubscriptionTable> {
  $$SubscriptionTableAnnotationComposer({
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

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get userAgent =>
      $composableBuilder(column: $table.userAgent, builder: (column) => column);

  GeneratedColumn<String> get panel =>
      $composableBuilder(column: $table.panel, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get ageSecretKey => $composableBuilder(
    column: $table.ageSecretKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agePublicKey => $composableBuilder(
    column: $table.agePublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hwidEnabled => $composableBuilder(
    column: $table.hwidEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hwid =>
      $composableBuilder(column: $table.hwid, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get uploadBytes => $composableBuilder(
    column: $table.uploadBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get downloadBytes => $composableBuilder(
    column: $table.downloadBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expireTimestamp => $composableBuilder(
    column: $table.expireTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get userInfoUpdatedAt => $composableBuilder(
    column: $table.userInfoUpdatedAt,
    builder: (column) => column,
  );
}

class $$SubscriptionTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubscriptionTable,
          SubscriptionData,
          $$SubscriptionTableFilterComposer,
          $$SubscriptionTableOrderingComposer,
          $$SubscriptionTableAnnotationComposer,
          $$SubscriptionTableCreateCompanionBuilder,
          $$SubscriptionTableUpdateCompanionBuilder,
          (
            SubscriptionData,
            BaseReferences<_$AppDatabase, $SubscriptionTable, SubscriptionData>,
          ),
          SubscriptionData,
          PrefetchHooks Function()
        > {
  $$SubscriptionTableTableManager(_$AppDatabase db, $SubscriptionTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubscriptionTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubscriptionTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubscriptionTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> userAgent = const Value.absent(),
                Value<String> panel = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> ageSecretKey = const Value.absent(),
                Value<String?> agePublicKey = const Value.absent(),
                Value<bool> hwidEnabled = const Value.absent(),
                Value<String?> hwid = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int?> uploadBytes = const Value.absent(),
                Value<int?> downloadBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<int?> expireTimestamp = const Value.absent(),
                Value<DateTime?> userInfoUpdatedAt = const Value.absent(),
              }) => SubscriptionCompanion(
                id: id,
                name: name,
                url: url,
                userAgent: userAgent,
                panel: panel,
                mode: mode,
                ageSecretKey: ageSecretKey,
                agePublicKey: agePublicKey,
                hwidEnabled: hwidEnabled,
                hwid: hwid,
                timestamp: timestamp,
                uploadBytes: uploadBytes,
                downloadBytes: downloadBytes,
                totalBytes: totalBytes,
                expireTimestamp: expireTimestamp,
                userInfoUpdatedAt: userInfoUpdatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String url,
                Value<String?> userAgent = const Value.absent(),
                Value<String> panel = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> ageSecretKey = const Value.absent(),
                Value<String?> agePublicKey = const Value.absent(),
                Value<bool> hwidEnabled = const Value.absent(),
                Value<String?> hwid = const Value.absent(),
                required DateTime timestamp,
                Value<int?> uploadBytes = const Value.absent(),
                Value<int?> downloadBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<int?> expireTimestamp = const Value.absent(),
                Value<DateTime?> userInfoUpdatedAt = const Value.absent(),
              }) => SubscriptionCompanion.insert(
                id: id,
                name: name,
                url: url,
                userAgent: userAgent,
                panel: panel,
                mode: mode,
                ageSecretKey: ageSecretKey,
                agePublicKey: agePublicKey,
                hwidEnabled: hwidEnabled,
                hwid: hwid,
                timestamp: timestamp,
                uploadBytes: uploadBytes,
                downloadBytes: downloadBytes,
                totalBytes: totalBytes,
                expireTimestamp: expireTimestamp,
                userInfoUpdatedAt: userInfoUpdatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubscriptionTable, SubscriptionData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SubscriptionTable,
                    SubscriptionData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SubscriptionTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubscriptionTable,
      SubscriptionData,
      $$SubscriptionTableFilterComposer,
      $$SubscriptionTableOrderingComposer,
      $$SubscriptionTableAnnotationComposer,
      $$SubscriptionTableCreateCompanionBuilder,
      $$SubscriptionTableUpdateCompanionBuilder,
      (
        SubscriptionData,
        BaseReferences<_$AppDatabase, $SubscriptionTable, SubscriptionData>,
      ),
      SubscriptionData,
      PrefetchHooks Function()
    >;
typedef $$GeoDataTableCreateCompanionBuilder = GeoDataCompanion Function({
  Value<int> id,
  required String name,
  required String type,
  required String url,
  required DateTime timestamp,
  required int categoryCount,
  required int ruleCount,
  Value<bool> installed,
});
typedef $$GeoDataTableUpdateCompanionBuilder = GeoDataCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> type,
  Value<String> url,
  Value<DateTime> timestamp,
  Value<int> categoryCount,
  Value<int> ruleCount,
  Value<bool> installed,
});

class $$GeoDataTableFilterComposer
    extends Composer<_$AppDatabase, $GeoDataTable> {
  $$GeoDataTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryCount => $composableBuilder(
    column: $table.categoryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ruleCount => $composableBuilder(
    column: $table.ruleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get installed => $composableBuilder(
    column: $table.installed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GeoDataTableOrderingComposer
    extends Composer<_$AppDatabase, $GeoDataTable> {
  $$GeoDataTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryCount => $composableBuilder(
    column: $table.categoryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ruleCount => $composableBuilder(
    column: $table.ruleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get installed => $composableBuilder(
    column: $table.installed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GeoDataTableAnnotationComposer
    extends Composer<_$AppDatabase, $GeoDataTable> {
  $$GeoDataTableAnnotationComposer({
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

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get categoryCount => $composableBuilder(
    column: $table.categoryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ruleCount =>
      $composableBuilder(column: $table.ruleCount, builder: (column) => column);

  GeneratedColumn<bool> get installed =>
      $composableBuilder(column: $table.installed, builder: (column) => column);
}

class $$GeoDataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GeoDataTable,
          GeoDataData,
          $$GeoDataTableFilterComposer,
          $$GeoDataTableOrderingComposer,
          $$GeoDataTableAnnotationComposer,
          $$GeoDataTableCreateCompanionBuilder,
          $$GeoDataTableUpdateCompanionBuilder,
          (
            GeoDataData,
            BaseReferences<_$AppDatabase, $GeoDataTable, GeoDataData>,
          ),
          GeoDataData,
          PrefetchHooks Function()
        > {
  $$GeoDataTableTableManager(_$AppDatabase db, $GeoDataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GeoDataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GeoDataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GeoDataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> categoryCount = const Value.absent(),
                Value<int> ruleCount = const Value.absent(),
                Value<bool> installed = const Value.absent(),
              }) => GeoDataCompanion(
                id: id,
                name: name,
                type: type,
                url: url,
                timestamp: timestamp,
                categoryCount: categoryCount,
                ruleCount: ruleCount,
                installed: installed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String type,
                required String url,
                required DateTime timestamp,
                required int categoryCount,
                required int ruleCount,
                Value<bool> installed = const Value.absent(),
              }) => GeoDataCompanion.insert(
                id: id,
                name: name,
                type: type,
                url: url,
                timestamp: timestamp,
                categoryCount: categoryCount,
                ruleCount: ruleCount,
                installed: installed,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GeoDataTable, GeoDataData>(table),
                  BaseReferences<_$AppDatabase, $GeoDataTable, GeoDataData>(
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

typedef $$GeoDataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GeoDataTable,
      GeoDataData,
      $$GeoDataTableFilterComposer,
      $$GeoDataTableOrderingComposer,
      $$GeoDataTableAnnotationComposer,
      $$GeoDataTableCreateCompanionBuilder,
      $$GeoDataTableUpdateCompanionBuilder,
      (GeoDataData, BaseReferences<_$AppDatabase, $GeoDataTable, GeoDataData>),
      GeoDataData,
      PrefetchHooks Function()
    >;
typedef $$RoutingProfileTableCreateCompanionBuilder =
    RoutingProfileCompanion Function({
      Value<int> id,
      required String name,
      Value<bool> advanced,
      required String data,
    });
typedef $$RoutingProfileTableUpdateCompanionBuilder =
    RoutingProfileCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<bool> advanced,
      Value<String> data,
    });

class $$RoutingProfileTableFilterComposer
    extends Composer<_$AppDatabase, $RoutingProfileTable> {
  $$RoutingProfileTableFilterComposer({
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

  ColumnFilters<bool> get advanced => $composableBuilder(
    column: $table.advanced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoutingProfileTableOrderingComposer
    extends Composer<_$AppDatabase, $RoutingProfileTable> {
  $$RoutingProfileTableOrderingComposer({
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

  ColumnOrderings<bool> get advanced => $composableBuilder(
    column: $table.advanced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoutingProfileTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoutingProfileTable> {
  $$RoutingProfileTableAnnotationComposer({
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

  GeneratedColumn<bool> get advanced =>
      $composableBuilder(column: $table.advanced, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$RoutingProfileTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoutingProfileTable,
          RoutingProfileData,
          $$RoutingProfileTableFilterComposer,
          $$RoutingProfileTableOrderingComposer,
          $$RoutingProfileTableAnnotationComposer,
          $$RoutingProfileTableCreateCompanionBuilder,
          $$RoutingProfileTableUpdateCompanionBuilder,
          (
            RoutingProfileData,
            BaseReferences<
              _$AppDatabase,
              $RoutingProfileTable,
              RoutingProfileData
            >,
          ),
          RoutingProfileData,
          PrefetchHooks Function()
        > {
  $$RoutingProfileTableTableManager(
    _$AppDatabase db,
    $RoutingProfileTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutingProfileTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutingProfileTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutingProfileTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> advanced = const Value.absent(),
                Value<String> data = const Value.absent(),
              }) => RoutingProfileCompanion(
                id: id,
                name: name,
                advanced: advanced,
                data: data,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> advanced = const Value.absent(),
                required String data,
              }) => RoutingProfileCompanion.insert(
                id: id,
                name: name,
                advanced: advanced,
                data: data,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RoutingProfileTable, RoutingProfileData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RoutingProfileTable,
                    RoutingProfileData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoutingProfileTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoutingProfileTable,
      RoutingProfileData,
      $$RoutingProfileTableFilterComposer,
      $$RoutingProfileTableOrderingComposer,
      $$RoutingProfileTableAnnotationComposer,
      $$RoutingProfileTableCreateCompanionBuilder,
      $$RoutingProfileTableUpdateCompanionBuilder,
      (
        RoutingProfileData,
        BaseReferences<_$AppDatabase, $RoutingProfileTable, RoutingProfileData>,
      ),
      RoutingProfileData,
      PrefetchHooks Function()
    >;
typedef $$ConnectionConfigTableCreateCompanionBuilder =
    ConnectionConfigCompanion Function({
      Value<int> id,
      Value<String> configurationJson,
    });
typedef $$ConnectionConfigTableUpdateCompanionBuilder =
    ConnectionConfigCompanion Function({
      Value<int> id,
      Value<String> configurationJson,
    });

class $$ConnectionConfigTableFilterComposer
    extends Composer<_$AppDatabase, $ConnectionConfigTable> {
  $$ConnectionConfigTableFilterComposer({
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

  ColumnFilters<String> get configurationJson => $composableBuilder(
    column: $table.configurationJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConnectionConfigTableOrderingComposer
    extends Composer<_$AppDatabase, $ConnectionConfigTable> {
  $$ConnectionConfigTableOrderingComposer({
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

  ColumnOrderings<String> get configurationJson => $composableBuilder(
    column: $table.configurationJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConnectionConfigTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConnectionConfigTable> {
  $$ConnectionConfigTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get configurationJson => $composableBuilder(
    column: $table.configurationJson,
    builder: (column) => column,
  );
}

class $$ConnectionConfigTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConnectionConfigTable,
          ConnectionConfigData,
          $$ConnectionConfigTableFilterComposer,
          $$ConnectionConfigTableOrderingComposer,
          $$ConnectionConfigTableAnnotationComposer,
          $$ConnectionConfigTableCreateCompanionBuilder,
          $$ConnectionConfigTableUpdateCompanionBuilder,
          (
            ConnectionConfigData,
            BaseReferences<
              _$AppDatabase,
              $ConnectionConfigTable,
              ConnectionConfigData
            >,
          ),
          ConnectionConfigData,
          PrefetchHooks Function()
        > {
  $$ConnectionConfigTableTableManager(
    _$AppDatabase db,
    $ConnectionConfigTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConnectionConfigTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConnectionConfigTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConnectionConfigTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> configurationJson = const Value.absent(),
              }) => ConnectionConfigCompanion(
                id: id,
                configurationJson: configurationJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> configurationJson = const Value.absent(),
              }) => ConnectionConfigCompanion.insert(
                id: id,
                configurationJson: configurationJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConnectionConfigTable, ConnectionConfigData>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ConnectionConfigTable,
                    ConnectionConfigData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConnectionConfigTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConnectionConfigTable,
      ConnectionConfigData,
      $$ConnectionConfigTableFilterComposer,
      $$ConnectionConfigTableOrderingComposer,
      $$ConnectionConfigTableAnnotationComposer,
      $$ConnectionConfigTableCreateCompanionBuilder,
      $$ConnectionConfigTableUpdateCompanionBuilder,
      (
        ConnectionConfigData,
        BaseReferences<
          _$AppDatabase,
          $ConnectionConfigTable,
          ConnectionConfigData
        >,
      ),
      ConnectionConfigData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CoreConfigTableTableManager get coreConfig =>
      $$CoreConfigTableTableManager(_db, _db.coreConfig);
  $$SubscriptionTableTableManager get subscription =>
      $$SubscriptionTableTableManager(_db, _db.subscription);
  $$GeoDataTableTableManager get geoData =>
      $$GeoDataTableTableManager(_db, _db.geoData);
  $$RoutingProfileTableTableManager get routingProfile =>
      $$RoutingProfileTableTableManager(_db, _db.routingProfile);
  $$ConnectionConfigTableTableManager get connectionConfig =>
      $$ConnectionConfigTableTableManager(_db, _db.connectionConfig);
}
