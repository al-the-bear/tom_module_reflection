// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Internal exports for generated reflection code.
///
/// This library exports the internal APIs that generated `.reflection.dart`
/// files need to import. It should not be used directly by user code.
library tom_reflection.generated;

export 'src/reflection/mirrors.dart';
export 'src/reflection/reflection_builder_based.dart'
    show
        data,
        memberSymbolMap,
        ReflectorData,
        ReflectionImpl,
        // Mirror implementation classes used by generated code:
        TypeVariableMirrorImpl,
        NonGenericClassMirrorImpl,
        GenericClassMirrorImpl,
        MethodMirrorImpl,
        VariableMirrorImpl,
        LibraryMirrorImpl,
        ParameterMirrorImpl,
        // Implicit accessor mirrors for field getters/setters:
        ImplicitGetterMirrorImpl,
        ImplicitSetterMirrorImpl,
        // Type utilities for generic types:
        FakeType;
