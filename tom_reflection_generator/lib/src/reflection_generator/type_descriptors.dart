// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Type descriptor functions for the reflection generator.
///
/// This file provides functions that encode type information into integer
/// descriptors. These descriptors are compact representations of type
/// attributes (private, static, const, final, nullable, etc.) that are
/// used in the generated reflection code.
///
/// The descriptor encoding uses bit flags defined in [encoding_constants.dart]
/// to represent various attributes of types, fields, methods, and parameters.
part of 'generator_implementation.dart';

// ============================================================================
// Utility Functions for Checking Element Types
// ============================================================================

/// Returns true if the accessor is not an implicit getter or setter.
///
/// Synthetic accessors are those automatically generated for fields.
bool _accessorIsntImplicitGetterOrSetter(PropertyAccessorElement accessor) {
  return !accessor.isSynthetic ||
      (accessor is! GetterElement && accessor is! SetterElement);
}

/// Returns true if the executable is not an implicit getter or setter.
bool _executableIsntImplicitGetterOrSetter(ExecutableElement executable) {
  if (executable is PropertyAccessorElement) {
    return _accessorIsntImplicitGetterOrSetter(executable);
  } else {
    return true;
  }
}

// ============================================================================
// Class Descriptors
// ============================================================================

/// Returns an integer encoding of the kind and attributes of the given class.
///
/// The descriptor includes information about:
/// - Whether the class is private
/// - Whether it is synthetic (compiler-generated)
/// - Whether it is abstract
/// - Whether it is an enum
/// - Nullability attributes
///
/// Example usage:
/// ```dart
/// int descriptor = _classDescriptor(myClassElement);
/// bool isPrivate = (descriptor & constants.privateAttribute) != 0;
/// ```
int _classDescriptor(InterfaceElement element) {
  int result = constants.clazz;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element is MixinElement ||
      element is ClassElement && element.isAbstract) {
    result |= constants.abstractAttribute;
  }
  if (element is EnumElement) result |= constants.enumAttribute;
  if (element is MixinApplication) {
    result |= constants.nonNullableAttribute;
    return result;
  }
  DartType thisType = element.thisType;
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(thisType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(thisType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

// ============================================================================
// Field and Variable Descriptors
// ============================================================================

/// Returns an integer encoding of the kind and attributes of the given
/// top-level variable.
///
/// Similar to [_fieldDescriptor] but includes the top-level attribute.
int _topLevelVariableDescriptor(TopLevelVariableElement element) {
  int result = constants.field;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) {
    result |= constants.constAttribute;
    // We will get `false` from `element.isFinal` in this case, but with
    // a mirror from 'dart:mirrors' it is considered to be "implicitly
    // final", so we follow that and ignore `element.isFinal`.
    result |= constants.finalAttribute;
  } else {
    if (element.isFinal) result |= constants.finalAttribute;
  }
  if (element.isStatic) result |= constants.staticAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType is DynamicType) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
    }
    result |= constants.topLevelAttribute;
  }
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(declaredType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(declaredType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// field.
///
/// The descriptor includes information about:
/// - Privacy (private/public)
/// - Synthetic status
/// - Const/final modifiers
/// - Static modifier
/// - Return type characteristics (void, dynamic, never, class type)
/// - Nullability
/// - Generic type status
int _fieldDescriptor(FieldElement element) {
  int result = constants.field;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) {
    result |= constants.constAttribute;
    // We will get `false` from `element.isFinal` in this case, but with
    // a mirror from 'dart:mirrors' it is considered to be "implicitly
    // final", so we follow that and ignore `element.isFinal`.
    result |= constants.finalAttribute;
  } else {
    if (element.isFinal) result |= constants.finalAttribute;
  }
  if (element.isStatic) result |= constants.staticAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType is DynamicType) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
      if (elementType.typeParameters.isNotEmpty) {
        result |= constants.genericTypeAttribute;
      }
    }
  }
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(declaredType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(declaredType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

// ============================================================================
// Parameter Descriptors
// ============================================================================

/// Returns an integer encoding of the kind and attributes of a parameter.
///
/// The descriptor includes information about:
/// - Privacy and synthetic status
/// - Const/final modifiers
/// - Optional and named status
/// - Default value presence
/// - Type characteristics (void, dynamic, never, class type)
/// - Nullability and generic type status
int _parameterDescriptor(FormalParameterElement element) {
  int result = constants.parameter;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) result |= constants.constAttribute;
  if (element.isFinal) result |= constants.finalAttribute;
  if (element.defaultValueCode != null) {
    result |= constants.hasDefaultValueAttribute;
  }
  if (element.isOptional) result |= constants.optionalAttribute;
  if (element.isNamed) result |= constants.namedAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType is DynamicType) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
      if (elementType.typeParameters.isNotEmpty) {
        result |= constants.genericTypeAttribute;
      }
    }
  }
  LibraryElement? library = element.library;
  if (library != null) {
    if (library.typeSystem.isNullable(declaredType)) {
      result |= constants.nullableAttribute;
    }
    if (library.typeSystem.isNonNullable(declaredType)) {
      result |= constants.nonNullableAttribute;
    }
  }
  return result;
}

