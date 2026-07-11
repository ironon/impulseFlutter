import 'template.dart';
import 'seed_templates.dart';

/// Registry-driven template layer (§2A.2). The Normal-mode UI — gallery,
/// per-template builder form, expansion, and the onboarding goal picker — is
/// generated from these entries, so adding a template is an isolated addition.
///
/// Seeding: on first run the registry is seeded with the hardcoded v1
/// defaults. It is designed forward for community-authored template libraries
/// loaded into the same registry (persisting arbitrary template *definitions*
/// is future work; v1 templates are code-defined).
class TemplateRegistry {
  final Map<String, Template> _templates = {};

  TemplateRegistry._();

  /// Build the registry seeded with the v1 default templates.
  factory TemplateRegistry.seeded() {
    final r = TemplateRegistry._();
    for (final t in <Template>[
      SunriseLockTemplate(),
      StudyTimeTemplate(),
      GymTimeTemplate(),
      PhoneFreeTemplate(),
    ]) {
      r.register(t);
    }
    return r;
  }

  void register(Template t) => _templates[t.id] = t;

  Template? byId(String id) => _templates[id];

  List<Template> get all => _templates.values.toList();

  /// Templates flagged as onboarders (§8.1 goal picker). v1: Sunrise Lock,
  /// Phone-Free, Gym Time, Study Time.
  List<Template> get onboarders =>
      all.where((t) => t.onboarder != null).toList();
}
