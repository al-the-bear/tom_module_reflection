// The shared domain for the reflection introduction sample.
//
// Two annotated classes — `User` and `Order` — plus the reflector that gates
// what the generator emits. Every scenario under `example/` imports this
// library (and its generated `domain.reflection.dart`) so the domain is
// declared exactly once.
//
// The reflector is a `const` subclass of `Reflection`; the capabilities passed
// to `super(...)` decide which mirror operations the generated code supports:
//
//   - invokingCapability       → invoke methods, getters and setters by name
//   - declarationsCapability   → enumerate fields / methods via the class mirror
//   - typeRelationsCapability  → walk superclass / interface relations
//   - metadataCapability       → read annotations off declarations
//
// Annotating a class with the `const` reflector instance (`@introReflector`)
// tells the generator to include that class in the generated reflection data.
library;

import 'package:tom_reflection/tom_reflection.dart';

/// The reflector for this sample. Declaring it once and reusing the single
/// `const` instance keeps the generated data small and unambiguous.
class IntroReflector extends Reflection {
  const IntroReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          metadataCapability,
        );
}

/// The single reflector instance used to annotate classes in this sample.
const introReflector = IntroReflector();

/// A user of the system — the primary entity we reflect over.
@introReflector
class User {
  String name;
  String email;
  int loginCount;

  User(this.name, this.email, {this.loginCount = 0});

  /// A method we will invoke *by name* through a mirror.
  String greet() => 'Hi, I am $name';

  /// A mutating method — invoking it through reflection changes real state.
  void recordLogin() => loginCount++;

  /// A getter — reflection reads it just like a field.
  bool get isActive => loginCount > 0;

  @override
  String toString() => 'User($name, $email, logins: $loginCount)';
}

/// An order placed by a [User]. Shows reflection over a class whose fields
/// include another reflected type and a `final` field.
@introReflector
class Order {
  final String id;
  final User customer;
  double amount;

  Order(this.id, this.customer, this.amount);

  /// Returns a human-readable summary — invoked by name in a scenario.
  String summary() =>
      'Order $id for ${customer.name}: \$${amount.toStringAsFixed(2)}';

  /// Applies a percentage discount and returns the new amount.
  double applyDiscount(double percent) =>
      amount = amount * (1 - percent / 100);

  @override
  String toString() => 'Order($id, ${customer.name}, \$$amount)';
}
