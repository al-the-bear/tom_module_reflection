# Reflection Capability Sample

> Part of the Tom Framework reflection toolkit. Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package — originally
> created by Erik Ernst and the Dart team (© 2015 the Dart project authors,
> BSD 3-Clause); Tom-specific refactoring,
> fixes and enhancements © 2026 Peter Nicolai Alexis Kyaw. See
> [`LICENSE`](../../tom_reflection/LICENSE).

The capability deep-dive for **engine 1** of the Tom reflection toolkit —
[`tom_reflection`](../../tom_reflection/README.md). The
[introduction](../reflection_introduction_sample/README.md) and
[advanced](../reflection_advanced_sample/README.md) samples *used* capabilities;
this one is *about* them.

A capability is the dial that controls how much mirror data the generator emits,
and therefore what you may do at runtime. Set it too narrow and a call throws;
set it too wide and you pay in generated code size. This sample makes that
trade-off concrete with four scenarios:

- **minimal vs broad** — the same class through two reflectors of different
  width,
- **the missing-capability error** — what `NoSuchCapabilityError` looks like and
  how its message points at the fix,
- **pattern capabilities** — `InstanceInvokeCapability('^get')`, and the crucial
  distinction between `NoSuchCapabilityError` and `ReflectionNoSuchMethodError`,
- **the "everything" end of the dial** — the full capability set, and its
  relationship to the generator's `--useAllCapabilities` flag.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The big idea: capabilities are a dial](#4-the-big-idea-capabilities-are-a-dial)
