// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PendingChangesTable extends PendingChanges
    with TableInfo<$PendingChangesTable, PendingChangeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingChangesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _eventUuidMeta = const VerificationMeta(
    'eventUuid',
  );
  @override
  late final GeneratedColumn<String> eventUuid = GeneratedColumn<String>(
    'event_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changeTypeMeta = const VerificationMeta(
    'changeType',
  );
  @override
  late final GeneratedColumn<int> changeType = GeneratedColumn<int>(
    'change_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proposedStateJsonMeta = const VerificationMeta(
    'proposedStateJson',
  );
  @override
  late final GeneratedColumn<String> proposedStateJson =
      GeneratedColumn<String>(
        'proposed_state_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _applyAfterMeta = const VerificationMeta(
    'applyAfter',
  );
  @override
  late final GeneratedColumn<DateTime> applyAfter = GeneratedColumn<DateTime>(
    'apply_after',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promotedMeta = const VerificationMeta(
    'promoted',
  );
  @override
  late final GeneratedColumn<bool> promoted = GeneratedColumn<bool>(
    'promoted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("promoted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventUuid,
    changeType,
    proposedStateJson,
    description,
    createdAt,
    applyAfter,
    promoted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_changes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingChangeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('event_uuid')) {
      context.handle(
        _eventUuidMeta,
        eventUuid.isAcceptableOrUnknown(data['event_uuid']!, _eventUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_eventUuidMeta);
    }
    if (data.containsKey('change_type')) {
      context.handle(
        _changeTypeMeta,
        changeType.isAcceptableOrUnknown(data['change_type']!, _changeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_changeTypeMeta);
    }
    if (data.containsKey('proposed_state_json')) {
      context.handle(
        _proposedStateJsonMeta,
        proposedStateJson.isAcceptableOrUnknown(
          data['proposed_state_json']!,
          _proposedStateJsonMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('apply_after')) {
      context.handle(
        _applyAfterMeta,
        applyAfter.isAcceptableOrUnknown(data['apply_after']!, _applyAfterMeta),
      );
    } else if (isInserting) {
      context.missing(_applyAfterMeta);
    }
    if (data.containsKey('promoted')) {
      context.handle(
        _promotedMeta,
        promoted.isAcceptableOrUnknown(data['promoted']!, _promotedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingChangeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingChangeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      eventUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_uuid'],
      )!,
      changeType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_type'],
      )!,
      proposedStateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposed_state_json'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      applyAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}apply_after'],
      )!,
      promoted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}promoted'],
      )!,
    );
  }

  @override
  $PendingChangesTable createAlias(String alias) {
    return $PendingChangesTable(attachedDatabase, alias);
  }
}

