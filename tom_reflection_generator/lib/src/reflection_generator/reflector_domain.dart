// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

class _ReflectorDomain {
  late final _ReflectionWorld _world;
  final LibraryResolver _resolver;
  final FileId _generatedLibraryId;
  final InterfaceElement _reflector;

  /// Do not use this, use [classes] which ensures that closure operations
  /// have been performed as requested in [_capabilities]. Exception: In
  /// `_computeWorld`, [_classes] is filled in with the set of directly
  /// covered classes during creation of this [_ReflectorDomain].
  /// NB: [_classes] should be final, but it is not possible because this
  /// would create a cycle of final fields, which cannot be initialized.
  late final _InterfaceElementEnhancedSet _classes;

  /// Used by [classes], only, to keep track of whether [_classes] has been
  /// properly initialized by means of closure operations.
  bool _classesInitialized = false;

  /// Returns the set of classes covered by `_reflector`, including the ones
  /// which are directly covered by carrying `_reflector` as metadata or being
  /// matched by a global quantifier, and including the ones which are reached
  /// via the closure operations requested in [_capabilities].
  Future<_InterfaceElementEnhancedSet> get classes async {
    if (!_classesInitialized) {
      if (_capabilities._impliesDownwardsClosure) {
        await _SubtypesFixedPoint(_world.subtypes).expand(_classes);
      }
      if (_capabilities._impliesUpwardsClosure) {
        await _SuperclassFixedPoint(
          await _capabilities._upwardsClosureBounds,
          _capabilities._impliesMixins,
        ).expand(_classes);
      } else {
        // Even without an upwards closure we cover some superclasses, namely
        // mixin applications where the class applied as a mixin is covered (it
        // seems natural to cover applications of covered mixins and there is
        // no other way to request that, other than requesting a full upwards
        // closure which might add many more classes).
        _mixinApplicationsOfClasses(_classes).forEach(_classes.add);
      }
      if (_capabilities._impliesTypes &&
          _capabilities._impliesTypeAnnotations) {
        var fix = _AnnotationClassFixedPoint(
          _resolver,
          _generatedLibraryId,
          _classes.domainOf,
        );
        if (_capabilities._impliesTypeAnnotationClosure) {
          await fix.expand(_classes);
        } else {
          await fix.singleExpand(_classes);
        }
      }
      _classesInitialized = true;
    }
    return _classes;
  }

  final Enumerator<LibraryElement> _libraries = Enumerator<LibraryElement>();

  final _Capabilities _capabilities;

  _ReflectorDomain(
    this._resolver,
    this._generatedLibraryId,
    this._reflector,
    this._capabilities,
  ) {
    _classes = _InterfaceElementEnhancedSet(this);
  }

  final _instanceMemberCache =
      <InterfaceElement, Map<String, ExecutableElement>>{};

  /// Returns a string that evaluates to a closure invoking [constructor] with
  /// the given arguments.
  /// [importCollector] is used to record all the imports needed to make the
  /// constant.
  /// This is to provide something that can be called with [Function.apply].
  ///
  /// For example for a constructor Foo(x, {y: 3}):
  /// returns "(x, {y: 3}) => prefix1.Foo(x, y)", and records an import of
  /// the library of `Foo` associated with prefix1 in [importCollector].
  Future<String> _constructorCode(
    ConstructorElement constructor,
    _ImportCollector importCollector,
  ) async {
    FunctionType type = constructor.type;

    int requiredPositionalCount = type.normalParameterTypes.length;
    int optionalPositionalCount = type.optionalParameterTypes.length;

    List<String> parameterNames = type.formalParameters
        .map((FormalParameterElement parameter) => parameter.nameOrUnknown)
        .toList();

    List<String> namedParameterNames = type.namedParameterTypes.keys.toList();

    // Special casing the `List` default constructor.
    //
    // After a bit of hesitation, we decided to special case `dart.core.List`.
    // The issue is that the default constructor for `List` has a representation
    // which is platform dependent and which is reflected imprecisely by the
    // analyzer model: The analyzer data claims that it is external, and that
    // its optional `length` argument has no default value. But it actually has
    // two different default values, one on the vm and one in dart2js generated
    // code. We handle this special case by ensuring that `length` is passed if
    // it differs from `null`, and otherwise we perform the invocation of the
    // constructor with no arguments; this will suppress the error in the case
    // where the caller specifies an explicit `null` argument, but otherwise
    // faithfully reproduce the behavior of non-reflective code, and that is
    // probably the closest we can get. We could specify a different default
    // argument (say, "Hello, world!") and then test for that value, but that
    // would suppress an error in a very-hard-to-explain case, so that's safer
    // in a sense, but too weird.
    if (constructor.library.isDartCore &&
        constructor.enclosingElement.name == 'List' &&
        constructor.name == '') {
      return '(bool b) => ([length]) => '
          'b ? (length == null ? [] : List.filled(length, null)) : null';
    }

    String positionals = Iterable.generate(
      requiredPositionalCount,
      (int i) => parameterNames[i],
    ).join(', ');

    var optionalsWithDefaultList = <String>[];
    for (var i = 0; i < optionalPositionalCount; i++) {
      String code = await _extractDefaultValueCode(
        importCollector,
        constructor.formalParameters[requiredPositionalCount + i],
      );
      var defaultPart = code.isEmpty ? '' : ' = $code';
      optionalsWithDefaultList.add(
        '${parameterNames[requiredPositionalCount + i]}$defaultPart',
      );
    }
    String optionalsWithDefaults = optionalsWithDefaultList.join(', ');

    var namedWithDefaultList = <String>[];
    for (var i = 0; i < namedParameterNames.length; i++) {
      // Note that the use of `requiredPositionalCount + i` below relies
      // on a language design where no parameter list can include
      // both optional positional and named parameters, so if there are
      // any named parameters then all optional parameters are named.
      FormalParameterElement parameterElement =
          constructor.formalParameters[requiredPositionalCount + i];
      String code = await _extractDefaultValueCode(
        importCollector,
        parameterElement,
      );
      var defaultPart = code.isEmpty ? '' : ' = $code';
      namedWithDefaultList.add('${parameterElement.name}$defaultPart');
    }
    String namedWithDefaults = namedWithDefaultList.join(', ');

    String optionalArguments = Iterable.generate(
      optionalPositionalCount,
      (int i) => parameterNames[i + requiredPositionalCount],
    ).join(', ');
    String namedArguments = namedParameterNames
        .map((String name) => '$name: $name')
        .join(', ');

    var parameterParts = <String>[];
    var argumentParts = <String>[];

    if (requiredPositionalCount != 0) {
      parameterParts.add(positionals);
      argumentParts.add(positionals);
    }
    if (optionalPositionalCount != 0) {
      parameterParts.add('[$optionalsWithDefaults]');
      argumentParts.add(optionalArguments);
    }
    if (namedParameterNames.isNotEmpty) {
      parameterParts.add('{$namedWithDefaults}');
      argumentParts.add(namedArguments);
    }

    var doRunArgument = 'b';
    while (parameterNames.contains(doRunArgument)) {
      doRunArgument = '${doRunArgument}b';
    }

    String prefix = importCollector._getPrefix(constructor.library);
    String? constructorName = await _nameOfConstructor(constructor);
    String constructorInvocation = constructorName != null
        ? '$prefix$constructorName(${argumentParts.join(', ')})'
        : 'null';
    return ('(bool $doRunArgument) => (${parameterParts.join(', ')}) => '
        '$doRunArgument ? $constructorInvocation : null');
  }

  /// The code of the const-construction of this reflector.
  Future<String> _constConstructionCode(
    _ImportCollector importCollector,
  ) async {
    String prefix = importCollector._getPrefix(_reflector.library);
    final reflectorName = _reflector.nameOrUnknown;
    if (_isPrivateName(reflectorName)) {
      await _severe(
        'reflector.const_construction.private_00',
        'Cannot access private reflector name `$reflectorName`. '
        'Library: ${_reflector.library.name}',
        _reflector,
      );
    }
    return 'const $prefix$reflectorName()';
  }

