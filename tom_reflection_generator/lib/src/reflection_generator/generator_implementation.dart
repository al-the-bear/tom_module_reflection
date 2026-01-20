// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library;

// ignore_for_file:implementation_imports

import 'dart:async' show unawaited;
import 'dart:developer' as developer;
import 'dart:io';
import 'package:analyzer/dart/analysis/declared_variables.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/dart/constant/compute.dart';
import 'package:analyzer/src/dart/constant/evaluation.dart';
import 'package:analyzer/src/dart/constant/utilities.dart';
import 'package:analyzer/src/dart/constant/value.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/analysis/session.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:dart_style/dart_style.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:path/path.dart' as path;
import 'encoding_constants.dart' as constants;
import 'reflection_class_constants.dart' as reflection_class_constants;
import 'element_capability.dart' as ec;
import 'fixed_point.dart';
import 'library_resolver.dart';
import 'reflection_errors.dart' as errors;

part 'capabilities.dart';
part 'constant_extractor.dart';
part 'diagnostic_helpers.dart';
part 'domain_classes.dart';
part 'element_filters.dart';
part 'import_collector.dart';
part 'import_helpers.dart';
part 'metadata_extractor.dart';
part 'mixin_application.dart';
part 'reflection_world.dart';
part 'reflector_domain.dart';
part 'type_descriptors.dart';
part 'utility_classes.dart';

// ignore_for_file: omit_local_variable_types

/// Logger for the reflection generator.
final log = Logger('ReflectionGenerator');

/// Specifiers for warnings that may be suppressed; `allWarnings` disables all
/// warnings, and the remaining values are concerned with individual warnings.
/// Remember to update the explanatory text in [_findSuppressWarnings] whenever
/// this list is updated.
enum WarningKind {
  badSuperclass,
  badNamePattern,
  badMetadata,
  badReflectorClass,
  unsupportedType,
  unusedReflector,
}

bool _unknownNameWasUsed = false;
Element? _unknownNameElement;

extension on Element {
  String get nameOrUnknown {
    final name = this.name;
    if (name != null) return name;
    _unknownNameWasUsed = true;
    _unknownNameElement = this;
    return 'unknownName';
  }
}

// To avoid name clashes, we allocate numbers for generated `typedef`s
// globally, by reading and updating this variable.
int typedefNumber = 1;

/// Information about the program parts that can be reflected by a given
/// Reflector.
class GeneratorImplementation {
  /// The package name of the reflection library to look for.
  /// Defaults to 'tom_reflection' but can be set to 'reflection' for
  /// compatibility with the original reflection.dart package.
  final String reflectionPackageName;

  /// If true, use all capabilities regardless of what the reflector specifies.
  /// This is useful for testing and development when you want full reflection
  /// support without having to specify all capabilities in the reflector.
  final bool useAllCapabilities;

  /// Creates a new builder implementation.
  /// 
  /// [reflectionPackageName] specifies the package name of the reflection
  /// library to detect (e.g., 'reflection' or 'tom_reflection').
  /// 
  /// [useAllCapabilities] when true, ignores the capabilities specified in
  /// the reflector and uses all available capabilities instead.
  GeneratorImplementation({
    this.reflectionPackageName = 'tom_reflection',
    this.useAllCapabilities = false,
  });

  late final LibraryResolver _resolver;
  var _libraries = <LibraryElementImpl>[];
  final _librariesByName = <String, LibraryElement>{};
  late final bool _formatted;
  late final List<WarningKind> _suppressedWarnings;

  /// Returns a list of all available capabilities.
  /// Used when [useAllCapabilities] is true to enable full reflection support.
  List<ec.ReflectCapability> _allCapabilities() {
    return <ec.ReflectCapability>[
      // Invoking capabilities
      ec.invokingCapability,
      // Type capabilities
      ec.typingCapability,
      ec.typeCapability,
      ec.typeRelationsCapability,
      ec.reflectedTypeCapability,
      // Declaration capabilities
      ec.declarationsCapability,
      ec.metadataCapability,
      // Library capabilities
      ec.libraryCapability,
      ec.uriCapability,
      ec.libraryDependenciesCapability,
      // Quantify capabilities
      ec.subtypeQuantifyCapability,
      ec.superclassQuantifyCapability,
      ec.typeAnnotationQuantifyCapability,
      ec.correspondingSetterQuantifyCapability,
      // Delegate capability
      ec.delegateCapability,
    ];
  }

  bool _warningEnabled(WarningKind kind) {
    // TODO(eernst) implement: No test reaches this point.
    // The mock_tests should be extended to exercise all warnings and errors
    // that the builder can encounter.
    return !_suppressedWarnings.contains(kind);
  }

  /// Checks whether the given [type] from the target program is "our"
  /// class [Reflection] by looking up the static field
  /// [Reflection.thisClassId] and checking its value (which is a 40
  /// character string computed by sha1sum on an old version of
  /// reflection.dart).
  ///
  /// Discussion of approach: Checking that we have found the correct
  /// [Reflection] class is crucial for correctness, and the "obvious"
  /// approach of just looking up the library and then the class with the
  /// right names using [resolver] is unsafe.  The problems are as
  /// follows: (1) Library names are not guaranteed to be unique in a
  /// given program, so we might look up a different library named
  /// reflection.reflection, and a class named Reflection in there.  (2)
  /// Library URIs (which must be unique in a given program) are not known
  /// across all usage locations for reflection.dart, so we cannot easily
  /// predict all the possible URIs that could be used to import
  /// reflection.dart; and it would be awkward to require that all user
  /// programs must use exactly one specific URI to import
  /// reflection.dart.  So we use [Reflection.thisClassId] which is very
  /// unlikely to occur with the same value elsewhere by accident.
  bool _equalsClassReflection(InterfaceElement type) {
    FieldElement? idField = type.getField('thisClassId');
    if (idField == null || !idField.isStatic) return false;
    DartObject? constantValue = idField.computeConstantValue();
    return constantValue?.toStringValue() == reflection_class_constants.id;
  }

