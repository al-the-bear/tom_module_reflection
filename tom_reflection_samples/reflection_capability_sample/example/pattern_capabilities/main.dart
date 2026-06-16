// Scenario 3 — a pattern capability, and the two error types it reveals.
//
// `gettersOnlyReflector` is built from `InstanceInvokeCapability('^get')`: a
// regular expression that covers only members whose name starts with "get".
// This surfaces the crucial distinction between the two failure modes:
//
//   * NoSuchCapabilityError      — the capability category is absent entirely.
//   * ReflectionNoSuchMethodError — you HAVE the capability, but this specific
//                                   member is not covered (pattern miss) or does
//                                   not exist.
import 'package:reflection_capability_sample/domain.dart';
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final sensor = Sensor(21);
  final mirror = gettersOnlyReflector.reflect(sensor);

  // Members matching ^get are covered and invoke normally.
  print('getRaw    -> ${mirror.invokeGetter('getRaw')}'); // getRaw    -> 21
  print('getScaled -> ${mirror.invokeGetter('getScaled')}'); // getScaled -> 42

  // `compute` exists on the class but does NOT match ^get. The capability is
  // present (instance invoke), the member just is not covered → a method error,
  // NOT a capability error.
  try {
    mirror.invoke('compute', const []);
    print('compute   -> (unexpected success)');
  } on ReflectionNoSuchMethodError {
    print('compute   -> ReflectionNoSuchMethodError (pattern did not cover it)');
    // compute   -> ReflectionNoSuchMethodError (pattern did not cover it)
  }

  // A member that does not exist at all also yields ReflectionNoSuchMethodError
  // — same category: "have the capability, no such member".
  try {
    mirror.invokeGetter('getMissing');
    print('getMissing -> (unexpected success)');
  } on ReflectionNoSuchMethodError {
    print('getMissing -> ReflectionNoSuchMethodError (no such member)');
    // getMissing -> ReflectionNoSuchMethodError (no such member)
  }
}
