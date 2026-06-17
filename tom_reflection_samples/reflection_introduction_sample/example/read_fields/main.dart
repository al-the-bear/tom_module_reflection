// Scenario 2 — read and write fields by name.
//
// `invokeGetter` / `invokeSetter` reach a field (or getter/setter) on the
// reflectee using only its string name — the basis of serializers, form
// binders and dependency injection.
import 'package:reflection_introduction_sample/domain.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final user = User('Grace', 'grace@example.com', loginCount: 3);
  final mirror = introReflector.reflect(user);

  // Read fields by name.
  print('name   -> ${mirror.invokeGetter('name')}'); // name   -> Grace
  print('email  -> ${mirror.invokeGetter('email')}'); // email  -> grace@example.com
  print('logins -> ${mirror.invokeGetter('loginCount')}'); // logins -> 3

  // Write a field by name; the change is visible on the real object.
  mirror.invokeSetter('email', 'grace.hopper@example.com');
  print('updated email (object) -> ${user.email}'); // updated email (object) -> grace.hopper@example.com
  print('updated email (mirror) -> ${mirror.invokeGetter('email')}'); // updated email (mirror) -> grace.hopper@example.com

  // The same works on a class whose fields reference another reflected type.
  final order = Order('A-100', user, 42.5);
  final orderMirror = introReflector.reflect(order);
  print('order id     -> ${orderMirror.invokeGetter('id')}'); // order id     -> A-100
  print('order amount -> ${orderMirror.invokeGetter('amount')}'); // order amount -> 42.5

  // Invoke a method that takes an argument.
  final discounted = orderMirror.invoke('applyDiscount', [10.0]);
  print('after 10% off -> ${(discounted as double).toStringAsFixed(2)}'); // after 10% off -> 38.25
}
