// Scenario 1 — minimal vs broad capability sets.
//
// `Account` is annotated with two reflectors. `minimalReflector` declares only
// `instanceInvokeCapability`; `broadReflector` adds declarations, type relations
// and metadata. Both reflect the *same* class — the difference is purely how
// much the generator was told to emit, and therefore what each can do.
import 'package:reflection_capability_sample/domain.dart';
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final account = Account('Ada', 100);

  // Both reflectors can invoke instance members — that capability is shared.
  final viaMinimal = minimalReflector.reflect(account);
  final viaBroad = broadReflector.reflect(account);
  print('minimal invoke deposit -> ${viaMinimal.invoke('deposit', [25.0])}');
  // minimal invoke deposit -> 125.0
  print('broad   read summary   -> ${viaBroad.invokeGetter('summary')}');
  // broad   read summary   -> Ada: $125.0

  // The broad reflector can enumerate declarations — it asked for
  // declarationsCapability.
  final broadClass = viaBroad.type;
  final names = broadClass.declarations.keys.toList()..sort();
  print('broad   declarations   -> $names');
  // broad   declarations   -> [Account, balance, deposit, owner, summary]

  // …and walk the superclass chain — it asked for typeRelations +
  // superclassQuantify.
  print('broad   superclass     -> ${broadClass.superclass?.simpleName}');
  // broad   superclass     -> Object

  // The minimal reflector asked for none of that. Attempting it fails fast with
  // a NoSuchCapabilityError — an explicit "you didn't ask for this" rather than
  // silent wrong behaviour.
  try {
    minimalReflector.reflect(account).type.declarations;
    print('minimal declarations   -> (unexpected success)');
  } on NoSuchCapabilityError catch (e) {
    print('minimal declarations   -> NoSuchCapabilityError: ${_firstLine(e)}');
    // minimal declarations   -> NoSuchCapabilityError: Attempt to get `type`
    //                           without `TypeCapability`.
  }
}

/// The capability errors carry a multi-line explanation; keep output to the
/// first line so the scenario prints predictably.
String _firstLine(Object e) => e.toString().split('\n').first;
