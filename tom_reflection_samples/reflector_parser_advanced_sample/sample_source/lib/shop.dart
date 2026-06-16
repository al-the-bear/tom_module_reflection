// Input source set for the engine-2 parser ADVANCED sample.
//
// This library is analyzed as *text* (like the introduction sample's
// sample_source/) and never executed. It deliberately exercises the harder
// corners of the model: generic bounds, nested type arguments, an `on`-clause
// mixin, an extension, a marker annotation carrying arguments, a self-
// referential (cyclic) field, and an interface implementation.
library;

/// A marker annotation that *carries arguments*. The model has slots for those
/// arguments (`AnnotationInfo.positionalArguments` / `namedArguments`), but the
/// current analyzer records annotations **by name** — see the sample README.
class Table {
  final String name;
  final String schema;
  const Table(this.name, {this.schema = 'public'});
}

/// A second marker, argument-free.
class Id {
  const Id();
}

/// The root contract every persisted thing implements.
abstract class Entity {
  String get id;
}

/// A mixin with an **`on` clause** — only mixable onto [Entity] subtypes.
/// Engine 2 records the on-types as a resolvable [Entity] reference.
mixin Timestamped on Entity {
  DateTime get createdAt;

  int ageInDays(DateTime now) => now.difference(createdAt).inDays;
}

/// A class that simultaneously **extends**, **mixes in**, and **implements** —
/// each surfaces as a separate, resolvable type reference in the model.
@Table('orders', schema: 'sales')
class Order extends Entity with Timestamped implements Comparable<Order> {
  @override
  @Id()
  final String id;

  @override
  final DateTime createdAt;

  /// A field whose type carries a **type argument** (`List<OrderLine>`).
  final List<OrderLine> lines;

  Order(this.id, this.createdAt, this.lines);

  @override
  int compareTo(Order other) => id.compareTo(other.id);

  /// A method whose return type **nests** type arguments two deep:
  /// `Map<String, List<OrderLine>>`.
  Map<String, List<OrderLine>> groupedByDay() => {};
}

/// A simpler entity referenced from [Order.lines].
@Table('order_lines')
class OrderLine extends Entity {
  @override
  final String id;
  final int quantity;
  OrderLine(this.id, this.quantity);
}

/// A generic class with a **bound** (`T extends Entity`) and a **self-
/// referential** field (`Node<T>? next`) — the model resolves the cycle in
/// memory without looping.
class Node<T extends Entity> {
  final T value;
  Node<T>? next;
  Node(this.value, [this.next]);
}

/// An **extension** on a generic type (`List<Order>`). Its `extendedType` is a
/// resolvable `List<Order>` reference.
extension OrderQuery on List<Order> {
  List<Order> openOnly() => this;
  int get lineCount => fold(0, (sum, order) => sum + order.lines.length);
}

/// A plain enum, to confirm enums coexist with the advanced features.
enum Status { open, paid, closed }

/// A top-level function — reflected as a global.
int recordCount() => 0;
