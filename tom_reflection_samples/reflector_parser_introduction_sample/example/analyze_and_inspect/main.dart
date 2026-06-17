// Scenario 1 — analyze a source set, then query the model.
//
// This is the entry point to engine 2: hand the analyzer a barrel file, get
// back an `AnalysisResult`, and use its query API to inspect the code's shape.
// No code from `sample_source/` is run — it is read as text and turned into
// data.
import 'package:reflector_parser_introduction_sample/catalog_analysis.dart';

Future<void> main() async {
  final result = await analyzeCatalog();

  // Top-level inventory. The AnalysisResult flattens every library's members
  // into `allClasses` / `allEnums` / `allFunctions` for convenient querying.
  print('package   -> ${result.rootPackage.name}'); // -> catalog_domain
  print('errors    -> ${result.errors.length}'); // -> 0
  print('classes   -> ${result.allClasses.map((c) => c.name).toList()}');
  // classes   -> [Entity, Product, Repository]
  print('enums     -> ${result.allEnums.map((e) => e.name).toList()}');
  // enums     -> [Availability]
  print('functions -> ${result.allFunctions.map((f) => f.name).toList()}');
  // functions -> [catalogVersion]

  // Drill into one class. `getClassOrThrow` is the by-name lookup; the members
  // are plain lists of typed model objects.
  final product = result.getClassOrThrow('Product');
  print('Product.isAbstract -> ${product.isAbstract}'); // -> false
  print('Product fields     -> '
      '${product.fields.map((f) => '${f.name}: ${renderType(f.type)}').toList()}');
  // Product fields     -> [label: String, name: String, price: double, sku: String, tags: List<String>]
  print('Product methods    -> '
      '${product.methods.map((m) => m.name).toList()}');
  // Product methods    -> [discounted]

  // Note: `label` is a *getter*, but this analyzer version folds accessors into
  // `fields` (a field with a getter and no setter). The README explains why.

  // Annotations are resolved by name — which is exactly what a code generator
  // keys on: "find every class marked @Entity". (This engine records annotation
  // presence, not argument values; see the README.)
  print('Product annotations -> '
      '${product.annotations.map((a) => '@${a.name}').toList()}');
  // Product annotations -> [@Entity]
  final entities = result.findClassesWithAnnotation('Entity');
  print('@Entity classes     -> ${entities.map((c) => c.name).toList()}');
  // @Entity classes     -> [Product]

  // The generic contract keeps its type parameter.
  final repo = result.getClassOrThrow('Repository');
  print('Repository type params -> '
      '${repo.typeParameters.map((t) => t.name).toList()}'); // -> [T]
}
