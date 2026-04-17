import 'dart:io';
import 'package:analyzer/src/summary2/package_bundle_format.dart';

void main() {
  final bytes = File('/home/alexis/tac/tom_ai/core/tom_flutter_form_test/.tom/analyzer-cache/sdk@3.11.4.sum').readAsBytesSync();
  final reader = PackageBundleReader(bytes);
  print('Libraries in SDK summary: ${reader.libraries.length}');
  print('Has SDK section: ${reader.sdk != null}');
  if (reader.sdk != null) {
    print('SDK language version: ${reader.sdk!.languageVersionMajor}.${reader.sdk!.languageVersionMinor}');
  }
  
  final libs = reader.libraries.map((l) => l.uriStr).toList()..sort();
  for (final uri in libs) {
    print('  $uri');
  }
}
