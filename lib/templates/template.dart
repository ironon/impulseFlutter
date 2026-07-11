import 'package:flutter/material.dart';

import '../models/automation_model.dart';

/// The kind of a template parameter, so the Normal-mode builder form can be
/// generated from the registry (§2A.2) rather than hand-coded per template.
enum ParamKind { time, durationSeconds, firmness, anchorRole, wifiSsid }

/// One friendly input a template collects.
class TemplateParam {
  final String key;
  final String label;
  final ParamKind kind;
  final dynamic defaultValue;

  /// For [ParamKind.anchorRole]: the role the anchor must fill (e.g. "bedroom").
  final String? anchorRole;

  /// Whether this param is part of the onboarder quick-form (≤2–3 of these).
  final bool inQuickForm;

  const TemplateParam({
    required this.key,
    required this.label,
    required this.kind,
    this.defaultValue,
    this.anchorRole,
    this.inQuickForm = false,
  });
}

/// Optional onboarder designation (§2A.2): surfaces a template as a first-run
/// goal with a problem statement, hero icon, quick-form and required anchors.
class OnboarderInfo {
  /// The problem in the user's voice ("I can't get out of bed").
  final String problemStatement;
  final IconData heroIcon;

  /// Anchor roles the goal needs, so onboarding drives hardware placement.
  final List<AnchorRoleRequirement> requiredAnchors;

  const OnboarderInfo({
    required this.problemStatement,
    required this.heroIcon,
    required this.requiredAnchors,
  });
}

/// A required anchor role with placement guidance copy (§8.1 item 4).
class AnchorRoleRequirement {
  final String role;
  final String label;
  final String placementCopy;
  const AnchorRoleRequirement({
    required this.role,
    required this.label,
    required this.placementCopy,
  });
}

/// A self-contained registry entry: friendly inputs → one or more tagged
/// advanced blocks, and the reverse (re-parse for editing). Adding a template
/// is an isolated addition, not a UI rewrite (§2A.2).
abstract class Template {
  String get id;
  TemplateOrigin get origin;
  String get displayName;
  String get description;
  IconData get icon;

  List<TemplateParam> get params;
  OnboarderInfo? get onboarder => null;

  Map<String, dynamic> get defaultParams => {
        for (final p in params)
          if (p.defaultValue != null) p.key: p.defaultValue,
      };

  /// The reduced quick-form param subset (onboarder path).
  List<TemplateParam> get quickFormParams =>
      params.where((p) => p.inQuickForm).toList();

  /// Expand friendly params into tagged advanced blocks. To preserve event
  /// UUIDs across edits (§8.9 item 3), [slotUuids] maps this template's stable
  /// slot keys to existing block UUIDs; unmapped slots get a fresh [newUuid].
  List<Automation> expand(
    Map<String, dynamic> params, {
    required String instanceId,
    required String Function() newUuid,
    Map<String, String> slotUuids = const {},
  });

  /// Re-derive editable params from the blocks one expansion produced, so
  /// Normal mode can re-render/edit an existing template instance.
  Map<String, dynamic> reparse(List<Automation> blocks);
}

/// Helpers shared by seed templates.
mixin TemplateHelpers {
  TimeOfDay timeFrom(dynamic v, TimeOfDay fallback) {
    if (v is Map) {
      return TimeOfDay(hour: v['hour'] as int, minute: v['minute'] as int);
    }
    return fallback;
  }

  Map<String, int> timeToMap(TimeOfDay t) => {'hour': t.hour, 'minute': t.minute};

  EnforcementProfile firmnessFrom(dynamic v, EnforcementProfile fallback) {
    if (v is String) {
      return EnforcementProfile.values.firstWhere(
        (e) => e.name == v,
        orElse: () => fallback,
      );
    }
    return fallback;
  }
}
