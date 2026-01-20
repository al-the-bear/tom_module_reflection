// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Constant code extraction utilities for the reflection generator.
///
/// This file provides functions to extract constant expressions from the
/// source code and convert them into string representations that can be
/// used in the generated reflection code.
///
/// The main function [_extractConstantCode] handles various expression types:
/// - List, Set, and Map literals
/// - Instance creation expressions (const constructors)
/// - Identifiers and property accesses
/// - Binary and conditional expressions
/// - Function references
/// - Primitive literals (int, bool, string, null, etc.)
part of 'generator_implementation.dart';

// ============================================================================
// List/Map Formatting Helpers
// ============================================================================

/// Formats an iterable as a typed list literal.
///
/// Example: `_formatAsList('int', [1, 2, 3])` → `'<int>[1, 2, 3]'`
String _formatAsList(String typeName, Iterable parts) =>
    '<$typeName>[${parts.join(', ')}]';

/// Formats an iterable as a const typed list literal.
///
/// Example: `_formatAsConstList('int', [1, 2, 3])` → `'const <int>[1, 2, 3]'`
String _formatAsConstList(String typeName, Iterable parts) =>
    'const <$typeName>[${parts.join(', ')}]';

/// Formats an iterable as an untyped (dynamic) list literal.
///
/// Example: `_formatAsDynamicList([1, 2, 3])` → `'[1, 2, 3]'`
String _formatAsDynamicList(Iterable parts) => '[${parts.join(', ')}]';

/// Formats an iterable as an untyped set literal.
///
/// Example: `_formatAsDynamicSet([1, 2, 3])` → `'{1, 2, 3}'`
String _formatAsDynamicSet(Iterable parts) => '{${parts.join(', ')}}';

/// Formats an iterable of key-value pairs as a map literal.
///
/// Example: `_formatAsMap(['a: 1', 'b: 2'])` → `'{a: 1, b: 2}'`
String _formatAsMap(Iterable parts) => '{${parts.join(', ')}}';

// ============================================================================
// Constant Code Extraction
// ============================================================================