  /// Generate the code which will create a `ReflectorData` instance
  /// containing the mirrors and other reflection data which is needed for
  /// `_reflector` to behave correctly.
  Future<String> _generateCode(
    _ReflectionWorld world,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    List<WarningKind> suppressedWarnings,
  ) async {
    // Library related collections.
    var libraries = Enumerator<_LibraryDomain>();
    var libraryMap = <LibraryElement, _LibraryDomain>{};
    var topLevelVariables = Enumerator<TopLevelVariableElement>();

    // Class related collections.
    var fields = Enumerator<FieldElement>();
    var typeParameters = Enumerator<TypeParameterElement>();
    // Reflected types not in `classes`; appended to `ReflectorData.types`.
    var reflectedTypes = Enumerator<ErasableDartType>();
    var instanceGetterNames = <String>{};
    var instanceSetterNames = <String>{};

    // Library and class related collections.
    var members = Enumerator<ExecutableElement>();
    var parameters = Enumerator<FormalParameterElement>();
    var parameterListShapes = Enumerator<ParameterListShape>();
    var parameterListShapeOf = <ExecutableElement, ParameterListShape>{};

    // Class element for [Object], needed as implicit upper bound. Initialized
    // if needed.
    InterfaceElement? objectInterfaceElement;

    /// Adds a library domain for [library] to [libraries], relying on checks
    /// for importability and insertion into [importCollector] to have taken
    /// place already.
    void uncheckedAddLibrary(LibraryElement library) {
      _LibraryDomain libraryDomain = _createLibraryDomain(library, this);
      libraries.add(libraryDomain);
      libraryMap[library] = libraryDomain;
      libraryDomain._declarations.forEach(members.add);
      libraryDomain._declaredParameters.forEach(parameters.add);
      libraryDomain._declaredVariables.forEach(topLevelVariables.add);
    }

    /// Used to add a library domain for [library] to [libraries], checking
    /// that it is importable and registering it with [importCollector].
    Future<void> addLibrary(LibraryElement library) async {
      if (!await _isImportableLibrary(
        library,
        _generatedLibraryId,
        _resolver,
      )) {
        return;
      }
      importCollector._addLibrary(library);
      uncheckedAddLibrary(library);
    }

    // Fill in [libraries], [typeParameters], [members], [fields],
    // [parameters], [instanceGetterNames], and [instanceSetterNames].
    _libraries.items.forEach(uncheckedAddLibrary);
    for (InterfaceElement classElement in await classes) {
      LibraryElement classLibrary = classElement.library;
      if (!libraries.items.any(
        (_LibraryDomain libraryDomain) =>
            libraryDomain._libraryElement == classLibrary,
      )) {
        unawaited(addLibrary(classLibrary));
      }
      classElement.typeParameters.forEach(typeParameters.add);
    }
    for (_ClassDomain classDomain in (await classes).domains) {
      // Gather the behavioral interface into [members]. Note that
      // this includes implicitly generated getters and setters, but
      // omits fields. Also note that this does not match the
      // semantics of the `declarations` method in a [ClassMirror].
      classDomain._declarations.forEach(members.add);

      // Add the behavioral interface from this class (redundantly, for
      // non-static members) and all superclasses (which matters) to
      // [members], such that it contains both the behavioral parts for
      // the target class and its superclasses, and the program structure
      // oriented parts for the target class (omitting those from its
      // superclasses).
      classDomain._instanceMembers.forEach(members.add);

      // Add all the formal parameters (as a single, global set) which
      // are declared by any of the methods in `classDomain._declarations`
      // as well as in `classDomain._instanceMembers`.
      classDomain._declaredParameters.forEach(parameters.add);
      classDomain._instanceParameters.forEach(parameters.add);

      // Gather the fields declared in the target class (not inherited
      // ones) in [fields], i.e., the elements missing from [members]
      // at this point, in order to support `declarations` in a
      // [ClassMirror].
      classDomain._declaredFields.forEach(fields.add);

      // Ensure that we include variables corresponding to the implicit
      // accessors that we have included into `members`.
      for (ExecutableElement element in members.items) {
        if (element is PropertyAccessorElement && element.isSynthetic) {
          PropertyInducingElement? variable = element.variable;
          if (variable is FieldElement) {
            fields.add(variable);
          } else if (variable is TopLevelVariableElement) {
            topLevelVariables.add(variable);
          } else {
            await _severe(
              'field.variable_type.unsupported',
              'This kind of variable is not yet supported: '
              '${variable.runtimeType}. Variable: ${variable.name}, '
              'Enclosing: ${variable.enclosingElement?.name}',
              variable,
            );
          }
        }
      }

      // Gather all getter and setter names based on [instanceMembers],
      // including both explicitly declared ones, implicitly generated ones
      // for fields, and the implicitly generated ones that correspond to
      // method tear-offs.
      for (ExecutableElement instanceMember in classDomain._instanceMembers) {
        final instanceMemberName = instanceMember.nameOrUnknown;
        if (instanceMember is PropertyAccessorElement) {
          // A getter or a setter, synthetic or declared.
          if (instanceMember is GetterElement) {
            instanceGetterNames.add(instanceMemberName);
          } else {
            instanceSetterNames.add("$instanceMemberName=");
          }
        } else if (instanceMember is MethodElement) {
          instanceGetterNames.add(instanceMemberName);
        } else {
          // `instanceMember` is a ConstructorElement.
          // Even though a generative constructor has a false
          // `isStatic`, we do not wish to include them among
          // instanceGetterNames, so we do nothing here.
        }
      }
    }

    // Add classes used as bounds for type variables, if needed.
    if (_capabilities._impliesTypes && _capabilities._impliesTypeAnnotations) {
      Future<void> addClass(InterfaceElement classElement) async {
        (await classes).add(classElement);
        LibraryElement classLibrary = classElement.library;
        if (!libraries.items.any(
          (domain) => domain._libraryElement == classLibrary,
        )) {
          uncheckedAddLibrary(classLibrary);
        }
      }

      var hasObject = false;
      var mustHaveObject = false;
      var classesToAdd = <InterfaceElement>{};
      InterfaceElement? anyInterfaceElement;
      for (InterfaceElement classElement in await classes) {
        if (_typeForReflection(classElement).isDartCoreObject) {
          hasObject = true;
          objectInterfaceElement = classElement;
          break;
        }
        if (classElement.typeParameters.isNotEmpty) {
          for (TypeParameterElement typeParameterElement
              in classElement.typeParameters) {
            DartType? typeParameterElementBound = typeParameterElement.bound;
            if (typeParameterElementBound == null) {
              mustHaveObject = true;
              anyInterfaceElement = classElement;
            } else {
              if (typeParameterElementBound is InterfaceType) {
                Element? boundElement = typeParameterElementBound.element;
                if (boundElement is InterfaceElement) {
                  classesToAdd.add(boundElement);
                }
              }
            }
          }
        }
      }
      if (mustHaveObject && !hasObject) {
        // If `mustHaveObject` is true then `anyInterfaceElement` is non-null.
        InterfaceElement someInterfaceElement = anyInterfaceElement!;
        while (!_typeForReflection(someInterfaceElement).isDartCoreObject) {
          InterfaceType? someInterfaceType = someInterfaceElement.supertype;
          someInterfaceElement = someInterfaceType!.element;
        }
        objectInterfaceElement = someInterfaceElement;
        await addClass(objectInterfaceElement);
      }
      for (var clazz in classesToAdd) {
        await addClass(clazz);
      }
    }

    // From this point, [classes] must be kept immutable.
    (await classes).makeUnmodifiable();

    // Record the names of covered members, if requested.
    if (_capabilities._impliesMemberSymbols) {
      for (ExecutableElement executableElement in members.items) {
        final executableElementName = executableElement.nameOrUnknown;
        _world.memberNames.add(
          executableElement is SetterElement
              ? "$executableElementName="
              : executableElementName,
        );
      }
    }

    // Record the method parameter list shapes, if requested.
    if (_capabilities._impliesParameterListShapes) {
      for (ExecutableElement element in members.items) {
        var count = 0;
        var optionalCount = 0;
        var names = <String>{};
        for (FormalParameterElement parameter in element.formalParameters) {
          if (!parameter.isNamed) count++;
          if (parameter.isOptionalPositional) optionalCount++;
          if (parameter.isNamed) names.add(parameter.nameOrUnknown);
        }
        var shape = ParameterListShape(count, optionalCount, names);
        parameterListShapes.add(shape);
        parameterListShapeOf[element] = shape;
      }
    }

    // Find the offsets of fields in members, and of methods and functions
    // in members, of type variables in type mirrors, and of `reflectedTypes`
    // in types.
    final int fieldsOffset = topLevelVariables.length;
    final int methodsOffset = fieldsOffset + fields.length;
    final int typeParametersOffset = (await classes).length;
    final reflectedTypesOffset = typeParametersOffset;

    // Generate code for creation of class mirrors.
    var typeMirrorsList = <String>[];
    if (_capabilities._impliesTypes || _capabilities._impliesInstanceInvoke) {
      for (_ClassDomain classDomain in (await classes).domains) {
        typeMirrorsList.add(
          await _classMirrorCode(
            classDomain,
            typeParameters,
            fields,
            fieldsOffset,
            methodsOffset,
            typeParametersOffset,
            members,
            parameterListShapes,
            parameterListShapeOf,
            reflectedTypes,
            reflectedTypesOffset,
            libraries,
            libraryMap,
            importCollector,
            typedefs,
          ),
        );
      }
      for (TypeParameterElement typeParameterElement in typeParameters.items) {
        typeMirrorsList.add(
          await _typeParameterMirrorCode(
            typeParameterElement,
            importCollector,
            objectInterfaceElement,
          ),
        );
      }
    }
    String classMirrorsCode = _formatAsList('m.TypeMirror', typeMirrorsList);

    // Generate code for creation of getter and setter closures.
    String gettersCode = _formatAsMap(instanceGetterNames.map(_gettingClosure));
    String settersCode = _formatAsMap(instanceSetterNames.map(_settingClosure));

    bool reflectedTypeRequested = _capabilities._impliesReflectedType;

    // Generate code for creation of member mirrors.
    var topLevelVariablesList = <String>[];
    for (TopLevelVariableElement element in topLevelVariables.items) {
      topLevelVariablesList.add(
        await _topLevelVariableMirrorCode(
          element,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs,
          reflectedTypeRequested,
        ),
      );
    }
    var fieldsList = <String>[];
    for (FieldElement element in fields.items) {
      fieldsList.add(
        await _fieldMirrorCode(
          element,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs,
          reflectedTypeRequested,
        ),
      );
    }
    var membersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      var methodsList = <String>[];
      for (ExecutableElement executableElement in members.items) {
        methodsList.add(
          await _methodMirrorCode(
            executableElement,
            topLevelVariables,
            fields,
            members,
            reflectedTypes,
            reflectedTypesOffset,
            parameters,
            importCollector,
            typedefs,
            reflectedTypeRequested,
          ),
        );
      }
      Iterable<String> membersList = [
        ...topLevelVariablesList,
        ...fieldsList,
        ...methodsList,
      ];
      membersCode = _formatAsList('m.DeclarationMirror', membersList);
    }

    // Generate code for creation of parameter mirrors.
    var parameterMirrorsCode = 'null';
    if (_capabilities._impliesDeclarations) {
      var parametersList = <String>[];
      for (FormalParameterElement element in parameters.items) {
        parametersList.add(
          await _parameterMirrorCode(
            element,
            fields,
            members,
            reflectedTypes,
            reflectedTypesOffset,
            importCollector,
            typedefs,
            reflectedTypeRequested,
          ),
        );
      }
      parameterMirrorsCode = _formatAsList('m.ParameterMirror', parametersList);
    }

    // Generate code for listing [Type] instances.
    var typesCodeList = <String>[];
    for (InterfaceElement classElement in await classes) {
      typesCodeList.add(_dynamicTypeCodeOfClass(classElement, importCollector));
    }
    for (ErasableDartType erasableDartType in reflectedTypes.items) {
      if (erasableDartType.erased) {
        var interfaceType = erasableDartType.dartType as InterfaceType;
        typesCodeList.add(
          _dynamicTypeCodeOfClass(interfaceType.element, importCollector),
        );
      } else {
        typesCodeList.add(
          await _typeCodeOfClass(
            erasableDartType.dartType,
            importCollector,
            typedefs,
            suppressedWarnings,
          ),
        );
      }
    }
    String typesCode = _formatAsList('Type', typesCodeList);

    // Generate code for creation of library mirrors.
    String librariesCode;
    if (!_capabilities._supportsLibraries) {
      librariesCode = 'null';
    } else {
      var librariesCodeList = <String>[];
      for (_LibraryDomain library in libraries.items) {
        librariesCodeList.add(
          await _libraryMirrorCode(
            library,
            libraries.indexOf(library)!,
            members,
            parameterListShapes,
            parameterListShapeOf,
            topLevelVariables,
            methodsOffset,
            importCollector,
          ),
        );
      }
      librariesCode = _formatAsList('m.LibraryMirror', librariesCodeList);
    }

    String parameterListShapesCode = _formatAsDynamicList(
      parameterListShapes.items.map((ParameterListShape shape) => shape.code),
    );

    if (_unknownNameWasUsed) {
      _unknownNameWasUsed = false;
      await _severe(
        'reflector.generate.nameless_entity',
        'Nameless entity encountered, '
        'please make sure the program has no syntax errors. '
        'Element: ${_unknownNameElement?.runtimeType}',
        _unknownNameElement,
      );
    }

