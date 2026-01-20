// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

class _ReflectionWorld {
  final LibraryResolver resolver;
  final List<LibraryElementImpl> libraries;
  final FileId generatedLibraryId;
  final List<_ReflectorDomain> reflectors;
  final LibraryElement reflectionLibrary;
  final LibraryElement entryPointLibrary;
  final _ImportCollector importCollector;

  /// Used to collect the names of covered members during `generateCode`, then
  /// used by `generateSymbolMap` to generate code for a mapping from symbols
  /// to the corresponding strings.
  final Set<String> memberNames = <String>{};

  _ReflectionWorld(
    this.resolver,
    this.libraries,
    this.generatedLibraryId,
    this.reflectors,
    this.reflectionLibrary,
    this.entryPointLibrary,
    this.importCollector,
  );

  /// The inverse relation of `superinterfaces` union `superclass`, globally.
  Map<InterfaceElement, Set<InterfaceElement>> get subtypes {
    if (_subtypesCache != null) return _subtypesCache!;

    // Initialize [_subtypesCache], ready to be filled in.
    var subtypes = <InterfaceElement, Set<InterfaceElement>>{};

    void addSubtypeRelation(
      InterfaceElement supertype,
      InterfaceElement subtype,
    ) {
      Set<InterfaceElement>? subtypesOfSupertype = subtypes[supertype];
      if (subtypesOfSupertype == null) {
        subtypesOfSupertype = <InterfaceElement>{};
        subtypes[supertype] = subtypesOfSupertype;
      }
      subtypesOfSupertype.add(subtype);
    }

    // Fill in [_subtypesCache].
    for (LibraryElementImpl library in libraries) {
      void addInterfaceElement(InterfaceElement interfaceElement) {
        InterfaceType? supertype = interfaceElement.supertype;
        if (interfaceElement.mixins.isEmpty) {
          InterfaceElement? supertypeElement = supertype?.element;
          if (supertypeElement != null) {
            addSubtypeRelation(supertypeElement, interfaceElement);
          }
        } else {
          // Mixins must be applied to a superclass, so it is not null.
          InterfaceElement superclass = supertype!.element;
          // Iterate over all mixins in most-general-first order (so with
          // `class C extends B with M1, M2..` we visit `M1` then `M2`.
          for (InterfaceType mixin in interfaceElement.mixins) {
            InterfaceElement mixinElement = mixin.element;
            InterfaceElement? subClass = mixin == interfaceElement.mixins.last
                ? interfaceElement
                : null;
            String? name = subClass == null
                ? null
                : (interfaceElement is MixinApplication &&
                          interfaceElement.isMixinApplication
                      ? interfaceElement.name
                      : null);
            var mixinApplication = MixinApplication(
              name,
              superclass,
              mixinElement,
              library,
              subClass,
            );
            addSubtypeRelation(superclass, mixinApplication);
            addSubtypeRelation(mixinElement, mixinApplication);
            if (subClass != null) {
              addSubtypeRelation(mixinApplication, subClass);
            }
            superclass = mixinApplication;
          }
        }
        for (InterfaceType type in interfaceElement.interfaces) {
          addSubtypeRelation(type.element, interfaceElement);
        }
      }

      for (ClassElement interfaceElement in library.classes) {
        addInterfaceElement(interfaceElement);
      }
      for (EnumElement interfaceElement in library.enums) {
        addInterfaceElement(interfaceElement);
      }
    }
    return _subtypesCache =
        Map<InterfaceElement, Set<InterfaceElement>>.unmodifiable(subtypes);
  }

  Map<InterfaceElement, Set<InterfaceElement>>? _subtypesCache;

  /// Returns code which will create all the data structures (esp. mirrors)
  /// needed to enable the correct behavior for all [reflectors].
  Future<String> generateCode(List<WarningKind> suppressedWarnings) async {
    var typedefs = <FunctionType, int>{};
    var typeVariablesInScope = <String>{}; // None at top level.
    var typedefsCode = '\n';
    var reflectorsCode = <String>[];
    for (_ReflectorDomain reflector in reflectors) {
      String reflectorCode = await reflector._generateCode(
        this,
        importCollector,
        typedefs,
        suppressedWarnings,
      );
      if (typedefs.isNotEmpty) {
        for (DartType dartType in typedefs.keys) {
          String body = await reflector._typeCodeOfTypeArgument(
            dartType,
            importCollector,
            typeVariablesInScope,
            typedefs,
            suppressedWarnings,
            useNameOfGenericFunctionType: false,
          );
          typedefsCode +=
              '\ntypedef ${_typedefName(typedefs[dartType]!)} = $body;';
        }
        typedefs.clear();
      }
      reflectorsCode.add(
        '${await reflector._constConstructionCode(importCollector)}: '
        '$reflectorCode',
      );
    }
    return 'final _data = <r.Reflection, r.ReflectorData>'
        '${_formatAsMap(reflectorsCode)};$typedefsCode';
  }

  /// Returns code which defines a mapping from symbols for covered members
  /// to the corresponding strings. Note that the data needed for doing this
  /// is collected during the execution of `generateCode`, which means that
  /// this method must be called after `generateCode`.
  String generateSymbolMap() {
    if (reflectors.any(
      (_ReflectorDomain reflector) =>
          reflector._capabilities._impliesMemberSymbols,
    )) {
      // Generate the mapping when requested, even if it is empty.
      String mapping = _formatAsMap(
        memberNames.map((String name) => "const Symbol(r'$name'): r'$name'"),
      );
      return mapping;
    } else {
      // The value `null` unambiguously indicates lack of capability.
      return 'null';
    }
  }
}