/// Returns a [String] containing code that will evaluate to the same
/// value when evaluated in the generated file as the given [expression]
/// would evaluate to in [originatingLibrary].
///
/// This function handles various expression types including:
/// - List literals (with optional type arguments)
/// - Set and Map literals (with optional type arguments)
/// - Instance creation expressions (const constructor calls)
/// - Identifiers (variables, properties)
/// - Binary expressions (a + b, a == b, etc.)
/// - Conditional expressions (a ? b : c)
/// - Function references
/// - Primitive literals (int, bool, string, null, double)
///
/// The [importCollector] is updated with any libraries that need to be
/// imported to make the constant expression valid in the generated code.
Future<String> _extractConstantCode(
  Expression expression,
  _ImportCollector importCollector,
  FileId generatedLibraryId,
  LibraryResolver resolver,
) async {
  // Helper to process type annotations in collection literals
  Future<String> typeAnnotationHelper(TypeAnnotation typeName) async {
    DartType? interfaceType = typeName.type;
    if (interfaceType is InterfaceType) {
      LibraryElement library = interfaceType.element.library;
      String prefix = importCollector._getPrefix(library);
      return '$prefix$typeName';
    } else {
      await _severe(
        'constant.type_annotation.unsupported',
        'Not yet supported! '
        'Encountered unexpected kind of type annotation: '
        '$typeName (type: ${interfaceType?.runtimeType})',
      );
      return '$typeName';
    }
  }

  // Recursive helper to process expressions
  Future<String> helper(Expression expression) async {
    // --- List Literals ---
    if (expression is ListLiteral) {
      return await _processListLiteral(
        expression,
        helper,
        typeAnnotationHelper,
      );
    }
    
    // --- Set/Map Literals ---
    if (expression is SetOrMapLiteral) {
      return await _processSetOrMapLiteral(
        expression,
        helper,
        typeAnnotationHelper,
      );
    }
    
    // --- Instance Creation (const constructor calls) ---
    if (expression is InstanceCreationExpression) {
      return await _processInstanceCreation(
        expression,
        helper,
        importCollector,
        generatedLibraryId,
        resolver,
      );
    }
    
    // --- Identifiers (variables, properties) ---
    if (expression is Identifier) {
      return await _processIdentifier(
        expression,
        helper,
        importCollector,
        generatedLibraryId,
        resolver,
      );
    }
    
    // --- Binary Expressions (a + b, a == b, etc.) ---
    if (expression is BinaryExpression) {
      String a = await helper(expression.leftOperand);
      String op = expression.operator.lexeme;
      String b = await helper(expression.rightOperand);
      return '$a $op $b';
    }
    
    // --- Conditional Expressions (a ? b : c) ---
    if (expression is ConditionalExpression) {
      String condition = await helper(expression.condition);
      String a = await helper(expression.thenExpression);
      String b = await helper(expression.elseExpression);
      return '$condition ? $a : $b';
    }
    
    // --- Parenthesized Expressions ---
    if (expression is ParenthesizedExpression) {
      String nested = await helper(expression.expression);
      return '($nested)';
    }
    
    // --- Property Access (obj.property) ---
    if (expression is PropertyAccess) {
      String target = await helper(expression.realTarget);
      String selector = expression.propertyName.token.lexeme;
      return '$target.$selector';
    }
    
    // --- Method Invocations (only 'identical' supported) ---
    if (expression is MethodInvocation) {
      // We only handle 'identical(a, b)'.
      assert(expression.target == null);
      assert(expression.methodName.token.lexeme == 'identical');
      NodeList<Expression> arguments = expression.argumentList.arguments;
      assert(arguments.length == 2);
      String a = await helper(arguments[0]);
      String b = await helper(arguments[1]);
      return 'identical($a, $b)';
    }
    
    // --- Named Expressions (used in argument lists) ---
    if (expression is NamedExpression) {
      String value = await _extractConstantCode(
        expression.expression,
        importCollector,
        generatedLibraryId,
        resolver,
      );
      return '${expression.name} $value';
    }
    
    // --- Function References ---
    if (expression is FunctionReference) {
      String function = await _extractConstantCode(
        expression.function,
        importCollector,
        generatedLibraryId,
        resolver,
      );
      TypeArgumentList? expressionTypeArguments = expression.typeArguments;
      if (expressionTypeArguments == null) {
        return function;
      } else {
        var typeArguments = <String>[];
        for (TypeAnnotation expressionTypeArgument
            in expressionTypeArguments.arguments) {
          String typeArgument = await typeAnnotationHelper(
            expressionTypeArgument,
          );
          typeArguments.add(typeArgument);
        }
        return '$function<${typeArguments.join(', ')}>';
      }
    }
    
    // --- Primitive Literals ---
    // These can be converted directly to source code
    assert(
      expression is IntegerLiteral ||
          expression is BooleanLiteral ||
          expression is StringLiteral ||
          expression is NullLiteral ||
          expression is SymbolLiteral ||
          expression is DoubleLiteral ||
          expression is TypedLiteral,
    );
    return expression.toSource();
  }

  return await helper(expression);
}

// ============================================================================
// Expression Processing Helpers
// ============================================================================

/// Processes a list literal expression.
Future<String> _processListLiteral(
  ListLiteral expression,
  Future<String> Function(Expression) helper,
  Future<String> Function(TypeAnnotation) typeAnnotationHelper,
) async {
  var elements = <String>[];
  for (CollectionElement collectionElement in expression.elements) {
    if (collectionElement is Expression) {
      Expression subExpression = collectionElement;
      elements.add(await helper(subExpression));
    } else {
      // TODO(eernst) implement: `if` and `spread` elements of list.
      await _severe(
        'constant.list_literal.element_not_expression',
        'Not yet supported! '
        'Encountered list literal element which is not an expression: '
        '$collectionElement (type: ${collectionElement.runtimeType})',
      );
      elements.add('');
    }
  }
  
  TypeArgumentList? expressionTypeArguments = expression.typeArguments;
  if (expressionTypeArguments == null ||
      expressionTypeArguments.arguments.isEmpty) {
    return 'const ${_formatAsDynamicList(elements)}';
  } else {
    assert(expressionTypeArguments.arguments.length == 1);
    String typeArgument = await typeAnnotationHelper(
      expressionTypeArguments.arguments[0],
    );
    return 'const <$typeArgument>${_formatAsDynamicList(elements)}';
  }
}

