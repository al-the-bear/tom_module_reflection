// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

class _LibraryDomain {
  /// Element describing the target library.
  final LibraryElement _libraryElement;

  /// Fields declared by [_libraryElement] and included for reflection support,
  /// according to the reflector described by the [_reflectorDomain];
  /// obtained by filtering `_libraryElement.fields`.
  final Iterable<TopLevelVariableElement> _declaredVariables;

  /// Methods which are declared by [_libraryElement] and included for
  /// reflection support, according to the reflector described by
  /// [_reflectorDomain]; obtained by filtering `_libraryElement.functions`.
  final Iterable<TopLevelFunctionElement> _declaredFunctions;

  /// Formal parameters declared by one of the [_declaredFunctions].
  final Iterable<FormalParameterElement> _declaredParameters;

  /// Getters and setters possessed by [_libraryElement] and included for
  /// reflection support, according to the reflector described by
  /// [_reflectorDomain]; obtained by filtering `_libraryElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors, implicitly
  /// created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _accessors;

  /// The reflector domain that holds [this] object as one of its
  /// library domains.
  final _ReflectorDomain _reflectorDomain;

  _LibraryDomain(
    this._libraryElement,
    this._declaredVariables,
    this._declaredFunctions,
    this._declaredParameters,
    this._accessors,
    this._reflectorDomain,
  );

