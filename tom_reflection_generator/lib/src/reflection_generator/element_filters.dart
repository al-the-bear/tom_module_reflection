// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Element filtering and extraction utilities for the reflection generator.
///
/// This file provides functions to filter and extract various types of
/// elements (variables, functions, fields, methods, constructors, accessors,
/// parameters) from libraries and classes based on the capabilities specified
/// in the reflector.
///
/// These functions are used to determine which elements should be included
/// in the generated reflection code based on the reflector's capabilities.
part of 'generator_implementation.dart';

// ============================================================================
// Type Definitions
// ============================================================================

/// Function type for checking if a capability supports a given element.
///
/// Used to abstract the capability checking logic for different element types.
typedef CapabilityChecker =
    bool Function(
      TypeSystem,
      String methodName,
      Iterable<ElementAnnotation> metadata,
      Iterable<ElementAnnotation>? getterMetadata,
    );

// ============================================================================
// Top-Level Element Extraction
// ============================================================================

/// Returns the top level variables declared in the given [libraryElement],
/// filtering them such that the returned ones are those that are supported
/// by [capabilities].
///
/// Excludes:
/// - Private variables
/// - Synthetic (compiler-generated) variables
/// - Variables not supported by the top-level invoke capability
Iterable<TopLevelVariableElement> _extractDeclaredVariables(
  LibraryResolver resolver,
  LibraryElement libraryElement,
  _Capabilities capabilities,
) sync* {
  for (TopLevelVariableElement variable in libraryElement.topLevelVariables) {
    if (variable.isPrivate || variable.isSynthetic) continue;
    if (capabilities.supportsTopLevelInvoke(
      variable.library.typeSystem,
      variable.nameOrUnknown,
      variable.metadata.annotations,
      null,
    )) {
      yield variable;
    }
  }
}

/// Returns the top level functions declared in the given [libraryElement],
/// filtering them such that the returned ones are those that are supported
/// by [capabilities].
///
/// Excludes:
/// - Private functions
/// - Functions not supported by the top-level invoke capability
Iterable<TopLevelFunctionElement> _extractDeclaredFunctions(
  LibraryResolver resolver,
  LibraryElement libraryElement,
  _Capabilities capabilities,
) sync* {
  for (TopLevelFunctionElement function in libraryElement.topLevelFunctions) {
    if (function.isPrivate) continue;
    if (capabilities.supportsTopLevelInvoke(
      function.library.typeSystem,
      function.nameOrUnknown,
      function.metadata.annotations,
      null,
    )) {
      yield function;
    }
  }
}

/// Returns the parameters declared in the given [declaredFunctions] as well
/// as the setters from the given [accessors].
///
/// This collects all parameters from top-level functions and setter accessors.
Iterable<FormalParameterElement> _extractDeclaredFunctionParameters(
  LibraryResolver resolver,
  Iterable<TopLevelFunctionElement> declaredFunctions,
  Iterable<ExecutableElement> accessors,
) {
  var result = <FormalParameterElement>[];
  for (TopLevelFunctionElement declaredFunction in declaredFunctions) {
    result.addAll(declaredFunction.formalParameters);
  }
  for (ExecutableElement accessor in accessors) {
    if (accessor is PropertyAccessorElement && accessor is SetterElement) {
      result.addAll(accessor.formalParameters);
    }
  }
  return result;
}

/// Returns the accessors from the given [libraryElement], filtered such that
/// the returned ones are the ones that are supported by [capabilities].
///
/// Handles both explicit accessors (declared getters/setters) and synthetic
/// accessors (auto-generated for fields).
Iterable<PropertyAccessorElement> _extractLibraryAccessors(
  LibraryResolver resolver,
  LibraryElement libraryElement,
  _Capabilities capabilities,
) sync* {
  for (PropertyAccessorElement accessor in [
    ...libraryElement.getters,
    ...libraryElement.setters,
  ]) {
    if (accessor.isPrivate) continue;
    
    // Get metadata from the appropriate source
    List<ElementAnnotation> metadata;
    List<ElementAnnotation>? getterMetadata;
    if (accessor.isSynthetic) {
      metadata = accessor.variable.metadata.annotations;
      getterMetadata = metadata;
    } else {
      metadata = accessor.metadata.annotations;
      // For explicit setters, check if corresponding getter has metadata
      if (capabilities._impliesCorrespondingSetters &&
          accessor is SetterElement &&
          !accessor.isSynthetic) {
        PropertyAccessorElement? correspondingGetter =
            accessor.correspondingGetter;
        getterMetadata = correspondingGetter?.metadata.annotations;
      }
    }

    // Format accessor name (setters include trailing '=')
    String accessorName = accessor is SetterElement
        ? "${accessor.nameOrUnknown}="
        : accessor.nameOrUnknown;

    if (capabilities.supportsTopLevelInvoke(
      accessor.library.typeSystem,
      accessorName,
      metadata,
      getterMetadata,
    )) {
      yield accessor;
    }
  }
}