/// Processes a set or map literal expression.
Future<String> _processSetOrMapLiteral(
  SetOrMapLiteral expression,
  Future<String> Function(Expression) helper,
  Future<String> Function(TypeAnnotation) typeAnnotationHelper,
) async {
  if (expression.isMap) {
    return await _processMapLiteral(
      expression,
      helper,
      typeAnnotationHelper,
    );
  } else if (expression.isSet) {
    return await _processSetLiteral(
      expression,
      helper,
      typeAnnotationHelper,
    );
  } else {
    unreachableError(
      'constant.set_or_map.invalid_state',
      'SetOrMapLiteral is neither a set nor a map: $expression',
    );
  }
}

/// Processes a map literal expression.
Future<String> _processMapLiteral(
  SetOrMapLiteral expression,
  Future<String> Function(Expression) helper,
  Future<String> Function(TypeAnnotation) typeAnnotationHelper,
) async {
  var elements = <String>[];
  for (CollectionElement collectionElement in expression.elements) {
    if (collectionElement is MapLiteralEntry) {
      String key = await helper(collectionElement.key);
      String value = await helper(collectionElement.value);
      elements.add('$key: $value');
    } else {
      // TODO(eernst) implement: `if` and `spread` elements of a map.
      await _severe(
        'constant.map_literal.element_not_entry',
        'Not yet supported! '
        'Encountered map literal element which is not a map entry: '
        '$collectionElement (type: ${collectionElement.runtimeType})',
      );
      elements.add('');
    }
  }
  
  TypeArgumentList? expressionTypeArguments = expression.typeArguments;
  if (expressionTypeArguments == null ||
      expressionTypeArguments.arguments.isEmpty) {
    return 'const ${_formatAsMap(elements)}';
  } else {
    assert(expressionTypeArguments.arguments.length == 2);
    String keyType = await typeAnnotationHelper(
      expressionTypeArguments.arguments[0],
    );
    String valueType = await typeAnnotationHelper(
      expressionTypeArguments.arguments[1],
    );
    return 'const <$keyType, $valueType>${_formatAsMap(elements)}';
  }
}

/// Processes a set literal expression.
Future<String> _processSetLiteral(
  SetOrMapLiteral expression,
  Future<String> Function(Expression) helper,
  Future<String> Function(TypeAnnotation) typeAnnotationHelper,
) async {
  var elements = <String>[];
  for (CollectionElement collectionElement in expression.elements) {
    if (collectionElement is Expression) {
      Expression subExpression = collectionElement;
      elements.add(await helper(subExpression));
    } else {
      // TODO(eernst) implement: `if` and `spread` elements of a set.
      await _severe(
        'constant.set_literal.element_not_expression',
        'Not yet supported! '
        'Encountered set literal element which is not an expression: '
        '$collectionElement (type: ${collectionElement.runtimeType})',
      );
      elements.add('');
    }
  }
  
  TypeArgumentList? expressionTypeArguments = expression.typeArguments;
  if (expressionTypeArguments == null ||
      expressionTypeArguments.arguments.isEmpty) {
    return 'const ${_formatAsDynamicSet(elements)}';
  } else {
    assert(expressionTypeArguments.arguments.length == 1);
    String typeArgument = await typeAnnotationHelper(
      expressionTypeArguments.arguments[0],
    );
    return 'const <$typeArgument>${_formatAsDynamicSet(elements)}';
  }
}

