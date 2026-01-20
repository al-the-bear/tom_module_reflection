// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library;

/// It is a transformation time error to use an instance of a
/// class that is not a direct subclass of [Reflection] as
/// metadata.
///
/// Rationale: A client may actually use instances of [Reflection]
/// itself, or of subsubclasses etc. of [Reflection] as metadata, for
/// entirely different purposes than using this transformer.  But we
/// consider these cases to be without merit: It would be very
/// error-prone if we were to silently ignore such "alien" usages of
/// metadata conforming to the type [Reflection], and it is so easy
/// to create a new class which is unrelated to [Reflection] but
/// structurally identical that they could just stop using
/// [Reflection] and use that.  So we simply outlaw all these usages
/// of reflectors, no matter whether they were used for a different
/// purpose or they were the result of a lack of knowledge that
/// such metadata will not have any effect.
const String metadataNotDirectSubclass =
    '[metadata.not_direct_subclass] '
    'Metadata has type Reflection, but is not an instance of '
    'a direct subclass of Reflection';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflection that is of
/// a non-class type.
const String superArgumentNonClass =
    '[capability.super_argument.non_class] '
    'The super constructor invocation receives an argument whose'
    ' type `{type}` is not a class.';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflection that is defined
/// outside the library 'package:reflection/capability.dart'.
const String superArgumentWrongLibrary =
    '[capability.super_argument.wrong_library] '
    'The super constructor invocation receives an argument whose'
    ' type `{element}` is defined outside the library `{library}`.';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflection that is non-const.
const String superArgumentNonConst =
    '[capability.super_argument.non_const] '
    'The super constructor invocation receives an argument'
    ' which is not a constant.';

/// It is a transformation time error to use an enum as a reflector class.
const String isEnum = 
    '[reflector.class.is_enum] '
    'Encountered a reflector class which is an enum.';

/// Finds any template holes of the form {name} in [template] and replaces them
/// with the corresponding value in [replacements].
String applyTemplate(String template, Map<String, String> replacements) {
  return template.replaceAllMapped(RegExp(r'{(.*?)}'), (Match match) {
    String? index = match.group(1);
    String? replacement = replacements[index];
    if (replacement == null) {
      throw ArgumentError('Missing template replacement for $index');
    }
    return replacement;
  });
}