// ============================================================================
// Class Member Extraction
// ============================================================================

/// Returns the declared fields in the given [interfaceElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
///
/// Excludes:
/// - Private fields
/// - Synthetic (compiler-generated) fields
/// - Fields not supported by the appropriate capability (static vs instance)
Iterable<FieldElement> _extractDeclaredFields(
  LibraryResolver resolver,
  InterfaceElement interfaceElement,
  _Capabilities capabilities,
) {
  return interfaceElement.fields.where((FieldElement field) {
    if (field.isPrivate) return false;
    
    // Use static or instance capability based on field type
    CapabilityChecker capabilityChecker = field.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    
    return !field.isSynthetic &&
        capabilityChecker(
          interfaceElement.library.typeSystem,
          field.nameOrUnknown,
          field.metadata.annotations,
          null,
        );
  });
}

/// Returns the declared methods in the given [interfaceElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
///
/// Excludes:
/// - Private methods
/// - Methods not supported by the appropriate capability (static vs instance)
Iterable<MethodElement> _extractDeclaredMethods(
  LibraryResolver resolver,
  InterfaceElement interfaceElement,
  _Capabilities capabilities,
) {
  return interfaceElement.methods.where((MethodElement method) {
    if (method.isPrivate) return false;
    
    // Use static or instance capability based on method type
    CapabilityChecker capabilityChecker = method.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    
    return capabilityChecker(
      method.library.typeSystem,
      method.nameOrUnknown,
      method.metadata.annotations,
      null,
    );
  });
}

/// Returns the declared parameters in the given [declaredMethods] and
/// [declaredConstructors], as well as the ones from the setters in
/// [accessors].
///
/// This collects all parameters from methods, constructors, and setter accessors.
List<FormalParameterElement> _extractDeclaredParameters(
  Iterable<MethodElement> declaredMethods,
  Iterable<ConstructorElement> declaredConstructors,
  Iterable<PropertyAccessorElement> accessors,
) {
  var result = <FormalParameterElement>[];
  
  for (MethodElement declaredMethod in declaredMethods) {
    result.addAll(declaredMethod.formalParameters);
  }
  for (ConstructorElement declaredConstructor in declaredConstructors) {
    result.addAll(declaredConstructor.formalParameters);
  }
  for (PropertyAccessorElement accessor in accessors) {
    if (accessor is SetterElement) {
      result.addAll(accessor.formalParameters);
    }
  }
  
  return result;
}

/// Returns the [PropertyAccessorElement]s which are the accessors
/// of the given [interfaceElement], including both the declared ones
/// and the implicitly generated ones corresponding to fields.
///
/// This is the set of accessors that corresponds to the behavioral interface
/// of the corresponding instances, as opposed to the source code oriented
/// interface, e.g., `declarations`. But the latter can be computed from
/// here, by filtering out the accessors whose `isSynthetic` is true
/// and adding the fields.
Iterable<PropertyAccessorElement> _extractAccessors(
  LibraryResolver resolver,
  InterfaceElement interfaceElement,
  _Capabilities capabilities,
) {
  return [...interfaceElement.getters, ...interfaceElement.setters].where((
    PropertyAccessorElement accessor,
  ) {
    if (accessor.isPrivate) return false;
    
    // Use static or instance capability based on accessor type
    CapabilityChecker capabilityChecker = accessor.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    
    // Get metadata from appropriate source
    List<ElementAnnotation> metadata = accessor.isSynthetic
        ? (accessor.variable.metadata.annotations)
        : accessor.metadata.annotations;
    
    // For explicit setters, check if corresponding getter has metadata
    List<ElementAnnotation>? getterMetadata;
    if (capabilities._impliesCorrespondingSetters &&
        accessor is SetterElement &&
        !accessor.isSynthetic) {
      PropertyAccessorElement? correspondingGetter =
          accessor.correspondingGetter;
      getterMetadata = correspondingGetter?.metadata.annotations;
    }

    // Format accessor name (setters include trailing '=')
    String accessorName = accessor is SetterElement
        ? "${accessor.nameOrUnknown}="
        : accessor.nameOrUnknown;

    return capabilityChecker(
      accessor.library.typeSystem,
      accessorName,
      metadata,
      getterMetadata,
    );
  });
}

