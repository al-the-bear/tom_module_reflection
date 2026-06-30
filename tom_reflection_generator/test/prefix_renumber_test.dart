import 'package:test/test.dart';
import 'package:tom_reflection_generator/src/reflection_generator/prefix_renumber.dart';

void main() {
  group('deterministicPrefixRemap', () {
    test('RG-PR-1: assigns 0..N-1 in ascending URI order', () {
      final remap = deterministicPrefixRemap({
        0: 'package:b/b.dart',
        1: 'package:a/a.dart',
        2: 'package:c/c.dart',
      });
      // a < b < c → a(old 1)=0, b(old 0)=1, c(old 2)=2
      expect(remap, equals({1: 0, 0: 1, 2: 2}));
    });

    test('RG-PR-2: independent of encounter order (stable output)', () {
      // Same library set, different old-index assignment (different
      // encounter order on a hypothetical other machine) → same renumbering
      // target URIs.
      final a = deterministicPrefixRemap({
        0: 'package:a/a.dart',
        1: 'package:b/b.dart',
      });
      final b = deterministicPrefixRemap({
        5: 'package:b/b.dart',
        9: 'package:a/a.dart',
      });
      // In both, a→0 and b→1 by URI.
      expect(a[0], equals(0)); // a
      expect(a[1], equals(1)); // b
      expect(b[9], equals(0)); // a
      expect(b[5], equals(1)); // b
    });

    test('RG-PR-3: ties on URI fall back to old index', () {
      final remap = deterministicPrefixRemap({
        7: 'package:x/x.dart',
        3: 'package:x/x.dart',
      });
      // Equal URIs → lower old index first.
      expect(remap[3], equals(0));
      expect(remap[7], equals(1));
    });

    test('RG-PR-4: empty input yields empty map', () {
      expect(deterministicPrefixRemap({}), isEmpty);
    });
  });

  group('applyPrefixRemap', () {
    test('RG-PR-5: rewrites qualified member access', () {
      const code = 'prefix0.Foo x = prefix1.Bar();';
      final out = applyPrefixRemap(code, {0: 2, 1: 0});
      expect(out, equals('prefix2.Foo x = prefix0.Bar();'));
    });

    test('RG-PR-6: leaves bare prefix tokens in strings untouched', () {
      // No trailing dot → not an import-qualified access.
      const code = "_symbolMap['prefix0'] = 1;";
      final out = applyPrefixRemap(code, {0: 9});
      expect(out, equals("_symbolMap['prefix0'] = 1;"));
    });

    test('RG-PR-7: does not touch identifiers that merely start with prefix',
        () {
      const code = 'myprefix0.field';
      final out = applyPrefixRemap(code, {0: 5});
      // \b before "prefix" prevents matching inside "myprefix0".
      expect(out, equals('myprefix0.field'));
    });

    test('RG-PR-8: distinguishes prefix1 from prefix10', () {
      const code = 'prefix1.A + prefix10.B';
      final out = applyPrefixRemap(code, {1: 3, 10: 4});
      expect(out, equals('prefix3.A + prefix10.B'.replaceFirst('prefix10', 'prefix4')));
      expect(out, equals('prefix3.A + prefix4.B'));
    });

    test('RG-PR-9: indices absent from remap are left as-is', () {
      const code = 'prefix2.Keep';
      final out = applyPrefixRemap(code, {0: 1});
      expect(out, equals('prefix2.Keep'));
    });
  });
}
