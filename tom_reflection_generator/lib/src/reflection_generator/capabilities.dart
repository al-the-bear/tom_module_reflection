// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

/// A wrapper around a list of Capabilities.
/// Supports queries about the methods supported by the set of capabilities.
class _Capabilities {
  final List<ec.ReflectCapability> _capabilities;
  _Capabilities(this._capabilities);

  bool _supportsName(ec.NamePatternCapability capability, String methodName) {
    var regexp = RegExp(capability.namePattern);
    return regexp.hasMatch(methodName);
  }

  bool _supportsMeta(
    TypeSystem typeSystem,
    ec.MetadataQuantifiedCapability capability,
    Iterable<DartObject>? metadata,
  ) {
    if (metadata == null) return false;
    var result = false;
    DartType capabilityType = _typeForReflection(capability.metadataType);
    for (DartObject metadatum in metadata) {
      if (typeSystem.isSubtypeOf(metadatum.type!, capabilityType)) {
        result = true;
        break;
      }
    }
    return result;
  }

  bool _supportsInstanceInvoke(
    TypeSystem typeSystem,
    List<ec.ReflectCapability> capabilities,
    String methodName,
    Iterable<DartObject> metadata,
    Iterable<DartObject>? getterMetadata,
  ) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.InstanceInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.InstanceInvokeMetaCapability &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsInstanceInvoke(
        typeSystem,
        capabilities,
        _setterNameToGetterName(methodName),
        getterMetadata,
        null,
      );
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsNewInstance(
    TypeSystem typeSystem,
    Iterable<ec.ReflectCapability> capabilities,
    String constructorName,
    Iterable<DartObject> metadata,
  ) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.NamePatternCapability) {
        if ((capability is ec.InvokingCapability ||
                capability is ec.NewInstanceCapability) &&
            _supportsName(capability, constructorName)) {
          return true;
        }
      }
      if (capability is ec.MetadataQuantifiedCapability) {
        if ((capability is ec.InvokingMetaCapability ||
                capability is ec.NewInstanceMetaCapability) &&
            _supportsMeta(typeSystem, capability, metadata)) {
          return true;
        }
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // All options exhausted, give up.
    return false;
  }

  // TODO(sigurdm) future: Find a way to cache these. Perhaps take an
  // element instead of name+metadata.
  bool supportsInstanceInvoke(
    TypeSystem typeSystem,
    String methodName,
    Iterable<ElementAnnotation> metadata,
    Iterable<ElementAnnotation>? getterMetadata,
  ) {
    return _supportsInstanceInvoke(
      typeSystem,
      _capabilities,
      methodName,
      _getEvaluatedMetadata(metadata),
      getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata),
    );
  }

  bool supportsNewInstance(
    TypeSystem typeSystem,
    String constructorName,
    Iterable<ElementAnnotation> metadata,
    LibraryElement libraryElement,
    LibraryResolver resolver,
  ) {
    return _supportsNewInstance(
      typeSystem,
      _capabilities,
      constructorName,
      _getEvaluatedMetadata(metadata),
    );
  }

  bool _supportsTopLevelInvoke(
    TypeSystem typeSystem,
    List<ec.ReflectCapability> capabilities,
    String methodName,
    Iterable<DartObject> metadata,
    Iterable<DartObject>? getterMetadata,
  ) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.TopLevelInvokeCapability) &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if ((capability is ec.TopLevelInvokeMetaCapability) &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities do not influence the availability
      // of reflection support for top-level invocation.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsTopLevelInvoke(
        typeSystem,
        capabilities,
        _setterNameToGetterName(methodName),
        getterMetadata,
        null,
      );
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsStaticInvoke(
    TypeSystem typeSystem,
    List<ec.ReflectCapability> capabilities,
    String methodName,
    Iterable<DartObject> metadata,
    Iterable<DartObject>? getterMetadata,
  ) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.StaticInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.StaticInvokeMetaCapability &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsStaticInvoke(
        typeSystem,
        capabilities,
        _setterNameToGetterName(methodName),
        getterMetadata,
        null,
      );
    }

    // All options exhausted, give up.
    return false;
  }

  bool supportsTopLevelInvoke(
    TypeSystem typeSystem,
    String methodName,
    Iterable<ElementAnnotation> metadata,
    Iterable<ElementAnnotation>? getterMetadata,
  ) {
    return _supportsTopLevelInvoke(
      typeSystem,
      _capabilities,
      methodName,
      _getEvaluatedMetadata(metadata),
      getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata),
    );
  }

  bool supportsStaticInvoke(
    TypeSystem typeSystem,
    String methodName,
    Iterable<ElementAnnotation> metadata,
    Iterable<ElementAnnotation>? getterMetadata,
  ) {
    return _supportsStaticInvoke(
      typeSystem,
      _capabilities,
      methodName,
      _getEvaluatedMetadata(metadata),
      getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata),
    );
  }

  late final bool _supportsMetadata = _capabilities.any(
    (ec.ReflectCapability capability) => capability is ec.MetadataCapability,
  );

  late final bool _supportsUri = _capabilities.any(
    (ec.ReflectCapability capability) => capability is ec.UriCapability,
  );

  /// Returns [true] iff these [Capabilities] specify reflection support
  /// where the set of classes must be downwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly covered by the given
  /// metadata and global quantifiers, such that coverage on a class `C`
  /// implies coverage of every class `D` such that `D` is a subtype of `C`.
  late final bool _impliesDownwardsClosure = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability == ec.subtypeQuantifyCapability,
  );

  /// Returns [true] iff these [Capabilities] specify reflection support where
  /// the set of included classes must be upwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly included as reflection
  /// because we must support operations like `superclass`.
  late final bool _impliesUpwardsClosure = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability is ec.SuperclassQuantifyCapability,
  );

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  bool get _impliesMixins => _impliesTypeRelations;

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  late final bool _impliesTypeRelations = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability is ec.TypeRelationsCapability,
  );

  /// Returns [true] iff these [Capabilities] specify that type annotations
  /// modeled by mirrors should also get support for their base level [Type]
  /// values, e.g., they should support `myVariableMirror.reflectedType`.
  /// The relevant kinds of mirrors are variable mirrors, parameter mirrors,
  /// and (for the return type) method mirrors.
  late final bool _impliesReflectedType = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability == ec.reflectedTypeCapability,
  );

  /// Maps each upper bound specified for the upwards closure to whether the
  /// bound itself is excluded, as indicated by `excludeUpperBound` in the
  /// corresponding capability. Intended usage: the `keys` of this map
  /// provides a listing of the upper bounds, and the map itself may then
  /// be consulted for each key (`if (myClosureBounds[key]) ..`) in order to
  /// take `excludeUpperBound` into account.
  Future<Map<InterfaceElement, bool>> get _upwardsClosureBounds async {
    var result = <InterfaceElement, bool>{};
    for (ec.ReflectCapability capability in _capabilities) {
      if (capability is ec.SuperclassQuantifyCapability) {
        Element? element = capability.upperBound;
        if (element == null) continue; // Means [Object], trivially satisfied.
        if (element is InterfaceElement) {
          result[element] = capability.excludeUpperBound;
        } else {
          await _severe(
            'capability.superclass_quantify.unexpected_bound',
            'Unexpected kind of upper bound specified '
            'for a `SuperclassQuantifyCapability`: $element '
            '(type: ${element.runtimeType}).',
          );
        }
      }
    }
    return result;
  }

  late final bool _impliesDeclarations = _capabilities.any((
    ec.ReflectCapability capability,
  ) {
    return capability is ec.DeclarationsCapability;
  });

  late final bool _impliesMemberSymbols = _capabilities.any((
    ec.ReflectCapability capability,
  ) {
    return capability == ec.delegateCapability;
  });

  bool get _impliesParameterListShapes {
    // If we have a capability for declarations then we also have it for
    // types, and in that case the strategy where we traverse the parameter
    // mirrors to gather the argument list shape (and cache it in the method
    // mirror) will work. It may be a bit slower, but we have a general
    // preference for space over time in this library: Reflection will never
    // be full speed.
    return !_impliesDeclarations;
  }

  late final bool _impliesTypes = _capabilities.any((
    ec.ReflectCapability capability,
  ) {
    return capability is ec.TypeCapability;
  });

  /// Returns true iff `_capabilities` contain any of the types of capability
  /// which are concerned with instance method invocation. The purpose of
  /// this predicate is to determine whether it is required to have class
  /// mirrors for instance invocation support. Note that it does not include
  /// `newInstance..` capabilities nor `staticInvoke..` capabilities, because
  /// they are simply absent if there are no class mirrors (so we cannot call
  /// them and then get a "cannot do this without a class mirror" error in the
  /// implementation).
  late final bool _impliesInstanceInvoke = _capabilities.any((
    ec.ReflectCapability capability,
  ) {
    return capability is ec.InstanceInvokeCapability ||
        capability is ec.InstanceInvokeMetaCapability;
  });

  late final bool _impliesTypeAnnotations = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability is ec.TypeAnnotationQuantifyCapability,
  );

  late final bool _impliesTypeAnnotationClosure = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability is ec.TypeAnnotationQuantifyCapability &&
        capability.transitive == true,
  );

  late final bool _impliesCorrespondingSetters = _capabilities.any(
    (ec.ReflectCapability capability) =>
        capability == ec.correspondingSetterQuantifyCapability,
  );

  late final bool _supportsLibraries = _capabilities.any(
    (ec.ReflectCapability capability) => capability is ec.LibraryCapability,
  );
}
