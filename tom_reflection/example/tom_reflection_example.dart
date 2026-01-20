// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// Modifications (c) 2026, Alexis Kyaw

/// Tom Reflection Example
///
/// This example demonstrates how to use the tom_reflection package
/// for runtime reflection in Dart.
///
/// To generate the reflection code, run from the tom_reflection directory:
/// ```bash
/// dart run tom_build_tools:reflection_generator example/tom_reflection_example.dart
/// ```
///
/// Then run this example:
/// ```bash
/// dart run example/tom_reflection_example.dart
/// ```
library;

import 'package:tom_reflection/tom_reflection.dart';
import 'tom_reflection_example.reflection.dart';

// ============================================================================
// Step 1: Define a Reflector
// ============================================================================

/// A reflector that enables full reflection capabilities.
///
/// Extend [Reflection] and pass the capabilities you need:
/// - [invokingCapability]: Call methods and constructors
/// - [declarationsCapability]: Access class declarations (fields, methods)
/// - [typeRelationsCapability]: Access superclass/interface information
/// - [metadataCapability]: Access metadata annotations
class MyReflector extends Reflection {
  const MyReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          metadataCapability,
        );
}

/// Singleton instance of the reflector to use as annotation.
const myReflector = MyReflector();

// ============================================================================
// Step 2: Annotate Classes for Reflection
// ============================================================================

/// A simple Person class annotated for reflection.
@myReflector
class Person {
  String name;
  int age;
  String? email;

  Person(this.name, this.age, {this.email});

  String greet() => 'Hello, I am $name!';

  String introduce() => 'I am $name, $age years old.';

  @override
  String toString() => 'Person(name: $name, age: $age, email: $email)';
}

/// An Employee class extending Person.
@myReflector
class Employee extends Person {
  String department;
  double salary;

  Employee(super.name, super.age, this.department, this.salary, {super.email});

  String getJobInfo() => '$name works in $department';

  @override
  String toString() =>
      'Employee(name: $name, age: $age, department: $department, salary: $salary)';
}

/// A Manager class extending Employee (for deeper hierarchy testing).
@myReflector
class Manager extends Employee {
  List<String> directReports;

  Manager(
    super.name,
    super.age,
    super.department,
    super.salary, {
    super.email,
    this.directReports = const [],
  });

  @override
  String toString() =>
      'Manager(name: $name, department: $department, reports: ${directReports.length})';
}

/// A container class with generic collections for type argument examples.
@myReflector
class Team {
  String teamName;
  List<Person> members;
  Map<String, Employee> employeeDirectory;
  Set<String> skills;

  Team(this.teamName)
      : members = [],
        employeeDirectory = {},
        skills = {};

  void addMember(Person p) => members.add(p);
  void addEmployee(String id, Employee e) => employeeDirectory[id] = e;
}

// ============================================================================
// Step 3: Use Reflection
// ============================================================================