class PendingChangeRow extends DataClass
    implements Insertable<PendingChangeRow> {
  final int id;

  /// UUID of the event whose loosening is queued (UUID stability, §8.9 item 3).
  final String eventUuid;

  /// Mirrors the firmware `change_type` byte (§9.5). See [PendingChangeType].
  final int changeType;

  /// Full proposed post-change state so promotion needs no re-derivation:
  /// a serialized Automation, a deletion marker, a negate-date, or a setting.
  final String proposedStateJson;

  /// Short human summary for the pending-changes UI ("gym SSID change").
  final String description;

  /// When the loosening was requested (wall clock, for display).
  final DateTime createdAt;

  /// Earliest wall-clock moment the change may take effect. The UI phrases this
  /// as "takes effect no earlier than <when>" — promotion is never earlier.
  final DateTime applyAfter;

  /// True once the app has actually re-pushed the promoted state to devices.
  final bool promoted;
  const PendingChangeRow({
    required this.id,
    required this.eventUuid,
    required this.changeType,
    required this.proposedStateJson,
    required this.description,
    required this.createdAt,
    required this.applyAfter,
    required this.promoted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['event_uuid'] = Variable<String>(eventUuid);
    map['change_type'] = Variable<int>(changeType);
    map['proposed_state_json'] = Variable<String>(proposedStateJson);
    map['description'] = Variable<String>(description);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['apply_after'] = Variable<DateTime>(applyAfter);
    map['promoted'] = Variable<bool>(promoted);
    return map;
  }

  PendingChangesCompanion toCompanion(bool nullToAbsent) {
    return PendingChangesCompanion(
      id: Value(id),
      eventUuid: Value(eventUuid),
      changeType: Value(changeType),
      proposedStateJson: Value(proposedStateJson),
      description: Value(description),
      createdAt: Value(createdAt),
      applyAfter: Value(applyAfter),
      promoted: Value(promoted),
    );
  }

  factory PendingChangeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingChangeRow(
      id: serializer.fromJson<int>(json['id']),
      eventUuid: serializer.fromJson<String>(json['eventUuid']),
      changeType: serializer.fromJson<int>(json['changeType']),
      proposedStateJson: serializer.fromJson<String>(json['proposedStateJson']),
      description: serializer.fromJson<String>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      applyAfter: serializer.fromJson<DateTime>(json['applyAfter']),
      promoted: serializer.fromJson<bool>(json['promoted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'eventUuid': serializer.toJson<String>(eventUuid),
      'changeType': serializer.toJson<int>(changeType),
      'proposedStateJson': serializer.toJson<String>(proposedStateJson),
      'description': serializer.toJson<String>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'applyAfter': serializer.toJson<DateTime>(applyAfter),
      'promoted': serializer.toJson<bool>(promoted),
    };
  }

  PendingChangeRow copyWith({
    int? id,
    String? eventUuid,
    int? changeType,
    String? proposedStateJson,
    String? description,
    DateTime? createdAt,
    DateTime? applyAfter,
    bool? promoted,
  }) => PendingChangeRow(
    id: id ?? this.id,
    eventUuid: eventUuid ?? this.eventUuid,
    changeType: changeType ?? this.changeType,
    proposedStateJson: proposedStateJson ?? this.proposedStateJson,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    applyAfter: applyAfter ?? this.applyAfter,
    promoted: promoted ?? this.promoted,
  );
  PendingChangeRow copyWithCompanion(PendingChangesCompanion data) {
    return PendingChangeRow(
      id: data.id.present ? data.id.value : this.id,
      eventUuid: data.eventUuid.present ? data.eventUuid.value : this.eventUuid,
      changeType: data.changeType.present
          ? data.changeType.value
          : this.changeType,
      proposedStateJson: data.proposedStateJson.present
          ? data.proposedStateJson.value
          : this.proposedStateJson,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      applyAfter: data.applyAfter.present
          ? data.applyAfter.value
          : this.applyAfter,
      promoted: data.promoted.present ? data.promoted.value : this.promoted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingChangeRow(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('changeType: $changeType, ')
          ..write('proposedStateJson: $proposedStateJson, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('applyAfter: $applyAfter, ')
          ..write('promoted: $promoted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventUuid,
    changeType,
    proposedStateJson,
    description,
    createdAt,
    applyAfter,
    promoted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingChangeRow &&
          other.id == this.id &&
          other.eventUuid == this.eventUuid &&
          other.changeType == this.changeType &&
          other.proposedStateJson == this.proposedStateJson &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.applyAfter == this.applyAfter &&
          other.promoted == this.promoted);
}

class PendingChangesCompanion extends UpdateCompanion<PendingChangeRow> {
  final Value<int> id;
  final Value<String> eventUuid;
  final Value<int> changeType;
  final Value<String> proposedStateJson;
  final Value<String> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> applyAfter;
  final Value<bool> promoted;
  const PendingChangesCompanion({
    this.id = const Value.absent(),
    this.eventUuid = const Value.absent(),
    this.changeType = const Value.absent(),
    this.proposedStateJson = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.applyAfter = const Value.absent(),
    this.promoted = const Value.absent(),
  });
  PendingChangesCompanion.insert({
    this.id = const Value.absent(),
    required String eventUuid,
    required int changeType,
    this.proposedStateJson = const Value.absent(),
    this.description = const Value.absent(),
    required DateTime createdAt,
    required DateTime applyAfter,
    this.promoted = const Value.absent(),
  }) : eventUuid = Value(eventUuid),
       changeType = Value(changeType),
       createdAt = Value(createdAt),
       applyAfter = Value(applyAfter);
  static Insertable<PendingChangeRow> custom({
    Expression<int>? id,
    Expression<String>? eventUuid,
    Expression<int>? changeType,
    Expression<String>? proposedStateJson,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? applyAfter,
    Expression<bool>? promoted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventUuid != null) 'event_uuid': eventUuid,
      if (changeType != null) 'change_type': changeType,
      if (proposedStateJson != null) 'proposed_state_json': proposedStateJson,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (applyAfter != null) 'apply_after': applyAfter,
      if (promoted != null) 'promoted': promoted,
    });
  }

  PendingChangesCompanion copyWith({
    Value<int>? id,
    Value<String>? eventUuid,
    Value<int>? changeType,
    Value<String>? proposedStateJson,
    Value<String>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? applyAfter,
    Value<bool>? promoted,
  }) {
    return PendingChangesCompanion(
      id: id ?? this.id,
      eventUuid: eventUuid ?? this.eventUuid,
      changeType: changeType ?? this.changeType,
      proposedStateJson: proposedStateJson ?? this.proposedStateJson,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      applyAfter: applyAfter ?? this.applyAfter,
      promoted: promoted ?? this.promoted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (eventUuid.present) {
      map['event_uuid'] = Variable<String>(eventUuid.value);
    }
    if (changeType.present) {
      map['change_type'] = Variable<int>(changeType.value);
    }
    if (proposedStateJson.present) {
      map['proposed_state_json'] = Variable<String>(proposedStateJson.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (applyAfter.present) {
      map['apply_after'] = Variable<DateTime>(applyAfter.value);
    }
    if (promoted.present) {
      map['promoted'] = Variable<bool>(promoted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingChangesCompanion(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('changeType: $changeType, ')
          ..write('proposedStateJson: $proposedStateJson, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('applyAfter: $applyAfter, ')
          ..write('promoted: $promoted')
          ..write(')'))
        .toString();
  }
}

class $EmergencyPassSpendsTable extends EmergencyPassSpends
    with TableInfo<$EmergencyPassSpendsTable, EmergencyPassSpendRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmergencyPassSpendsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _eventUuidMeta = const VerificationMeta(
    'eventUuid',
  );
  @override
  late final GeneratedColumn<String> eventUuid = GeneratedColumn<String>(
    'event_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _forDateMeta = const VerificationMeta(
    'forDate',
  );
  @override
  late final GeneratedColumn<int> forDate = GeneratedColumn<int>(
    'for_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spentAtMeta = const VerificationMeta(
    'spentAt',
  );
  @override
  late final GeneratedColumn<DateTime> spentAt = GeneratedColumn<DateTime>(
    'spent_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushedMeta = const VerificationMeta('pushed');
  @override
  late final GeneratedColumn<bool> pushed = GeneratedColumn<bool>(
    'pushed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pushed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventUuid,
    forDate,
    spentAt,
    pushed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emergency_pass_spends';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmergencyPassSpendRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('event_uuid')) {
      context.handle(
        _eventUuidMeta,
        eventUuid.isAcceptableOrUnknown(data['event_uuid']!, _eventUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_eventUuidMeta);
    }
    if (data.containsKey('for_date')) {
      context.handle(
        _forDateMeta,
        forDate.isAcceptableOrUnknown(data['for_date']!, _forDateMeta),
      );
    } else if (isInserting) {
      context.missing(_forDateMeta);
    }
    if (data.containsKey('spent_at')) {
      context.handle(
        _spentAtMeta,
        spentAt.isAcceptableOrUnknown(data['spent_at']!, _spentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_spentAtMeta);
    }
    if (data.containsKey('pushed')) {
      context.handle(
        _pushedMeta,
        pushed.isAcceptableOrUnknown(data['pushed']!, _pushedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmergencyPassSpendRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmergencyPassSpendRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      eventUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_uuid'],
      )!,
      forDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}for_date'],
      )!,
      spentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}spent_at'],
      )!,
      pushed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pushed'],
      )!,
    );
  }

  @override
  $EmergencyPassSpendsTable createAlias(String alias) {
    return $EmergencyPassSpendsTable(attachedDatabase, alias);
  }
}

class EmergencyPassSpendRow extends DataClass
    implements Insertable<EmergencyPassSpendRow> {
  final int id;

  /// The commitment the pass was spent on.
  final String eventUuid;

  /// The single day skipped, as YYYYMMDD (matches the `…001B` wire format).
  final int forDate;

  /// When the pass was spent (wall clock; also the rolling-window aging basis).
  final DateTime spentAt;

  /// True once the resulting one-off negate has been pushed to devices (a spend
  /// on an active window re-pushes the schedule immediately, §8.10).
  final bool pushed;
  const EmergencyPassSpendRow({
    required this.id,
    required this.eventUuid,
    required this.forDate,
    required this.spentAt,
    required this.pushed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['event_uuid'] = Variable<String>(eventUuid);
    map['for_date'] = Variable<int>(forDate);
    map['spent_at'] = Variable<DateTime>(spentAt);
    map['pushed'] = Variable<bool>(pushed);
    return map;
  }

  EmergencyPassSpendsCompanion toCompanion(bool nullToAbsent) {
    return EmergencyPassSpendsCompanion(
      id: Value(id),
      eventUuid: Value(eventUuid),
      forDate: Value(forDate),
      spentAt: Value(spentAt),
      pushed: Value(pushed),
    );
  }

  factory EmergencyPassSpendRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmergencyPassSpendRow(
      id: serializer.fromJson<int>(json['id']),
      eventUuid: serializer.fromJson<String>(json['eventUuid']),
      forDate: serializer.fromJson<int>(json['forDate']),
      spentAt: serializer.fromJson<DateTime>(json['spentAt']),
      pushed: serializer.fromJson<bool>(json['pushed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'eventUuid': serializer.toJson<String>(eventUuid),
      'forDate': serializer.toJson<int>(forDate),
      'spentAt': serializer.toJson<DateTime>(spentAt),
      'pushed': serializer.toJson<bool>(pushed),
    };
  }

  EmergencyPassSpendRow copyWith({
    int? id,
    String? eventUuid,
    int? forDate,
    DateTime? spentAt,
    bool? pushed,
  }) => EmergencyPassSpendRow(
    id: id ?? this.id,
    eventUuid: eventUuid ?? this.eventUuid,
    forDate: forDate ?? this.forDate,
    spentAt: spentAt ?? this.spentAt,
    pushed: pushed ?? this.pushed,
  );
  EmergencyPassSpendRow copyWithCompanion(EmergencyPassSpendsCompanion data) {
    return EmergencyPassSpendRow(
      id: data.id.present ? data.id.value : this.id,
      eventUuid: data.eventUuid.present ? data.eventUuid.value : this.eventUuid,
      forDate: data.forDate.present ? data.forDate.value : this.forDate,
      spentAt: data.spentAt.present ? data.spentAt.value : this.spentAt,
      pushed: data.pushed.present ? data.pushed.value : this.pushed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmergencyPassSpendRow(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('forDate: $forDate, ')
          ..write('spentAt: $spentAt, ')
          ..write('pushed: $pushed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, eventUuid, forDate, spentAt, pushed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmergencyPassSpendRow &&
          other.id == this.id &&
          other.eventUuid == this.eventUuid &&
          other.forDate == this.forDate &&
          other.spentAt == this.spentAt &&
          other.pushed == this.pushed);
}

class EmergencyPassSpendsCompanion
    extends UpdateCompanion<EmergencyPassSpendRow> {
  final Value<int> id;
  final Value<String> eventUuid;
  final Value<int> forDate;
  final Value<DateTime> spentAt;
  final Value<bool> pushed;
  const EmergencyPassSpendsCompanion({
    this.id = const Value.absent(),
    this.eventUuid = const Value.absent(),
    this.forDate = const Value.absent(),
    this.spentAt = const Value.absent(),
    this.pushed = const Value.absent(),
  });
  EmergencyPassSpendsCompanion.insert({
    this.id = const Value.absent(),
    required String eventUuid,
    required int forDate,
    required DateTime spentAt,
    this.pushed = const Value.absent(),
  }) : eventUuid = Value(eventUuid),
       forDate = Value(forDate),
       spentAt = Value(spentAt);
  static Insertable<EmergencyPassSpendRow> custom({
    Expression<int>? id,
    Expression<String>? eventUuid,
    Expression<int>? forDate,
    Expression<DateTime>? spentAt,
    Expression<bool>? pushed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventUuid != null) 'event_uuid': eventUuid,
      if (forDate != null) 'for_date': forDate,
      if (spentAt != null) 'spent_at': spentAt,
      if (pushed != null) 'pushed': pushed,
    });
  }

  EmergencyPassSpendsCompanion copyWith({
    Value<int>? id,
    Value<String>? eventUuid,
    Value<int>? forDate,
    Value<DateTime>? spentAt,
    Value<bool>? pushed,
  }) {
    return EmergencyPassSpendsCompanion(
      id: id ?? this.id,
      eventUuid: eventUuid ?? this.eventUuid,
      forDate: forDate ?? this.forDate,
      spentAt: spentAt ?? this.spentAt,
      pushed: pushed ?? this.pushed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (eventUuid.present) {
      map['event_uuid'] = Variable<String>(eventUuid.value);
    }
    if (forDate.present) {
      map['for_date'] = Variable<int>(forDate.value);
    }
    if (spentAt.present) {
      map['spent_at'] = Variable<DateTime>(spentAt.value);
    }
    if (pushed.present) {
      map['pushed'] = Variable<bool>(pushed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmergencyPassSpendsCompanion(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('forDate: $forDate, ')
          ..write('spentAt: $spentAt, ')
          ..write('pushed: $pushed')
          ..write(')'))
        .toString();
  }
}

class $AuditTrailTable extends AuditTrail
    with TableInfo<$AuditTrailTable, AuditEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditTrailTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventUuidMeta = const VerificationMeta(
    'eventUuid',
  );
  @override
  late final GeneratedColumn<String> eventUuid = GeneratedColumn<String>(
    'event_uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timestamp,
    category,
    eventUuid,
    detail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_trail';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('event_uuid')) {
      context.handle(
        _eventUuidMeta,
        eventUuid.isAcceptableOrUnknown(data['event_uuid']!, _eventUuidMeta),
      );
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      eventUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_uuid'],
      ),
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      )!,
    );
  }

  @override
  $AuditTrailTable createAlias(String alias) {
    return $AuditTrailTable(attachedDatabase, alias);
  }
}

class AuditEntryRow extends DataClass implements Insertable<AuditEntryRow> {
  final int id;
  final DateTime timestamp;

  /// e.g. `pass_spent`, `pass_allowance_changed`, `loosening_queued`,
  /// `loosening_promoted`, `loosening_cancelled`, `tightening_applied`.
  final String category;
  final String? eventUuid;

  /// Human-readable detail line, voice-guide compliant.
  final String detail;
  const AuditEntryRow({
    required this.id,
    required this.timestamp,
    required this.category,
    this.eventUuid,
    required this.detail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || eventUuid != null) {
      map['event_uuid'] = Variable<String>(eventUuid);
    }
    map['detail'] = Variable<String>(detail);
    return map;
  }

  AuditTrailCompanion toCompanion(bool nullToAbsent) {
    return AuditTrailCompanion(
      id: Value(id),
      timestamp: Value(timestamp),
      category: Value(category),
      eventUuid: eventUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(eventUuid),
      detail: Value(detail),
    );
  }

  factory AuditEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEntryRow(
      id: serializer.fromJson<int>(json['id']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      category: serializer.fromJson<String>(json['category']),
      eventUuid: serializer.fromJson<String?>(json['eventUuid']),
      detail: serializer.fromJson<String>(json['detail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'category': serializer.toJson<String>(category),
      'eventUuid': serializer.toJson<String?>(eventUuid),
      'detail': serializer.toJson<String>(detail),
    };
  }

  AuditEntryRow copyWith({
    int? id,
    DateTime? timestamp,
    String? category,
    Value<String?> eventUuid = const Value.absent(),
    String? detail,
  }) => AuditEntryRow(
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    category: category ?? this.category,
    eventUuid: eventUuid.present ? eventUuid.value : this.eventUuid,
    detail: detail ?? this.detail,
  );
  AuditEntryRow copyWithCompanion(AuditTrailCompanion data) {
    return AuditEntryRow(
      id: data.id.present ? data.id.value : this.id,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      category: data.category.present ? data.category.value : this.category,
      eventUuid: data.eventUuid.present ? data.eventUuid.value : this.eventUuid,
      detail: data.detail.present ? data.detail.value : this.detail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEntryRow(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('category: $category, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, timestamp, category, eventUuid, detail);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEntryRow &&
          other.id == this.id &&
          other.timestamp == this.timestamp &&
          other.category == this.category &&
          other.eventUuid == this.eventUuid &&
          other.detail == this.detail);
}

class AuditTrailCompanion extends UpdateCompanion<AuditEntryRow> {
  final Value<int> id;
  final Value<DateTime> timestamp;
  final Value<String> category;
  final Value<String?> eventUuid;
  final Value<String> detail;
  const AuditTrailCompanion({
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.category = const Value.absent(),
    this.eventUuid = const Value.absent(),
    this.detail = const Value.absent(),
  });
  AuditTrailCompanion.insert({
    this.id = const Value.absent(),
    required DateTime timestamp,
    required String category,
    this.eventUuid = const Value.absent(),
    this.detail = const Value.absent(),
  }) : timestamp = Value(timestamp),
       category = Value(category);
  static Insertable<AuditEntryRow> custom({
    Expression<int>? id,
    Expression<DateTime>? timestamp,
    Expression<String>? category,
    Expression<String>? eventUuid,
    Expression<String>? detail,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp,
      if (category != null) 'category': category,
      if (eventUuid != null) 'event_uuid': eventUuid,
      if (detail != null) 'detail': detail,
    });
  }

  AuditTrailCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? timestamp,
    Value<String>? category,
    Value<String?>? eventUuid,
    Value<String>? detail,
  }) {
    return AuditTrailCompanion(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      eventUuid: eventUuid ?? this.eventUuid,
      detail: detail ?? this.detail,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (eventUuid.present) {
      map['event_uuid'] = Variable<String>(eventUuid.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditTrailCompanion(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('category: $category, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PendingChangesTable pendingChanges = $PendingChangesTable(this);
  late final $EmergencyPassSpendsTable emergencyPassSpends =
      $EmergencyPassSpendsTable(this);
  late final $AuditTrailTable auditTrail = $AuditTrailTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pendingChanges,
    emergencyPassSpends,
    auditTrail,
  ];
}

typedef $$PendingChangesTableCreateCompanionBuilder =
    PendingChangesCompanion Function({
      Value<int> id,
      required String eventUuid,
      required int changeType,
      Value<String> proposedStateJson,
      Value<String> description,
      required DateTime createdAt,
      required DateTime applyAfter,
      Value<bool> promoted,
    });
typedef $$PendingChangesTableUpdateCompanionBuilder =
    PendingChangesCompanion Function({
      Value<int> id,
      Value<String> eventUuid,
      Value<int> changeType,
      Value<String> proposedStateJson,
      Value<String> description,
      Value<DateTime> createdAt,
      Value<DateTime> applyAfter,
      Value<bool> promoted,
    });

class $$PendingChangesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingChangesTable> {
  $$PendingChangesTableFilterComposer({
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

  ColumnFilters<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changeType => $composableBuilder(
    column: $table.changeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proposedStateJson => $composableBuilder(
    column: $table.proposedStateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get applyAfter => $composableBuilder(
    column: $table.applyAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get promoted => $composableBuilder(
    column: $table.promoted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingChangesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingChangesTable> {
  $$PendingChangesTableOrderingComposer({
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

  ColumnOrderings<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changeType => $composableBuilder(
    column: $table.changeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proposedStateJson => $composableBuilder(
    column: $table.proposedStateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get applyAfter => $composableBuilder(
    column: $table.applyAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get promoted => $composableBuilder(
    column: $table.promoted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingChangesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingChangesTable> {
  $$PendingChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventUuid =>
      $composableBuilder(column: $table.eventUuid, builder: (column) => column);

  GeneratedColumn<int> get changeType => $composableBuilder(
    column: $table.changeType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get proposedStateJson => $composableBuilder(
    column: $table.proposedStateJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get applyAfter => $composableBuilder(
    column: $table.applyAfter,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get promoted =>
      $composableBuilder(column: $table.promoted, builder: (column) => column);
}

class $$PendingChangesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingChangesTable,
          PendingChangeRow,
          $$PendingChangesTableFilterComposer,
          $$PendingChangesTableOrderingComposer,
          $$PendingChangesTableAnnotationComposer,
          $$PendingChangesTableCreateCompanionBuilder,
          $$PendingChangesTableUpdateCompanionBuilder,
          (
            PendingChangeRow,
            BaseReferences<
              _$AppDatabase,
              $PendingChangesTable,
              PendingChangeRow
            >,
          ),
          PendingChangeRow,
          PrefetchHooks Function()
        > {
  $$PendingChangesTableTableManager(
    _$AppDatabase db,
    $PendingChangesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingChangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> eventUuid = const Value.absent(),
                Value<int> changeType = const Value.absent(),
                Value<String> proposedStateJson = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> applyAfter = const Value.absent(),
                Value<bool> promoted = const Value.absent(),
              }) => PendingChangesCompanion(
                id: id,
                eventUuid: eventUuid,
                changeType: changeType,
                proposedStateJson: proposedStateJson,
                description: description,
                createdAt: createdAt,
                applyAfter: applyAfter,
                promoted: promoted,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String eventUuid,
                required int changeType,
                Value<String> proposedStateJson = const Value.absent(),
                Value<String> description = const Value.absent(),
                required DateTime createdAt,
                required DateTime applyAfter,
                Value<bool> promoted = const Value.absent(),
              }) => PendingChangesCompanion.insert(
                id: id,
                eventUuid: eventUuid,
                changeType: changeType,
                proposedStateJson: proposedStateJson,
                description: description,
                createdAt: createdAt,
                applyAfter: applyAfter,
                promoted: promoted,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingChangesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingChangesTable,
      PendingChangeRow,
      $$PendingChangesTableFilterComposer,
      $$PendingChangesTableOrderingComposer,
      $$PendingChangesTableAnnotationComposer,
      $$PendingChangesTableCreateCompanionBuilder,
      $$PendingChangesTableUpdateCompanionBuilder,
      (
        PendingChangeRow,
        BaseReferences<_$AppDatabase, $PendingChangesTable, PendingChangeRow>,
      ),
      PendingChangeRow,
      PrefetchHooks Function()
    >;
typedef $$EmergencyPassSpendsTableCreateCompanionBuilder =
    EmergencyPassSpendsCompanion Function({
      Value<int> id,
      required String eventUuid,
      required int forDate,
      required DateTime spentAt,
      Value<bool> pushed,
    });
typedef $$EmergencyPassSpendsTableUpdateCompanionBuilder =
    EmergencyPassSpendsCompanion Function({
      Value<int> id,
      Value<String> eventUuid,
      Value<int> forDate,
      Value<DateTime> spentAt,
      Value<bool> pushed,
    });

class $$EmergencyPassSpendsTableFilterComposer
    extends Composer<_$AppDatabase, $EmergencyPassSpendsTable> {
  $$EmergencyPassSpendsTableFilterComposer({
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

  ColumnFilters<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get forDate => $composableBuilder(
    column: $table.forDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get spentAt => $composableBuilder(
    column: $table.spentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pushed => $composableBuilder(
    column: $table.pushed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EmergencyPassSpendsTableOrderingComposer
    extends Composer<_$AppDatabase, $EmergencyPassSpendsTable> {
  $$EmergencyPassSpendsTableOrderingComposer({
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

  ColumnOrderings<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get forDate => $composableBuilder(
    column: $table.forDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get spentAt => $composableBuilder(
    column: $table.spentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pushed => $composableBuilder(
    column: $table.pushed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EmergencyPassSpendsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmergencyPassSpendsTable> {
  $$EmergencyPassSpendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventUuid =>
      $composableBuilder(column: $table.eventUuid, builder: (column) => column);

  GeneratedColumn<int> get forDate =>
      $composableBuilder(column: $table.forDate, builder: (column) => column);

  GeneratedColumn<DateTime> get spentAt =>
      $composableBuilder(column: $table.spentAt, builder: (column) => column);

  GeneratedColumn<bool> get pushed =>
      $composableBuilder(column: $table.pushed, builder: (column) => column);
}

class $$EmergencyPassSpendsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmergencyPassSpendsTable,
          EmergencyPassSpendRow,
          $$EmergencyPassSpendsTableFilterComposer,
          $$EmergencyPassSpendsTableOrderingComposer,
          $$EmergencyPassSpendsTableAnnotationComposer,
          $$EmergencyPassSpendsTableCreateCompanionBuilder,
          $$EmergencyPassSpendsTableUpdateCompanionBuilder,
          (
            EmergencyPassSpendRow,
            BaseReferences<
              _$AppDatabase,
              $EmergencyPassSpendsTable,
              EmergencyPassSpendRow
            >,
          ),
          EmergencyPassSpendRow,
          PrefetchHooks Function()
        > {
  $$EmergencyPassSpendsTableTableManager(
    _$AppDatabase db,
    $EmergencyPassSpendsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmergencyPassSpendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmergencyPassSpendsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EmergencyPassSpendsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> eventUuid = const Value.absent(),
                Value<int> forDate = const Value.absent(),
                Value<DateTime> spentAt = const Value.absent(),
                Value<bool> pushed = const Value.absent(),
              }) => EmergencyPassSpendsCompanion(
                id: id,
                eventUuid: eventUuid,
                forDate: forDate,
                spentAt: spentAt,
                pushed: pushed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String eventUuid,
                required int forDate,
                required DateTime spentAt,
                Value<bool> pushed = const Value.absent(),
              }) => EmergencyPassSpendsCompanion.insert(
                id: id,
                eventUuid: eventUuid,
                forDate: forDate,
                spentAt: spentAt,
                pushed: pushed,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EmergencyPassSpendsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmergencyPassSpendsTable,
      EmergencyPassSpendRow,
      $$EmergencyPassSpendsTableFilterComposer,
      $$EmergencyPassSpendsTableOrderingComposer,
      $$EmergencyPassSpendsTableAnnotationComposer,
      $$EmergencyPassSpendsTableCreateCompanionBuilder,
      $$EmergencyPassSpendsTableUpdateCompanionBuilder,
      (
        EmergencyPassSpendRow,
        BaseReferences<
          _$AppDatabase,
          $EmergencyPassSpendsTable,
          EmergencyPassSpendRow
        >,
      ),
      EmergencyPassSpendRow,
      PrefetchHooks Function()
    >;
typedef $$AuditTrailTableCreateCompanionBuilder =
    AuditTrailCompanion Function({
      Value<int> id,
      required DateTime timestamp,
      required String category,
      Value<String?> eventUuid,
      Value<String> detail,
    });
typedef $$AuditTrailTableUpdateCompanionBuilder =
    AuditTrailCompanion Function({
      Value<int> id,
      Value<DateTime> timestamp,
      Value<String> category,
      Value<String?> eventUuid,
      Value<String> detail,
    });

class $$AuditTrailTableFilterComposer
    extends Composer<_$AppDatabase, $AuditTrailTable> {
  $$AuditTrailTableFilterComposer({
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

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditTrailTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditTrailTable> {
  $$AuditTrailTableOrderingComposer({
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

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditTrailTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditTrailTable> {
  $$AuditTrailTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get eventUuid =>
      $composableBuilder(column: $table.eventUuid, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);
}

class $$AuditTrailTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditTrailTable,
          AuditEntryRow,
          $$AuditTrailTableFilterComposer,
          $$AuditTrailTableOrderingComposer,
          $$AuditTrailTableAnnotationComposer,
          $$AuditTrailTableCreateCompanionBuilder,
          $$AuditTrailTableUpdateCompanionBuilder,
          (
            AuditEntryRow,
            BaseReferences<_$AppDatabase, $AuditTrailTable, AuditEntryRow>,
          ),
          AuditEntryRow,
          PrefetchHooks Function()
        > {
  $$AuditTrailTableTableManager(_$AppDatabase db, $AuditTrailTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditTrailTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditTrailTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditTrailTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> eventUuid = const Value.absent(),
                Value<String> detail = const Value.absent(),
              }) => AuditTrailCompanion(
                id: id,
                timestamp: timestamp,
                category: category,
                eventUuid: eventUuid,
                detail: detail,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime timestamp,
                required String category,
                Value<String?> eventUuid = const Value.absent(),
                Value<String> detail = const Value.absent(),
              }) => AuditTrailCompanion.insert(
                id: id,
                timestamp: timestamp,
                category: category,
                eventUuid: eventUuid,
                detail: detail,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditTrailTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditTrailTable,
      AuditEntryRow,
      $$AuditTrailTableFilterComposer,
      $$AuditTrailTableOrderingComposer,
      $$AuditTrailTableAnnotationComposer,
      $$AuditTrailTableCreateCompanionBuilder,
      $$AuditTrailTableUpdateCompanionBuilder,
      (
        AuditEntryRow,
        BaseReferences<_$AppDatabase, $AuditTrailTable, AuditEntryRow>,
      ),
      AuditEntryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PendingChangesTableTableManager get pendingChanges =>
      $$PendingChangesTableTableManager(_db, _db.pendingChanges);
  $$EmergencyPassSpendsTableTableManager get emergencyPassSpends =>
      $$EmergencyPassSpendsTableTableManager(_db, _db.emergencyPassSpends);
  $$AuditTrailTableTableManager get auditTrail =>
      $$AuditTrailTableTableManager(_db, _db.auditTrail);
}
