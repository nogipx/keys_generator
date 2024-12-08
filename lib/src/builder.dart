import 'dart:async';
import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

/// Returns an instance of [KeysBuilder] as a [Builder].
Builder keysBuilder(BuilderOptions options) => KeysBuilder();

/// A [Builder] that transforms `.keys.yaml` or `.keys.yml` files into Dart code.
/// It generates Dart classes with nested structures based on the YAML keys.
/// Each key in the YAML file corresponds to a Dart property or nested class,
/// allowing you to reference keys in code as static fields.
///
/// Usage:
/// - Place a YAML file ending with `.keys.yaml` or `.keys.yml`.
/// - Run the build system (build_runner) to generate a corresponding `.keys.dart` file.
/// - The generated file will contain a class (and possibly nested classes) with fields
///   mirroring your YAML structure. Each field holds a string key suitable for localization,
///   configuration, or resource management.
class KeysBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.keys.yaml': ['.keys.dart'],
    '.keys.yml': ['.keys.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Generate the Dart code from the given YAML file.
    final result = await _generate(buildStep);
    // If no code was generated (e.g., invalid file extension), skip writing.
    if (result.isEmpty) return;
    // Write the generated Dart code into a .dart file.
    await buildStep.writeAsString(buildStep.inputId.changeExtension('.dart'), result);
  }

  /// Generates the Dart code by reading the input YAML file, parsing its structure,
  /// and then invoking [_generateClasses] to produce classes and fields.
  ///
  /// Returns an empty string if the file is not a recognized keys file.
  Future<String> _generate(BuildStep buildStep) async {
    final id = buildStep.inputId;
    final path = id.path;

    // Only process files that end with .keys.yaml or .keys.yml
    if (!path.endsWith('.keys.yml') && !path.endsWith('.keys.yaml')) return '';

    // Extract the base name of the file by removing the .keys.yaml/.keys.yml part.
    final baseName = id.pathSegments.last.replaceAll('.keys.yaml', '').replaceAll('.keys.yml', '');

    // Convert the base name into a class name in PascalCase, appending "Keys".
    final className = '${_capitalize(_toCamelCase(baseName))}Keys';

    // Read and parse the YAML content into a YamlMap.
    final yamlMap = loadYaml(await buildStep.readAsString(id)) as YamlMap;

    // Generate a list of classes (the main class and any nested classes).
    final classes = _generateClasses(
      className: className,
      map: yamlMap,
      scope: '$baseName.keys',
    );

    // Create a buffer for the generated Dart code.
    final buffer = StringBuffer()..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND\n');
    for (final c in classes) {
      buffer.writeln(c);
    }

    return buffer.toString();
  }

  /// Recursively generates Dart classes and their fields from the given [map].
  ///
  /// Parameters:
  /// - [className]: The name of the class being generated.
  /// - [map]: The YamlMap representing the keys and possibly nested maps.
  /// - [scope]: A string representing the hierarchical path of keys, used to generate unique values.
  /// - [currentPath]: Tracks the current path of nested keys. For top-level, this is empty.
  /// - [docTemplateName]: If doc comments (templates) are present, this name helps identify them.
  ///
  /// The method returns a list of class definitions as strings.
  /// The first item is the current class definition, followed by any nested classes.
  List<String> _generateClasses({
    required String className,
    required YamlMap map,
    required String scope,
    String currentPath = '',
    String docTemplateName = '',
  }) {
    final mainBuffer = StringBuffer();
    final nestedClasses = <String>[];
    final fields = <String>[];

    // If the YAML map has a "_doc_" key, treat it as documentation for this class.
    final docComment = map['_doc_'] is String ? map['_doc_'] as String : null;

    // Iterate over each key in the YAML map.
    // If the value is another map, we create a nested class.
    // If the value is a string, we create a string field.
    map.forEach((key, value) {
      if (key == '_doc_') return; // Skip doc key from generating fields.

      final fullPath = currentPath.isEmpty ? key : '$currentPath.$key';
      final variableValue = scope.isNotEmpty ? '$scope.$fullPath' : fullPath;
      // Convert the full path into a template name for documentation placeholders.
      final templateName = _toCamelCase(variableValue, '.');
      final camelKey = _toCamelCase(key);

      if (value is YamlMap) {
        // For nested maps, we create a nested class.
        // The nested class name is derived by capitalizing each part of the path.
        final classPath = fullPath.split('.').map(_capitalize).join('_');
        final nestedClassName = '_${_capitalize(_toCamelCase(classPath))}Keys';

        // Add a reference field to the nested class instance.
        fields.add('  /// {@macro $templateName}');
        fields.add('  final $nestedClassName $camelKey = $nestedClassName._();');

        // Recursively generate the nested classes.
        nestedClasses.addAll(_generateClasses(
          className: nestedClassName,
          docTemplateName: templateName,
          map: value,
          currentPath: fullPath,
          scope: scope,
        ));
      } else if (value is String) {
        // For strings, we create a string field that holds the generated key path.
        fields.add('  /// $value');
        fields.add("  final $camelKey = '$variableValue';");
      }
    });

    // If we have a doc comment and a template name, wrap it in a doc template.
    if (docComment != null && docTemplateName.isNotEmpty) {
      mainBuffer
        ..writeln('/// {@template $docTemplateName}')
        ..writeln('/// $docComment')
        ..writeln('/// {@endtemplate}');
    }

    // Define the class, starting with its constructor and static instance if top-level.
    mainBuffer
      ..writeln('class $className {')
      ..writeln('  $className._();');

    // For the root class (no currentPath), add a static instance.
    if (currentPath.isEmpty) {
      mainBuffer.writeln('  static final $className i = $className._();');
    }

    // Add all generated fields to the class.
    for (final field in fields) {
      mainBuffer.writeln(field);
    }

    mainBuffer.writeln('}');

    // Return this class's definition along with any nested classes.
    return [mainBuffer.toString(), ...nestedClasses];
  }

  /// Converts a string to camelCase, using [sep] as a separator to split words.
  ///
  /// For example:
  /// - `_toCamelCase("my_example")` -> "myExample"
  /// - `_toCamelCase("my.example", ".")` -> "myExample"
  String _toCamelCase(String input, [String sep = '_']) {
    final parts = input.split(sep);
    if (parts.isEmpty) return '';
    final head = parts.first;
    final tail =
        parts.skip(1).map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join('');
    return head + tail;
  }

  /// Capitalizes the first letter of the given string.
  ///
  /// For example: `_capitalize("example")` -> "Example".
  String _capitalize(String input) =>
      input.isEmpty ? '' : input[0].toUpperCase() + input.substring(1);
}