void main() {
  // Initialize reflection - REQUIRED before any reflection operations
  initializeReflection();

  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║                 Tom Reflection Example                           ║');
  print('╚══════════════════════════════════════════════════════════════════╝\n');

  // -------------------------------------------------------------------------
  // Example 1: Reflect on an instance
  // -------------------------------------------------------------------------
  print('=== Example 1: Reflecting on an Instance ===\n');

  final person = Person('Alice', 30, email: 'alice@example.com');
  final instanceMirror = myReflector.reflect(person);

  print('Reflected on: $person');
  print('Instance mirror type: ${instanceMirror.runtimeType}\n');

  // -------------------------------------------------------------------------
  // Example 2: Invoke methods dynamically
  // -------------------------------------------------------------------------
  print('=== Example 2: Dynamic Method Invocation ===\n');

  // Invoke the greet() method by name
  final greeting = instanceMirror.invoke('greet', []);
  print('Calling greet(): $greeting');

  // Invoke the introduce() method by name
  final introduction = instanceMirror.invoke('introduce', []);
  print('Calling introduce(): $introduction\n');

  // -------------------------------------------------------------------------
  // Example 3: Inspect class declarations
  // -------------------------------------------------------------------------
  print('=== Example 3: Class Introspection ===\n');

  final classMirror = instanceMirror.type;
  print('Class name: ${classMirror.simpleName}');
  print('Qualified name: ${classMirror.qualifiedName}');

  print('\nDeclared members:');
  for (final entry in classMirror.declarations.entries) {
    final name = entry.key;
    final declaration = entry.value;
    final kind = switch (declaration) {
      MethodMirror m when m.isGetter => 'getter',
      MethodMirror m when m.isSetter => 'setter',
      MethodMirror m when m.isConstructor => 'constructor',
      MethodMirror() => 'method',
      VariableMirror() => 'field',
      _ => 'other',
    };
    print('  - $name ($kind)');
  }

  // -------------------------------------------------------------------------
  // Example 4: Access field values
  // -------------------------------------------------------------------------
  print('\n=== Example 4: Field Access ===\n');

  // Get field values using the instance mirror
  final nameValue = instanceMirror.invokeGetter('name');
  final ageValue = instanceMirror.invokeGetter('age');
  final emailValue = instanceMirror.invokeGetter('email');

  print('Field values via reflection:');
  print('  name: $nameValue');
  print('  age: $ageValue');
  print('  email: $emailValue');

  // Set a field value
  instanceMirror.invokeSetter('age', 31);
  print('\nAfter setting age to 31:');
  print('  age: ${instanceMirror.invokeGetter('age')}');

  // -------------------------------------------------------------------------
  // Example 5: Reflect on a subclass
  // -------------------------------------------------------------------------
  print('\n=== Example 5: Subclass Reflection ===\n');

  final employee = Employee('Bob', 35, 'Engineering', 75000.0);
  final empMirror = myReflector.reflect(employee);
  final empClassMirror = empMirror.type;

  print('Class: ${empClassMirror.simpleName}');
  print('Superclass: ${empClassMirror.superclass?.simpleName ?? "none"}');

  final jobInfo = empMirror.invoke('getJobInfo', []);
  print('Job info: $jobInfo');

  // -------------------------------------------------------------------------
  // Example 6: Reflect on a Type
  // -------------------------------------------------------------------------
  print('\n=== Example 6: Type Reflection ===\n');

  final typeMirror = myReflector.reflectType(Person);
  print('Type mirror for Person:');
  print('  simpleName: ${typeMirror.simpleName}');
  print('  isOriginalDeclaration: ${typeMirror.isOriginalDeclaration}');

  // -------------------------------------------------------------------------
  // Example 7: List all annotated classes
  // -------------------------------------------------------------------------
  print('\n=== Example 7: Annotated Classes ===\n');

  print('Classes covered by myReflector:');
  for (final classMirror in myReflector.annotatedClasses) {
    print('  - ${classMirror.simpleName}');
  }

  // -------------------------------------------------------------------------
  // Example 8: isSubtype<S>() - Type Hierarchy Checking (No Capabilities Needed)
  // -------------------------------------------------------------------------
  print('\n=== Example 8: isSubtype<S>() - Type Hierarchy ===\n');

  final personType = myReflector.reflectType(Person) as ClassMirror;
  final employeeType = myReflector.reflectType(Employee) as ClassMirror;
  final managerType = myReflector.reflectType(Manager) as ClassMirror;
  final teamType = myReflector.reflectType(Team) as ClassMirror;

  // isSubtype<S>() checks if S is a subtype of this mirror's type (T)
  // personType.isSubtype<Employee>() asks: "Is Employee a subtype of Person?"
  print('Type hierarchy checks using isSubtype<S>():');
  print('  Is Employee subtype of Person? ${personType.isSubtype<Employee>()}');
  print('  Is Manager subtype of Person? ${personType.isSubtype<Manager>()}');
  print('  Is Manager subtype of Employee? ${employeeType.isSubtype<Manager>()}');
  print('  Is Person subtype of Employee? ${employeeType.isSubtype<Person>()}');
  print('  Is Team subtype of Person? ${personType.isSubtype<Team>()}');

  print('\nPractical use - checking runtime types:');
  final manager = Manager('Carol', 45, 'Product', 120000.0, directReports: ['Alice', 'Bob']);
  final managerMirror = myReflector.reflect(manager);
  print('  Manager instance type: ${managerMirror.type.simpleName}');
  // Check if Manager (from managerMirror.type) is subtype of Person
  print('  Is Manager subtype of Person? ${personType.isSubtype<Manager>()}');
  print('  Is Manager subtype of Employee? ${employeeType.isSubtype<Manager>()}');

  // -------------------------------------------------------------------------
  // Example 9: isInstanceOf - Runtime Type Checking
  // -------------------------------------------------------------------------
  print('\n=== Example 9: isInstanceOf - Runtime Type Checking ===\n');

  final alice = Person('Alice', 30);
  final bob = Employee('Bob', 35, 'Engineering', 75000.0);
  final carol = manager; // Manager from above

  print('Checking instances against types:');
  print('  personType.isInstanceOf(alice): ${personType.isInstanceOf(alice)}');
  print('  personType.isInstanceOf(bob): ${personType.isInstanceOf(bob)}');
  print('  personType.isInstanceOf(carol): ${personType.isInstanceOf(carol)}');
  print('  employeeType.isInstanceOf(alice): ${employeeType.isInstanceOf(alice)}');
  print('  employeeType.isInstanceOf(bob): ${employeeType.isInstanceOf(bob)}');
  print('  managerType.isInstanceOf(bob): ${managerType.isInstanceOf(bob)}');
  print('  managerType.isInstanceOf(carol): ${managerType.isInstanceOf(carol)}');

  // -------------------------------------------------------------------------
  // Example 10: Creating typed Lists, Sets, and Maps
  // -------------------------------------------------------------------------
  print('\n=== Example 10: Creating Typed Collections ===\n');

  // Use ClassMirror to create typed collections
  print('Creating collections using ClassMirror:');

  // Create a List<Person>
  final personList = personType.createList();
  personList.add(Person('Dave', 28));
  personList.add(Employee('Eve', 32, 'Sales', 65000.0));
  print('  Created List<Person> with ${personList.length} items');
  print('  List runtime type: ${personList.runtimeType}');

  // Create a Set<Person>
  final personSet = personType.createSet();
  personSet.add(Person('Frank', 40));
  print('  Created Set<Person> with ${personSet.length} items');
  print('  Set runtime type: ${personSet.runtimeType}');

  // Create a Map<String, Person>
  final personMap = personType.createValuedMap<String>();
  personMap['p1'] = Person('Grace', 35);
  personMap['e1'] = Employee('Henry', 29, 'IT', 70000.0);
  print('  Created Map<String, Person> with ${personMap.length} entries');
  print('  Map runtime type: ${personMap.runtimeType}');

  // -------------------------------------------------------------------------
  // Example 11: Inspecting Class Declarations (Fields and Methods)
  // -------------------------------------------------------------------------
  print('\n=== Example 11: Class Declarations ===\n');

  final team = Team('Alpha Team');
  team.addMember(Person('Ian', 30));
  team.addEmployee('E001', Employee('Jane', 28, 'Dev', 80000.0));

  // Reflect on the team instance
  final teamMirror = myReflector.reflect(team);
  print('Team instance name: ${teamMirror.invokeGetter('teamName')}');
  print('Team members count: ${(teamMirror.invokeGetter('members') as List).length}');

  print('\nTeam class declarations:');
  for (final entry in teamType.declarations.entries) {
    final decl = entry.value;
    final kind = switch (decl) {
      MethodMirror m when m.isGetter => 'getter',
      MethodMirror m when m.isSetter => 'setter',
      MethodMirror m when m.isConstructor => 'constructor',
      MethodMirror() => 'method',
      VariableMirror() => 'field',
      _ => 'other',
    };
    print('  ${entry.key} ($kind)');
  }

  // -------------------------------------------------------------------------
  // Example 12: Walking the Superclass Chain
  // -------------------------------------------------------------------------
  print('\n=== Example 12: Walking the Superclass Chain ===\n');

  print('Manager superclass chain:');
  ClassMirror? current = managerType;
  var depth = 0;
  while (current != null) {
    final indent = '  ' * depth;
    print('$indent${current.simpleName}');
    depth++;
    // Try to get superclass - will fail for unmarked classes like Object
    try {
      current = current.superclass;
    } catch (e) {
      // Reached an unmarked class (e.g., Object), stop here
      print('${'  ' * depth}(base class)');
      break;
    }
  }

  // -------------------------------------------------------------------------
  // Example 13: Finding Common Supertype using isInstanceOf
  // -------------------------------------------------------------------------
  print('\n=== Example 13: Finding Common Supertype ===\n');

  // Check which annotated classes are subtypes of Person using isInstanceOf
  // This requires creating a sample instance, but we can check via superclass chain
  print('Classes that are subtypes of Person (by superclass chain):');

  bool isInSuperclassChain(ClassMirror classMirror, String targetName) {
    ClassMirror? current = classMirror;
    while (current != null) {
      if (current.simpleName == targetName) return true;
      try {
        current = current.superclass;
      } catch (e) {
        // Reached unmarked class
        break;
      }
    }
    return false;
  }

  for (final classMirror in myReflector.annotatedClasses) {
    if (isInSuperclassChain(classMirror, 'Person')) {
      print('  - ${classMirror.simpleName}');
    }
  }

  print('\nClasses that are subtypes of Employee:');
  for (final classMirror in myReflector.annotatedClasses) {
    if (isInSuperclassChain(classMirror, 'Employee')) {
      print('  - ${classMirror.simpleName}');
    }
  }

  // Demonstrating isInstanceOf for runtime type checking
  print('\nRuntime type checking with isInstanceOf:');
  final objects = <Object>[alice, bob, carol, team];
  for (final obj in objects) {
    print('  ${obj.runtimeType}: isPerson=${personType.isInstanceOf(obj)}, '
        'isEmployee=${employeeType.isInstanceOf(obj)}');
  }

  print('\n╔══════════════════════════════════════════════════════════════════╗');
  print('║                    Example Complete!                             ║');
  print('╚══════════════════════════════════════════════════════════════════╝');
}