/// Returns the declared constructors from [interfaceElement], filtered such that
/// the returned ones are the ones that are supported by [capabilities].
///
/// Excludes:
/// - Private constructors
/// - Constructors not supported by the new instance capability
Iterable<ConstructorElement> _extractDeclaredConstructors(
  LibraryResolver resolver,
  LibraryElement libraryElement,
  InterfaceElement interfaceElement,
  _Capabilities capabilities,
) {
  return interfaceElement.constructors.where((ConstructorElement constructor) {
    if (constructor.isPrivate) return false;
    
    String name = constructor.nameOrUnknown;
    if (name == "new") {
      name = "";
    }
    
    return capabilities.supportsNewInstance(
      constructor.library.typeSystem,
      name,
      constructor.metadata.annotations,
      libraryElement,
      resolver,
    );
  });
}

// ============================================================================
// Domain Creation Helpers
// ============================================================================

/// Creates a [_LibraryDomain] for the given library with all its
/// extracted declarations.
_LibraryDomain _createLibraryDomain(
  LibraryElement library,
  _ReflectorDomain domain,
) {
  Iterable<TopLevelVariableElement> declaredVariablesOfLibrary =
      _extractDeclaredVariables(
        domain._resolver,
        library,
        domain._capabilities,
      ).toList();
  
  Iterable<TopLevelFunctionElement> declaredFunctionsOfLibrary =
      _extractDeclaredFunctions(
        domain._resolver,
        library,
        domain._capabilities,
      ).toList();
  
  Iterable<PropertyAccessorElement> accessorsOfLibrary =
      _extractLibraryAccessors(
        domain._resolver,
        library,
        domain._capabilities,
      ).toList();
  
  Iterable<FormalParameterElement> declaredParametersOfLibrary =
      _extractDeclaredFunctionParameters(
        domain._resolver,
        declaredFunctionsOfLibrary,
        accessorsOfLibrary,
      ).toList();
  
  return _LibraryDomain(
    library,
    declaredVariablesOfLibrary,
    declaredFunctionsOfLibrary,
    declaredParametersOfLibrary,
    accessorsOfLibrary,
    domain,
  );
}

/// Creates a [_ClassDomain] for the given class/mixin with all its
/// extracted declarations.
///
/// Handles both regular classes and mixin applications specially.
_ClassDomain _createClassDomain(
  InterfaceElement type,
  _ReflectorDomain domain,
) {
  // Handle mixin applications specially
  if (type is MixinApplication) {
    return _createMixinApplicationDomain(type, domain);
  }

  // Regular class/interface handling
  List<FieldElement> declaredFieldsOfClass = _extractDeclaredFields(
    domain._resolver,
    type,
    domain._capabilities,
  ).toList();
  
  List<MethodElement> declaredMethodsOfClass = _extractDeclaredMethods(
    domain._resolver,
    type,
    domain._capabilities,
  ).toList();
  
  List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
      _extractAccessors(domain._resolver, type, domain._capabilities).toList();
  
  List<ConstructorElement> declaredConstructorsOfClass =
      _extractDeclaredConstructors(
        domain._resolver,
        type.library,
        type,
        domain._capabilities,
      ).toList();
  
  List<FormalParameterElement> declaredParametersOfClass =
      _extractDeclaredParameters(
        declaredMethodsOfClass,
        declaredConstructorsOfClass,
        declaredAndImplicitAccessorsOfClass,
      );
  
  return _ClassDomain(
    type,
    declaredFieldsOfClass,
    declaredMethodsOfClass,
    declaredParametersOfClass,
    declaredAndImplicitAccessorsOfClass,
    declaredConstructorsOfClass,
    domain,
  );
}

/// Creates a [_ClassDomain] for a mixin application.
///
/// Mixin applications have special handling:
/// - Fields and methods come from the mixin, excluding statics
/// - Constructors are empty (mixins don't have constructors)
_ClassDomain _createMixinApplicationDomain(
  MixinApplication type,
  _ReflectorDomain domain,
) {
  Iterable<FieldElement> declaredFieldsOfClass = _extractDeclaredFields(
    domain._resolver,
    type.mixin,
    domain._capabilities,
  ).where((FieldElement e) => !e.isStatic).toList();
  
  Iterable<MethodElement> declaredMethodsOfClass = _extractDeclaredMethods(
    domain._resolver,
    type.mixin,
    domain._capabilities,
  ).where((MethodElement e) => !e.isStatic).toList();
  
  Iterable<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
      _extractAccessors(
        domain._resolver,
        type.mixin,
        domain._capabilities,
      ).toList();
  
  Iterable<ConstructorElement> declaredConstructorsOfClass =
      <ConstructorElement>[];
  
  Iterable<FormalParameterElement> declaredParametersOfClass =
      _extractDeclaredParameters(
        declaredMethodsOfClass,
        declaredConstructorsOfClass,
        declaredAndImplicitAccessorsOfClass,
      );

  return _ClassDomain(
    type,
    declaredFieldsOfClass,
    declaredMethodsOfClass,
    declaredParametersOfClass,
    declaredAndImplicitAccessorsOfClass,
    declaredConstructorsOfClass,
    domain,
  );
}
