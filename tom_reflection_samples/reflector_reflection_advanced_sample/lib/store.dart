// Domain model for the engine-2 ADVANCED reflection-generation sample.
//
// Where the introduction sample used flat, unrelated classes, this library is
// a small CLASS HIERARCHY — an abstract base, a mixin, an interface, two
// concrete subclasses, and static members. The point of the advanced sample is
// to show what the generated reflection does with inheritance, mixin
// application, interface implementation, and static members — and the one
// gotcha that bites every reflective serializer (`isInstance` is subtype-
// inclusive). Like the introduction sample, NOTHING here is constructed or
// called directly by the scenarios; every instance is built and driven through
// the generated reflection in `store.r.dart`.
library;

/// Marks a class as a persistable entity and records its storage table.
///
/// Engine 2 records this annotation **by name** on each target class; it does
/// NOT capture the constructor argument (`'users'`). Scenario 3 uses the
/// presence of `@Persisted` to build a table registry; it reads the table name
/// from a `static` field on each class, not from the annotation.
class Persisted {
  final String table;
  const Persisted(this.table);
}

/// A mixin that contributes a computed `isoDate` getter on top of whatever
/// `epochMillis` the host class supplies.
///
/// In the generated reflection a mixin's members are FLATTENED into every class
/// that applies it: `User` and `Order` both expose `isoDate` as a read-only
/// field whose `declaringClassQualifiedName` points back at `Timestamped`.
mixin Timestamped {
  int get epochMillis;

  String get isoDate =>
      DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true)
          .toIso8601String();
}

/// The abstract base of the hierarchy.
///
/// Demonstrates three things the advanced reflection has to handle:
///   * an `abstract` class (its descriptor carries `isAbstract: true` and its
///     generative constructor has no invoker — you cannot `newInstance` it);
///   * `static` members (`schemaVersion`, `describe`) which land in the
///     descriptor's `staticFields` / `staticMethods`, separate from instance
///     members; and
///   * a concrete inherited method (`baseFields`) that every subclass exposes
///     with `declaringClassQualifiedName` set to `Entity`.
abstract class Entity {
  /// Inherited final field — every subclass reflects `id` with
  /// `declaringClassQualifiedName == Entity`.
  final String id;

  Entity(this.id);

  /// Abstract getter — each concrete subclass overrides it; in the reflection
  /// it surfaces as a read-only field on the subclass.
  String get kind;

  /// A mutable static field — read/written through `getStaticProperty` /
  /// `setStaticProperty`, never through an instance.
  static int schemaVersion = 3;

  /// A static method — invoked through `invokeStatic`, not `invoke`.
  static String describe() => 'entity schema v$schemaVersion';

  /// A concrete instance method, inherited by every subclass.
  Map<String, Object?> baseFields() => {'id': id, 'kind': kind};
}

/// An interface (abstract class used via `implements`).
///
/// `User` implements it; `Order` does not. Scenario 2 uses
/// `implementsInterface` to tell them apart — and shows that the check walks
/// the whole superclass chain, not just the leaf.
abstract class Auditable {
  Map<String, Object?> auditFields();
}

/// A concrete entity that pulls together every relation at once: it `extends`
/// the abstract base, mixes in `Timestamped`, and `implements Auditable`.
@Persisted('users')
class User extends Entity with Timestamped implements Auditable {
  /// The storage table, exposed as a static so scenario 3 can read it without
  /// decoding the `@Persisted` annotation's argument (engine 2 keeps the
  /// annotation by name only).
  static const String table = 'users';

  String name;
  String email;

  /// Final mutable-state source for the mixin's `isoDate` — reflected as a
  /// read-only field (it has a getter but no setter).
  @override
  final int epochMillis;

  /// A writable field that is NOT a constructor parameter. Scenario 3's generic
  /// round-trip rebuilds the object through the constructor, then re-applies
  /// leftover writable fields like this one via `setProperty`.
  int loginCount = 0;

  User({
    required String id,
    required this.name,
    required this.email,
    required this.epochMillis,
  }) : super(id);

  @override
  String get kind => 'user';

  /// A mutator invoked by name in scenario 2.
  void recordLogin() => loginCount++;

  @override
  Map<String, Object?> auditFields() => {'id': id, 'name': name};

  @override
  String toString() => 'User($id)';
}

/// A second concrete entity — extends the base and mixes in `Timestamped`, but
/// does NOT implement `Auditable`. Having two subtypes is what makes the
/// polymorphic dispatch in scenario 2 and the generic serializer in scenario 3
/// meaningful: the same reflective code drives both with no per-type branches.
@Persisted('orders')
class Order extends Entity with Timestamped {
  static const String table = 'orders';

  double total;

  @override
  final int epochMillis;

  Order({
    required String id,
    required this.total,
    required this.epochMillis,
  }) : super(id);

  @override
  String get kind => 'order';

  @override
  String toString() => 'Order($id)';
}

/// A standalone enum. Engine 2 records the enum's presence as a named type; it
/// does not enumerate the constant values (see the README).
enum Channel { web, mobile, api }