    return 'r.ReflectorData($classMirrorsCode, $membersCode, '
        '$parameterMirrorsCode, $typesCode, $reflectedTypesOffset, '
        '$gettersCode, $settersCode, $librariesCode, '
        '$parameterListShapesCode)';
  }

  Future<int> _computeTypeIndexBase(
    Element? typeElement,
    bool isVoid,
    bool isDynamic,
    bool isNever,
    bool isClassType,
  ) async {
    if (_capabilities._impliesTypes) {
      if (isDynamic || isVoid || isNever) {
        // The mirror will report 'dynamic', 'void', 'Never',
        // and it will never use the index.
        return constants.noCapabilityIndex;
      }
      if (isClassType && (await classes).contains(typeElement)) {
        // Normal encoding of a class type which has been added to `classes`.
        return (await classes).indexOf(typeElement!)!;
      }
      // At this point [typeElement] may be a non-class type, or it may be a
      // class that has not been added to `classes`, say, an argument type
      // annotation in a setting where we do not have an
      // [ec.TypeAnnotationQuantifyCapability]. In both cases we fall through
      // because the relevant capability is absent.
    }
    return constants.noCapabilityIndex;
  }

  Future<int> _computeVariableTypeIndex(
    PropertyInducingElement element,
    int descriptor,
  ) async {
    if (!_capabilities._impliesTypes) return constants.noCapabilityIndex;
    DartType interfaceType = element.type;
    if (interfaceType is! InterfaceType) return constants.noCapabilityIndex;
    return await _computeTypeIndexBase(
      interfaceType.element,
      descriptor & constants.voidAttribute != 0,
      descriptor & constants.dynamicAttribute != 0,
      descriptor & constants.neverAttribute != 0,
      descriptor & constants.classTypeAttribute != 0,
    );
  }

  Future<bool> _hasSupportedReflectedTypeArguments(DartType dartType) async {
    if (dartType is ParameterizedType) {
      for (DartType typeArgument in dartType.typeArguments) {
        if (!await _hasSupportedReflectedTypeArguments(typeArgument)) {
          return false;
        }
      }
      return true;
    } else if (dartType is VoidType) {
      return true;
    } else if (dartType is TypeParameterType || dartType is DynamicType) {
      return false;
    } else {
      await _severe(
        'type.reflected_type_args.unsupported_nested',
        '`reflectedTypeArguments` where an actual type argument '
        '(possibly nested) is $dartType (type: ${dartType.runtimeType})',
      );
      return false;
    }
  }

  Future<String> _computeReflectedTypeArguments(
    DartType dartType,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
  ) async {
    if (dartType is InterfaceType) {
      List<TypeParameterElement> typeParameters =
          dartType.element.typeParameters;
      if (typeParameters.isEmpty) {
        // We have no formal type parameters, so there cannot be any actual
        // type arguments.
        return 'const <int>[]';
      } else {
        // We have some formal type parameters: `dartType` is a generic class.
        List<DartType> typeArguments = dartType.typeArguments;
        // This method is called with variable/parameter type annotations and
        // function return types, and they denote instantiated generic classes
        // rather than "original" generic classes; so they do have actual type
        // arguments when there are formal type parameters.
        assert(typeArguments.length == typeParameters.length);
        var allTypeArgumentsSupported = true;
        for (var typeArgument in typeArguments) {
          if (!await _hasSupportedReflectedTypeArguments(typeArgument)) {
            allTypeArgumentsSupported = false;
            break;
          }
        }
        if (allTypeArgumentsSupported) {
          var typesIndices = <int?>[];
          for (var actualTypeArgument in typeArguments) {
            if (actualTypeArgument is InterfaceType ||
                actualTypeArgument is VoidType ||
                actualTypeArgument is DynamicType) {
              await _fine(
                'type.reflected_type_args.adding',
                'Adding reflected type argument '
                '$actualTypeArgument (nullability: ${actualTypeArgument.nullabilitySuffix}) '
                'for $dartType',
              );
              typesIndices.add(
                _dynamicTypeCodeIndex(
                  actualTypeArgument,
                  await classes,
                  reflectedTypes,
                  reflectedTypesOffset,
                  typedefs,
                ),
              );
            } else {
              // TODO(eernst) clarify: Are `dynamic` et al `InterfaceType`s?
              // Otherwise this means "a case that we have not it considered".
              await _severe(
                'type.reflected_type_args.unsupported',
                '`reflectedTypeArguments` where one actual type argument'
                ' is $actualTypeArgument (type: ${actualTypeArgument.runtimeType})',
              );
              typesIndices.add(0);
            }
          }
          return _formatAsConstList('int', typesIndices);
        } else {
          return 'null';
        }
      }
    } else {
      // If the type is not a ParameterizedType then it has no type arguments.
      return 'const <int>[]';
    }
  }

  Future<int> _computeReturnTypeIndex(
    ExecutableElement element,
    int descriptor,
  ) async {
    if (!_capabilities._impliesTypes) return constants.noCapabilityIndex;
    DartType interfaceType = element.returnType;
    if (interfaceType is! InterfaceType) return constants.noCapabilityIndex;
    int result = await _computeTypeIndexBase(
      interfaceType.element,
      descriptor & constants.voidReturnTypeAttribute != 0,
      descriptor & constants.dynamicReturnTypeAttribute != 0,
      descriptor & constants.neverReturnTypeAttribute != 0,
      descriptor & constants.classReturnTypeAttribute != 0,
    );
    return result;
  }

  Future<int?> _computeOwnerIndex(
    ExecutableElement element,
    int descriptor,
  ) async {
    final enclosingElement = element.enclosingElement;
    if (enclosingElement is InterfaceElement) {
      return (await classes).indexOf(enclosingElement);
    } else if (enclosingElement?.firstFragment is LibraryFragment) {
      return _libraries.indexOf(element.library);
    }
    await _severe(
      'owner.compute_index.unexpected_kind',
      'Unexpected kind of request for owner. '
      'Element: ${element.name}, enclosing: ${enclosingElement?.runtimeType}',
    );
    return 0;
  }

  Iterable<ExecutableElement> _gettersOfLibrary(_LibraryDomain library) sync* {
    yield* library._accessors.whereType<GetterElement>();
    yield* library._declaredFunctions;
  }

  Iterable<PropertyAccessorElement> _settersOfLibrary(_LibraryDomain library) {
    return library._accessors.whereType<SetterElement>();
  }

  Future<String> _typeParameterMirrorCode(
    TypeParameterElement typeParameterElement,
    _ImportCollector importCollector,
    InterfaceElement? objectInterfaceElement,
  ) async {
    int? upperBoundIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypeAnnotations) {
      DartType? bound = typeParameterElement.bound;
      if (bound == null) {
        assert(objectInterfaceElement != null);
        // Missing bound should be reported as the semantic default: `Object`.
        // We use an ugly hack to obtain the [InterfaceElement] for `Object`.
        upperBoundIndex = (await classes).indexOf(objectInterfaceElement!);
        assert(upperBoundIndex != null);
      } else if (bound is DynamicType) {
        // We use [null] to indicate that this bound is [dynamic] ([void]
        // cannot be a bound, so the only special case is [dynamic]).
        upperBoundIndex = null;
      } else {
        if (bound is InterfaceType) {
          upperBoundIndex = (await classes).indexOf(bound.element);
        } else {
          upperBoundIndex = constants.noCapabilityIndex;
        }
      }
    }
    int? ownerIndex = (await classes).indexOf(
      typeParameterElement.enclosingElement!,
    );
    // TODO(eernst) implement: Update when type variables support metadata.
    var metadataCode = _capabilities._supportsMetadata ? '<Object>[]' : 'null';
    return "r.TypeVariableMirrorImpl(r'${typeParameterElement.name}', "
        "r'${_qualifiedTypeParameterName(typeParameterElement)}', "
        '${await _constConstructionCode(importCollector)}, '
        '$upperBoundIndex, $ownerIndex, $metadataCode)';
  }

  Future<String> _classMirrorCode(
    _ClassDomain classDomain,
    Enumerator<TypeParameterElement> typeParameters,
    Enumerator<FieldElement> fields,
    int fieldsOffset,
    int methodsOffset,
    int typeParametersOffset,
    Enumerator<ExecutableElement> members,
    Enumerator<ParameterListShape> parameterListShapes,
    Map<ExecutableElement, ParameterListShape> parameterListShapeOf,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    Enumerator<_LibraryDomain> libraries,
    Map<LibraryElement, _LibraryDomain> libraryMap,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
  ) async {
    int descriptor = _classDescriptor(classDomain._interfaceElement);

    // Fields go first in [memberMirrors], so they will get the
    // same index as in [fields].
    Iterable<int> fieldsIndices = classDomain._declaredFields.map((
      FieldElement element,
    ) {
      try {
        return fields.indexOf(element)! + fieldsOffset;
      }catch(e){
        log.warning(
          '[field.member_mirror.index_failed] '
          'Failed to get field index for ${element.name}. '
          'Enclosing: ${element.enclosingElement.name}, '
          'Base: ${element.baseElement.name}',
        );
        return 0;
      }
    });

    // All the elements in the behavioral interface go after the
    // fields in [memberMirrors], so they must get an offset of
    // `fields.length` on the index.
    Iterable<int> methodsIndices = classDomain._declarations
        .where(_executableIsntImplicitGetterOrSetter)
        .map((ExecutableElement element) {
          // TODO(eernst) implement: The "magic" default constructor in `Object`
          // (the one that ultimately allocates the memory for _every_ new
          // object) has no index, which creates the need to catch a `null`
          // here. Search for "magic" to find other occurrences of the same
          // issue. For now, we use the index [constants.noCapabilityIndex]
          // for this declaration, because it is not yet supported.
          // Need to find the correct solution, though!
          int? index = members.indexOf(element);
          return index == null
              ? constants.noCapabilityIndex
              : index + methodsOffset;
        });

    String declarationsCode = _capabilities._impliesDeclarations
        ? _formatAsConstList('int', [...fieldsIndices, ...methodsIndices])
        : 'const <int>[${constants.noCapabilityIndex}]';

    // All instance members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    var instanceMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      instanceMembersCode = _formatAsConstList(
        'int',
        classDomain._instanceMembers.map((ExecutableElement element) {
          // TODO(eernst) implement: The "magic" default constructor has
          // index: noCapabilityIndex; adjust this when support for it has
          // been implemented.
          int? index = members.indexOf(element);
          return index == null
              ? constants.noCapabilityIndex
              : index + methodsOffset;
        }),
      );
    }

    // All static members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    var staticMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      staticMembersCode = _formatAsConstList(
        'int',
        classDomain._staticMembers.map((ExecutableElement element) {
          int? index = members.indexOf(element);
          return index == null
              ? constants.noCapabilityIndex
              : index + methodsOffset;
        }),
      );
    }

    InterfaceElement interfaceElement = classDomain._interfaceElement;
    InterfaceElement? superclass = (await classes).superclassOf(
      interfaceElement,
    );

    var superclassIndex = '${constants.noCapabilityIndex}';
    if (_capabilities._impliesTypeRelations) {
      // [Object]'s superclass is reported as `null`: it does not exist and
      // hence we cannot decide whether it's supported or unsupported.; by
      // convention we make it supported and report it in the same way as
      // 'dart:mirrors'. Other superclasses use `noCapabilityIndex` to
      // indicate missing support.
      superclassIndex =
          (interfaceElement is! MixinApplication &&
              _typeForReflection(interfaceElement).isDartCoreObject)
          ? 'null'
          : ((await classes).contains(superclass))
          ? '${(await classes).indexOf(superclass!)}'
          : '${constants.noCapabilityIndex}';
    }

    String constructorsCode;
    if (interfaceElement is MixinApplication) {
      // There may be any number of constructors, but they are implicitly
      // induced forwarding constructors, so it won't help anybody to be
      // able to get to them. Also, we can't invoke them because the mixin
      // application is an abstract class.
      constructorsCode = 'const {}';
    } else {
      var mapEntries = <String>[];
      for (ConstructorElement constructor in classDomain._constructors) {
        InterfaceElement enclosingElement = constructor.enclosingElement;
        if (constructor.isFactory ||
            ((enclosingElement is ClassElement &&
                    !enclosingElement.isAbstract) &&
                enclosingElement is! EnumElement)) {
          String code = await _constructorCode(constructor, importCollector);
          String constructorName = constructor.nameOrUnknown;
          if (constructorName == "new") {
            constructorName = "";
          }
          mapEntries.add("r'$constructorName': $code");
        }
      }
      constructorsCode = _formatAsMap(mapEntries);
    }

    var staticGettersCode = 'const {}';
    var staticSettersCode = 'const {}';
    if (interfaceElement is! MixinApplication) {
      var staticGettersCodeList = <String>[];
      for (MethodElement method in classDomain._declaredMethods) {
        if (method.isStatic) {
          staticGettersCodeList.add(
            await _staticGettingClosure(
              importCollector,
              interfaceElement,
              method.nameOrUnknown,
            ),
          );
        }
      }
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor is GetterElement) {
          staticGettersCodeList.add(
            await _staticGettingClosure(
              importCollector,
              interfaceElement,
              accessor.nameOrUnknown,
            ),
          );
        }
      }
      staticGettersCode = _formatAsMap(staticGettersCodeList);
      var staticSettersCodeList = <String>[];
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor is SetterElement) {
          staticSettersCodeList.add(
            await _staticSettingClosure(
              importCollector,
              interfaceElement,
              "${accessor.nameOrUnknown}=",
            ),
          );
        }
      }
      staticSettersCode = _formatAsMap(staticSettersCodeList);
    }

    int? mixinIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypeRelations) {
      _InterfaceElementEnhancedSet theClasses = await classes;
      if (interfaceElement is MixinApplication &&
          interfaceElement.isMixinApplication) {
        // Named mixin application (using the syntax `class B = A with M;`).
        mixinIndex = theClasses.indexOf(interfaceElement.mixins.last.element);
      } else if (interfaceElement is MixinApplication) {
        // Anonymous mixin application.
        mixinIndex = theClasses.indexOf(interfaceElement.mixin);
      } else {
        // No mixins, by convention we use the class itself.
        mixinIndex = theClasses.indexOf(interfaceElement);
      }
      // We may not have support for the given class, in which case we must
      // correct the `null` from `indexOf` to indicate missing capability.
      mixinIndex ??= constants.noCapabilityIndex;
    }

    int ownerIndex = _capabilities._supportsLibraries
        ? libraries.indexOf(libraryMap[interfaceElement.library]!)!
        : constants.noCapabilityIndex;

    var superinterfaceIndices = 'const <int>[${constants.noCapabilityIndex}]';
    if (_capabilities._impliesTypeRelations) {
      superinterfaceIndices = _formatAsConstList(
        'int',
        interfaceElement.interfaces
            .map((InterfaceType type) => type.element)
            .where((await classes).contains)
            .map((await classes).indexOf),
      );
    }

    String classMetadataCode;
    if (_capabilities._supportsMetadata) {
      classMetadataCode = await _extractMetadataCode(
        interfaceElement,
        _resolver,
        importCollector,
        _generatedLibraryId,
      );
    } else {
      classMetadataCode = 'null';
    }

    int classIndex = (await classes).indexOf(interfaceElement)!;

    var parameterListShapesCode = 'null';
    if (_capabilities._impliesParameterListShapes) {
      Iterable<ExecutableElement> membersList = [
        ...classDomain._instanceMembers,
        ...classDomain._staticMembers,
      ];
      parameterListShapesCode = _formatAsMap(
        membersList.map((ExecutableElement element) {
          // shape != null: every method must have its shape in `..shapeOf`.
          ParameterListShape shape = parameterListShapeOf[element]!;
          // index != null: every shape must be in `..Shapes`.
          int index = parameterListShapes.indexOf(shape)!;
          String name = element.nameOrUnknown;
          if (element is SetterElement) {
            name += "=";
          }
          if (element.name == "-") {
            name = "unary-";
          }
          return "r'$name': $index";
        }),
      );
    }

    String genericType = _createClassMirrorGenericType(classDomain, importCollector, interfaceElement,"NonGenericClassMirrorImpl");
    if (interfaceElement.typeParameters.isEmpty) {
      return "r.NonGenericClassMirrorImpl$genericType(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(interfaceElement)}', $descriptor, $classIndex, "
          '${await _constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $mixinIndex, '
          '$superinterfaceIndices, $classMetadataCode, '
          '$parameterListShapesCode)';
    } else {
      // We are able to match up a given instance with a given generic type
      // by checking that the instance `is` an instance of the fully dynamic
      // instance of that generic type (for the generic class `List`, that is
      // `List<dynamic>`), and not an instance of any of its immediate subtypes,
      // if any. [isCheckCode] is a function which will test that its argument
      // (1) `is` an instance of the fully dynamic instance of the generic
      // class modeled by [interfaceElement], and (2) that it is not an instance
      // of the fully dynamic instance of any of the classes that `extends` or
      // `implements` this [interfaceElement].
      var isCheckList = <String>[];
      if (interfaceElement.isPrivate ||
          interfaceElement is MixinElement ||
          (interfaceElement is ClassElement && interfaceElement.isAbstract) ||
          (interfaceElement is MixinApplication &&
              !interfaceElement.isMixinApplication) ||
          !await _isImportable(
            interfaceElement,
            _generatedLibraryId,
            _resolver,
          )) {
        // Note that this location is dead code until we get support for
        // anonymous mixin applications using type arguments as generic
        // classes (currently, no classes will pass the tests above). See
        // https://github.com/dart-lang/sdk/issues/25344 for more details.
        // However, the result that we will return is well-defined, because
        // no object can be an instance of an anonymous mixin application.
        isCheckList.add('(o) => false');
      } else {
        String prefix = importCollector._getPrefix(interfaceElement.library);
        isCheckList.add('(o) { return o is $prefix${interfaceElement.name}');

        // Add 'is checks' to [list], based on [interfaceElement].
        Future<void> helper(
          List<String> list,
          InterfaceElement interfaceElement,
        ) async {
          Iterable<InterfaceElement> subtypes =
              _world.subtypes[interfaceElement] ?? <InterfaceElement>[];
          for (var subtype in subtypes) {
            if (subtype.isPrivate ||
                subtype is MixinElement ||
                (subtype is ClassElement && subtype.isAbstract) ||
                (subtype is MixinApplication && !subtype.isMixinApplication) ||
                !await _isImportable(subtype, _generatedLibraryId, _resolver)) {
              await helper(list, subtype);
            } else {
              String prefix = importCollector._getPrefix(subtype.library);
              list.add(' && o is! $prefix${subtype.name}');
            }
          }
        }

        await helper(isCheckList, interfaceElement);
        isCheckList.add('; }');
      }
      String isCheckCode = isCheckList.join();

      var typeParameterIndices = 'null';
      if (_capabilities._impliesDeclarations) {
        int indexOf(TypeParameterElement typeParameter) =>
            typeParameters.indexOf(typeParameter)! + typeParametersOffset;
        typeParameterIndices = _formatAsConstList(
          'int',
          interfaceElement.typeParameters
              .where(typeParameters.items.contains)
              .map(indexOf),
        );
      }

      int? dynamicReflectedTypeIndex = _dynamicTypeCodeIndex(
        _typeForReflection(interfaceElement),
        await classes,
        reflectedTypes,
        reflectedTypesOffset,
        typedefs,
      );

      String genericType = _createClassMirrorGenericType(classDomain, importCollector, interfaceElement,"GenericClassMirrorImpl");
      return "r.GenericClassMirrorImpl$genericType(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(interfaceElement)}', $descriptor, $classIndex, "
          '${await _constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $mixinIndex, '
          '$superinterfaceIndices, $classMetadataCode, '
          '$parameterListShapesCode, $isCheckCode, '
          '$typeParameterIndices, $dynamicReflectedTypeIndex)';
    }
  }

  String _createClassMirrorGenericType(_ClassDomain classDomain, _ImportCollector importCollector, InterfaceElement interfaceElement, String location) {
    String suffix = "";
    String xname = "";
    try {
      if( classDomain._interfaceElement.thisType.nullabilitySuffix == NullabilitySuffix.question ) {
        suffix = "?";
      }
      xname = classDomain._interfaceElement.thisType.toString();
    }catch(e){
      // ignore
    }
    String plainName = classDomain._simpleName;
    // Handle mixin application names which contain " with " keyword
    // or start with "." - extract just the base class name
    if (plainName.startsWith(".")) {
      // Format: ".BaseClass with Mixin1, Mixin2" - extract "BaseClass"
      plainName = plainName.substring(1, plainName.indexOf(" "));
      log.fine(
        '[class_mirror.mixin_name.shortened] '
        'Shortened name to $plainName from ${classDomain._simpleName} '
        'for $xname ($location)',
      );
    } else if (plainName.contains(" with ")) {
      // Format: "qualified.BaseClass with qualified.Mixin1" - extract last part of base class
      final withIndex = plainName.indexOf(" with ");
      final baseClassQualified = plainName.substring(0, withIndex);
      // Get just the simple name (last segment after the last dot)
      final lastDotIndex = baseClassQualified.lastIndexOf(".");
      plainName = lastDotIndex >= 0 
          ? baseClassQualified.substring(lastDotIndex + 1) 
          : baseClassQualified;
      log.fine(
        '[class_mirror.mixin_name.extracted] '
        'Extracted base class $plainName from mixin application '
        '${classDomain._simpleName} ($location)',
      );
    }
    String prefix = importCollector._getPrefix(interfaceElement.library);
    // Exclude types that can't be used as type arguments with Object bound:
    // - Private types (start with _)
    // - Future, FutureOr (special handling / async types)
    // - Null (doesn't extend Object in null-safety)
    bool shouldExclude = plainName.startsWith("_") || 
        plainName == "Future" || 
        plainName == "FutureOr" || 
        plainName == "Null";
    String genericType = shouldExclude ? "" : "<$prefix$plainName$suffix>";
    return genericType;
  }

  Future<String> _methodMirrorCode(
    ExecutableElement element,
    Enumerator<TopLevelVariableElement> topLevelVariables,
    Enumerator<FieldElement> fields,
    Enumerator<ExecutableElement> members,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    Enumerator<FormalParameterElement> parameters,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    bool reflectedTypeRequested,
  ) async {
    if (element is PropertyAccessorElement && element.isSynthetic) {
      // There is no type propagation, so we declare an `accessorElement`.
      PropertyAccessorElement accessorElement = element;
      PropertyInducingElement? variable = accessorElement.variable;
      int variableMirrorIndex = variable is TopLevelVariableElement
          ? topLevelVariables.indexOf(variable)!
          : variable is FieldElement
          ? fields.indexOf(variable)!
          : constants.noCapabilityIndex;
      int selfIndex = members.indexOf(accessorElement)! + fields.length;
      if (accessorElement is GetterElement) {
        return 'r.ImplicitGetterMirrorImpl('
            '${await _constConstructionCode(importCollector)}, '
            '$variableMirrorIndex, $selfIndex)';
      } else {
        assert(accessorElement is SetterElement);
        return 'r.ImplicitSetterMirrorImpl('
            '${await _constConstructionCode(importCollector)}, '
            '$variableMirrorIndex, $selfIndex)';
      }
    } else {
      // [element] is a method, a function, or an explicitly declared
      // getter or setter.
      int descriptor = _declarationDescriptor(element);
      int returnTypeIndex = await _computeReturnTypeIndex(element, descriptor);
      int ownerIndex =
          (await _computeOwnerIndex(element, descriptor)) ??
          constants.noCapabilityIndex;
      var reflectedTypeArgumentsOfReturnType = 'null';
      if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
        reflectedTypeArgumentsOfReturnType =
            await _computeReflectedTypeArguments(
              element.returnType,
              reflectedTypes,
              reflectedTypesOffset,
              importCollector,
              typedefs,
            );
      }
      String parameterIndicesCode = _formatAsConstList(
        'int',
        element.formalParameters.map((FormalParameterElement parameterElement) {
          return parameters.indexOf(parameterElement);
        }),
      );
      int reflectedReturnTypeIndex = constants.noCapabilityIndex;
      if (reflectedTypeRequested) {
        reflectedReturnTypeIndex = _typeCodeIndex(
          element.returnType,
          await classes,
          reflectedTypes,
          reflectedTypesOffset,
          typedefs,
        );
      }
      int dynamicReflectedReturnTypeIndex = constants.noCapabilityIndex;
      if (reflectedTypeRequested) {
        dynamicReflectedReturnTypeIndex = _dynamicTypeCodeIndex(
          element.returnType,
          await classes,
          reflectedTypes,
          reflectedTypesOffset,
          typedefs,
        );
      }
      String? metadataCode = _capabilities._supportsMetadata
          ? await _extractMetadataCode(
              element,
              _resolver,
              importCollector,
              _generatedLibraryId,
            )
          : null;

      String name = element is SetterElement
          ? "${element.nameOrUnknown}="
          : element.nameOrUnknown;

      if (name == "new") name = "";

      return "r.MethodMirrorImpl(r'$name', $descriptor, "
          '$ownerIndex, $returnTypeIndex, $reflectedReturnTypeIndex, '
          '$dynamicReflectedReturnTypeIndex, '
          '$reflectedTypeArgumentsOfReturnType, $parameterIndicesCode, '
          '${await _constConstructionCode(importCollector)}, $metadataCode)';
    }
  }

  Future<String> _topLevelVariableMirrorCode(
    TopLevelVariableElement element,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    bool reflectedTypeRequested,
  ) async {
    int descriptor = _topLevelVariableDescriptor(element);
    LibraryElement owner = element.library;
    int ownerIndex = _libraries.indexOf(owner) ?? constants.noCapabilityIndex;
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int? reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    int? dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    var reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
        element.type,
        reflectedTypes,
        reflectedTypesOffset,
        importCollector,
        typedefs,
      );
    }
    String? metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
        element,
        _resolver,
        importCollector,
        _generatedLibraryId,
      );
    } else {
      // We encode 'without capability' as `null` for metadata, because
      // it is a `List<Object>`, which has no other natural encoding.
      metadataCode = null;
    }
    return "r.VariableMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, '
        '$dynamicReflectedTypeIndex, $reflectedTypeArguments, '
        '$metadataCode)';
  }

  Future<String> _fieldMirrorCode(
    FieldElement element,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    bool reflectedTypeRequested,
  ) async {
    int descriptor = _fieldDescriptor(element);
    int ownerIndex =
        (await classes).indexOf(element.enclosingElement) ??
        constants.noCapabilityIndex;
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    var reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
        element.type,
        reflectedTypes,
        reflectedTypesOffset,
        importCollector,
        typedefs,
      );
    }
    String? metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
        element,
        _resolver,
        importCollector,
        _generatedLibraryId,
      );
    } else {
      // We encode 'without capability' as `null` for metadata, because
      // it is a `List<Object>`, which has no other natural encoding.
      metadataCode = null;
    }
    return "r.VariableMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, '
        '$dynamicReflectedTypeIndex, $reflectedTypeArguments, $metadataCode)';
  }

  /// Returns the index into `ReflectorData.types` of the [Type] object
  /// corresponding to [dartType]. It may refer to a covered class, in which
  /// case [classes] is used to find it, or it may be outside the set of
  /// covered classes, in which case [reflectedTypes] may already contain it;
  /// otherwise it is not represented anywhere so far, and it is added to
  /// [reflectedTypes]; [reflectedTypesOffset] is used to adjust the index
  /// as computed by [reflectedTypes], because the elements in there will be
  /// added to `ReflectorData.types` after the elements of [classes] have been
  /// added.
  int _typeCodeIndex(
    DartType dartType,
    _InterfaceElementEnhancedSet classes,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    Map<FunctionType, int> typedefs,
  ) {
    // The types `dynamic` and `void` are handled via `...Attribute` bits.
    if (dartType is DynamicType) return constants.noCapabilityIndex;
    if (dartType is VoidType) return constants.noCapabilityIndex;
    if (dartType is InterfaceType) {
      if (dartType.typeArguments.isEmpty) {
        // A plain, non-generic class, may be handled already.
        InterfaceElement interfaceElement = dartType.element;
        if (classes.contains(interfaceElement)) {
          return classes.indexOf(interfaceElement)!;
        }
      }
      // An instantiation of a generic class, or a non-generic class which is
      // not present in `classes`: Use `reflectedTypes`, possibly adding it.
      var erasableDartType = ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      var erasableDartType = ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      var erasableDartType = ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
      if (dartType.typeParameters.isNotEmpty) {
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above. In particular,
    // we cannot produce code to return a value for `void`.
    return constants.noCapabilityIndex;
  }

  /// Returns the index into `ReflectorData.types` of the [Type] object
  /// corresponding to the fully dynamic instantiation of [dartType]. The
  /// fully dynamic instantiation replaces any existing type arguments by
  /// `dynamic`; for a non-generic class it makes no difference. This erased
  /// [Type] object may refer to a covered class, in which case [classes] is
  /// used to find it, or it may be outside the set of covered classes, in
  /// which case [reflectedTypes] may already contain it; otherwise it is not
  /// represented anywhere so far, and it is added to [reflectedTypes];
  /// [reflectedTypesOffset] is used to adjust the index as computed by
  /// [reflectedTypes], because the elements in there will be added to
  /// `ReflectorData.types` after the elements of [classes] have been added.
  int _dynamicTypeCodeIndex(
    DartType dartType,
    _InterfaceElementEnhancedSet classes,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    Map<FunctionType, int> typedefs,
  ) {
    // The types `void` and `dynamic` are handled via the `...Attribute` bits.
    if (dartType is VoidType || dartType is DynamicType) {
      return constants.noCapabilityIndex;
    }
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if (classes.contains(interfaceElement)) {
        return classes.indexOf(interfaceElement)!;
      }
      // [dartType] is not present in `classes`, so we must use `reflectedTypes`
      // and iff it has type arguments we must specify that it should be erased
      // (if there are no type arguments we will use "not erased": erasure
      // makes no difference and we don't want to have two identical copies).
      var erasableDartType = ErasableDartType(
        dartType,
        erased: dartType.typeArguments.isNotEmpty,
      );
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      var erasableDartType = ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      var erasableDartType = ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
      if (dartType.typeParameters.isNotEmpty) {
        // TODO(eernst) clarify: Maybe we should create an "erased" version
        // of `dartType` in this case, and adjust `erased:` above?
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above.
    return constants.noCapabilityIndex;
  }

  /// Returns true iff the given [type] is not and does not contain a free
  /// type variable. [typeVariablesInScope] gives the names of type variables
  /// which are in scope (and hence not free in the relevant context).
  bool _hasNoFreeTypeVariables(
    DartType type, [
    Set<String>? typeVariablesInScope,
  ]) {
    if (type is TypeParameterType &&
        (typeVariablesInScope == null ||
            !typeVariablesInScope.contains(type.getDisplayString()))) {
      return false;
    }
    if (type is InterfaceType) {
      if (type.typeArguments.isEmpty) return true;
      return type.typeArguments.every(
        (type) => _hasNoFreeTypeVariables(type, typeVariablesInScope),
      );
    }
    // Possible kinds of types at this point (apart from several types
    // indicating an error that we do not expect here): `BottomTypeImpl`,
    // `DynamicTypeImpl`, `FunctionTypeImpl`, `VoidTypeImpl`. None of these
    // have type variables.
    return true;
  }

  /// Returns a string containing a type expression that in the generated
  /// library will serve as a type argument with the same meaning as the
  /// [dartType] has where it occurs. The [importCollector] is used to
  /// find the library prefixes needed in order to obtain values from other
  /// libraries. [typeVariablesInScope] is used to allow generation of
  /// type expressions containing type variables which are in scope because
  /// they were introduced by an enclosing generic function type. [typedefs]
  /// is a mapping from generic function types which have had a `typedef`
  /// declaration allocated for them to their indices; it may be extended
  /// as well as used by this function. [useNameOfGenericFunctionType]
  /// is used to decide whether the output should be a simple `typedef`
  /// name or a fully spelled-out generic function type (and it has no
  /// effect when [dartType] is not a generic function type).
  Future<String> _typeCodeOfTypeArgument(
    DartType dartType,
    _ImportCollector importCollector,
    Set<String> typeVariablesInScope,
    Map<FunctionType, int> typedefs,
    List<WarningKind> suppressedWarnings, {
    bool useNameOfGenericFunctionType = true,
    bool includeNullabilitySuffix = true,
  }) async {
    Future<String> fail() async {
      InterfaceElement? element = dartType is InterfaceType
          ? dartType.element
          : null;
      if (!suppressedWarnings.contains(WarningKind.unsupportedType)) {
        log.warning(
          '[type.code_of_type_argument.unsupported] '
          '${await _formatDiagnosticMessage(
            'Attempt to generate code for an '
            'unsupported kind of type: $dartType (${dartType.runtimeType}). '
            'Generating `dynamic`.',
            element,
            _resolver,
          )}',
        );
      }
      return 'dynamic';
    }

    if (dartType is DynamicType) return 'dynamic';
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        return await fail();
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      String suffix = dartType.nullabilitySuffix == NullabilitySuffix.question && includeNullabilitySuffix ? '?' : '';
      if (interfaceElement.typeParameters.isEmpty) {
        return '$prefix${interfaceElement.name}$suffix';
      } else {
        if (dartType.typeArguments.every(
          (type) => _hasNoFreeTypeVariables(type, typeVariablesInScope),
        )) {
          var argumentList = <String>[];
          for (DartType typeArgument in dartType.typeArguments) {
            argumentList.add(
              await _typeCodeOfTypeArgument(
                typeArgument,
                importCollector,
                typeVariablesInScope,
                typedefs,
                suppressedWarnings,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType,
              ),
            );
          }
          String arguments = argumentList.join(', ');
          return '$prefix${interfaceElement.name}<$arguments>$suffix';
        } else {
          return await fail();
        }
      }
    } else if (dartType is VoidType) {
      return 'void';
    } else if (dartType is FunctionType) {
      final Element? dartTypeElement = dartType.alias?.element;
      if (dartTypeElement is TypeAliasElement) {
        String prefix = importCollector._getPrefix(dartTypeElement.library);
        return '$prefix${dartTypeElement.name}';
      } else {
        // Generic function types need separate `typedef`s.
        if (dartType.typeParameters.isNotEmpty) {
          if (useNameOfGenericFunctionType) {
            // Requested: just the name of the typedef; get it and return.
            int dartTypeNumber = typedefs.containsKey(dartType)
                ? typedefs[dartType]!
                : typedefNumber++;
            return _typedefName(dartTypeNumber);
          } else {
            // Requested: the spelled-out generic function type; continue.
            typeVariablesInScope.addAll(
              dartType.typeParameters.map((element) => element.nameOrUnknown),
            );
          }
        }
        String returnType = await _typeCodeOfTypeArgument(
          dartType.returnType,
          importCollector,
          typeVariablesInScope,
          typedefs,
          suppressedWarnings,
          useNameOfGenericFunctionType: useNameOfGenericFunctionType,
        );
        var typeArguments = '';
        if (dartType.typeParameters.isNotEmpty) {
          Iterable<String> typeArgumentList = dartType.typeParameters.map(
            (TypeParameterElement typeParameter) => typeParameter.toString(),
          );
          typeArguments = '<${typeArgumentList.join(', ')}>';
        }
        var argumentTypes = '';
        if (dartType.normalParameterTypes.isNotEmpty) {
          var normalParameterTypeList = <String>[];
          for (DartType parameterType in dartType.normalParameterTypes) {
            normalParameterTypeList.add(
              await _typeCodeOfTypeArgument(
                parameterType,
                importCollector,
                typeVariablesInScope,
                typedefs,
                suppressedWarnings,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType,
              ),
            );
          }
          argumentTypes = normalParameterTypeList.join(', ');
        }
        if (dartType.optionalParameterTypes.isNotEmpty) {
          var optionalParameterTypeList = <String>[];
          for (DartType parameterType in dartType.optionalParameterTypes) {
            optionalParameterTypeList.add(
              await _typeCodeOfTypeArgument(
                parameterType,
                importCollector,
                typeVariablesInScope,
                typedefs,
                suppressedWarnings,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType,
              ),
            );
          }
          var connector = argumentTypes.isEmpty ? '' : ', ';
          argumentTypes =
              '$argumentTypes$connector'
              '[${optionalParameterTypeList.join(', ')}]';
        }
        if (dartType.namedParameterTypes.isNotEmpty) {
          Map<String, DartType> parameterMap = dartType.namedParameterTypes;
          var namedParameterTypeList = <String>[];
          for (String name in parameterMap.keys) {
            DartType parameterType = parameterMap[name]!;
            String typeCode = await _typeCodeOfTypeArgument(
              parameterType,
              importCollector,
              typeVariablesInScope,
              typedefs,
              suppressedWarnings,
              useNameOfGenericFunctionType: useNameOfGenericFunctionType,
            );
            namedParameterTypeList.add('$typeCode $name');
          }
          var connector = argumentTypes.isEmpty ? '' : ', ';
          argumentTypes =
              '$argumentTypes$connector'
              '{${namedParameterTypeList.join(', ')}}';
        }
        return '$returnType Function$typeArguments($argumentTypes)';
      }
    } else if (dartType is TypeParameterType &&
        typeVariablesInScope.contains(dartType.getDisplayString())) {
      return dartType.getDisplayString();
    } else {
      return fail();
    }
  }

  /// Returns a string containing code that in the generated library will
  /// evaluate to a [Type] value like the value we would have obtained by
  /// evaluating the [typeDefiningElement] as an expression in the library
  /// where it occurs. [importCollector] is used to find the library prefixes
  /// needed in order to obtain values from other libraries.
  Future<String> _typeCodeOfClass(
    DartType dartType,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    List<WarningKind> suppressedWarnings,
  ) async {
    var typeVariablesInScope = <String>{}; // None at this level.
    if (dartType is DynamicType) return 'dynamic';
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        // The test for an anonymous mixin application above may be dead code:
        // Currently no test uses an anonymous mixin application to reach this
        // point. But code coverage is not easy to achieve in this case:
        // An anonymous mixin application cannot be the type of an instance,
        // and it cannot be denoted by an expression and hence it cannot be a
        // type annotation.
        //
        // However, if the situation should arise the following approach will
        // work for the anonymous mixin application as well as for the private
        // class.
        return "const r.FakeType(r'${_qualifiedName(interfaceElement)}')";
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      if (interfaceElement.typeParameters.isEmpty) {
        return '$prefix${interfaceElement.name}';
      } else {
        if (dartType.typeArguments.every(_hasNoFreeTypeVariables)) {
          String typeArgumentCode = await _typeCodeOfTypeArgument(
            dartType,
            importCollector,
            typeVariablesInScope,
            typedefs,
            suppressedWarnings,
            useNameOfGenericFunctionType: true,
            includeNullabilitySuffix: false
          );
          return 'const m.TypeValue<$typeArgumentCode>().type';
        } else {
          String arguments = dartType.typeArguments
              .map((DartType typeArgument) => typeArgument.toString())
              .join(', ');
          return 'const r.FakeType('
              "r'${_qualifiedName(interfaceElement)}<$arguments>')";
        }
      }
    } else if (dartType is VoidType) {
      return 'const m.TypeValue<void>().type';
    } else if (dartType is FunctionType) {
      // A function type is inherently not private, so we ignore privacy.
      // Note that some function types are _claimed_ to be private in analyzer
      // 0.36.4, so it is a bug to test for it.
      final Element? dartTypeElement = dartType.alias?.element;
      if (dartTypeElement is TypeAliasElement) {
        String prefix = importCollector._getPrefix(dartTypeElement.library);
        return '$prefix${dartTypeElement.name}';
      } else {
        if (dartType.typeParameters.isNotEmpty) {
          // `dartType` is a generic function type, so we must use a
          // separately generated `typedef` to obtain a `Type` for it.
          return await _typeCodeOfTypeArgument(
            dartType,
            importCollector,
            typeVariablesInScope,
            typedefs,
            suppressedWarnings,
            useNameOfGenericFunctionType: true,
            includeNullabilitySuffix: false
          );
        } else {
          String typeArgumentCode = await _typeCodeOfTypeArgument(
            dartType,
            importCollector,
            typeVariablesInScope,
            typedefs,
            suppressedWarnings,
            includeNullabilitySuffix: false
          );
          return 'const m.TypeValue<$typeArgumentCode>().type';
        }
      }
    } else {
      InterfaceElement? element = dartType is InterfaceType
          ? dartType.element
          : null;
      if (!suppressedWarnings.contains(WarningKind.unsupportedType)) {
        log.warning(
          '[type.type_code.unsupported] '
          '${await _formatDiagnosticMessage(
            'Attempt to generate code for an '
            'unsupported kind of type: $dartType (${dartType.runtimeType}). '
            'Generating `dynamic`.',
            element,
            _resolver,
          )}',
        );
      }
      return 'dynamic';
    }
  }

  /// Returns a string containing code that in the generated library will
  /// evaluate to a [Type] value like the value we would have obtained by
  /// evaluating the [typeDefiningElement] as an expression in the library
  /// where it occurs, except that all type arguments are stripped such
  /// that we get the fully dynamic instantiation if it is a generic class.
  /// [importCollector] is used to find the library prefixes needed in order
  /// to obtain values from other libraries.
  String _dynamicTypeCodeOfClass(
    Element typeDefiningElement,
    _ImportCollector importCollector,
  ) {
    DartType? type = typeDefiningElement is InterfaceElement
        ? _typeForReflection(typeDefiningElement)
        : null;
    if (type is DynamicType) return 'dynamic';
    if (type is InterfaceType) {
      InterfaceElement interfaceElement = type.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        return "const r.FakeType(r'${_qualifiedName(interfaceElement)}')";
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      String suffix = type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
      return '$prefix${interfaceElement.name}$suffix';
    } else if (type is VoidType) {
      return 'const m.TypeValue<void>().type';
    } else {
      // This may be dead code: There is no test which reaches this point,
      // and it is not obvious how we could encounter any [type] which is not
      // an [InterfaceType], given that it is a member of `classes`. However,
      // the following treatment is benign, and nicer than crashing if there
      // is some exception that we have overlooked.
      return "const r.FakeType(r'${_qualifiedName(typeDefiningElement)}')";
    }
  }

  Future<String> _libraryMirrorCode(
    _LibraryDomain libraryDomain,
    int libraryIndex,
    Enumerator<ExecutableElement> members,
    Enumerator<ParameterListShape> parameterListShapes,
    Map<ExecutableElement, ParameterListShape> parameterListShapeOf,
    Enumerator<TopLevelVariableElement> variables,
    int methodsOffset,
    _ImportCollector importCollector,
  ) async {
    LibraryElement library = libraryDomain._libraryElement;

    var gettersCodeList = <String>[];
    for (ExecutableElement getter in _gettersOfLibrary(libraryDomain)) {
      gettersCodeList.add(
        await _topLevelGettingClosure(
          importCollector,
          library,
          getter.nameOrUnknown,
        ),
      );
    }
    String gettersCode = _formatAsMap(gettersCodeList);

    var settersCodeList = <String>[];
    for (PropertyAccessorElement setter in _settersOfLibrary(libraryDomain)) {
      settersCodeList.add(
        await _topLevelSettingClosure(
          importCollector,
          library,
          "${setter.nameOrUnknown}=",
        ),
      );
    }
    String settersCode = _formatAsMap(settersCodeList);

    // Fields go first in [memberMirrors], so they will get the
    // same index as in [fields].
    Iterable<int> variableIndices = libraryDomain._declaredVariables.map((
      TopLevelVariableElement element,
    ) {
      return variables.indexOf(element)!;
    });

    // All the elements in the behavioral interface go after the
    // fields in [memberMirrors], so they must get an offset of
    // `fields.length` on the index.
    Iterable<int> methodIndices = libraryDomain._declarations
        .where(_executableIsntImplicitGetterOrSetter)
        .map((ExecutableElement element) {
          int index = members.indexOf(element)!;
          return index + methodsOffset;
        });

    var declarationsCode = 'const <int>[${constants.noCapabilityIndex}]';
    if (_capabilities._impliesDeclarations) {
      Iterable<int> declarationsIndices = [
        ...variableIndices,
        ...methodIndices,
      ];
      declarationsCode = _formatAsConstList('int', declarationsIndices);
    }

    // URIs may not work at run time, but we use the `assetId` to get a
    // plausible URI when possible.
    String uriCode;
    if (_capabilities._supportsUri || _capabilities._supportsLibraries) {
      FileId? assetId;
      try {
        assetId = await _resolver.fileIdForElement(library);
      } catch (_) {
        assetId = null;
      }
      if (assetId != null) {
        uriCode = "Uri.parse('${assetId.uri}')";
      } else {
        uriCode = "Uri.parse(r'reflection://$libraryIndex/$library')";
      }
    } else {
      uriCode = 'null';
    }

    String metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
        library,
        _resolver,
        importCollector,
        _generatedLibraryId,
      );
    } else {
      metadataCode = 'null';
    }

    var parameterListShapesCode = 'null';
    if (_capabilities._impliesParameterListShapes) {
      parameterListShapesCode = _formatAsMap(
        libraryDomain._declarations.map((ExecutableElement element) {
          // shape != null: every method has a shape in `..shapeOf`.
          ParameterListShape shape = parameterListShapeOf[element]!;
          // index != null: every shape is in `..Shapes`.
          int index = parameterListShapes.indexOf(shape)!;

          String baseName = element.nameOrUnknown;
          String name = element is GetterElement ? baseName : "$baseName=";
          return "r'$name': $index";
        }),
      );
    }

    return "r.LibraryMirrorImpl(r'${library.name}', $uriCode, "
        '${await _constConstructionCode(importCollector)}, '
        '$declarationsCode, $gettersCode, $settersCode, $metadataCode, '
        '$parameterListShapesCode)';
  }

  Future<String> _parameterMirrorCode(
    FormalParameterElement element,
    Enumerator<FieldElement> fields,
    Enumerator<ExecutableElement> members,
    Enumerator<ErasableDartType> reflectedTypes,
    int reflectedTypesOffset,
    _ImportCollector importCollector,
    Map<FunctionType, int> typedefs,
    bool reflectedTypeRequested,
  ) async {
    int descriptor = _parameterDescriptor(element);
    int ownerIndex =
        members.indexOf(element.enclosingElement!)! + fields.length;
    int classMirrorIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypes) {
      if (descriptor & constants.dynamicAttribute != 0 ||
          descriptor & constants.voidAttribute != 0) {
        // This parameter will report its type as [dynamic]/[void], and it
        // will never use `classMirrorIndex`. Keep noCapabilityIndex.
      } else if (descriptor & constants.classTypeAttribute != 0) {
        // Normal encoding of a class type. If that class has been added
        // to `classes` we use its `indexOf`; otherwise (if we do not have an
        // [ec.TypeAnnotationQuantifyCapability]) we must indicate that the
        // capability is absent.
        DartType elementType = element.type;
        if (elementType is InterfaceType) {
          InterfaceElement elementTypeElement = elementType.element;
          classMirrorIndex = (await classes).contains(elementTypeElement)
              ? (await classes).indexOf(elementTypeElement)!
              : constants.noCapabilityIndex;
        } else {
          classMirrorIndex = constants.noCapabilityIndex;
        }
      }
    }
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(
            element.type,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs,
          )
        : constants.noCapabilityIndex;
    var reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
        element.type,
        reflectedTypes,
        reflectedTypesOffset,
        importCollector,
        typedefs,
      );
    }
    var metadataCode = 'null';
    if (_capabilities._supportsMetadata) {
      // TODO(eernst): 'dart:*' is not considered valid. To survive, we
      // return the empty metadata for elements from 'dart:*'. Issue 173.
      if (_isPlatformLibrary(element.library!)) {
        metadataCode = 'const []';
      } else {
        var node =
            await _getDeclarationAst(element, _resolver) as FormalParameter?;
        // The node may be null because the element is synthetic, and
        // then it has no metadata.
        if (node == null) {
          metadataCode = 'const []';
        } else {
          metadataCode = await _extractMetadataCode(
            element,
            _resolver,
            importCollector,
            _generatedLibraryId,
          );
        }
      }
    }
    String code = await _extractDefaultValueCode(importCollector, element);
    var defaultValueCode = code.isEmpty ? 'null' : code;
    var parameterSymbolCode = descriptor & constants.namedAttribute != 0
        ? '#${element.name}'
        : 'null';

    return "r.ParameterMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, $dynamicReflectedTypeIndex, '
        '$reflectedTypeArguments, $metadataCode, $defaultValueCode, '
        '$parameterSymbolCode)';
  }

  /// Given an [importCollector] and a [parameterElement], returns '' if there
  /// is no default value, otherwise returns code for an expression that
  /// evaluates to said default value.
  Future<String> _extractDefaultValueCode(
    _ImportCollector importCollector,
    FormalParameterElement parameterElement,
  ) async {
    // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
    // '' for all declarations from there. Issue 173.
    if (_isPlatformLibrary(parameterElement.library!)) return '';
    var parameterNode =
        await _getDeclarationAst(parameterElement, _resolver)
            as FormalParameter?;
    // The node can be null because the declaration is synthetic, e.g.,
    // the parameter of an induced setter; they have no default value.
    if (parameterNode is DefaultFormalParameter &&
        parameterNode.defaultValue != null) {
      return await _extractConstantCode(
        parameterNode.defaultValue!,
        importCollector,
        _generatedLibraryId,
        _resolver,
      );
    } else if (parameterElement is DefaultFormalParameter) {
      Expression? defaultValue = parameterElement.constantInitializer;
      if (defaultValue != null) {
        return await _extractConstantCode(
          defaultValue,
          importCollector,
          _generatedLibraryId,
          _resolver,
        );
      }
    }
    return '';
  }
}

