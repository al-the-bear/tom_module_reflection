// Scenario 2 — drive live objects entirely through the generated reflection.
//
// No `Product(...)` or `product.discountedPrice(...)` appears below. Every
// construction, method call, and property access goes through the descriptors
// in `catalog.r.dart`. This is the "code generation" payoff: a generic caller
// can operate on a type it was never compiled against.
import 'package:reflector_reflection_introduction_sample/catalog.r.dart';

void main() {
  final product = reflectionApi.findClass('Product')!;

  // Construct via the UNNAMED constructor — it is keyed 'new', not ''.
  final widget = product.newInstance(
    constructorName: 'new',
    named: {#sku: 'A-100', #name: 'Widget', #price: 20.0, #stock: 7},
  )!;
  print('built -> $widget');
  // built -> Product(A-100)

  // Invoke an instance method by name, with positional args.
  final discounted = product.invoke(widget, 'discountedPrice', positional: [0.25]);
  print('discountedPrice(0.25) -> $discounted');
  // discountedPrice(0.25) -> 15.0

  // Read properties. `label` is a getter; it reflects as a read-only field and
  // is still readable through getProperty.
  print('price -> ${product.getProperty(widget, 'price')}');
  // price -> 20.0
  print('label -> ${product.getProperty(widget, 'label')}');
  // label -> Widget (A-100)

  // Mutate a writable field, then re-read.
  product.setProperty(widget, 'price', 8.0);
  print('price after set -> ${product.getProperty(widget, 'price')}');
  // price after set -> 8.0

  // Writing a read-only member (a final field) throws StateError — the
  // descriptor carries no setter closure for it.
  try {
    product.setProperty(widget, 'sku', 'NOPE');
  } on StateError catch (e) {
    print('setProperty(sku) rejected -> ${e.message}');
  }
  // setProperty(sku) rejected -> No instance property named sku for ...Product

  // The named constructor is keyed by its name.
  final sample = product.newInstance(constructorName: 'sample')!;
  print('Product.sample() -> $sample '
      'name=${product.getProperty(sample, 'name')}');
  // Product.sample() -> Product(SKU-0001) name=Sample Widget

  // Type queries work against the qualified name recorded by the generator.
  print('widget isInstanceOf Product -> '
      '${product.isInstance(widget)}');
  // widget isInstanceOf Product -> true

  // Globals are invoked through their own descriptor.
  final version = reflectionApi.findGlobal('catalogVersion')!;
  print('catalogVersion() -> ${version.invokeFunction!([], {})}');
  // catalogVersion() -> 7
}
