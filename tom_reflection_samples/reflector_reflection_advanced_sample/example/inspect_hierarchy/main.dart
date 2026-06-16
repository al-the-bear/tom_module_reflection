// Scenario 1 — read the SHAPE of a class hierarchy out of generated reflection.
//
// The introduction sample inspected flat classes. Here the generated
// `store.r.dart` describes an inheritance graph: an abstract base (`Entity`), a
// mixin (`Timestamped`), an interface (`Auditable`), and two concrete subtypes
// (`User`, `Order`). This scenario walks that structure — abstract flags,
// the extends/with/implements triad, OWN vs INHERITED members (told apart by
// `declaringClassQualifiedName`), and the static members that live in their own
// descriptor maps.
import 'package:reflector_reflection_advanced_sample/store.r.dart';

String _short(String qualifiedName) => qualifiedName.split('.').last;

void main() {
  // Top-level inventory. `Persisted` (the annotation) is itself a class.
  print('classes -> ${reflectionApi.allClasses.map((c) => c.name).toList()}');
  // classes -> [Auditable, Entity, Order, Persisted, User]
  print('mixins  -> ${reflectionApi.allMixins.map((m) => m.name).toList()}');
  // mixins  -> [Timestamped]
  print('enums   -> ${reflectionApi.allEnums.map((e) => e.name).toList()}');
  // enums   -> [Channel]

  // Abstract vs concrete. An abstract class cannot be constructed reflectively
  // (its generative constructor carries no invoker); the descriptor records it.
  final entity = reflectionApi.findClass('Entity')!;
  final user = reflectionApi.findClass('User')!;
  print('\nEntity isAbstract -> ${entity.isAbstract}');
  // Entity isAbstract -> true
  print('User isAbstract   -> ${user.isAbstract}');
  // User isAbstract   -> false

  // The extends/with/implements triad — each relation is recorded by qualified
  // name, so it survives even when the related type lives in another library.
  print('\nUser extends    -> ${_short(user.superclassQualifiedName!)}');
  // User extends    -> Entity
  print('User with       -> ${user.mixinQualifiedNames.map(_short).toList()}');
  // User with       -> [Timestamped]
  print('User implements -> '
      '${user.interfaceQualifiedNames.map(_short).toList()}');
  // User implements -> [Auditable]

  // Inherited + mixed-in members are FLATTENED onto each class. The generator
  // marks where each one came from: locally declared members have a null
  // `declaringClassQualifiedName`; inherited ones point at the declaring type.
  final own = <String>[];
  final inherited = <String>[];
  for (final f in user.fields.values) {
    final from = f.declaringClassQualifiedName;
    (from == null ? own : inherited)
        .add(from == null ? f.name : '${f.name}<-${_short(from)}');
  }
  print('\nUser own fields       -> $own');
  // User own fields       -> [name, email, epochMillis, loginCount, kind]
  print('User inherited fields -> $inherited');
  // User inherited fields -> [id<-Entity, isoDate<-Timestamped]

  // Methods are flattened the same way: `baseFields` is inherited from Entity.
  for (final m in user.methods.values) {
    final from = m.declaringClassQualifiedName;
    print('  method ${m.name}: ${from == null ? 'declared' : 'from ${_short(from)}'}');
  }
  // method recordLogin: declared
  // method auditFields: declared
  // method toString: declared
  // method baseFields: from Entity

  // Static members live in their OWN maps, never mixed with instance members.
  print('\nEntity static fields  -> ${entity.staticFields.keys.toList()}');
  // Entity static fields  -> [schemaVersion]
  print('Entity static methods -> ${entity.staticMethods.keys.toList()}');
  // Entity static methods -> [describe]
  print('Entity instance methods (incl inherited) -> '
      '${entity.methods.keys.toList()}');
  // Entity instance methods (incl inherited) -> [baseFields]

  // Read-only vs writable. A getter (`kind`, `isoDate`) and a final field
  // (`epochMillis`, `id`) both reflect as fields with no setter; only `isFinal`
  // separates a stored final from a computed getter.
  for (final name in ['epochMillis', 'kind', 'loginCount']) {
    final f = user.fields[name]!;
    print('  field $name: final=${f.isFinal} writable=${f.setInstance != null}');
  }
  // field epochMillis: final=true writable=false
  // field kind: final=false writable=false
  // field loginCount: final=false writable=true
}