  /// Returns the declared methods, accessors and constructors in
  /// [_interfaceElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations => [
    ..._declaredFunctions,
    ..._accessors,
  ];

  @override
  String toString() {
    return 'LibraryDomain($_libraryElement)';
  }

  @override
  bool operator ==(Object other) {
    if (other is _LibraryDomain) {
      return _libraryElement == other._libraryElement &&
          _reflectorDomain == other._reflectorDomain;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => _libraryElement.hashCode ^ _reflectorDomain.hashCode;
}

/// Information about reflectability for a given class.
class _ClassDomain {
  /// Element describing the target class.
  final InterfaceElement _interfaceElement;

  /// Fields declared by [_interfaceElement] and included for reflection support,
  /// according to the reflector described by the [_reflectorDomain];
  /// obtained by filtering `_interfaceElement.fields`.
  final Iterable<FieldElement> _declaredFields;

  /// Methods which are declared by [_interfaceElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_interfaceElement.methods`.
  final Iterable<MethodElement> _declaredMethods;

  /// Formal parameters declared by one of the [_declaredMethods].
  final Iterable<FormalParameterElement> _declaredParameters;

  /// Getters and setters possessed by [_interfaceElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_interfaceElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors,
  /// implicitly created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _accessors;

  /// Constructors declared by [_interfaceElement] and included for reflection
  /// support, according to the reflector described by [_reflectorDomain];
  /// obtained by filtering `_interfaceElement.constructors`.
  final Iterable<ConstructorElement> _constructors;

  /// The reflector domain that holds [this] object as one of its
  /// class domains.
  final _ReflectorDomain _reflectorDomain;

  _ClassDomain(
    this._interfaceElement,
    this._declaredFields,
    this._declaredMethods,
    this._declaredParameters,
    this._accessors,
    this._constructors,
    this._reflectorDomain,
  );

  String get _simpleName {
    // TODO(eernst) clarify: Decide whether this should be simplified
    // by adding a method implementation to `MixinApplication`.
    InterfaceElement interfaceElement = _interfaceElement;
    if (interfaceElement is MixinApplication &&
        interfaceElement.isMixinApplication) {
      // This is the case `class B = A with M;`.
      return interfaceElement.name;
    } else if (interfaceElement is MixinApplication) {
      // This is the case `class B extends A with M1, .. Mk {..}`
      // where `interfaceElement` denotes one of the mixin applications
      // that constitute the superclass chain between `B` and `A`, both
      // excluded.
      List<InterfaceType> mixins = interfaceElement.mixins;
      var superclassType = interfaceElement.supertype as InterfaceType;
      InterfaceElement superclassTypeElement = superclassType.element;
      String superclassName = _qualifiedName(superclassTypeElement);
      var name = StringBuffer(superclassName);
      var firstSeparator = true;
      for (var mixin in mixins) {
        name.write(firstSeparator ? ' with ' : ', ');
        name.write(_qualifiedName(mixin.element));
        firstSeparator = false;
      }
      return name.toString();
    } else {
      // This is a regular class, i.e., we can use its declared name.
      return interfaceElement.nameOrUnknown;
    }
  }

  /// Returns the declared methods, accessors and constructors in
  /// [_interfaceElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations => [
    // TODO(sigurdm) feature: Include type variables (if we keep them).
    ..._declaredMethods,
    ..._accessors,
    ..._constructors,
  ];

  /// Finds all instance members by going through the class hierarchy.
  Iterable<ExecutableElement> get _instanceMembers {
    Map<String, ExecutableElement> helper(InterfaceElement interfaceElement) {
      Map<String, ExecutableElement>? member =
          _reflectorDomain._instanceMemberCache[interfaceElement];
      if (member != null) return member;
      var result = <String, ExecutableElement>{};

      void addIfCapable(String name, ExecutableElement member) {
        if (member.isPrivate) return;
        // If [member] is a synthetic accessor created from a field, search for
        // the metadata on the original field.
        List<ElementAnnotation> metadata =
            (member is PropertyAccessorElement && member.isSynthetic)
            ? (member.variable.metadata.annotations)
            : member.metadata.annotations;
        List<ElementAnnotation>? getterMetadata;
        if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
            member is PropertyAccessorElement &&
            !member.isSynthetic &&
            member is SetterElement) {
          PropertyAccessorElement? correspondingGetter =
              member.correspondingGetter;
          getterMetadata = correspondingGetter?.metadata.annotations;
        }
        if (member is SetterElement) {
          name += "=";
        }
        if (_reflectorDomain._capabilities.supportsInstanceInvoke(
          member.library.typeSystem,
          name,
          metadata,
          getterMetadata,
        )) {
          result[name] = member;
        }
      }

      void addTypeIfCapable(InterfaceType type) {
        helper(type.element).forEach(addIfCapable);
      }

      void addIfCapableConcreteInstance(ExecutableElement member) {
        if (!member.isAbstract && !member.isStatic) {
          addIfCapable(member.nameOrUnknown, member);
        }
      }

      Map<String, ExecutableElement> cacheResult(
        Map<String, ExecutableElement> result,
      ) {
        result = Map.unmodifiable(result);
        _reflectorDomain._instanceMemberCache[interfaceElement] = result;
        return result;
      }

      if (interfaceElement is MixinApplication) {
        helper(interfaceElement.superclass).forEach(addIfCapable);
        helper(interfaceElement.mixin).forEach(addIfCapable);
        return cacheResult(result);
      }
      InterfaceType? superclassType = interfaceElement.supertype;
      if (superclassType is InterfaceType) {
        InterfaceElement superclassElement = superclassType.element;
        helper(superclassElement).forEach(addIfCapable);
      }
      interfaceElement.mixins.forEach(addTypeIfCapable);
      interfaceElement.methods.forEach(addIfCapableConcreteInstance);
      interfaceElement.getters.forEach(addIfCapableConcreteInstance);
      interfaceElement.setters.forEach(addIfCapableConcreteInstance);

      return cacheResult(result);
    }

    return helper(_interfaceElement).values;
  }

  /// Finds all parameters of instance members.
  Iterable<FormalParameterElement> get _instanceParameters {
    var result = <FormalParameterElement>[];
    if (_reflectorDomain._capabilities._impliesDeclarations) {
      for (ExecutableElement executableElement in _instanceMembers) {
        result.addAll(executableElement.formalParameters);
      }
    }
    return result;
  }

  /// Finds all static members.
  Iterable<ExecutableElement> get _staticMembers {
    var result = <ExecutableElement>[];
    if (_interfaceElement is MixinApplication) return result;

    void possiblyAddMethod(MethodElement method) {
      if (method.isStatic &&
          !method.isPrivate &&
          _reflectorDomain._capabilities.supportsStaticInvoke(
            method.library.typeSystem,
            method.nameOrUnknown,
            method.metadata.annotations,
            null,
          )) {
        result.add(method);
      }
    }

    void possiblyAddAccessor(PropertyAccessorElement accessor) {
      if (!accessor.isStatic || accessor.isPrivate) return;
      // If [member] is a synthetic accessor created from a field, search for
      // the metadata on the original field.
      List<ElementAnnotation> metadata = accessor.isSynthetic
          ? (accessor.variable.metadata.annotations)
          : accessor.metadata.annotations;
      List<ElementAnnotation>? getterMetadata;
      if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
          accessor is SetterElement &&
          !accessor.isSynthetic) {
        PropertyAccessorElement? correspondingGetter =
            accessor.correspondingGetter;
        getterMetadata = correspondingGetter?.metadata.annotations;
      }
      if (_reflectorDomain._capabilities.supportsStaticInvoke(
        accessor.library.typeSystem,
        accessor.nameOrUnknown,
        metadata,
        getterMetadata,
      )) {
        result.add(accessor);
      }
    }

    _interfaceElement.methods.forEach(possiblyAddMethod);
    _interfaceElement.getters.forEach(possiblyAddAccessor);
    _interfaceElement.setters.forEach(possiblyAddAccessor);
    return result;
  }

  @override
  String toString() {
    return 'ClassDomain($_interfaceElement)';
  }
}
