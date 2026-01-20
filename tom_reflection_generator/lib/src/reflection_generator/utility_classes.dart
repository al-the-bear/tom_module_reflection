// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

/// Similar to a `Set<T>` but also keeps track of the index of the first
/// insertion of each item.
class Enumerator<T extends Object> {
  final Map<T, int> _map = <T, int>{};
  int _count = 0;

  bool _contains(Object? t) => _map.containsKey(t);

  int get length => _count;

  /// Tries to insert [t]. If it was already there return false, else insert it
  /// and return true.
  bool add(T t) {
    if (_contains(t)) return false;
    _map[t] = _count;
    ++_count;
    return true;
  }

  /// Returns the index of a given item.
  int? indexOf(Object t) {
    return _map[t];
  }

  /// Returns all the items in the order they were inserted.
  Iterable<T> get items {
    return _map.keys;
  }

  /// Clears all elements from this [Enumerator].
  void clear() {
    _map.clear();
    _count = 0;
  }
}

/// Hybrid data structure holding [InterfaceElement]s and supporting data.
/// It holds three different data structures used to describe the set of
/// classes under transformation. It holds an [Enumerator] named
/// [interfaceElements] which is a set-like data structure that also enables
/// clients to obtain unique indices for each member; it holds a map
/// [elementToDomain] that maps each [InterfaceElement] to a corresponding
/// [_ClassDomain]; and it holds a relation [mixinApplicationSupers] that
/// maps each [InterfaceElement] which is a direct subclass of a mixin
/// application to its superclass. The latter is needed because the analyzer
/// representation of mixins and mixin applications makes it difficult to find
/// a superclass which is a mixin application (`InterfaceElement.supertype` is
/// the _syntactic_ superclass, that is, for `class C extends B with M..` it
/// is `B`, not the mixin application `B with M`). The three data structures
/// are bundled together in this class because they must remain consistent and
/// hence all operations on them should be expressed in one location, namely
/// this class. Note that this data structure can delegate all read-only
/// operations to the [interfaceElements], because they will not break
/// consistency, but for every mutating method we need to maintain the
/// invariants.
class _InterfaceElementEnhancedSet implements Set<InterfaceElement> {
  final _ReflectorDomain reflectorDomain;
  final Enumerator<InterfaceElement> interfaceElements =
      Enumerator<InterfaceElement>();
  final Map<InterfaceElement, _ClassDomain> elementToDomain =
      <InterfaceElement, _ClassDomain>{};
  final Map<InterfaceElement, MixinApplication> mixinApplicationSupers =
      <InterfaceElement, MixinApplication>{};
  bool _unmodifiable = false;

  _InterfaceElementEnhancedSet(this.reflectorDomain);

  void makeUnmodifiable() {
    // A very simple implementation, just enough to help spotting cases
    // where modification happens even though it is known to be a bug:
    // Check whether `_unmodifiable` is true whenever a mutating method
    // is called.
    _unmodifiable = true;
  }

  @override
  Iterable<T> map<T>(T Function(InterfaceElement) f) =>
      interfaceElements.items.map<T>(f);

  @override
  Set<R> cast<R>() {
    Iterable<Object?> self = this;
    return self is Set<R> ? self : Set.castFrom<InterfaceElement, R>(this);
  }

  @override
  Iterable<InterfaceElement> where(bool Function(InterfaceElement) f) {
    return interfaceElements.items.where(f);
  }

  @override
  Iterable<T> whereType<T>() sync* {
    for (var element in this) {
      if (element is T) {
        yield (element as T);
      }
    }
  }

  @override
  Iterable<T> expand<T>(Iterable<T> Function(InterfaceElement) f) {
    return interfaceElements.items.expand<T>(f);
  }

  @override
  void forEach(void Function(InterfaceElement) f) =>
      interfaceElements.items.forEach(f);

  @override
  InterfaceElement reduce(
    InterfaceElement Function(InterfaceElement, InterfaceElement) combine,
  ) {
    return interfaceElements.items.reduce(combine);
  }

  @override
  T fold<T>(T initialValue, T Function(T, InterfaceElement) combine) {
    return interfaceElements.items.fold<T>(initialValue, combine);
  }

  @override
  bool every(bool Function(InterfaceElement) f) =>
      interfaceElements.items.every(f);

  @override
  String join([String separator = '']) =>
      interfaceElements.items.join(separator);

  @override
  bool any(bool Function(InterfaceElement) f) => interfaceElements.items.any(f);

  @override
  List<InterfaceElement> toList({bool growable = true}) {
    return interfaceElements.items.toList(growable: growable);
  }

  @override
  int get length => interfaceElements.items.length;

  @override
  bool get isEmpty => interfaceElements.items.isEmpty;

