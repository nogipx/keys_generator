import 'dart:async';

import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

typedef ClassGenerationResult = ({
  String classString,
  Iterable<ClassInfo> nestedClasses,
});

typedef ClassInternalGenerationResult = ({
  Iterable<String> fields,
  Iterable<ClassInfo> nestedClasses,
  String? doc,
});

/// Creates an instance of [KeysBuilder].
Builder keysBuilder(BuilderOptions options) => KeysBuilder();

/// A builder that generates Dart classes from YAML files with `.keys.yaml` or `.keys.yml` extensions.
class KeysBuilder implements Builder {
  /// Specifies the input and output file extensions.
  @override
  final buildExtensions = const {
    '.keys.yaml': ['.keys.dart'],
    '.keys.yml': ['.keys.dart'],
  };

  /// The main build method invoked by the build system.
  @override
  Future<void> build(BuildStep buildStep) async {
    final result = await _generate(buildStep);

    // If no content is generated, exit early to avoid writing empty files.
    if (result.isEmpty) return;

    // Write the generated Dart code to the corresponding `.dart` file.
    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.dart'),
      result,
    );
  }

  /// Generates Dart code based on the provided YAML file.
  Future<String> _generate(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final path = inputId.path;

    // Ensure the file has a valid `.keys.yml` or `.keys.yaml` extension.
    if (!path.endsWith('.keys.yml') && !path.endsWith('.keys.yaml')) return '';

    // Extract the base name of the file without the extension.
    final baseName = inputId.pathSegments.last
        .replaceAll('.keys.yaml', '')
        .replaceAll('.keys.yml', '');

    // Create the root class name by capitalizing and converting to camel case.
    final className = '${_capitalize(_toCamelCase(baseName))}Keys';

    // Read the content of the YAML file.
    final content = await buildStep.readAsString(inputId);
    if (content.trim().isEmpty) {
      // If the YAML file is empty, skip generation to prevent empty Dart files.
      return '';
    }

    // Parse the YAML content into a YamlMap.
    final yamlMap = loadYaml(content) as YamlMap;

    // Generate Dart classes based on the YAML structure.
    final classes = _generateClassesIterative(
      className: className,
      map: yamlMap,
      scope: baseName,
    );

    // Build the final Dart code with headers and generated classes.
    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND (keys_generator)')
      ..writeln('// SOURCE YAML - ${buildStep.inputId.uri}')
      ..writeln('// ignore_for_file: library_private_types_in_public_api')
      ..writeln('');
    for (final classDefinition in classes) {
      buffer.writeln(classDefinition);
    }

    return buffer.toString();
  }

  /// Iteratively generates Dart classes from the provided [YamlMap].
  ///
  /// This method uses a stack to handle nested classes without recursion,
  /// which helps prevent stack overflow in deeply nested YAML structures.
  List<String> _generateClassesIterative({
    required String className,
    required YamlMap map,
    required String scope,
  }) {
    final stack = <ClassInfo>[];
    stack.add(
      ClassInfo(
        className: className,
        map: map,
        currentPath: scope,
        isRoot: true,
      ),
    );

    final allClasses = <String>[];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final generated = _generateClassFromInfo(current);

      // Add any nested classes to the stack for further processing.
      stack.addAll(generated.nestedClasses);

      // Collect the generated class string.
      allClasses.add(generated.classString);
    }

    return allClasses.toList();
  }

  /// Generates a Dart class from the provided [ClassInfo].
  ///
  /// This method constructs the class definition, including fields and nested classes.
  ClassGenerationResult _generateClassFromInfo(ClassInfo info) {
    ClassInternalGenerationResult generationResult = (
      fields: [],
      nestedClasses: [],
      doc: '',
    );

    // Determine whether to generate fields from a map or a list.
    if (info.map != null) {
      generationResult = _generateFieldsForMap(
        currentPath: info.currentPath,
        map: info.map!,
      );
    } else if (info.list != null) {
      generationResult = _generateFieldsForList(
        currentPath: info.currentPath,
        list: info.list!,
      );
    }

    final buffer = StringBuffer();

    // Add documentation if available.
    if (generationResult.doc?.isNotEmpty == true) {
      buffer.writeln('/// ${generationResult.doc}');
    }

    // Start the class definition.
    buffer
      ..writeln('class ${info.className} {')
      ..writeln('  const ${info.className}._();');

    // If it's the root class, add a static instance for easy access.
    if (info.isRoot) {
      buffer.writeln(
        '  static const ${info.className} i = ${info.className}._();',
      );
    }

    // Add all fields to the class.
    for (final field in generationResult.fields) {
      buffer.writeln(field);
    }

    // Close the class definition.
    buffer.writeln('}');

    return (
      classString: buffer.toString(),
      nestedClasses: generationResult.nestedClasses,
    );
  }

  /// Generates fields for a class based on a [YamlMap].
  ///
  /// Handles different types of values (maps, lists, strings) and creates appropriate fields.
  ClassInternalGenerationResult _generateFieldsForMap({
    required String currentPath,
    required YamlMap map,
  }) {
    final fields = <String>[];
    final nestedClasses = <ClassInfo>[];

    // Extract documentation if provided.
    final doc = map['_doc_'] ?? '';

    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      // Skip documentation entries to avoid generating fields for them.
      if (key == '_doc_') {
        continue;
      }

      final getterName = _toCamelCase(key);
      final fullPath = currentPath.isEmpty ? key : '$currentPath.$key';

      // Generate a unique nested class name based on the path.
      final nestedClassName = '_${_capitalize(_toCamelCase(fullPath))}Keys';

      if (value is YamlMap) {
        // If the value is a map, create a nested class with its own fields.
        final doc = value['_doc_'] ?? '';
        fields.add(
          "${doc is String && doc.isNotEmpty ? '\n  /// $doc\n' : ''}"
          "  $nestedClassName get $getterName => const $nestedClassName._();",
        );
        nestedClasses.add(
          ClassInfo(
            className: nestedClassName,
            map: value,
            currentPath: fullPath,
          ),
        );
      } else if (value is YamlList) {
        // If the value is a list, create fields based on the list items.
        final values = value.value.whereType<String>();
        final docRaw = _firstWhereOrNull(values, (e) => e.startsWith('//'));
        final doc = docRaw?.substring(2, docRaw.length).trim();

        fields.add(
          "${doc is String && doc.isNotEmpty ? '\n  /// $doc\n' : ''}"
          "  $nestedClassName get $getterName => const $nestedClassName._();",
        );
        nestedClasses.add(
          ClassInfo(
            className: nestedClassName,
            list: value,
            currentPath: fullPath,
          ),
        );
      } else {
        // For simple string values, create a string getter.
        final getterValue = fullPath;
        fields.add(
          "${value is String && value.isNotEmpty ? '\n  /// $value\n' : ''}"
          "  String get $getterName => '$getterValue';",
        );
      }
    }

    return (
      fields: fields,
      nestedClasses: nestedClasses,
      doc: doc,
    );
  }

  /// Generates fields for a class based on a [YamlList].
  ///
  /// Handles list items, which can include documentation or nested keys.
  ClassInternalGenerationResult _generateFieldsForList({
    required String currentPath,
    required YamlList list,
  }) {
    final fields = <String>[];
    String classDoc = '';

    for (final rawName in list) {
      if (rawName == null || rawName.toString().isEmpty) {
        continue; // Skip empty or null entries.
      }

      String getterDoc = '';
      String name = rawName;

      if (rawName is String && rawName.contains('//')) {
        if (rawName.startsWith('//')) {
          // If the item starts with `//`, treat the rest as class documentation.
          final docCandidate = rawName.substring(2, rawName.length).trim();
          if (docCandidate.isNotEmpty) {
            classDoc = docCandidate;
          }
          continue; // Skip adding a field for documentation entries.
        } else {
          // Split the item into name and documentation.
          final splittedName = rawName.split('//');
          name = splittedName.elementAtOrNull(0)?.trim() ?? rawName;
          getterDoc = splittedName.length > 1
              ? splittedName.skip(1).join(' ').replaceAll('//', '').trim()
              : '';
        }
      }

      final getterName = _toCamelCase(name);
      final getterValue = '$currentPath.$name';

      fields.add(
        "${getterDoc.isNotEmpty ? '\n  /// $getterDoc\n' : ''}"
        "  String get $getterName => '$getterValue';",
      );
    }

    return (
      fields: fields,
      nestedClasses: const [],
      doc: classDoc,
    );
  }
}

/// Contains information about a class to be generated.
class ClassInfo {
  final String className;
  final YamlMap? map;
  final YamlList? list;
  final String currentPath;
  final bool isRoot;

  const ClassInfo({
    required this.className,
    required this.currentPath,
    this.isRoot = false,
    this.map,
    this.list,
  });

  @override
  String toString() => 'ClassInfo('
      'className: $className, '
      'currenPath: $currentPath, '
      '${map != null ? 'map: $map' : ''}'
      '${list != null ? 'list: $list' : ''}'
      ')';
}

/// Converts a string to camelCase.
String _toCamelCase(String input) {
  final parts = input.split(RegExp(r'[_.]'));
  if (parts.isEmpty) return '';
  final head = parts.first;
  final tail = parts.skip(1).map((s) {
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }).join('');
  return head + tail;
}

/// Capitalizes the first letter of a string.
String _capitalize(String input) {
  if (input.isEmpty) return '';
  return input[0].toUpperCase() + input.substring(1);
}

/// Returns the first element in [data] that satisfies [test], or `null` if none do.
T? _firstWhereOrNull<T>(Iterable<T> data, bool Function(T element) test) {
  for (var element in data) {
    if (test(element)) return element;
  }
  return null;
}
