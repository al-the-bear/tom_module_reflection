// The shared domain for the reflection ADVANCED sample.
//
// One reflector with a broad capability set covers every class, so the four
// scenarios under `example/` can each lean on a different slice of the mirror
// API without redefining the domain.
//
// Capability set (why each is here):
//   - invokingCapability         → invoke instance AND static members by name
//   - declarationsCapability     → declarations / instanceMembers / staticMembers
//   - typeRelationsCapability    → superclass, superinterfaces
//   - superclassQuantifyCapability → follow the superclass chain up to Object
//   - newInstanceCapability      → construct objects via newInstance
//   - metadataCapability         → read annotations off declarations
//   - reflectedTypeCapability    → reflectedReturnType for generic members
library;

import 'package:tom_reflection/tom_reflection.dart';

/// The reflector for this sample. A single broad reflector keeps the four
/// scenarios reading from one coherent set of generated data.
class AdvancedReflector extends Reflection {
  const AdvancedReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          superclassQuantifyCapability,
          newInstanceCapability,
          metadataCapability,
          reflectedTypeCapability,
        );
}

const advancedReflector = AdvancedReflector();

// ---------------------------------------------------------------------------
// Serialization domain — used by the `serializer` scenario.
// Mutable, non-final fields plus an all-optional constructor make the class
// reconstructable via `newInstance('', [])` followed by `invokeSetter`.
// ---------------------------------------------------------------------------

@advancedReflector
class Product {
  String sku;
  String name;
  double price;
  int stock;

  Product({this.sku = '', this.name = '', this.price = 0.0, this.stock = 0});

  /// A getter — deliberately *not* serialized (it is derived, not state).
  String get label => '$name ($sku)';

  @override
  String toString() => 'Product($sku, $name, \$$price, x$stock)';
}

// ---------------------------------------------------------------------------
// Type-relations hierarchy — used by the `type_relations` scenario.
// `Circle` extends `Shape` and implements the annotated `Drawable` interface,
// so its superclass chain and superinterfaces are both observable.
// ---------------------------------------------------------------------------

@advancedReflector
class Shape {
  const Shape();
  double get area => 0;
}

/// An annotated marker interface — only annotated superinterfaces appear in
/// `superinterfaces`, so this must carry the reflector too.
@advancedReflector
class Drawable {
  const Drawable();
}

@advancedReflector
class Circle extends Shape implements Drawable {
  final double radius;
  const Circle(this.radius);

  @override
  double get area => 3.14159 * radius * radius;
}

// ---------------------------------------------------------------------------
// Static-member domain — used by the `static_members` scenario.
// ---------------------------------------------------------------------------

@advancedReflector
class Temperature {
  final double celsius;
  Temperature(this.celsius);

  /// Static factory methods invoked through the class mirror.
  static Temperature freezing() => Temperature(0);
  static Temperature boiling() => Temperature(100);

  double get fahrenheit => celsius * 9 / 5 + 32;

  @override
  String toString() => '${celsius}C';
}

// ---------------------------------------------------------------------------
// Generics + mixins — used by the `generics_and_mixins` scenario.
// `Versioned` is a generic mixin; `Note` applies it with `String`.
// ---------------------------------------------------------------------------

@advancedReflector
mixin class Versioned<T> {
  T? payload;
  int version = 0;
}

@advancedReflector
class Note with Versioned<String> {
  String text;
  Note(this.text);

  @override
  String toString() => 'Note($text, v$version)';
}