DartType _typeForReflection(InterfaceElement interfaceElement) {
  // TODO(eernst): This getter is used to inspect subclass relationships,
  // so there is no need to handle type parameters/arguments. So we might
  // be able to improve performance by working on classes as such.
  var typeArguments = List<DartType>.filled(
    interfaceElement.typeParameters.length,
    interfaceElement.library.typeProvider.dynamicType,
  );
  return interfaceElement.instantiate(
    typeArguments: typeArguments,
    nullabilitySuffix: NullabilitySuffix.star,
  );
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SubtypesFixedPoint extends FixedPoint<InterfaceElement> {
  final Map<InterfaceElement, Set<InterfaceElement>> subtypes;

  _SubtypesFixedPoint(this.subtypes);

  /// Returns all the immediate subtypes of the given [classMirror].
  @override
  Future<Iterable<InterfaceElement>> successors(
    final InterfaceElement interfaceElement,
  ) async {
    Iterable<InterfaceElement>? interfaceElements = subtypes[interfaceElement];
    return interfaceElements ?? <InterfaceElement>[];
  }
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SuperclassFixedPoint extends FixedPoint<InterfaceElement> {
  final Map<InterfaceElement, bool> upwardsClosureBounds;
  final bool mixinsRequested;

  _SuperclassFixedPoint(this.upwardsClosureBounds, this.mixinsRequested);

  /// Returns the direct superclass of [element] if it satisfies the given
  /// bounds: If there are any elements in [upwardsClosureBounds] only
  /// classes which are subclasses of an upper bound specified there are
  /// returned (for each bound, if it maps to true then `excludeUpperBound`
  /// was specified, in which case only proper subclasses are returned).
  /// If [mixinsRequested], when considering a superclass which was created as
  /// a mixin application, the class which was applied as a mixin
  /// is also returned (without consulting [upwardsClosureBounds], because a
  /// class used as a mixin cannot have other superclasses than [Object]).
  /// TODO(eernst) implement: When mixins can have nontrivial superclasses
  /// we may or may not wish to enforce the bounds even for mixins.
  @override
  Future<Iterable<InterfaceElement>> successors(
    InterfaceElement element,
  ) async {
    // A mixin application is handled by its regular subclasses.
    if (element is MixinApplication) return [];
    // If upper bounds not satisfied then there are no successors.
    if (!_includedByUpwardsClosure(element)) return [];

    InterfaceType? workingSuperType = element.supertype;
    if (workingSuperType == null) {
      return []; // "Superclass of [Object]", ignore.
    }
    InterfaceElement workingSuperclass = workingSuperType.element;

    var result = <InterfaceElement>[];

    if (_includedByUpwardsClosure(workingSuperclass)) {
      result.add(workingSuperclass);
    }

    // Create the chain of mixin applications between [interfaceElement] and the
    // next non-mixin-application class that it extends. If [mixinsRequested]
    // then for each mixin application add the class [mixinClass] which was
    // applied as a mixin (it is then considered as yet another superclass).
    // Note that we iterate from the most general to more special mixins,
    // that is, for `class C extends B with M1, M2..` we visit `M1` before
    // `M2`, which makes the right `superclass` available at each step. We
    // must provide the immediate subclass of each [MixinApplication] when
    // is a regular class (not a mixin application), otherwise [null], which
    // is done with [subClass].
    var superclass = workingSuperclass;
    for (InterfaceType mixin in element.mixins) {
      InterfaceElement mixinClass = mixin.element;
      if (mixinsRequested) result.add(mixinClass);
      InterfaceElement? subClass = mixin == element.mixins.last
          ? element
          : null;
      String? name = subClass == null
          ? null
          : (element is MixinApplication && element.isMixinApplication
                ? element.name
                : null);
      InterfaceElement mixinApplication = MixinApplication(
        name,
        superclass,
        mixinClass,
        element.library as LibraryElementImpl,
        subClass,
      );
      // We have already ensured that `workingSuperclass` is a
      // subclass of a bound (if any); the value of `superclass` is
      // either `workingSuperclass` or one of its superclasses created
      // by mixin application. Since there is no way to denote these
      // mixin applications directly, they must also be subclasses
      // of a bound, so these mixin applications must be added
      // unconditionally.
      result.add(mixinApplication);
      superclass = mixinApplication;
    }
    return result;
  }

  bool _includedByUpwardsClosure(InterfaceElement interfaceElement) {
    bool helper(InterfaceElement interfaceElement, bool direct) {
      bool isSuperclassOfInterfaceElement(InterfaceElement bound) {
        if (interfaceElement == bound) {
          // If `!direct` then the desired subclass relation exists.
          // If `direct` then the original `interfaceElement` is equal to
          // `bound`, so we must return false if `excludeUpperBound`.
          return !direct || !upwardsClosureBounds[bound]!;
        }
        InterfaceType? interfaceElementSupertype = interfaceElement.supertype;
        if (interfaceElementSupertype == null) return false;
        return helper(interfaceElementSupertype.element, false);
      }

      return upwardsClosureBounds.keys.any(isSuperclassOfInterfaceElement);
    }

    return upwardsClosureBounds.isEmpty || helper(interfaceElement, true);
  }
}

/// Auxiliary function used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
Set<InterfaceElement> _mixinApplicationsOfClasses(
  Set<InterfaceElement> classes,
) {
  var mixinApplications = <InterfaceElement>{};
  for (InterfaceElement interfaceElement in classes) {
    // Mixin-applications are handled when they are created.
    if (interfaceElement is MixinApplication) continue;
    InterfaceType? supertype = interfaceElement.supertype;
    if (supertype == null) continue; // "Superclass of [Object]", ignore.
    InterfaceElement superclass = supertype.element;
    // Note that we iterate from the most general mixin to more specific ones,
    // that is, with `class C extends B with M1, M2..` we visit `M1` before
    // `M2`; this ensures that the right `superclass` is available for each
    // new [MixinApplication] created.  We must provide the immediate subclass
    // of each [MixinApplication] when it is a regular class (not a mixin
    // application), otherwise [null], which is done with [subClass].
    for (InterfaceType mixin in interfaceElement.mixins) {
      InterfaceElement mixinClass = mixin.element;
      InterfaceElement? subClass = mixin == interfaceElement.mixins.last
          ? interfaceElement
          : null;
      String? name = subClass == null
          ? null
          : (interfaceElement is MixinApplication &&
                    interfaceElement.isMixinApplication
                ? interfaceElement.name
                : null);
      InterfaceElement mixinApplication = MixinApplication(
        name,
        superclass,
        mixinClass,
        interfaceElement.library as LibraryElementImpl,
        subClass,
      );
      mixinApplications.add(mixinApplication);
      superclass = mixinApplication;
    }
  }
  return mixinApplications;
}

/// Auxiliary type used by [_AnnotationClassFixedPoint].
typedef _ElementToDomain = _ClassDomain Function(InterfaceElement);

/// Auxiliary class used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
/// It uses [resolver] in a check for "importability" of some private core
/// classes (that we must avoid attempting to use because they are unavailable
/// to user programs). [generatedLibraryId] must refer to the asset where the
/// generated code will be stored; it is used in the same check.
class _AnnotationClassFixedPoint extends FixedPoint<InterfaceElement> {
  final LibraryResolver resolver;
  final FileId generatedLibraryId;
  final _ElementToDomain elementToDomain;

  _AnnotationClassFixedPoint(
    this.resolver,
    this.generatedLibraryId,
    this.elementToDomain,
  );

  /// Returns the classes that occur as return types of covered methods or in
  /// type annotations of covered variables and parameters of covered methods,
  @override
  Future<Iterable<InterfaceElement>> successors(
    InterfaceElement interfaceElement,
  ) async {
    if (!await _isImportable(interfaceElement, generatedLibraryId, resolver)) {
      return [];
    }
    _ClassDomain classDomain = elementToDomain(interfaceElement);

    // Mixin-applications do not add further methods and fields.
    if (classDomain._interfaceElement is MixinApplication) return [];

    var result = <InterfaceElement>[];

    // Traverse type annotations to find successors. Note that we cannot
    // abstract the many redundant elements below, because `yield` cannot
    // occur in a local function.
    for (FieldElement fieldElement in classDomain._declaredFields) {
      DartType fieldType = fieldElement.type;
      if (fieldType is InterfaceType) {
        result.add(fieldType.element);
      }
    }
    for (FormalParameterElement parameterElement
        in classDomain._declaredParameters) {
      DartType parameterType = parameterElement.type;
      if (parameterType is InterfaceType) {
        result.add(parameterType.element);
      }
    }
    for (FormalParameterElement parameterElement
        in classDomain._instanceParameters) {
      DartType parameterType = parameterElement.type;
      if (parameterType is InterfaceType) {
        result.add(parameterType.element);
      }
    }
    for (ExecutableElement executableElement in classDomain._declaredMethods) {
      DartType executableReturnType = executableElement.returnType;
      if (executableReturnType is InterfaceType) {
        result.add(executableReturnType.element);
      }
    }
    for (ExecutableElement executableElement in classDomain._instanceMembers) {
      DartType executableReturnType = executableElement.returnType;
      if (executableReturnType is InterfaceType) {
        result.add(executableReturnType.element);
      }
    }
    return result;
  }
}

final RegExp _identifierRegExp = RegExp(r'^[A-Za-z$_][A-Za-z$_0-9]*$');

// Auxiliary function used by `_generateCode`.
String _gettingClosure(String getterName) {
  if (getterName == "-") {
    getterName = "unary-";
  }

  String closure;
  if (_identifierRegExp.hasMatch(getterName)) {
    // Starts with letter, not an operator.
    closure = '(dynamic instance) => instance.$getterName';
  } else if (getterName == '[]=') {
    closure = '(dynamic instance) => (x, v) => instance[x] = v';
  } else if (getterName == '[]') {
    closure = '(dynamic instance) => (x) => instance[x]';
  } else if (getterName == 'unary-') {
    closure = '(dynamic instance) => () => -instance';
  } else if (getterName == '~') {
    closure = '(dynamic instance) => () => ~instance';
  } else {
    closure = '(dynamic instance) => (x) => instance $getterName x';
  }
  return "r'$getterName': $closure";
}

// Auxiliary function used by `_generateCode`.
String _settingClosure(String setterName) {
  assert(setterName.substring(setterName.length - 1) == '=');
  String name = setterName.substring(0, setterName.length - 1);
  return "r'$setterName': (dynamic instance, value) => instance.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticGettingClosure(
  _ImportCollector importCollector,
  InterfaceElement interfaceElement,
  String getterName,
) async {
  String className = interfaceElement.nameOrUnknown;
  String prefix = importCollector._getPrefix(interfaceElement.library);
  // Operators cannot be static.
  if (_isPrivateName(getterName)) {
    await _severe(
      'static_getter.name.private_01',
      'Cannot access private getter name `$getterName`. '
      'Class: $className',
      interfaceElement,
    );
  }
  if (_isPrivateName(className)) {
    await _severe(
      'static_getter.class.private_02',
      'Cannot access private class name `$className` for getter `$getterName`',
      interfaceElement,
    );
  }
  return "r'$getterName': () => $prefix$className.$getterName";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticSettingClosure(
  _ImportCollector importCollector,
  InterfaceElement interfaceElement,
  String setterName,
) async {
  assert(setterName.substring(setterName.length - 1) == '=');
  // The [setterName] includes the '=', remove it.
  String name = setterName.substring(0, setterName.length - 1);
  String className = interfaceElement.nameOrUnknown;
  String prefix = importCollector._getPrefix(interfaceElement.library);
  if (_isPrivateName(setterName)) {
    await _severe(
      'static_setter.name.private_03',
      'Cannot access private setter name `$setterName`. '
      'Class: $className',
      interfaceElement,
    );
  }
  if (_isPrivateName(className)) {
    await _severe(
      'static_setter.class.private_04',
      'Cannot access private class name `$className` for setter `$setterName`',
      interfaceElement,
    );
  }
  return "r'$setterName': (dynamic value) => $prefix$className.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _topLevelGettingClosure(
  _ImportCollector importCollector,
  LibraryElement library,
  String getterName,
) async {
  String prefix = importCollector._getPrefix(library);
  // Operators cannot be top-level.
  if (_isPrivateName(getterName)) {
    await _severe(
      'toplevel_getter.name.private_05',
      'Cannot access private top-level getter name `$getterName`. '
      'Library: ${library.name}',
      library,
    );
  }
  return "r'$getterName': () => $prefix$getterName";
}

// Auxiliary function used by `_generateCode`.
Future<String> _topLevelSettingClosure(
  _ImportCollector importCollector,
  LibraryElement library,
  String setterName,
) async {
  assert(setterName.substring(setterName.length - 1) == '=');
  // The [setterName] includes the '=', remove it.
  String name = setterName.substring(0, setterName.length - 1);
  String prefix = importCollector._getPrefix(library);
  if (_isPrivateName(name)) {
    await _severe(
      'toplevel_setter.name.private_06',
      'Cannot access private top-level setter name `$name`. '
      'Library: ${library.name}',
      library,
    );
  }
  return "r'$setterName': (dynamic value) => $prefix$name = value";
}

// Auxiliary function used by `_typeCodeIndex`.
String _typedefName(int id) => 'typedef$id';

// TODO(eernst) future: Keep in mind, with reference to
// http://dartbug.com/21654 comment #5, that it would be very valuable
// if this transformation can interact smoothly with incremental
// compilation.  By nature, that is hard to achieve for a
// source-to-source translation scheme, but a long source-to-source
// translation step which is invoked frequently will certainly destroy
// the immediate feedback otherwise offered by incremental compilation.
// WORKAROUND: A work-around for this issue which is worth considering
// is to drop the translation entirely during most of development,
// because we will then simply work on a normal Dart program that uses
// dart:mirrors, which should have the same behavior as the translated
// program, and this could work quite well in practice, except for
// debugging which is concerned with the generated code (but that would
// ideally be an infrequent occurrence).

/// Keeps track of the number of entry points seen. Used to determine when the
/// transformation job is complete during `pub build..` or stand-alone
/// transformation, such that it is time to give control to the debugger.
/// Only in use when `const bool.fromEnvironment('reflection.pause.at.exit')`.
int _processedEntryPointCount = 0;

