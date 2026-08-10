/// A second library for [default_value_prefix_fixture.dart], so that a type
/// literal written with a *source* import prefix (`lib.Imported`) can be put
/// in a default value.
///
/// The generated file imports every library under its own `prefixNN` alias, so
/// a type literal must be re-qualified with the generated prefix — never with
/// the prefix it happened to carry in the source. This library exists to make
/// that distinction observable.
library;

/// A class referenced from the fixture through a source import prefix.
class Imported {
  const Imported();
}