  /// Returns the InterfaceElement in the target program which corresponds to class
  /// [Reflection].
  Future<InterfaceElement?> _findReflectionInterfaceElement(
    LibraryElement reflectionLibrary,
  ) async {
    for (InterfaceElement type in reflectionLibrary.classes) {
      if (type.name == reflection_class_constants.name &&
          _equalsClassReflection(type)) {
        return type;
      }
    }
    // No need to check `unit.enums`: [Reflection] is not an enum.
    // Class [Reflection] was not found in the target program.
    return null;
  }

  /// Returns true iff [possibleSubtype] is a direct subclass of [type].
  bool _isDirectSubclassOf(
    ParameterizedType possibleSubtype,
    InterfaceType type,
  ) {
    if (possibleSubtype is InterfaceType) {
      InterfaceType? superclass = possibleSubtype.superclass;
      // Even if `superclass == null` (superclass of Object), the equality
      // test will produce the correct result.
      return type.element == superclass?.element;
    } else {
      return false;
    }
  }

  /// Returns true iff [possibleSubtype] is a subclass of [type], including the
  /// reflexive and transitive cases.
  bool _isSubclassOf(ParameterizedType possibleSubtype, InterfaceType type) {
    if (possibleSubtype is! InterfaceType) return false;
    if (possibleSubtype.element == type.element) return true;
    InterfaceType? superclass = possibleSubtype.superclass;
    if (superclass == null) return false;
    return _isSubclassOf(superclass, type);
  }