/// Processes an instance creation expression (const constructor call).
Future<String> _processInstanceCreation(
  InstanceCreationExpression expression,
  Future<String> Function(Expression) helper,
  _ImportCollector importCollector,
  FileId generatedLibraryId,
  LibraryResolver resolver,
) async {
  String constructor = expression.constructorName.toSource();
  
  if (_isPrivateName(constructor)) {
    await _severe(
      'constant.constructor.private',
      'Cannot access private constructor `$constructor`, '
      'needed for expression $expression',
    );
    return '';
  }
  
  LibraryElement libraryOfConstructor =
      expression.constructorName.element!.library;
  
  if (await _isImportableLibrary(
    libraryOfConstructor,
    generatedLibraryId,
    resolver,
  )) {
    importCollector._addLibrary(libraryOfConstructor);
    String prefix = importCollector._getPrefix(libraryOfConstructor);
    
    // Process constructor arguments
    var argumentList = <String>[];
    for (Expression argument in expression.argumentList.arguments) {
      argumentList.add(await helper(argument));
    }
    String arguments = argumentList.join(', ');
    
    // Double-check for private name after processing
    if (_isPrivateName(constructor)) {
      await _severe(
        'constant.constructor.private_recheck',
        'Cannot access private constructor `$constructor`, '
        'needed for expression $expression (second check)',
      );
      return '';
    }
    
    return 'const $prefix$constructor($arguments)';
  } else {
    await _severe(
      'constant.library.not_importable',
      'Cannot access library ${libraryOfConstructor.name}, '
      'needed for expression $expression. '
      'Library URI: ${libraryOfConstructor.firstFragment.source.uri}',
    );
    return '';
  }
}

/// Processes an identifier expression (variable, property reference).
Future<String> _processIdentifier(
  Identifier expression,
  Future<String> Function(Expression) helper,
  _ImportCollector importCollector,
  FileId generatedLibraryId,
  LibraryResolver resolver,
) async {
  // Handle private identifiers by expanding to their initializer
  if (Identifier.isPrivateName(expression.name)) {
    return await _processPrivateIdentifier(expression, helper, resolver);
  }
  
  // Handle public identifiers
  Element? element = expression.element;
  
  if (element == null) {
    // Unresolved identifier - this can occur in some edge cases
    await _fine(
      'constant.identifier.unresolved',
      'Encountered unresolved identifier $expression '
      'in constant; using null. Expression type: ${expression.runtimeType}',
    );
    return 'null';
  }
  
  if (element.library == null) {
    // Core library element (like 'null', 'true', 'false')
    return '${element.name}';
  }
  
  // Standard case: element from an importable library
  LibraryElement? elementLibrary = element.library;
  if (elementLibrary != null &&
      await _isImportableLibrary(
        elementLibrary,
        generatedLibraryId,
        resolver,
      )) {
    importCollector._addLibrary(elementLibrary);
    String prefix = importCollector._getPrefix(elementLibrary);
    
    // Handle class members (static fields, etc.)
    Element? enclosingElement = element.enclosingElement;
    if (enclosingElement is InterfaceElement) {
      prefix += '${enclosingElement.name}.';
    }
    
    String? elementName = element.name;
    if (elementName != null && _isPrivateName(elementName)) {
      await _severe(
        'constant.identifier.private_name',
        'Cannot access private name `$elementName`, '
        'needed for expression $expression. '
        'Library: ${elementLibrary.name}',
      );
    }
    
    return '$prefix$elementName';
  } else {
    await _severe(
      'constant.identifier.library_not_importable',
      'Cannot access library ${elementLibrary?.name}, '
      'needed for expression $expression. '
      'Library may be null or not importable.',
    );
    return '';
  }
}

/// Processes a private identifier by expanding it to its initializer.
Future<String> _processPrivateIdentifier(
  Identifier expression,
  Future<String> Function(Expression) helper,
  LibraryResolver resolver,
) async {
  Element? staticElement = expression.element;
  
  if (staticElement is PropertyAccessorElement) {
    VariableElement? variable = staticElement.variable;
    AstNode? variableDeclaration = await _getDeclarationAst(
      variable,
      resolver,
    );
    
    if (variableDeclaration == null ||
        variableDeclaration is! VariableDeclaration) {
      await _severe(
        'constant.identifier.private_no_declaration',
        'Cannot handle private identifier $expression. '
        'No valid variable declaration found.',
      );
      return '';
    }
    
    // A constant variable _does_ have an initializer.
    return await helper(variableDeclaration.initializer!);
  } else {
    await _severe(
      'constant.identifier.private_not_accessor',
      'Cannot handle private identifier $expression. '
      'Element is not a PropertyAccessorElement: ${staticElement?.runtimeType}',
    );
    return '';
  }
}