5. [The domain — four reflectors](#5-the-domain--four-reflectors)
6. [Scenario 1 — minimal vs broad](#6-scenario-1--minimal-vs-broad)
7. [Scenario 2 — the missing-capability error](#7-scenario-2--the-missing-capability-error)
8. [Scenario 3 — pattern capabilities and the two error types](#8-scenario-3--pattern-capabilities-and-the-two-error-types)
9. [Scenario 4 — the "everything" end of the dial](#9-scenario-4--the-everything-end-of-the-dial)
10. [`useAllCapabilities`: the generator-side switch](#10-useallcapabilities-the-generator-side-switch)
11. [The aggregator](#11-the-aggregator)
12. [Two errors, side by side](#12-two-errors-side-by-side)
13. [Choosing a capability set](#13-choosing-a-capability-set)
14. [Regenerating after a change](#14-regenerating-after-a-change)
15. [Where to go next](#15-where-to-go-next)

---

## 1. What you'll build

Four reflectors over a small domain, each exercised by one runnable scenario:

| Scenario | Demonstrates | Key API |
| -------- | ------------ | ------- |
| `minimal_vs_broad` | How a capability set gates what you can do | `instanceInvokeCapability` vs a broad set |
| `missing_capability` | The `NoSuchCapabilityError` path | the error + `canReflect` |
| `pattern_capabilities` | Selecting members by regex; two error types | `InstanceInvokeCapability('^get')` |
| `use_all_capabilities` | The full set, incl. `newInstance` | every capability + `--useAllCapabilities` |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
four and reports a pass/fail tally.

The theme throughout: **capabilities fail loudly, not silently.** Ask for an
operation you did not enable and you get a precise error naming what is missing —
never a wrong-but-quiet result.

---

## 2. Project layout

```
reflection_capability_sample/
  pubspec.yaml                 depends on tom_reflection (runtime) +
                               tom_reflection_generator (dev, generates code)
  build.yaml                   tells build_runner to generate for example/**/main.dart
  reflection_generation.sh     one-liner to regenerate the mirror data
  analysis_options.yaml        package:lints/recommended.yaml
  lib/
    domain.dart                four reflectors + their annotated classes
  example/
    minimal_vs_broad/
      main.dart                scenario 1 entry point
      main.reflection.dart     GENERATED mirror data (committed)
    missing_capability/
      main.dart                scenario 2 + GENERATED
    pattern_capabilities/
      main.dart                scenario 3 + GENERATED
    use_all_capabilities/
      main.dart                scenario 4 + GENERATED
  bin/
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
```

As in the other engine-1 samples: the annotated classes live in
`lib/domain.dart`, but the generated files sit next to each scenario's
`main.dart`, because the generator is *entry-point driven*. The
`*.reflection.dart` files are committed so the sample runs with a plain `dart
run`; never hand-edit them — regenerate (see [§14](#14-regenerating-after-a-change)).

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all four scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/minimal_vs_broad/main.dart
dart run example/missing_capability/main.dart
dart run example/pattern_capabilities/main.dart
dart run example/use_all_capabilities/main.dart
```

The aggregator finishes with:

```text
----------------------------------------
Scenarios: 4  passed: 4  failed: 0
```

and exits `0`; any scenario that throws prints `FAILED: <name>: <error>` and
exits `1`.

---

## 4. The big idea: capabilities are a dial

Unlimited reflection is expensive. To support *every* operation on *every* class,
the generator would emit data for every member, type relation, constructor and
piece of metadata in your program — bloating the binary for things you never use.

Capabilities are how you turn that down. A reflector declares, in its `super(...)`
call, exactly which operations it needs:

```
  narrow ◄──────────────────────────────────────────────────► wide
  instanceInvokeCapability   …   the full set / --useAllCapabilities
  (smallest generated code)      (largest generated code)
```

The generator reads those declarations and emits *only* the matching data. At
runtime the mirror system enforces them: a call outside the declared set throws
rather than returning a wrong answer. The whole sample is a tour of that
enforcement.

---

## 5. The domain — four reflectors

[`lib/domain.dart`](lib/domain.dart) declares four reflectors, each tuned for one
scenario, plus the classes they annotate.

```dart
// Scenario 1 — the narrowest useful reflector, and a broad one.
class MinimalReflector extends Reflection {
  const MinimalReflector() : super(instanceInvokeCapability);
}
class BroadReflector extends Reflection {
  const BroadReflector()
      : super(invokingCapability, declarationsCapability,
              typeRelationsCapability, metadataCapability,
              superclassQuantifyCapability);
}

// Scenario 2 — declarations + invoke, but NO type relations.
class DeclOnlyReflector extends Reflection {
  const DeclOnlyReflector()
      : super(declarationsCapability, instanceInvokeCapability);
}

// Scenario 3 — a pattern: only members whose name starts with "get".
class GettersOnlyReflector extends Reflection {
  const GettersOnlyReflector() : super(const InstanceInvokeCapability('^get'));
}

// Scenario 4 — the full set.
class AllCapabilitiesReflector extends Reflection {
  const AllCapabilitiesReflector()
      : super(invokingCapability, declarationsCapability, typeRelationsCapability,
              superclassQuantifyCapability, metadataCapability,
              newInstanceCapability, reflectedTypeCapability);
}
```

A note on two convenience capabilities: `invokingCapability` is the *broad* invoke
capability — it covers **instance and static** members, getters and setters.
`instanceInvokeCapability` is its instance-only sibling. The pattern form,
`InstanceInvokeCapability('regexp')`, narrows invocation to members whose name
matches the expression.

### The invoke family, briefly

The scenarios use three sibling calls on an instance mirror, and it helps to keep
them straight before reading the output:

| Call | Reaches | Example in this sample |
| ---- | ------- | ---------------------- |
| `invoke(name, args)` | a **method** | `viaMinimal.invoke('deposit', [25.0])` |
| `invokeGetter(name)` | a **getter** (or field read) | `viaBroad.invokeGetter('summary')` |
| `invokeSetter(name, value)` | a **setter** (or field write) | `builtMirror.invokeSetter('name', 'Ada')` |

All three are gated by the *same* invoke capability — `instanceInvokeCapability`
covers a class's methods, getters and setters together; you do not enable them
separately. A pattern capability filters all three by name at once: with
`InstanceInvokeCapability('^get')`, `invokeGetter('getRaw')` is covered but
`invoke('compute', …)` is not, because the *member name* — not the kind of call —
is what the regex matches.

One subtlety the scenarios lean on: `.type` (the class mirror) is gated by
`TypeCapability`, which `declarationsCapability` implies. That is why
`minimalReflector` — instance-invoke only — can call `invoke` but throws the moment
it touches `.type`, while every reflector that lists `declarationsCapability` can
enumerate declarations and walk on to type relations.

---

## 6. Scenario 1 — minimal vs broad

[`example/minimal_vs_broad/main.dart`](example/minimal_vs_broad/main.dart)

`Account` carries **both** `minimalReflector` and `broadReflector`. Same class,
two windows of different width:

```dart
final viaMinimal = minimalReflector.reflect(account);
final viaBroad = broadReflector.reflect(account);

viaMinimal.invoke('deposit', [25.0]);        // both can invoke
viaBroad.invokeGetter('summary');            // both can invoke

viaBroad.type.declarations;                  // broad only
viaBroad.type.superclass;                    // broad only

minimalReflector.reflect(account).type;      // throws NoSuchCapabilityError
```

Output:

```text
minimal invoke deposit -> 125.0
broad   read summary   -> Ada: $125.0
broad   declarations   -> [Account, balance, deposit, owner, summary]
broad   superclass     -> Object
minimal declarations   -> NoSuchCapabilityError: Attempt to get `type` without `TypeCapability`.
```

Both reflectors share instance invocation, so `deposit` and `summary` work
through either. But the moment the minimal reflector reaches for `.type` — the
gateway to declarations and type relations — it throws, because
`instanceInvokeCapability` alone does not include the `TypeCapability` that `.type`
requires. The broad reflector asked for `declarationsCapability` and
`typeRelationsCapability`, so the same calls succeed.

That single class, reflected two ways, is the whole point: **what you can do is a
function of what the reflector declared**, not of the object.

---

## 7. Scenario 2 — the missing-capability error

[`example/missing_capability/main.dart`](example/missing_capability/main.dart)

`declOnlyReflector` has declarations + instance invoke but **no** type relations.
There are two distinct ways to trip `NoSuchCapabilityError`, and the scenario
shows both:

```dart
final mirror = declOnlyReflector.reflect(widget);

mirror.invoke('render', const []);     // works — has the capability
mirror.type.declarations;              // works — has declarationsCapability

mirror.type.superclass;                // throws — no typeRelationsCapability
declOnlyReflector.reflect(const Unregistered()); // throws — class not covered
```

Output:

```text
invoke render      -> <btn/>
declarations       -> [id, render]
superclass         -> NoSuchCapabilityError (names typeRelations: true)
canReflect(Unregistered) -> false
reflect Unregistered     -> NoSuchCapabilityError (class not covered)
```

Two things worth internalising:

- **The error names the capability you forgot.** Calling `.superclass` without
  `typeRelationsCapability` throws a `NoSuchCapabilityError` whose message
  contains `typeRelationsCapability` — the fastest possible diagnosis. The
  scenario asserts that substring is present rather than printing the full
  message, so its output stays stable.
- **`canReflect` is the cheap pre-check.** Before reflecting an object whose
  class you are unsure about, `reflector.canReflect(obj)` returns a boolean
  (`false` for `Unregistered`), letting you branch without catching. `reflect`
  itself throws `NoSuchCapabilityError` when the class is outside every
  reflector's scope.

---

## 8. Scenario 3 — pattern capabilities and the two error types

[`example/pattern_capabilities/main.dart`](example/pattern_capabilities/main.dart)

`gettersOnlyReflector` is `InstanceInvokeCapability('^get')`: a regular expression
that covers only members whose name starts with `get`. `Sensor` has `getRaw`,
`getScaled` (both match) and `compute` (does not).

```dart
final mirror = gettersOnlyReflector.reflect(sensor);

mirror.invokeGetter('getRaw');        // covered → 21
mirror.invokeGetter('getScaled');     // covered → 42

mirror.invoke('compute', const []);   // present but NOT covered → method error
mirror.invokeGetter('getMissing');    // does not exist → method error
```

Output:

```text
getRaw    -> 21
getScaled -> 42
compute   -> ReflectionNoSuchMethodError (pattern did not cover it)
getMissing -> ReflectionNoSuchMethodError (no such member)
```

This scenario exists to teach **one distinction**:

- `compute` *exists* on `Sensor`, and the reflector *does* have an instance-invoke
  capability — it is just a pattern that does not match `compute`. So the failure
  is a `ReflectionNoSuchMethodError` ("have the capability, no such covered
  member"), **not** a `NoSuchCapabilityError` ("no such capability at all").
- A member that does not exist (`getMissing`) yields the same
  `ReflectionNoSuchMethodError` — same category.

Pattern capabilities let you reflect a precise slice of a class — say, only its
getters, or only members matching a naming convention — keeping the generated data
to exactly that slice.

---

## 9. Scenario 4 — the "everything" end of the dial

[`example/use_all_capabilities/main.dart`](example/use_all_capabilities/main.dart)

`allCapabilitiesReflector` lists the full capability set, so the same `Profile`
class supports every operation — including construction via `newInstance`, which
none of the earlier reflectors enabled:

```dart
final mirror = allCapabilitiesReflector.reflect(profile);

mirror.invoke('greet', const []);              // Hi Grace
mirror.invokeGetter('badge');                  // Grace (37)
mirror.type.declarations;                      // [Profile, age, badge, greet, name]
mirror.type.superclass;                        // Object

final built = mirror.type.newInstance('', const []); // construct by name
allCapabilitiesReflector.reflect(built)
  ..invokeSetter('name', 'Ada')
  ..invokeSetter('age', 36);
```

Output:

```text
invoke greet  -> Hi Grace
read badge    -> Grace (37)
declarations  -> [Profile, age, badge, greet, name]
superclass    -> Object
newInstance   -> Ada (36)
```

This is the opposite extreme from scenario 1's `minimalReflector`: where that one
threw on `.type`, this one does everything. The cost is real — the full set tells
the generator to emit the maximum amount of mirror data — which is exactly why a
tight set is the default advice and "all capabilities" is a deliberate choice, not
a default.

---

## 10. `useAllCapabilities`: the generator-side switch

There are two ways to reach "emit everything":

1. **Declare the full capability set**, as `allCapabilitiesReflector` does above.
   Portable: it works through `build_runner` and is what this sample uses.
2. **Pass `--useAllCapabilities` to the generator.** This makes the generator
   *ignore* whatever the reflector declares and emit data for every capability —
   so even a reflector that declares only `instanceInvokeCapability` ends up with
   full reflection at runtime.

The second is a property of the **generator invocation**, not of the source. It is
exposed by the standalone `tom_reflection_generator` CLI:

```bash
dart run tom_reflection_generator example/**/main.dart --useAllCapabilities
```

The `build_runner` builder does **not** surface this flag, so a `build.yaml`-driven
project (like this sample) cannot switch it on — which is why scenario 4 reaches
the full set the portable way, by declaring it. The end state is identical:
maximal generated code. Reach for either only when you genuinely need open-ended
reflection (a generic serializer over arbitrary types, say) and have accepted the
size cost.

---

## 11. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix, runs them in turn, and counts failures — the same shape as every
sample in this toolkit. Because each scenario re-calls the idempotent
`initializeReflection()` before reflecting, running all four back-to-back in one
process is safe.

---

## 12. Two errors, side by side

The single most useful thing to take from this sample is telling the two failures
apart:

| Error | Means | Typical fix |
| ----- | ----- | ----------- |
| `NoSuchCapabilityError` | The reflector did not declare the capability this operation needs — **or** the object's class is not covered by the reflector at all | Add the capability to the reflector's `super(...)` and regenerate; or annotate the class |
| `ReflectionNoSuchMethodError` | You **have** the relevant capability, but this specific member is not covered (a pattern miss) or does not exist | Widen the pattern, or check the member name |

Rule of thumb: **capability errors are about the reflector; method errors are about
the member.**

---

## 13. Choosing a capability set

A practical default ladder, narrow to wide:

1. `instanceInvokeCapability` — invoke instance members by name. The smallest
   footprint; enough for dynamic dispatch.
2. `+ declarationsCapability` — enumerate members (and reach `.type`).
3. `+ typeRelationsCapability` (`+ superclassQuantifyCapability`) — walk the
   superclass chain and interfaces.
4. `+ newInstanceCapability` — construct objects by name (serializers).
5. `+ metadataCapability`, `+ reflectedTypeCapability` — read annotations,
   reflected types.

Use a **pattern capability** (`InstanceInvokeCapability('regexp')`) when you only
need a slice of a class. Reach for the full set or `--useAllCapabilities` only
when the consumer is genuinely open-ended.

---

## 14. Regenerating after a change

Regenerate when you change members, types, capabilities or annotations — **not**
when you only edit a method body.

```bash
./reflection_generation.sh
# which is just:
dart run build_runner build
```

Then re-run `dart run bin/run_example.dart` and commit the regenerated files
alongside the source change. Treat the generated files as outputs: never edit them
by hand.

---

## 15. Where to go next

- [`reflection_introduction_sample`](../reflection_introduction_sample/README.md)
  — the starting point: annotate → generate → reflect → invoke.
- [`reflection_advanced_sample`](../reflection_advanced_sample/README.md) —
  declarations, `newInstance`, static members, type relations, generics & mixins,
  in a realistic serializer.
- [`tom_reflection`](../../tom_reflection/README.md) — the runtime library
  reference (full mirror API and the complete capability list).
- [`tom_reflection_generator`](../../tom_reflection_generator/README.md) — the
  generator (builder, CLI including `--useAllCapabilities`, and configuration).
- The samples index: [`../README.md`](../README.md).

For the *other* engine — build-time structural reflection that produces a
serializable model rather than runtime mirrors — start at
[`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md).

---

## License

BSD 3-Clause. Derived from
[`reflectable`](https://pub.dev/packages/reflectable) — originally created by
Erik Ernst and the Dart team — retaining the upstream copyright
(© 2015 the Dart project authors) alongside Tom's modifications
(© 2026 Peter Nicolai Alexis Kyaw). See
[`tom_reflection/LICENSE`](../../tom_reflection/LICENSE).
