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

Builder keysBuilder(BuilderOptions options) => KeysBuilder();

class KeysBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.keys.yaml': ['.keys.dart'],
    '.keys.yml': ['.keys.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final result = await _generate(buildStep);

    if (result.isEmpty) return;

    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.dart'),
      result,
    );
  }

  Future<String> _generate(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final path = inputId.path;

    if (!path.endsWith('.keys.yml') && !path.endsWith('.keys.yaml')) return '';

    final baseName = inputId.pathSegments.last
        .replaceAll('.keys.yaml', '')
        .replaceAll('.keys.yml', '');

    final className = '${_capitalize(_toCamelCase(baseName))}Keys';

    final content = await buildStep.readAsString(inputId);
    if (content.trim().isEmpty) {
      return '';
    }
    final yamlMap = loadYaml(content) as YamlMap;

    final classes = _generateClassesIterative(
      className: className,
      map: yamlMap,
      scope: baseName,
    );

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

      stack.addAll(generated.nestedClasses);

      allClasses.add(generated.classString);
    }

    return allClasses.toList();
  }

  ClassGenerationResult _generateClassFromInfo(ClassInfo info) {
    ClassInternalGenerationResult generationResult = (
      fields: [],
      nestedClasses: [],
      doc: '',
    );

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

    if (generationResult.doc?.isNotEmpty == true) {
      buffer.writeln('/// ${generationResult.doc}');
    }

    buffer
      ..writeln('class ${info.className} {')
      ..writeln('  const ${info.className}._();');

    if (info.isRoot) {
      buffer.writeln(
        '  static const ${info.className} i = ${info.className}._();',
      );
    }

    for (final field in generationResult.fields) {
      buffer.writeln(field);
    }

    buffer.writeln('}');

    return (
      classString: buffer.toString(),
      nestedClasses: generationResult.nestedClasses,
    );
  }

  ClassInternalGenerationResult _generateFieldsForMap({
    required String currentPath,
    required YamlMap map,
  }) {
    final fields = <String>[];
    final nestedClasses = <ClassInfo>[];

    final doc = map['_doc_'] ?? '';

    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == '_doc_') {
        continue;
      }

      final getterName = _toCamelCase(key);
      final fullPath = currentPath.isEmpty ? key : '$currentPath.$key';

      final nestedClassName = '_${_capitalize(_toCamelCase(fullPath))}Keys';

      if (value is YamlMap) {
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

  ClassInternalGenerationResult _generateFieldsForList({
    required String currentPath,
    required YamlList list,
  }) {
    final fields = <String>[];
    String classDoc = '';

    for (final rawName in list) {
      if (rawName == null || rawName.toString().isEmpty) {
        continue;
      }

      String getterDoc = '';
      String name = rawName;

      if (rawName is String && rawName.contains('//')) {
        if (rawName.startsWith('//')) {
          final docCandidate = rawName.substring(2, rawName.length).trim();
          if (docCandidate.isNotEmpty) {
            classDoc = docCandidate;
          }
          continue;
        } else {
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

String _capitalize(String input) {
  if (input.isEmpty) return '';
  return input[0].toUpperCase() + input.substring(1);
}

T? _firstWhereOrNull<T>(Iterable<T> data, bool Function(T element) test) {
  for (var element in data) {
    if (test(element)) return element;
  }
  return null;
}
