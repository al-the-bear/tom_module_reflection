// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Tom Reflection Generator — tool definition using tom_build_base v2.
///
/// Exposes the runtime-mirror reflection generator (engine 1) as a
/// single-command, buildkit-nestable tool.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../version.versioner.dart';

// =============================================================================
// Tool-specific Options
// =============================================================================

/// Tool-specific options for tom_reflection_generator.
///
/// Standard options (`--verbose`/`-v`, `--help`/`-h`, `--version`, `--nested`,
/// `--dump-definitions`, project-traversal flags) are contributed automatically
/// by the framework via [NavigationFeatures] and must NOT be redeclared here.
///
/// Note: `--package` deliberately has no `-p` abbreviation — `-p` is reserved
/// by the standard `--project` traversal option.
const reflectionGeneratorOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'all',
    description: 'Process directory targets recursively',
  ),
  OptionDefinition.option(
    name: 'package',
    description:
        'Reflection package whose annotations trigger generation '
        '(default: tom_reflection)',
    valueName: 'name',
    defaultValue: 'tom_reflection',
  ),
  OptionDefinition.option(
    name: 'extension',
    abbr: 'e',
    description: 'Output file extension (default: .reflection.dart)',
    valueName: 'ext',
    defaultValue: '.reflection.dart',
  ),
  OptionDefinition.option(
    name: 'config',
    abbr: 'c',
    description:
        'build.yaml path used for the build-mode fallback (default: build.yaml)',
    valueName: 'path',
    defaultValue: 'build.yaml',
  ),
  OptionDefinition.flag(
    name: 'useAllCapabilities',
    description:
        'Use all capabilities instead of those declared on the reflector class',
  ),
  // Deliberately a distinct flag rather than the framework's --dry-run (which
  // this tool leaves disabled). Dry-run means "show what would happen and
  // succeed"; --check means "fail if it would change anything". The exit
  // status is the entire point, so it gets its own name.
  OptionDefinition.flag(
    name: 'check',
    description:
        'Verify committed *.reflection.dart files instead of writing them; '
        'fail if any differs from what would be generated',
  ),
  OptionDefinition.flag(
    name: 'no-cache',
    description: 'Disable analyzer summary caching for dependencies',
  ),
  OptionDefinition.flag(
    name: 'rebuild-cache',
    description: 'Force regeneration of all cached summaries',
  ),
  OptionDefinition.flag(
    name: 'show-cache-status',
    description: 'Show which packages have cached summaries, then stop',
  ),
  OptionDefinition.multi(
    name: 'cache-only',
    description: 'Restrict summary caching to the given package(s) (repeatable)',
    valueName: 'package',
  ),
];

// =============================================================================
// Tool Definition
// =============================================================================

/// Tom Reflection Generator tool definition (single-command).
final reflectionGeneratorTool = ToolDefinition(
  name: 'reflectiongenerator',
  description:
      'Runtime-mirror reflection code generator — emits *.reflection.dart',
  version: ReflectionGenVersionInfo.version,
  versionString: 'Tom Reflection Generator ${ReflectionGenVersionInfo.versionLong}',
  mode: ToolMode.singleCommand,
  worksWithNatures: {DartProjectFolder},
  features: const NavigationFeatures(
    projectTraversal: true,
    gitTraversal: false,
    recursiveScan: true,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: true,
  ),
  globalOptions: reflectionGeneratorOptions,
  helpFooter: '''
Configuration:
  In nested/traversal mode the generator reads a tom_reflection_generator:
  section from each project's buildkit.yaml:

  tom_reflection_generator:
    generate_for:
      - lib/**/*.dart
    package: tom_reflection
    extension: .reflection.dart
    use_all_capabilities: false

  Projects without that section fall back to build.yaml generate_for patterns,
  and are skipped if neither is present.

Related:
  For the build-time structural model, use tom_reflector:
    reflector --help
''',
);
