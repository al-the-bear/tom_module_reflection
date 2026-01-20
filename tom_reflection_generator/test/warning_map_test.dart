import 'package:test/test.dart';
import 'package:tom_reflection_generator/reflection_generator.dart';

void main() {
  test('warning map exposes all toggles', () {
    expect(mapEnvironmentToWarningKind, isNotEmpty);
    expect(
      mapEnvironmentToWarningKind['REFLECTION_SUPPRESS_ALL_WARNINGS'],
      equals(WarningKind.values.toSet()),
    );
    expect(
      mapEnvironmentToWarningKind.keys,
      containsAll([
        'REFLECTION_SUPPRESS_BAD_SUPERCLASS',
        'REFLECTION_SUPPRESS_BAD_METADATA',
        'REFLECTION_SUPPRESS_BAD_REFLECTOR_CLASS',
        'REFLECTION_SUPPRESS_BAD_NAME_PATTERN',
        'REFLECTION_SUPPRESS_UNSUPPORTED_TYPE',
        'REFLECTION_SUPPRESS_UNUSED_REFLECTOR',
      ]),
    );
  });
}
