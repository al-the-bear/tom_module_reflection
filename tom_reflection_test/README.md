# tom_reflection_test

> Part of the Tom Framework reflection toolkit. Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package — originally
> created by Erik Ernst and the Dart team (© 2015 the Dart project authors,
> BSD 3-Clause); Tom-specific refactoring,
> fixes and enhancements © 2026 Peter Nicolai Alexis Kyaw. See
> [`LICENSE`](LICENSE).

The **end-to-end fixture suite** for engine 1 of the Tom reflection toolkit. It
proves that [`tom_reflection_generator`](../tom_reflection_generator/README.md)
emits correct `*.reflection.dart` for [`tom_reflection`](../tom_reflection/README.md),
across the whole capability and language surface.

> **These are test fixtures, not user-facing samples.** Each `test/*_test.dart`
> is a generation + behaviour check, paired with a committed
> `test/*_test.reflection.dart` that the generator must reproduce. If you want to
> *learn* the API, go to the teaching samples instead:
> [`tom_reflection_samples`](../tom_reflection_samples/README.md) — start with
> [`reflection_introduction_sample`](../tom_reflection_samples/reflection_introduction_sample/README.md).

This package is `publish_to: none`; it ships no public API.

## What it covers

Each fixture is a self-contained Dart file that declares a reflector with some
set of capabilities, annotates target classes, and asserts that reflection over
the generated mirror data behaves correctly. The committed
`*_test.reflection.dart` next to it is the **expected generator output** — so the
suite catches both *behaviour* regressions (a mirror returns the wrong thing) and
*generation* regressions (the generator emits different code).

| Category | Representative fixtures |
| -------- | ----------------------- |
| Basic invocation | `basic_test`, `reflect_test`, `invoke_test`, `invoker_test`, `invoker_operator_test` |
| Capabilities | `capabilities_test`, `invoke_capabilities_test`, `member_capability_test`, `no_such_capability_test` |
| Declarations & members | `declarations_test`, `field_test`, `multi_field_test`, `class_property_test`, `inherited_variable_test`, `library_declarations_test` |
| Accessors | `implicit_getter_setter_test`, `corresponding_setter_test` |
| Parameters | `parameter_test`, `parameter_mirrors_test`, `default_values_test` |
| Construction | `new_instance_test`, `new_instance_default_values_test`, `new_instance_optional_arguments_test`, `new_instance_native_test` |
| Static members | `static_members_test`, `static_type_arguments_test`, `mixin_application_static_invoke_test`, `mixin_static_const_test` |
| Type relations | `type_relations_test`, `no_type_relations_test`, `subtype_test`, `subtype_quantify_test`, `superinterfaces_test` |
| Generics | `generic_instantiation_test`, `generic_mixin_test`, `expanding_generics_test`, `literal_type_arguments_test`, `type_variable_test`, `nullability_test` |
| Reflected type | `reflected_type_test`, `reflected_type_void_test`, `dynamic_reflected_type_test` |
| Metadata | `metadata_test`, `metadata_subtype_test`, `metadata_name_clash_test`, `prefixed_annotation_test` |
| Mixins | `mixin_test`, `mixin_application_static_member_test` |
| Libraries / prefixes / exports | `libraries_test`, `export_test`, `exported_main_test`, `three_files_test`, `use_prefix_test`, `original_prefix_test`, `prefixed_reflector_test`, `name_clash_test` |
| Enums | `enum_test` |
| Meta-reflectors & quantifiers | `meta_reflector_test`, `meta_reflectors_test`, `global_quantify_test`, `reflectors_test`, `unused_reflector_test` |
| Edge cases & regressions | `issue_255_test`, `no_such_method_test`, `private_class_test`, `proxy_test`, `serialize_test`, `delegate_test`, `function_type_annotation_test`, `polymer_basic_needs_test`, `annotated_classes_test` |

**72 fixtures** in total (each with its committed expected `*.reflection.dart`).

## Running the suite

From this package's root:

```bash
testkit :test          # run all fixtures, append a result column to the baseline
testkit :baseline      # start a fresh baseline CSV
```

`testkit` is the workspace standard (use it instead of `dart test`); baselines
land in the gitignored `testlog/`. To target a subset:

```bash
testkit :test --test-args="--name 'capabilit'"
```

## Regenerating the fixtures

The committed `*_test.reflection.dart` files are **build outputs** — never
hand-edit them. Regenerate via `build_runner`, configured by this package's
`build.yaml` (which generates for `test/**_test.dart`):

```bash
dart run build_runner build --delete-conflicting-outputs
# or via the standalone CLI:
reflectiongenerator build "test/**_test.dart"
```

> **Regenerate only on signature changes.** Touching a fixture's *body* does not
> require regeneration; only changes to the reflected **shape** (members, types,
> capabilities, annotations) do. After regenerating, run `testkit :test` and
> commit the regenerated files together with the source change so the expected
> output stays in lockstep.

When this suite is used to **validate the generator**, generate the output to a
scratch location and diff it against the committed reference — a mismatch on any
fixture (other than known SDK-version drift in type strings) is a generator
regression.

## Architecture

```
test/<name>_test.dart              fixture source: reflector + annotated classes + assertions
test/<name>_test.reflection.dart   committed expected generator output (regenerated, not edited)
build.yaml                         generate_for: test/**_test.dart  → *.reflection.dart
```

There are no library files under `lib/`; the package exists purely to exercise
the generator/runtime pair end to end.

## Ecosystem

```
tom_reflection            runtime mirror library  ─┐
tom_reflection_generator  emits *.reflection.dart ─┤── both exercised end-to-end by
                                                    └► tom_reflection_test  (THIS PACKAGE)
```

For the build-time *structural* engine and its own checks, see
[`tom_reflector`](../tom_reflector/README.md). Repo map and engine selection:
[`../README.md`](../README.md).

## Status

- **Version:** 1.0.1 (`publish_to: none`).
- **SDK:** Dart `^3.10.4`.
- **Fixtures:** 72 `*_test.dart` suites, each with a committed expected
  `*_test.reflection.dart`.
- **Role:** the reference oracle for engine-1 generator correctness.

## License

BSD 3-Clause. Derived from
[`reflectable`](https://pub.dev/packages/reflectable) — originally created by
Erik Ernst and the Dart team — retaining the upstream copyright
(© 2015 the Dart project authors) alongside Tom's modifications
(© 2026 Peter Nicolai Alexis Kyaw). See [`LICENSE`](LICENSE).