  @override
  bool get isNotEmpty => interfaceElements.items.isNotEmpty;

  @override
  Iterable<InterfaceElement> take(int count) =>
      interfaceElements.items.take(count);

  @override
  Iterable<InterfaceElement> takeWhile(bool Function(InterfaceElement) test) {
    return interfaceElements.items.takeWhile(test);
  }

  @override
  Iterable<InterfaceElement> skip(int count) =>
      interfaceElements.items.skip(count);

  @override
  Iterable<InterfaceElement> skipWhile(bool Function(InterfaceElement) test) {
    return interfaceElements.items.skipWhile(test);
  }

  @override
  Iterable<InterfaceElement> followedBy(
    Iterable<InterfaceElement> other,
  ) sync* {
    yield* this;
    yield* other;
  }

  @override
  InterfaceElement get first => interfaceElements.items.first;

  @override
  InterfaceElement get last => interfaceElements.items.last;

  @override
  InterfaceElement get single => interfaceElements.items.single;

  @override
  InterfaceElement firstWhere(
    bool Function(InterfaceElement) test, {
    InterfaceElement Function()? orElse,
  }) {
    return interfaceElements.items.firstWhere(test, orElse: orElse);
  }

  @override
  InterfaceElement lastWhere(
    bool Function(InterfaceElement) test, {
    InterfaceElement Function()? orElse,
  }) {
    return interfaceElements.items.lastWhere(test, orElse: orElse);
  }

  @override
  InterfaceElement singleWhere(
    bool Function(InterfaceElement) test, {
    InterfaceElement Function()? orElse,
  }) {
    return interfaceElements.items.singleWhere(test);
  }

  @override
  InterfaceElement elementAt(int index) =>
      interfaceElements.items.elementAt(index);

  @override
  Iterator<InterfaceElement> get iterator => interfaceElements.items.iterator;

  @override
  bool contains(Object? value) => interfaceElements.items.contains(value);

  @override
  bool add(InterfaceElement value) {
    assert(!_unmodifiable);
    bool result = interfaceElements.add(value);
    if (result) {
      assert(!elementToDomain.containsKey(value));
      elementToDomain[value] = _createClassDomain(value, reflectorDomain);
      if (value is MixinApplication) {
        InterfaceElement? valueSubclass = value.subclass;
        if (valueSubclass != null) {
          // [value] is a mixin application which is the immediate superclass
          // of a class which is a regular class (not a mixin application). This
          // means that we must store it in `mixinApplicationSupers` such that
          // we can look it up during invocations of [superclassOf].
          assert(!mixinApplicationSupers.containsKey(valueSubclass));
          mixinApplicationSupers[valueSubclass] = value;
        }
      }
    }
    return result;
  }

  @override
  void addAll(Iterable<InterfaceElement> elements) => elements.forEach(add);

  @override
  bool remove(Object? value) {
    assert(!_unmodifiable);
    bool result = interfaceElements._contains(value);
    interfaceElements._map.remove(value);
    if (result) {
      assert(elementToDomain.containsKey(value));
      elementToDomain.remove(value);
      if (value is MixinApplication && value.subclass != null) {
        // [value] must have been stored in `mixinApplicationSupers`,
        // so for consistency we must remove it from there, too.
        assert(mixinApplicationSupers.containsKey(value.subclass));
        mixinApplicationSupers.remove(value.subclass);
      }
    }
    return result;
  }

  @override
  InterfaceElement? lookup(Object? object) {
    for (InterfaceElement classElement in interfaceElements._map.keys) {
      if (object == classElement) return classElement;
    }
    return null;
  }

  @override
  void removeAll(Iterable<Object?> elements) => elements.forEach(remove);

  @override
  void retainAll(Iterable<Object?> elements) {
    bool test(InterfaceElement element) => !elements.contains(element);
    removeWhere(test);
  }

  @override
  void removeWhere(bool Function(InterfaceElement) test) {
    var toRemove = <InterfaceElement>{};
    for (InterfaceElement classElement in interfaceElements.items) {
      if (test(classElement)) toRemove.add(classElement);
    }
    removeAll(toRemove);
  }

  @override
  void retainWhere(bool Function(InterfaceElement) test) {
    bool invertedTest(InterfaceElement element) => !test(element);
    removeWhere(invertedTest);
  }

  @override
  bool containsAll(Iterable<Object?> other) {
    return interfaceElements.items.toSet().containsAll(other);
  }

  @override
  Set<InterfaceElement> intersection(Set<Object?> other) {
    return interfaceElements.items.toSet().intersection(other);
  }

  @override
  Set<InterfaceElement> union(Set<InterfaceElement> other) {
    return interfaceElements.items.toSet().union(other);
  }

