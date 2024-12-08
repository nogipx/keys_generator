import 'dart:async';
import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

Builder keysBuilder(BuilderOptions options) => KeysBuilder();

class KeysBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.keys.yaml': ['.keys.g.dart'],
    '.keys.yml': ['.keys.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final generated = await _generate(buildStep);
    if (generated.isEmpty) {
      return;
    }

    final outputId = inputId.changeExtension('.g.dart');
    await buildStep.writeAsString(outputId, generated);
  }

  FutureOr<String> _generate(BuildStep buildStep) async {
    final path = buildStep.inputId.path;
    if (!path.endsWith('.keys.yml') && !path.endsWith('.keys.yaml')) {
      return '';
    }

    final baseName = buildStep.inputId.pathSegments.last
        .replaceAll('.keys.yaml', '')
        .replaceAll('.keys.yml', '');
    final className = '${_capitalize(_toCamelCase(baseName))}Keys';

    final inputId = buildStep.inputId;
    final content = await buildStep.readAsString(inputId);
    final yamlMap = loadYaml(content) as YamlMap;

    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND\n');

    final classes = _generateClasses(className, yamlMap, '');
    for (final c in classes) {
      buffer.writeln(c);
    }

    return buffer.toString();
  }

  List<String> _generateClasses(String className, YamlMap map, String currentPath) {
    final mainBuffer = StringBuffer();
    final nestedClasses = <String>[];
    final fields = <String>[];

    map.forEach((key, value) {
      final fullPath = currentPath.isEmpty ? key : '$currentPath.$key';
      final camelCaseKey = _toCamelCase(key);

      if (value is YamlMap) {
        final nestedClassName = '_${_capitalize(_toCamelCase(key))}Keys';
        fields.add('  final $nestedClassName $camelCaseKey = const $nestedClassName._();');
        final nested = _generateClasses(nestedClassName, value, fullPath);
        nestedClasses.addAll(nested);
      } else if (value is String) {
        fields.add('  /// $value');
        fields.add("  final String $camelCaseKey = const '$fullPath';");
      }
    });

    mainBuffer.writeln('class $className {');
    mainBuffer.writeln('  const $className._();');

    // Добавляем i только для корневого класса
    if (currentPath.isEmpty) {
      mainBuffer.writeln('  static const $className i = const $className._();');
    }

    for (final field in fields) {
      mainBuffer.writeln(field);
    }
    mainBuffer.writeln('}');

    return [mainBuffer.toString(), ...nestedClasses];
  }

  String _toCamelCase(String input) {
    final parts = input.split('_');
    return parts.first + parts.skip(1).map((s) => s[0].toUpperCase() + s.substring(1)).join('');
  }

  String _capitalize(String input) => input[0].toUpperCase() + input.substring(1);
}