// ============================================================================
// Declaration Descriptors (Methods, Constructors, Accessors)
// ============================================================================

/// Returns an integer encoding of the kind and attributes of an executable
/// element (method, constructor, getter, setter, or function).
///
/// The descriptor encodes:
/// - The kind of declaration (method, getter, setter, constructor, function)
/// - For constructors: factory, const, redirecting status
/// - Return type characteristics
/// - Privacy, static, synthetic, and abstract status
/// - Top-level attribute for functions
int _declarationDescriptor(ExecutableElement element) {
  var result = 0;

  void handleReturnType(ExecutableElement element) {
    DartType returnType = element.returnType;
    if (returnType is VoidType) {
      result |= constants.voidReturnTypeAttribute;
    }
    if (returnType is DynamicType) {
      result |= constants.dynamicReturnTypeAttribute;
    }
    if (returnType is VoidType) {
      result |= constants.neverReturnTypeAttribute;
    }
    if (returnType is InterfaceType) {
      Element? elementReturnType = returnType.element;
      if (elementReturnType is InterfaceElement) {
        result |= constants.classReturnTypeAttribute;
        if (elementReturnType.typeParameters.isNotEmpty) {
          result |= constants.genericReturnTypeAttribute;
        }
      }
    }
  }

  if (element is PropertyAccessorElement) {
    result |= element is GetterElement ? constants.getter : constants.setter;
    handleReturnType(element);
  } else if (element is ConstructorElement) {
    if (element.isFactory) {
      result |= constants.factoryConstructor;
    } else {
      result |= constants.generativeConstructor;
    }
    if (element.isConst) result |= constants.constAttribute;
    if (element.redirectedConstructor != null) {
      result |= constants.redirectingConstructorAttribute;
    }
  } else if (element is MethodElement) {
    result |= constants.method;
    handleReturnType(element);
  } else {
    assert(element is TopLevelFunctionElement);
    result |= constants.function;
    handleReturnType(element);
  }
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isStatic) result |= constants.staticAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isAbstract) result |= constants.abstractAttribute;
  if (element.enclosingElement is! InterfaceElement) {
    result |= constants.topLevelAttribute;
  }
  return result;
}

// ============================================================================
// Constructor Name Helper
// ============================================================================

/// Returns the constructor name formatted for use in generated code.
///
/// For unnamed constructors, returns the class name.
/// For named constructors, returns "ClassName.constructorName".
///
/// Returns null if the constructor is private.
Future<String?> _nameOfConstructor(ConstructorElement element) async {
  String name = element.name == '' || element.name == 'new'
      ? element.enclosingElement.nameOrUnknown
      : '${element.enclosingElement.nameOrUnknown}.${element.nameOrUnknown}';
  if (_isPrivateName(name)) {
    await _severe(
      'constructor.name.private',
      'Cannot access private name `$name`. '
      'Constructor: ${element.enclosingElement.name}',
      element,
    );
    return null;
  }
  return name;
}