  @override
  Set<InterfaceElement> difference(Set<Object?> other) {
    return interfaceElements.items.toSet().difference(other);
  }

  @override
  void clear() {
    assert(!_unmodifiable);
    interfaceElements.clear();
    elementToDomain.clear();
  }

  @override
  Set<InterfaceElement> toSet() => this;

  /// Returns the superclass of the given [classElement] using the language
  /// semantics rather than the analyzer model (where the superclass is the
  /// syntactic one, i.e., `class C extends B with M..` has superclass `B`,
  /// not the mixin application `B with M`). This method will use the analyzer
  /// data to find the superclass, which means that it will _not_ refrain
  /// from returning a class which is not covered by any particular reflector.
  /// It is up to the caller to check that.
  InterfaceElement? superclassOf(InterfaceElement classElement) {
    // By construction of [MixinApplication]s, their `superclass` is correct.
    if (classElement is MixinApplication) return classElement.superclass;
    // For a regular class whose superclass is also not a mixin application,
    // the analyzer `supertype` is what we want. Note that this gets [null]
    // from [Object], which is intended: We consider that (non-existing) class
    // as covered, and use [null] to represent it; there is no clash with
    // returning [null] to indicate that a superclass is not covered, because
    // this method does not check coverage.
    if (classElement.mixins.isEmpty) {
      return classElement.supertype?.element;
    }
    // [classElement] is now known to be a regular class whose superclass
    // is a mixin application. For each [MixinApplication] `m` we store, if it
    // was created as a superclass of a regular (non mixin application) class
    // `C` then we have stored a mapping from `C` to `m` in the map
    // `mixinApplicationSupers`.
    assert(mixinApplicationSupers.containsKey(classElement));
    return mixinApplicationSupers[classElement];
  }

  /// Returns the _ClassDomain corresponding to the given [classElement],
  /// which must be a member of this [_InterfaceElementEnhancedSet].
  _ClassDomain domainOf(InterfaceElement classElement) {
    assert(elementToDomain.containsKey(classElement));
    return elementToDomain[classElement]!;
  }

  /// Returns the index of the given [classElement] if it is contained
  /// in this [_InterfaceElementEnhancedSet], otherwise [null].
  int? indexOf(Object classElement) {
    return interfaceElements.indexOf(classElement);
  }

  Iterable<_ClassDomain> get domains => elementToDomain.values;
}

/// Used to bundle a [DartType] with information about whether it should be
/// erased (such that, e.g., `List<int>` becomes `List`). The alternative would
/// be to construct a new [InterfaceType] with all-dynamic type arguments in
/// the cases where we need to have the erased type, but constructing such
/// new analyzer data seems to transgress yet another privacy boundary of the
/// analyzer, so we decided that we did not want to do that.
class ErasableDartType {
  final DartType dartType;
  final bool erased;
  final bool isNullable;  // NEW: Track nullability

  ErasableDartType(this.dartType, {required this.erased}) : isNullable = dartType.nullabilitySuffix == NullabilitySuffix.question;

  @override
  bool operator ==(other) { 
    return
      other is ErasableDartType &&
      other.dartType == dartType &&
      other.erased == erased &&
      other.isNullable == isNullable;
  }

  @override
  int get hashCode => dartType.hashCode ^ erased.hashCode ^ isNullable.hashCode;

  @override
  String toString() => 'ErasableDartType($dartType, $erased)';
}

/// Models the shape of a parameter list, which enables invocation to detect
/// mismatches such that we can raise a suitable no-such-method error.
class ParameterListShape {
  final int numberOfPositionalParameters;
  final int numberOfOptionalPositionalParameters;
  final Set<String> namesOfNamedParameters;

  const ParameterListShape(
    this.numberOfPositionalParameters,
    this.numberOfOptionalPositionalParameters,
    this.namesOfNamedParameters,
  );

  @override
  bool operator ==(other) => other is ParameterListShape
      ? numberOfPositionalParameters == other.numberOfPositionalParameters &&
            numberOfOptionalPositionalParameters ==
                other.numberOfOptionalPositionalParameters &&
            namesOfNamedParameters
                .difference(other.namesOfNamedParameters)
                .isEmpty
      : false;

  @override
  int get hashCode =>
      numberOfPositionalParameters.hashCode ^
      numberOfOptionalPositionalParameters.hashCode;

  String get code {
    var names = 'null';
    if (namesOfNamedParameters.isNotEmpty) {
      Iterable<String> symbols = namesOfNamedParameters.map((name) => '#$name');
      names = 'const ${_formatAsDynamicList(symbols)}';
    }
    return 'const [$numberOfPositionalParameters, '
        '$numberOfOptionalPositionalParameters, $names]';
  }
}
