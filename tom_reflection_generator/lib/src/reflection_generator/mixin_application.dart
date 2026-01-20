// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

class MixinApplication implements ClassElementImpl {
  final String? declaredName;
  final InterfaceElement superclass;
  final InterfaceElement mixin;
  final InterfaceElement? subclass;

  @override
  final LibraryElementImpl library;

  MixinApplication(
    this.declaredName,
    this.superclass,
    this.mixin,
    this.library,
    this.subclass,
  );

  @override
  String get name {
    if (declaredName != null) return declaredName!;
    if (superclass is MixinApplication) {
      return '${superclass.name}, ${_qualifiedName(mixin)}';
    } else {
      return '${_qualifiedName(superclass)} with ${_qualifiedName(mixin)}';
    }
  }

  @override
  String get displayName => name;

  @override
  List<InterfaceTypeImpl> get interfaces => const <InterfaceTypeImpl>[];

  @override
  MetadataImpl get metadata => MetadataImpl(const []);

  @override
  bool get isSynthetic => declaredName == null;

  @override
  InterfaceTypeImpl instantiate({
    required List<DartType> typeArguments,
    required NullabilitySuffix nullabilitySuffix,
  }) => InterfaceTypeImpl(
    element: this,
    typeArguments: typeArguments.cast(),
    nullabilitySuffix: nullabilitySuffix,
  );

  @override
  InterfaceTypeImpl? get supertype {
    if (superclass is MixinApplication) {
      return superclass.supertype as InterfaceTypeImpl;
    }
    return _typeForReflection(superclass) as InterfaceTypeImpl;
  }

  @override
  List<InterfaceTypeImpl> get mixins {
    var result = <InterfaceTypeImpl>[];
    if (superclass is MixinApplication) {
      result.addAll(superclass.mixins.cast());
    }
    result.add(_typeForReflection(mixin) as InterfaceTypeImpl);
    return result;
  }

  @override
  AnalysisSessionImpl get session => mixin.session as AnalysisSessionImpl;

  /// Returns true iff this class was declared using the syntax
  /// `class B = A with M;`, i.e., if it is an explicitly named mixin
  /// application.
  @override
  bool get isMixinApplication => declaredName != null;

  @override
  bool get isAbstract {
    InterfaceElement mixin = this.mixin;
    return !isMixinApplication ||
        mixin is MixinElement ||
        mixin is ClassElement && mixin.isAbstract;
  }

  // This seems to be the defined behaviour according to dart:mirrors.
  @override
  bool get isPrivate => false;

  @override
  List<TypeParameterElementImpl> get typeParameters =>
      <TypeParameterElementImpl>[];

  @override
  ElementKind get kind => ElementKind.CLASS;

  @override
  bool operator ==(Object other) {
    return other is MixinApplication &&
        superclass == other.superclass &&
        mixin == other.mixin &&
        library == other.library &&
        subclass == other.subclass;
  }

  @override
  int get hashCode => superclass.hashCode ^ mixin.hashCode ^ library.hashCode;

  @override
  String toString() => 'MixinApplication($superclass, $mixin)';

  // Let the compiler generate forwarders for all remaining methods: Instances
  // of this class are only ever passed around locally in this library, so
  // we will never need to support any members that we don't use locally.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    log.severe('[mixin_application.no_such_method] Missing MixinApplication '
        'member: ${invocation.memberName}. '
        'Superclass: ${superclass.name}, Mixin: ${mixin.name}');
  }
}

bool _isSetterName(String name) => name.endsWith('=');
String _setterNameToGetterName(String name) {
  assert(_isSetterName(name));
  return name.substring(0, name.length - 1);
}

String _qualifiedName(Element? element) {
  LibraryElement? elementLibrary = element?.library;
  if (element == null || elementLibrary == null) return 'null';
  return '${elementLibrary.name}.${element.name}';
}

String _qualifiedFunctionName(TopLevelFunctionElement functionElement) {
  return '${functionElement.library.name}.${functionElement.name}';
}

String _qualifiedTypeParameterName(TypeParameterElement? typeParameterElement) {
  if (typeParameterElement == null) return 'null';
  return '${_qualifiedName(typeParameterElement.enclosingElement!)}.'
      '${typeParameterElement.name}';
}

bool _isPrivateName(String name) {
  return name.startsWith('_') || name.contains('._');
}

Future<DartObject?> _evaluateConstant(
  LibraryElement library,
  Expression expression,
) async {
  AstNode? currentUnit = expression.parent;
  var levels = 0;
  while (currentUnit != null &&
      currentUnit is! CompilationUnit &&
      ++levels < 100) {
    currentUnit = currentUnit.parent;
  }
  if (currentUnit is! CompilationUnit) {
    await _severe(
      'constant.evaluate.no_compilation_unit',
      'Expression `$expression` has no enclosing compilation unit. '
      'Searched $levels parent levels without finding CompilationUnit.',
    );
    return null;
  }

  LibraryFragment unitElement = currentUnit.declaredFragment!;
  Source source = unitElement.source;
  var libraryElement = unitElement.element as LibraryElementImpl;

  var errorListener = RecordingDiagnosticListener();
  var errorReporter = DiagnosticReporter(errorListener, source);
  var declaredVariables = DeclaredVariables(); // No variables.

  var evaluationEngine = ConstantEvaluationEngine(
    declaredVariables: declaredVariables,
    configuration: ConstantEvaluationConfiguration(),
  );

  var dependencies = <ConstantEvaluationTarget>[];
  expression.accept(ReferenceFinder(dependencies.add));

  computeConstants(
    declaredVariables: declaredVariables,
    constants: dependencies,
    featureSet: libraryElement.featureSet,
    configuration: ConstantEvaluationConfiguration(),
  );

  var visitor = ConstantVisitor(
    evaluationEngine,
    libraryElement,
    errorReporter,
  );

  Constant constant = visitor.evaluateAndReportInvalidConstant(expression);
  DartObjectImpl? dartObject = constant is DartObjectImpl ? constant : null;

  if (errorListener.diagnostics.isNotEmpty) {
    var message = StringBuffer('Constant `$expression` has errors:\n');
    for (Diagnostic error in errorListener.diagnostics) {
      message.writeln(error);
    }
    unawaited(_severe('constant.evaluate.has_errors', message.toString()));
  }

  return dartObject;
}

/// Returns the result of evaluating [elementAnnotation].
DartObject? _getEvaluatedMetadatum(ElementAnnotation elementAnnotation) =>
    elementAnnotation.computeConstantValue();

/// Returns the result of evaluating [metadata].
///
/// Returns the result of evaluating each of the element annotations
/// in [metadata] using [_getEvaluatedMetadatum].
Iterable<DartObject> _getEvaluatedMetadata(
  Iterable<ElementAnnotation>? metadata,
) {
  if (metadata == null) return [];
  var result = <DartObject>[];
  for (ElementAnnotation annotation in metadata) {
    DartObject? evaluatedMetadatum = _getEvaluatedMetadatum(annotation);
    if (evaluatedMetadatum != null) result.add(evaluatedMetadatum);
  }
  return result;
}

/// Determine whether the given library is a platform library.
///
/// TODO(eernst): This function is only needed until a solution is found to the
/// problem that platform libraries are considered invalid when obtained from
/// `getResolvedLibraryByElement`, such that subsequent use will throw.
/// Issue 173.
bool _isPlatformLibrary(LibraryElement? libraryElement) =>
    libraryElement?.firstFragment.source.uri.scheme == 'dart';

