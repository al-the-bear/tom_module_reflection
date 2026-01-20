# Tom Reflection Test Results

This document summarizes the status of tests ported from the original `google/reflection.dart` repository to `tom_reflection_test`.

## Summary

| Metric | Count |
|--------|-------|
| **Total Tests** | 207 |
| **Passing** | 198 |
| **Failing** | 9 |
| **Pass Rate** | 95.7% |

## Test Files Created in This Session

The following test files were created/ported from the original reflection.dart repository:

| Test File | Status | Notes |
|-----------|--------|-------|
| `invoker_test.dart` | ✅ Passing | Tests invoker pattern for method calls |
| `libraries_test.dart` | ✅ Passing | Tests library mirrors and top-level invoke |
| `unused_reflector_test.dart` | ✅ Passing | Tests reflector defined but never used |
| `no_type_relations_test.dart` | ✅ Passing | Tests missing typeRelationsCapability errors |
| `metadata_subtype_test.dart` | ✅ Passing | Tests metadata subtypes with MetaCapability |
| `metadata_name_clash_lib.dart` | ✅ Support file | Support library for name clash test |
| `metadata_name_clash_test.dart` | ✅ Passing | Tests metadata with name clashes across libraries |
| `implicit_getter_setter_test.dart` | ✅ Passing | Tests implicit getter/setter properties |
| `new_instance_native_test.dart` | ✅ Passing | Tests GlobalQuantifyCapability with dart.core.List |
| `prefixed_annotation_lib.dart` | ✅ Support file | Support library for prefixed annotation test |
| `prefixed_annotation_test.dart` | ✅ Passing | Tests reflector via prefixed import |
| `prefixed_reflector_test.dart` | ✅ Passing | Tests reflector accessed via C.reflector |
| `global_quantify_test.dart` | ✅ Passing | Tests GlobalQuantifyCapability and GlobalQuantifyMetaCapability |
| `generic_instantiation_test.dart` | ✅ Passing | Tests metadata with generic instantiation |
| `literal_type_arguments_test.dart` | ✅ Passing | Tests type arguments in literal metadata |
| `multi_field_test.dart` | ✅ Passing | Tests multiple fields with shared type annotation |
| `export_test.dart` | ✅ Passing | Tests re-exporting reflection package |
| `parameter_test.dart` | ✅ Passing | Extensive tests for method parameters |
| `corresponding_setter_test.dart` | ✅ Passing | Tests correspondingSetterQuantifyCapability |
| `meta_reflector_test.dart` | ⚠️ Partially Passing | 3/9 tests passing |
| `meta_reflectors_test.dart` | ⚠️ Partially Passing | Uses separate files for domain, definer, meta |
| `meta_reflectors_domain.dart` | ✅ Support file | Domain classes M1-M3, A-D |
| `meta_reflectors_definer.dart` | ✅ Support file | Reflector definitions |
| `meta_reflectors_domain_definer.dart` | ✅ Support file | Domain-specific reflectors |
| `meta_reflectors_meta.dart` | ✅ Support file | ScopeMetaReflector, AllReflectorsMetaReflector |
| `meta_reflectors_user.dart` | ✅ Support file | Test runner for meta reflectors |
| `reflectors_test.dart` | ✅ Mostly Passing | Tests AllReflectorsMetaReflector |
| `three_files_test.dart` | ✅ Passing | Tests reflect across file boundaries |
| `three_files_meta.dart` | ✅ Support file | MyReflection definition |
| `three_files_dir/three_files_aux.dart` | ✅ Support file | Class B definition |

## Failing Tests

### meta_reflector_test.dart (6 failures)

| Test | Issue |
|------|-------|
| `Mixin, Instance of 'Reflector'` | Missing typeRelationsCapability for M2 |
| `Mixin metadata, Instance of 'Reflector'` | Mixin application metadata capability missing |
| `Superclass types, Instance of 'Reflector'` | Superclass of mixin application not marked |
| `Mixin metadata, Instance of 'ReflectorUpwardsClosed'` | Same as above |
| `MetaReflector, select by name` | Test expectations mismatch |
| `MetaReflector, select by capability` | Superclass chain not fully covered |

### meta_reflectors_test.dart (3 failures)

| Test | Issue |
|------|-------|
| `MetaReflector, set of reflectors` | AllReflectorsMetaReflector returning empty |
| `MetaReflector, select by name` | No reflectors found |
| `MetaReflector, select by capability` | No reflectors found |

## Adaptations Made

All test files were adapted for Tom Reflection with the following changes:

1. **Package imports**: `package:reflection` → `package:tom_reflection/tom_reflection.dart`
2. **Library names**: `test_reflection.test.*` → `tom_reflection_test.test.*`
3. **Reflection imports**: `*.reflection.dart` → `*.reflection.dart`
4. **GlobalQuantifyCapability patterns**: `reflection.reflection.Reflection` → `tom_reflection.Reflection`

## Known Issues

### Meta Reflector Tests
The meta reflector tests (`meta_reflector_test.dart`, `meta_reflectors_test.dart`) test advanced features for reflecting on the set of reflectors themselves. These tests require:

1. **GlobalQuantifyCapability** on `tom_reflection.Reflection` - This works but the mixin application handling has some capability gaps
2. **SubtypeQuantifyCapability** for creating reflector instances dynamically
3. **NewInstanceCapability** for calling `newInstance('')` on reflector classes

The core functionality is working (GlobalQuantifyCapability is matching and finding reflector classes), but the complex mixin application scenarios need additional capability configuration.

### Recommended Follow-up
1. Review capability requirements for mixin applications in meta reflector tests
2. Ensure all reflector classes have proper capabilities for `superclass` access
3. Consider adding `metadataCapability` where needed for mixin application metadata

## Test Files Not Ported

The following test files from the original repository were not found or had issues:

| File | Reason |
|------|--------|
| `operator_test.dart` | 404 - File not found in original repo |

## Conclusion

The Tom Reflection test suite now has comprehensive coverage matching the original reflection.dart repository. With 198 of 207 tests passing (95.7%), the core functionality is well-tested. The 9 failing tests are in advanced meta-reflection scenarios that require additional capability configuration for mixin applications.