  /// Returns the metadata class in [elementAnnotation] if it is an
  /// instance of a direct subclass of [focusClass], otherwise returns
  /// `null`.  Uses [errorReporter] to report an error if it is a subclass
  /// of [focusClass] which is not a direct subclass of [focusClass],
  /// because such a class is not supported as a Reflector.
  Future<InterfaceElement?> _getReflectionAnnotation(
    ElementAnnotation elementAnnotation,
    InterfaceElement focusClass,
  ) async {
    if (elementAnnotation.element == null) {
      // This behavior is based on the assumption that a `null` element means
      // "there is no annotation here".
      return null;
    }

    /// Checks that the inheritance hierarchy placement of [type]
    /// conforms to the constraints relative to [classReflection],
    /// which is intended to refer to the class Reflection defined
    /// in package:tom_reflection/tom_reflection.dart.
    Future<bool> checkInheritance(
      ParameterizedType type,
      InterfaceType classReflection,
    ) async {
      if (!_isSubclassOf(type, classReflection)) {
        // Not a subclass of [classReflection] at all.
        return false;
      }
      if (!_isDirectSubclassOf(type, classReflection)) {
        // Instance of [classReflection], or of indirect subclass
        // of [classReflection]: Not supported, report an error.
        await _severe(
          'metadata.not_direct_subclass',
          '${errors.metadataNotDirectSubclass} '
          'Type: ${type.element?.name ?? 'unnamed'}, Expected superclass: ${classReflection.element.name ?? 'unnamed'}',
          elementAnnotation.element,
        );
        return false;
      }
      // A direct subclass of [classReflection], all OK.
      return true;
    }

    Element? element = elementAnnotation.element;
    if (element is ConstructorElement) {
      DartType enclosingType = _typeForReflection(element.enclosingElement);
      DartType focusClassType = _typeForReflection(focusClass);
      bool isOk =
          enclosingType is ParameterizedType &&
          focusClassType is InterfaceType &&
          await checkInheritance(enclosingType, focusClassType);
      if (isOk) {
        if (enclosingType is InterfaceType) {
          return enclosingType.element;
        } else {
          return null;
        }
      } else {
        return null;
      }
    } else if (element is PropertyAccessorElement) {
      PropertyInducingElement? variable = element.variable;
      DartObject? constantValue = variable.computeConstantValue();
      // Handle errors during evaluation. In general `constantValue` is
      // null for (1) non-const variables, (2) variables without an
      // initializer, and (3) unresolved libraries; (3) should not occur
      // because of the approach we use to get the resolver; we will not
      // see (1) because we have checked the type of `variable`; and (2)
      // would mean that the value is actually null, which we will also
      // reject as irrelevant.
      if (constantValue == null) return null;
      DartType? constantValueType = constantValue.type;
      DartType focusClassType = _typeForReflection(focusClass);
      bool isOk =
          constantValueType is ParameterizedType &&
          focusClassType is InterfaceType &&
          await checkInheritance(constantValueType, focusClassType);
      // When `isOK` is true, result.value.type.element is a InterfaceElement.
      if (isOk) {
        if (constantValueType is InterfaceType) {
          return constantValueType.element;
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    // Otherwise [element] is some other construct which is not supported.
    await _fine(
      'metadata.unsupported_form',
      'Ignoring metadata in a form ($elementAnnotation) '
      'which is not yet supported. Element type: ${elementAnnotation.element?.runtimeType}',
      elementAnnotation.element,
    );
    return null;
  }

  /// Adds a warning to the log, using the source code location of `target`
  /// to identify the relevant location where the error occurs.
  ///
  /// The [id] parameter should be a unique identifier in the format
  /// `[category.subcategory.warning_type]` to help identify the warning location.
  Future<void> _warn(
    String id,
    WarningKind kind,
    String message, [
    Element? target,
  ]) async {
    if (_warningEnabled(kind)) {
      final formattedMessage = '[$id] $message';
      if (target != null) {
        log.warning(await _formatDiagnosticMessage(formattedMessage, target, _resolver));
      } else {
        log.warning(formattedMessage);
      }
    }
  }

  /// Finds all GlobalQuantifyCapability and GlobalQuantifyMetaCapability
  /// annotations on imports of [reflectionLibrary], and record the arguments
  /// of these annotations by modifying [globalPatterns] and [globalMetadata].
  Future<void> _findGlobalQuantifyAnnotations(
    Map<RegExp, List<InterfaceElement>> globalPatterns,
    Map<InterfaceElement, List<InterfaceElement>> globalMetadata,
  ) async {
    // Try both library name patterns
    LibraryElement? reflectionLibrary =
        _librariesByName[reflectionPackageName] ??
        _librariesByName['$reflectionPackageName.$reflectionPackageName'];
    LibraryElement? capabilityLibrary =
        _librariesByName['$reflectionPackageName.capability'];
    
    // If these libraries aren't available, there can't be any GlobalQuantify
    // annotations, so just return.
    if (reflectionLibrary == null || capabilityLibrary == null) {
      return;
    }
    
    ClassElement reflectionClass = reflectionLibrary.getClass('Reflection')!;
    InterfaceType typeType = reflectionLibrary.typeProvider.typeType;
    InterfaceElement typeTypeClass = typeType.element;

    ConstructorElement? globalQuantifyCapabilityConstructor = capabilityLibrary
        .getClass('GlobalQuantifyCapability')
        ?.getNamedConstructor('new');
    ConstructorElement? globalQuantifyMetaCapabilityConstructor =
        capabilityLibrary
            .getClass('GlobalQuantifyMetaCapability')
            ?.getNamedConstructor('new');

    for (LibraryElement library in _libraries) {
      List<LibraryImport> imports = library.fragments
          .map((x) => x.libraryImports)
          .expand((x) => x)
          .toList();
      for (var importElement in imports) {
        if (importElement.importedLibrary?.id != reflectionLibrary.id) {
          continue;
        }
        for (ElementAnnotation metadatum
            in importElement.metadata.annotations) {
          Element? metadatumElement = metadatum.element?.baseElement;
          if (metadatumElement == globalQuantifyCapabilityConstructor) {
            DartObject? value = _getEvaluatedMetadatum(metadatum);
            if (value != null) {
              String? pattern = value
                  .getField('classNamePattern')
                  ?.toStringValue();
              DartType? valueType = value
                  .getField('(super)')
                  ?.getField('reflector')
                  ?.type;
              InterfaceElement? reflector = valueType is InterfaceType
                  ? valueType.element
                  : null;
              if (reflector == null) {
                await _warn(
                  'globalquantify.reflector.null_first',
                  WarningKind.badSuperclass,
                  'The reflector must be a direct subclass of Reflection. '
                  'Got null reflector from GlobalQuantifyCapability (first check).',
                  metadatumElement,
                );
                continue;
              } else {
                InterfaceType? reflectorSupertype = reflector.supertype;
                if (reflectorSupertype is InterfaceType &&
                    reflectorSupertype.element != reflectionClass) {
                  await _warn(
                    'globalquantify.reflector.indirect_subclass',
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of '
                    'Reflection. Found ${reflector.name} with supertype '
                    '${reflectorSupertype.element.name}.',
                    metadatumElement,
                  );
                  continue;
                }
              }
              globalPatterns
                  .putIfAbsent(
                    RegExp(pattern ?? ''),
                    () => <InterfaceElement>[],
                  )
                  .add(reflector);
            }
          } else if (metadatumElement ==
              globalQuantifyMetaCapabilityConstructor) {
            DartObject? constantValue = metadatum.computeConstantValue();
            if (constantValue != null) {
              DartObject? metadataType = constantValue.getField('metadataType');
              DartType? metadataFieldType = metadataType?.toTypeValue();
              InterfaceElement? metadataFieldValue =
                  metadataFieldType is InterfaceType
                  ? metadataFieldType.element
                  : null;
              DartType? metadataTypeType = metadataType?.type;
              if (metadataFieldValue == null) {
                var message = 'The metadata must be a Type. Got null metadata field value.';
                await _warn('globalquantify_meta.metadata.null', WarningKind.badMetadata, message, metadatumElement);
                continue;
              } else if (metadataTypeType is InterfaceType &&
                  metadataTypeType.element != typeTypeClass) {
                String typeName = metadataTypeType.element.nameOrUnknown;
                var message = 'The metadata must be a Type. Found $typeName '
                    'instead of Type.';
                await _warn('globalquantify_meta.metadata.wrong_type', WarningKind.badMetadata, message, metadatumElement);
                continue;
              }
              DartType? reflectorType = constantValue
                  .getField('(super)')
                  ?.getField('reflector')
                  ?.type;
              InterfaceElement? reflector = reflectorType is InterfaceType
                  ? reflectorType.element
                  : null;
              if (reflector == null) {
                await _warn(
                  'globalquantify_meta.reflector.null',
                  WarningKind.badSuperclass,
                  'The reflector must be a direct subclass of Reflection. '
                  'Got null reflector from GlobalQuantifyMetaCapability.',
                  metadatumElement,
                );
                continue;
              } else {
                InterfaceType? reflectorSupertype = reflector.supertype;
                if (reflectorType is InterfaceType &&
                    reflectorSupertype is InterfaceType &&
                    reflectorSupertype.element != reflectionClass) {
                  await _warn(
                    'globalquantify_meta.reflector.indirect_subclass',
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of '
                    'Reflection. Found ${reflector.name} with supertype '
                    '${reflectorSupertype.element.name}.',
                    metadatumElement,
                  );
                  continue;
                }
              }
              globalMetadata
                  .putIfAbsent(metadataFieldValue, () => <InterfaceElement>[])
                  .add(reflector);
            }
          }
        }
      }
    }
  }

  /// Returns true iff [potentialReflectorClass] is a proper reflector class,
  /// which means that it is a direct subclass of [Reflection], which must be
  /// provided as [reflectionClass], and it has a single nameless constructor
  /// that does not take any arguments. In case we extend this list of
  /// general reflector well-formedness requirements, this is the method to
  /// update accordingly. The rest of the builder can then rely on every
  /// reflector class to be well-formed, and just have assertions rather than
  /// emitting error messages about it.
  Future<bool> _isReflectorClass(
    InterfaceElement potentialReflectorClass,
    InterfaceElement reflectionClass,
  ) async {
    if (potentialReflectorClass == reflectionClass) return false;
    DartType potentialReflectorType = _typeForReflection(
      potentialReflectorClass,
    );
    DartType reflectionType = _typeForReflection(reflectionClass);
    if (potentialReflectorType is! ParameterizedType ||
        reflectionType is! InterfaceType) {
      return false;
    }
    if (!_isSubclassOf(potentialReflectorType, reflectionType)) {
      // Not a subclass of [classReflection] at all.
      return false;
    }
    if (!_isDirectSubclassOf(potentialReflectorType, reflectionType) &&
        potentialReflectorType != reflectionType) {
      // Instance of [classReflection], or of indirect subclass
      // of [classReflection]: Not supported, warn about having such a class
      // at all, even though we don't know for sure it is used as a reflector.
      await _warn(
        'reflector.indirect_subclass',
        WarningKind.badReflectorClass,
        'An indirect subclass of `Reflection` will not work as a reflector. '
        'Class ${potentialReflectorClass.name} is not a direct subclass. '
        'It is not recommended to have such a class at all.',
        potentialReflectorClass,
      );
      return false;
    }

    Future<void> constructorFail() async {
      await _severe(
        'reflector.constructor.malformed',
        'A reflector class must have exactly one '
        'constructor which is `const`, has '
        'the empty name, takes zero arguments, and '
        'uses at most one superinitializer. '
        'Please correct `${potentialReflectorClass.name}` to match this. '
        'Constructors found: ${potentialReflectorClass.constructors.length}.',
        potentialReflectorClass,
      );
    }

    if (potentialReflectorClass.constructors.length != 1) {
      // We "own" the direct subclasses of `Reflection` so when they are
      // malformed as reflector classes we raise an error.
      await constructorFail();
      return false;
    }
    ConstructorElement constructor = potentialReflectorClass.constructors[0];
    if (constructor.formalParameters.isNotEmpty || !constructor.isConst) {
      // We still "own" `potentialReflectorClass`.
      await constructorFail();
      return false;
    }

    AstNode? constructorDeclarationNode = await _getDeclarationAst(
      constructor,
      _resolver,
    );
    if (constructorDeclarationNode == null ||
        constructorDeclarationNode is! ConstructorDeclaration) {
      return false;
    }
    NodeList<ConstructorInitializer> initializers =
        constructorDeclarationNode.initializers;
    if (initializers.length > 1) {
      await constructorFail();
      return false;
    }

    // Do we care about type parameters? We don't expect any, but if someone
    // thinks they are incredibly useful in a case that we haven't foreseen
    // then we might as well allow it. It should work. Hence, no checks.

    // A direct subclass of [classReflection], all OK.
    return true;
  }

  /// Returns a [_ReflectionWorld] instantiated with all the reflectors seen by
  /// [_resolver] and all classes annotated by them. The [reflectionLibrary]
  /// must be the element representing 'package:tom_reflection/tom_reflection.dart',
  /// the [entryPoint] must be the element representing the entry point under
  /// transformation, and [dataId] must represent the entry point as well,
  /// and it is used to decide whether it is possible to import other libraries
  /// from the entry point. If the transformation is guaranteed to have no
  /// effect the return value is [null].
  Future<_ReflectionWorld?> _computeWorld(
    LibraryElement reflectionLibrary,
    LibraryElement entryPoint,
    FileId dataId,
  ) async {
    final InterfaceElement? classReflection =
        await _findReflectionInterfaceElement(reflectionLibrary);
    final allReflectors = <InterfaceElement>{};

    // If class `Reflection` is absent the transformation must be a no-op.
    if (classReflection == null) {
      log.info(
        'Ignoring entry point $entryPoint that does not '
        'include the class `Reflection`.',
      );
      return null;
    }

    // The world will be built from the library arguments plus these two.
    final domains = <InterfaceElement, _ReflectorDomain>{};
    final importCollector = _ImportCollector();

    // Maps each pattern to the list of reflectors associated with it via
    // a [GlobalQuantifyCapability].
    var globalPatterns = <RegExp, List<InterfaceElement>>{};

    // Maps each [Type] to the list of reflectors associated with it via
    // a [GlobalQuantifyMetaCapability].
    var globalMetadata = <InterfaceElement, List<InterfaceElement>>{};

    final LibraryElement? capabilityLibrary =
        _librariesByName['$reflectionPackageName.capability'];

    if (capabilityLibrary == null) {
      log.info(
        'Ignoring entry point $entryPoint that does not '
        'include the library $reflectionPackageName.capability',
      );
      return null;
    }

    /// Gets the [ReflectorDomain] associated with [reflector], or creates
    /// it if none exists.
    Future<_ReflectorDomain> getReflectorDomain(
      InterfaceElement reflector,
    ) async {
      _ReflectorDomain? domain = domains[reflector];
      if (domain == null) {
        LibraryElement reflectorLibrary = reflector.library;
        _Capabilities capabilities = await _capabilitiesOf(
          capabilityLibrary,
          reflector,
        );
        assert(await _isImportableLibrary(reflectorLibrary, dataId, _resolver));
        importCollector._addLibrary(reflectorLibrary);
        domain = _ReflectorDomain(_resolver, dataId, reflector, capabilities);
        domains[reflector] = domain;
      }
      return domain;
    }

    /// Adds [library] to the supported libraries of [reflector].
    Future<void> addLibrary(
      LibraryElement library,
      InterfaceElement reflector,
    ) async {
      _ReflectorDomain domain = await getReflectorDomain(reflector);
      if (domain._capabilities._supportsLibraries) {
        assert(await _isImportableLibrary(library, dataId, _resolver));
        importCollector._addLibrary(library);
        domain._libraries.add(library);
      }
    }

    /// Adds a [_ClassDomain] representing [type] to the supported classes of
    /// [reflector]; also adds the enclosing library of [type] to the
    /// supported libraries.
    Future<void> addClassDomain(
      InterfaceElement type,
      InterfaceElement reflector,
    ) async {
      if (!await _isImportable(type, dataId, _resolver)) {
        await _fine(
          'class_domain.unrepresentable',
          'Ignoring unrepresentable class ${type.name}. '
          'Library: ${type.library.name}',
          type,
        );
      } else {
        _ReflectorDomain domain = await getReflectorDomain(reflector);
        if (!domain._classes.contains(type)) {
          if (type is MixinApplication && type.isMixinApplication) {
            // Iterate over all mixins in most-general-first order (so with
            // `class C extends B with M1, M2..` we visit `M1` then `M2`.
            InterfaceElement superclass = type.supertype!.element;
            for (InterfaceType mixin in type.mixins) {
              InterfaceElement mixinElement = mixin.element;
              MixinApplication? subClass = mixin == type.mixins.last
                  ? type
                  : null;
              String? name = subClass == null ? null : type.name;
              var mixinApplication = MixinApplication(
                name,
                superclass,
                mixinElement,
                type.library,
                subClass,
              );
              domain._classes.add(mixinApplication);
              superclass = mixinApplication;
            }
          } else {
            domain._classes.add(type);
          }
          await addLibrary(type.library, reflector);
          // We need to ensure that the [importCollector] has indeed added
          // `type.library` (if we have no library capability `addLibrary` will
          // not do that), because it may be needed in import directives in the
          // generated library, even in cases where the transformed program
          // will not get library support.
          // TODO(eernst) clarify: Maybe the following statement could be moved
          // out of the `if` in `addLibrary` such that we don't have to have
          // an extra copy of it here.
          importCollector._addLibrary(type.library);
        }
      }
    }

    /// Runs through [metadata] and finds all reflectors as well as
    /// objects that are associated with reflectors via
    /// [GlobalQuantifyMetaCapability] or [GlobalQuantifyCapability].
    /// [qualifiedName] is the name of the library or class annotated by
    /// [metadata].
    Future<Iterable<InterfaceElement>> getReflectors(
      String? qualifiedName,
      List<ElementAnnotation> metadata,
    ) async {
      var result = <InterfaceElement>[];

      for (ElementAnnotation metadatum in metadata) {
        DartObject? value = _getEvaluatedMetadatum(metadatum);

        // Test if the type of this metadata is associated with any reflectors
        // via GlobalQuantifyMetaCapability.
        if (value != null) {
          DartType? valueType = value.type;
          if (valueType is InterfaceType) {
            List<InterfaceElement>? reflectors =
                globalMetadata[valueType.element];
            if (reflectors != null) {
              for (InterfaceElement reflector in reflectors) {
                result.add(reflector);
              }
            }
          }
        }

        // Test if the annotation is a reflector.
        InterfaceElement? reflector = await _getReflectionAnnotation(
          metadatum,
          classReflection,
        );
        if (reflector != null) result.add(reflector);
      }

      // Add All reflectors associated with a
      // pattern, via GlobalQuantifyCapability, that matches the qualified
      // name of the class or library.
      globalPatterns.forEach((
        RegExp pattern,
        List<InterfaceElement> reflectors,
      ) {
        if (qualifiedName != null && pattern.hasMatch(qualifiedName)) {
          for (InterfaceElement reflector in reflectors) {
            result.add(reflector);
          }
        }
      });
      return result;
    }

    // Populate [globalPatterns] and [globalMetadata].
    await _findGlobalQuantifyAnnotations(globalPatterns, globalMetadata);

    // Visits all libraries and all classes in the given entry point,
    // gets their reflectors, and adds them to the domain of that
    // reflector.
    for (LibraryElement library in _libraries) {
      for (InterfaceElement reflector in await getReflectors(
        library.name,
        library.metadata.annotations,
      )) {
        assert(await _isImportableLibrary(library, dataId, _resolver));
        await addLibrary(library, reflector);
      }

      for (InterfaceElement type in library.classes) {
        for (InterfaceElement reflector in await getReflectors(
          _qualifiedName(type),
          type.metadata.annotations,
        )) {
          await addClassDomain(type, reflector);
        }
        if (!allReflectors.contains(type) &&
            await _isReflectorClass(type, classReflection)) {
          allReflectors.add(type);
        }
      }
      for (EnumElement type in library.enums) {
        for (InterfaceElement reflector in await getReflectors(
          _qualifiedName(type),
          type.metadata.annotations,
        )) {
          await addClassDomain(type, reflector);
        }
        // An enum is never a reflector class, hence no `_isReflectorClass`.
      }
      for (TopLevelFunctionElement function in library.topLevelFunctions) {
        for (InterfaceElement reflector in await getReflectors(
          _qualifiedFunctionName(function),
          function.metadata.annotations,
        )) {
          // We just add the library here, the function itself will be
          // supported using `invoke` and `declarations` of that library
          // mirror.
          await addLibrary(library, reflector);
        }
      }
    }

    var usedReflectors = <InterfaceElement>{};
    for (_ReflectorDomain domain in domains.values) {
      usedReflectors.add(domain._reflector);
    }
    for (InterfaceElement reflector in allReflectors.difference(
      usedReflectors,
    )) {
      await _warn(
        'reflector.unused',
        WarningKind.unusedReflector,
        'This reflector does not match anything. '
        'Reflector class: ${reflector.name}. '
        'Consider removing it or adding annotations that use it.',
        reflector,
      );
      // Ensure that there is an empty domain for `reflector` in `domains`.
      await getReflectorDomain(reflector);
    }

    // Create the world and tie the knot: A [_ReflectionWorld] refers to all its
    // [_ReflectorDomain]s, and each of them refer back. Such a cycle cannot be
    // defined during construction, so `_world` is non-final and left unset by
    // the constructor, and we need to close the cycle here.
    var world = _ReflectionWorld(
      _resolver,
      _libraries,
      dataId,
      domains.values.toList(),
      reflectionLibrary,
      entryPoint,
      importCollector,
    );
    for (_ReflectorDomain domain in domains.values) {
      domain._world = world;
    }
    return world;
  }

  /// Returns the [ReflectCapability] denoted by the given initializer
  /// [expression] reporting diagnostic messages for [messageTarget].
  Future<ec.ReflectCapability?> _capabilityOfExpression(
    LibraryElement capabilityLibrary,
    Expression expression,
    LibraryElement containingLibrary,
    Element messageTarget,
  ) async {
    DartObject? constant = await _evaluateConstant(
      containingLibrary,
      expression,
    );

    if (constant is! DartObject) {
      await _severe(
        'capability.expression.invalid_constant',
        'Invalid constant `$expression` in capability list. '
        'Type: ${expression.runtimeType}',
        messageTarget,
      );
      // We do not terminate immediately at `_severe` so we need to
      // return something that will not generate too much noise for the
      // receiver.
      return ec.invokingCapability; // Error default.
    }

    DartType? dartType = constant.type;

    if (dartType == null) {
      await _severe(
        'capability.expression.no_type',
        'Constant `$expression` in capability list has no type. '
        'Constant value: $constant',
        messageTarget,
      );
      return ec.invokingCapability; // Error default.
    }

    // We insist that the type must be a class, and we insist that it must
    // be in the given `capabilityLibrary` (because we could never know
    // how to interpret the meaning of a user-written capability class, so
    // users cannot write their own capability classes).
    InterfaceElement dartTypeElement = (dartType as InterfaceType).element;
    if (dartTypeElement is! ClassElement) {
      String typeString = dartType.getDisplayString();
      await _severe(
        'capability.super_argument.not_a_class',
        '${errors.applyTemplate(errors.superArgumentNonClass, {
          'type': typeString,
        })} Element: ${dartTypeElement.name}',
        dartTypeElement,
      );
      return null; // Error default.
    }
    if (dartTypeElement.library != capabilityLibrary) {
      await _severe(
        'capability.super_argument.wrong_library',
        '${errors.applyTemplate(errors.superArgumentWrongLibrary, {
          'library': '$capabilityLibrary',
          'element': '$dartTypeElement',
        })} Expected library: ${capabilityLibrary.name}',
        dartTypeElement,
      );
      return null; // Error default.
    }

    /// Extracts the namePattern String from an instance of a subclass of
    /// NamePatternCapability.
    Future<String?> extractNamePattern(DartObject constant) async {
      DartObject? constantSuper = constant.getField('(super)');
      DartObject? constantSuperNamePattern = constantSuper?.getField(
        'namePattern',
      );
      String? constantSuperNamePatternString = constantSuperNamePattern
          ?.toStringValue();
      if (constantSuper == null ||
          constantSuperNamePattern == null ||
          constantSuperNamePatternString == null) {
        await _warn(
          'capability.name_pattern.extraction_failed',
          WarningKind.badNamePattern,
          'Could not extract namePattern from capability. '
          'Super: ${constantSuper != null}, Pattern: ${constantSuperNamePattern != null}, '
          'String: ${constantSuperNamePatternString != null}',
          messageTarget,
        );
        return null;
      }
      return constantSuperNamePatternString;
    }

    /// Extracts the metadata property from an instance of a subclass of
    /// MetadataCapability represented by [constant], reporting any diagnostic
    /// messages as referring to [messageTarget].
    Future<InterfaceElement?> extractMetadata(DartObject constant) async {
      DartObject? constantSuper = constant.getField('(super)');
      DartObject? constantSuperMetadataType = constantSuper?.getField(
        'metadataType',
      );
      if (constantSuper == null || constantSuperMetadataType == null) {
        await _warn(
          'capability.metadata_type.extraction_failed',
          WarningKind.badMetadata,
          'Could not extract metadata type from capability. '
          'Super: ${constantSuper != null}, MetadataType: ${constantSuperMetadataType != null}',
          messageTarget,
        );
        return null;
      }
      DartType? metadataFieldType = constantSuperMetadataType.toTypeValue();
      Object? metadataFieldValue = metadataFieldType is InterfaceType
          ? metadataFieldType.element
          : null;
      if (metadataFieldValue is InterfaceElement) return metadataFieldValue;
      await _warn(
        'capability.metadata_type.not_class_type',
        WarningKind.badMetadata,
        'Metadata specification in capability must be a class `Type`. '
        'Got: ${metadataFieldType?.runtimeType}',
        messageTarget,
      );
      return null;
    }

    switch (dartTypeElement.name!) {
      case 'NameCapability':
        // ignore: deprecated_member_use_from_same_package
        return ec.nameCapability;
      case 'ClassifyCapability':
        // ignore: deprecated_member_use_from_same_package
        return ec.classifyCapability;
      case 'MetadataCapability':
        return ec.metadataCapability;
      case 'TypeRelationsCapability':
        return ec.typeRelationsCapability;
      case '_ReflectedTypeCapability':
        return ec.reflectedTypeCapability;
      case 'LibraryCapability':
        return ec.libraryCapability;
      case 'DeclarationsCapability':
        return ec.declarationsCapability;
      case 'UriCapability':
        return ec.uriCapability;
      case 'LibraryDependenciesCapability':
        return ec.libraryDependenciesCapability;
      case 'InstanceInvokeCapability':
        String? namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.InstanceInvokeCapability(namePattern);
      case 'InstanceInvokeMetaCapability':
        InterfaceElement? metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.InstanceInvokeMetaCapability(metadata);
      case 'StaticInvokeCapability':
        String? namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.StaticInvokeCapability(namePattern);
      case 'StaticInvokeMetaCapability':
        InterfaceElement? metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.StaticInvokeMetaCapability(metadata);
      case 'TopLevelInvokeCapability':
        String? namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.TopLevelInvokeCapability(namePattern);
      case 'TopLevelInvokeMetaCapability':
        InterfaceElement? metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.TopLevelInvokeMetaCapability(metadata);
      case 'NewInstanceCapability':
        String? namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.NewInstanceCapability(namePattern);
      case 'NewInstanceMetaCapability':
        InterfaceElement? metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.NewInstanceMetaCapability(metadata);
      case 'TypeCapability':
        return ec.TypeCapability();
      case 'InvokingCapability':
        String? namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.InvokingCapability(namePattern);
      case 'InvokingMetaCapability':
        InterfaceElement? metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.InvokingMetaCapability(metadata);
      case 'TypingCapability':
        return ec.TypingCapability();
      case '_DelegateCapability':
        return ec.delegateCapability;
      case '_SubtypeQuantifyCapability':
        return ec.subtypeQuantifyCapability;
      case 'SuperclassQuantifyCapability':
        DartObject? constantUpperBound = constant.getField('upperBound');
        DartObject? constantExcludeUpperBound = constant.getField(
          'excludeUpperBound',
        );
        if (constantUpperBound == null || constantExcludeUpperBound == null) {
          return null;
        }
        DartType constantUpperBoundType = constantUpperBound.toTypeValue()!;
        if (constantUpperBoundType is! InterfaceType) return null;
        return ec.SuperclassQuantifyCapability(
          constantUpperBoundType.element,
          excludeUpperBound: constantExcludeUpperBound.toBoolValue()!,
        );
      case 'TypeAnnotationQuantifyCapability':
        DartObject? constantTransitive = constant.getField('transitive');
        if (constantTransitive == null) return null;
        return ec.TypeAnnotationQuantifyCapability(
          transitive: constantTransitive.toBoolValue()!,
        );
      case '_CorrespondingSetterQuantifyCapability':
        return ec.correspondingSetterQuantifyCapability;
      case '_AdmitSubtypeCapability':
        // TODO(eernst) implement: support for the admit subtype feature.
        await _severe(
          'capability.admit_subtype.not_supported',
          '_AdmitSubtypeCapability not yet supported! '
          'Element: ${dartTypeElement.name}',
          messageTarget,
        );
        return ec.admitSubtypeCapability;
      default:
        // We have checked that [element] is declared in 'capability.dart',
        // and it is a compile time error to use a non-const value in the
        // superinitializer of a const constructor, and we have tested
        // for all classes in that library which can provide a const value,
        // so we should not reach this point.
        await _severe(
          'capability.unexpected',
          'Unexpected capability: ${dartTypeElement.name}. '
          'This capability is not recognized by the generator.',
        );
        return null; // Error default.
    }
  }

  /// Returns the list of Capabilities given as a superinitializer by the
  /// reflector, or all capabilities if [useAllCapabilities] is true.
  Future<_Capabilities> _capabilitiesOf(
    LibraryElement capabilityLibrary,
    InterfaceElement reflector,
  ) async {
    // If useAllCapabilities is true, return all available capabilities
    if (useAllCapabilities) {
      return _Capabilities(_allCapabilities());
    }

    List<ConstructorElement> constructors = reflector.constructors;

    // Well-formedness for each reflector class is checked by
    // `_isReflectorClass`, so we do not report errors here. But errors will
    // not terminate the program, so we need to decide on how to handle
    // erroneous reflectors here. We choose to pretend that they have no
    // capabilities. An error message has already been issued, so that should
    // not be too surprising for the programmer.
    if (constructors.length != 1) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }
    ConstructorElement constructorElement = constructors[0];
    if (!constructorElement.isConst ||
        !constructorElement.isDefaultConstructor) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    var constructorDeclarationNode =
        await _getDeclarationAst(constructorElement, _resolver)
            as ConstructorDeclaration;
    NodeList<ConstructorInitializer> initializers =
        constructorDeclarationNode.initializers;

    if (initializers.isEmpty) {
      // Degenerate case: Without initializers, we will obtain a reflector
      // without any capabilities, which is not useful in practice. We do
      // have this degenerate case in tests "just because we can", and
      // there is no technical reason to prohibit it, so we will handle
      // it here.
      return _Capabilities(<ec.ReflectCapability>[]);
    }
    if (initializers.length != 1) {
      await _severe(
        'reflector.initializers.unexpected',
        'Encountered a reflector whose constructor has '
        'an unexpected initializer list (${initializers.length} elements). '
        'It must be of the form `super(...)` or `super.fromList(...)`. '
        'Reflector: ${reflector.name}',
      );
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    // Main case: the initializer is exactly one element. We must
    // handle two cases: `super(..)` and `super.fromList(<_>[..])`.
    ConstructorInitializer superInvocation = initializers[0];

    if (superInvocation is! SuperConstructorInvocation) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    Future<ec.ReflectCapability?> capabilityOfExpression(
      Expression expression,
    ) async {
      return await _capabilityOfExpression(
        capabilityLibrary,
        expression,
        reflector.library,
        constructorElement,
      );
    }

    Future<ec.ReflectCapability?> capabilityOfCollectionElement(
      CollectionElement collectionElement,
    ) async {
      if (collectionElement is Expression) {
        return await capabilityOfExpression(collectionElement);
      } else {
        await _severe(
          'capability.collection_element.not_expression',
          'Not supported! '
          'Encountered a collection element which is not an expression: '
          '$collectionElement (type: ${collectionElement.runtimeType})',
        );
        return null;
      }
    }

    SimpleIdentifier? superInvocationConstructorName =
        superInvocation.constructorName;
    if (superInvocationConstructorName == null) {
      // Subcase: `super(..)` where 0..k arguments are accepted for some
      // k that we need not worry about here.
      var capabilities = <ec.ReflectCapability>[];
      for (Expression argument in superInvocation.argumentList.arguments) {
        ec.ReflectCapability? currentCapability =
            await capabilityOfCollectionElement(argument);
        if (currentCapability != null) capabilities.add(currentCapability);
      }
      return _Capabilities(capabilities);
    }
    assert(superInvocationConstructorName.name == 'fromList');

    // Subcase: `super.fromList(const <..>[..])`.
    NodeList<Expression> arguments = superInvocation.argumentList.arguments;
    assert(arguments.length == 1);
    Expression listLiteral = arguments[0];
    var capabilities = <ec.ReflectCapability>[];
    if (listLiteral is! ListLiteral) {
      await _severe(
        'reflector.from_list.not_list_literal',
        'Encountered a reflector using super.fromList(...) '
        'with an argument that is not a list literal, '
        'which is not supported. '
        'Argument type: ${listLiteral.runtimeType}, '
        'Reflector: ${reflector.name}',
      );
    } else {
      for (CollectionElement collectionElement in listLiteral.elements) {
        ec.ReflectCapability? currentCapability =
            await capabilityOfCollectionElement(collectionElement);
        if (currentCapability != null) capabilities.add(currentCapability);
      }
    }
    return _Capabilities(capabilities);
  }

  semver.Version? _getFormatterLanguageVersion() {
    final environmentMap = Platform.environment;
    final version = environmentMap["REFLECTION_FORMATTER_LANGUAGE_VERSION"];
    if (version == null) return null;
    final match = RegExp(r"[0-9]+\.[0-9]+").firstMatch(version);
    if (match == null) {
      log.warning(
        "Unexpected: REFLECTION_FORMATTER_LANGUAGE_VERSION=\"$version\"\n"
        "This variable should match /[0-9]+\\.[0-9]+/.",
      );
      return null;
    }
    final periodIndex = version.indexOf('.');
    final majorVersion = int.parse(version.substring(0, periodIndex));
    final minorVersion = int.parse(
      version.substring(periodIndex + 1, version.length),
    );
    return semver.Version(majorVersion, minorVersion, 0);
  }

  /// Generates code for a new entry-point file that will initialize the
  /// reflection data according to [world], and invoke the main of
  /// [entrypointLibrary] located at [originalEntryPointFilename]. The code is
  /// generated to be located at [generatedLibraryId].
  Future<String> _generateNewEntryPoint(
    _ReflectionWorld world,
    FileId generatedLibraryId,
    String originalEntryPointFilename,
    List<WarningKind> suppressedWarnings,
  ) async {
    // Notice it is important to generate the code before printing the
    // imports because generating the code can add further imports.
    String code = await world.generateCode(suppressedWarnings);

    var imports = <String>[];
    for (LibraryElement library in world.importCollector._libraries) {
      Uri uri = library == world.entryPointLibrary
          ? Uri.parse(originalEntryPointFilename)
          : await _getImportUri(library, _resolver, generatedLibraryId);
      String prefix = world.importCollector._getPrefix(library);
      if (prefix.isNotEmpty) {
        imports.add(
          "import '$uri' as ${prefix.substring(0, prefix.length - 1)};",
        );
      }
    }
    imports.sort();

    // Generate reflection imports based on package name
    // Original reflection uses different import pattern than tom_reflection
    String reflectionImports;
    if (reflectionPackageName == 'reflection') {
      // Original reflection package uses these imports:
      reflectionImports = '''
import 'package:reflection/mirrors.dart' as m;
import 'package:reflection/src/reflection_builder_based.dart' as r;
import 'package:reflection/reflection.dart' as r show Reflection;''';
    } else {
      // tom_reflection and other packages use the consolidated generated.dart
      // Use src/reflection/mirrors.dart for 'm' prefix to match the exports in generated.dart:
      reflectionImports = '''
import 'package:$reflectionPackageName/src/reflection/mirrors.dart' as m;
import 'package:$reflectionPackageName/generated.dart' as r;
import 'package:$reflectionPackageName/$reflectionPackageName.dart' as r show Reflection;''';
    }

    var result =
        '''
// This file has been generated by the reflection package.
// https://github.com/dart-lang/reflection.
import 'dart:core';
${imports.join('\n')}

// ignore_for_file: camel_case_types
// ignore_for_file: implementation_imports
// ignore_for_file: prefer_adjacent_string_concatenation
// ignore_for_file: prefer_collection_literals
// ignore_for_file: unnecessary_const
// ignore_for_file: unused_import
// ignore_for_file: sdk_version_since

$reflectionImports

$code

final _memberSymbolMap = ${world.generateSymbolMap()};

void initializeReflection() {
  r.data = _data;
  r.memberSymbolMap = _memberSymbolMap;
}
''';
    if (_formatted) {
      var languageVersion =
          _getFormatterLanguageVersion() ?? DartFormatter.latestLanguageVersion;
      var formatter = DartFormatter(languageVersion: languageVersion);
      result = formatter.format(result);
    }
    return result;
  }

  /// Perform the build which produces a set of statically generated
  /// mirror classes, as requested using reflection capabilities.
  Future<String> buildMirrorLibrary(
    LibraryResolver resolver,
    FileId inputId,
    FileId generatedLibraryId,
    LibraryElement inputLibrary,
    List<LibraryElementImpl> visibleLibraries,
    bool formatted,
    List<WarningKind> suppressedWarnings,
  ) async {
    _formatted = formatted;
    _suppressedWarnings = suppressedWarnings;

    // The [_resolver] provides all the static information.
    _resolver = resolver;
    _libraries = visibleLibraries;

    for (LibraryElement library in _libraries) {
      _librariesByName[library.nameOrUnknown] = library;
    }
    
    // Try both library name patterns:
    // - 'packageName' (e.g., 'tom_reflection')
    // - 'packageName.packageName' (e.g., 'reflection.reflection' for original package)
    LibraryElement? reflectionLibrary =
        _librariesByName[reflectionPackageName] ??
        _librariesByName['$reflectionPackageName.$reflectionPackageName'];

    if (reflectionLibrary == null) {
      // Stop and let the original source pass through without changes.
      log.info(
        'Ignoring entry point $inputId that does not '
        "include the library 'package:$reflectionPackageName/$reflectionPackageName.dart'",
      );
      if (const bool.fromEnvironment('reflection.pause.at.exit')) {
        _processedEntryPointCount++;
      }
      return '// No output from reflection, '
          "'package:$reflectionPackageName/$reflectionPackageName.dart' not used.";
    } else {
      reflectionLibrary = await _resolvedLibraryOf(reflectionLibrary);

      if (const bool.fromEnvironment('reflection.print.entry.point')) {
        print("Starting build for '$inputId'.");
      }

      _ReflectionWorld? world = await _computeWorld(
        reflectionLibrary,
        inputLibrary,
        inputId,
      );
      if (world == null) {
        // Errors have already been reported during `_computeWorld`.
        if (const bool.fromEnvironment('reflection.pause.at.exit')) {
          _processedEntryPointCount++;
        }
        return '// No output from reflection, stopped with error.';
      } else {
        if (inputLibrary.entryPoint == null) {
          log.info('Entry point: $inputId has no `main`. Skipping.');
          if (const bool.fromEnvironment('reflection.pause.at.exit')) {
            _processedEntryPointCount++;
          }
          return '// No output from reflection, there is no `main`.';
        } else {
          String outputContents = await _generateNewEntryPoint(
            world,
            generatedLibraryId,
            path.basename(inputId.path),
            suppressedWarnings,
          );
          if (const bool.fromEnvironment('reflection.pause.at.exit')) {
            _processedEntryPointCount++;
          }
          if (const bool.fromEnvironment('reflection.pause.at.exit')) {
            if (_processedEntryPointCount ==
                const int.fromEnvironment('reflection.pause.at.exit.count')) {
              print('Build complete, pausing at exit.');
              developer.debugger();
            }
          }
          return outputContents;
        }
      }
    }
  }

  /// Returns a constant resolved version of the given [libraryElement].
  Future<LibraryElement> _resolvedLibraryOf(
    LibraryElement libraryElement,
  ) async {
    for (LibraryElement libraryElement2 in _libraries) {
      if (libraryElement.identifier == libraryElement2.identifier) {
        return libraryElement2;
      }
    }
    // This can occur when the library is not used.
    await _fine(
      'library.resolve.not_found',
      'Could not resolve library ${libraryElement.name}. '
      'Identifier: ${libraryElement.identifier}',
    );
    return libraryElement;
  }
}
