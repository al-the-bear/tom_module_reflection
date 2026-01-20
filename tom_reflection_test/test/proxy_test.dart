// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Implements a very simple kind of proxy object.

library test_reflection.test.proxy_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'proxy_test.reflection.dart';

// ignore_for_file: omit_local_variable_types

class ProxyReflection extends Reflection {
  const ProxyReflection()
    : super(instanceInvokeCapability, declarationsCapability);
}

const proxyReflection = ProxyReflection();

@proxyReflection
class A {
  int i = 0;
  String foo() => i == 42 ? 'OK!' : 'Error!';
  void bar(int i) {
    this.i = i;
  }
}

class Proxy implements A {
  final dynamic forwardee;
  final Map<Symbol, Function> methodMap;
  const Proxy(this.forwardee, this.methodMap);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return Function.apply(
      methodMap[invocation.memberName]!(forwardee),
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}

Map<Symbol, Function> createMethodMap(Type T) {
  var methodMapForT = <Symbol, Function>{};
  var classMirror = proxyReflection.reflectType(T) as ClassMirror;
  Map<String, DeclarationMirror> declarations = classMirror.declarations;

  for (String name in declarations.keys) {
    var declaration = declarations[name];
    if (declaration is MethodMirror) {
      methodMapForT.putIfAbsent(
        Symbol(name),
        () => (forwardee) {
          InstanceMirror instanceMirror = proxyReflection.reflect(forwardee);
          return instanceMirror.invokeGetter(name);
        },
      );
    }
  }
  return methodMapForT;
}

void main() {
  initializeReflection();

  // Set up support for proxying A instances.
  Map<Symbol, Function> methodMapForA = createMethodMap(A);

  // Set up a single proxy for a single instance.
  final a = A();
  var proxy = Proxy(a, methodMapForA);

  // Use it.
  test('Using proxy', () {
    proxy.bar(42);
    expect(a.i, 42);
    expect(proxy.foo(), 'OK!');
  });
}
