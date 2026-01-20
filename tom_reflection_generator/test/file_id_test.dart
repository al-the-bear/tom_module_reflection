import 'package:test/test.dart';
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

void main() {
  group('FileId', () {
    test('changeExtension rewrites dart suffix', () {
      final id = FileId('example_pkg', 'lib/src/foo.dart');
      final updated = id.changeExtension('.reflection.dart');
      expect(updated.package, equals('example_pkg'));
      expect(updated.path, equals('lib/src/foo.reflection.dart'));
    });

    test('uri resolves to package path', () {
      final id = FileId('example_pkg', 'lib/models/user.dart');
      expect(id.uri.toString(), equals('package:example_pkg/models/user.dart'));
    });

    test('equality uses package and path', () {
      final a = FileId('example_pkg', 'lib/foo.dart');
      final b = FileId('example_pkg', 'lib/foo.dart');
      final c = FileId('example_pkg', 'lib/bar.dart');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
