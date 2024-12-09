import 'dart:async';

import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

/// Provides an instance of [KeysBuilder] as a [Builder].
///
/// This function is invoked by the build system to instantiate the [KeysBuilder].
/// It accepts [BuilderOptions] as a parameter, allowing for potential configuration
/// of the builder if necessary.
Builder keysBuilder(BuilderOptions options) => KeysBuilder();

/// A [Builder] that transforms `.keys.yaml` or `.keys.yml` files into Dart code.
///
/// The [KeysBuilder] processes YAML files defining hierarchical keys used for
/// localization, configuration, or other resource-driven purposes. Each `.keys.yaml`
/// or `.keys.yml` file is converted into a Dart file containing a class hierarchy
/// that mirrors the structure of the YAML. Every key in the YAML file is exposed
/// as a static field or a nested class, enabling developers to reference them
/// directly in their Dart code.
///
/// **Example Usage:**
///
/// Consider a YAML file named `app.keys.yaml`:
/// ```yaml
/// _doc_: "Top-level documentation for these keys."
/// title: "App Title"
/// messages:
///   _doc_: "Keys for messages displayed in the UI."
///   hello: "Hello, World!"
///   goodbye: "Goodbye!"
/// ```
///
/// After running the builder, a Dart file `app.keys.dart` will be generated with the following content:
///
/// ```dart
/// // GENERATED CODE - DO NOT MODIFY BY HAND
/// class AppKeys {
///   const AppKeys._();
///   static final AppKeys i = AppKeys._();
///
///   /// App Title
///   String get title => 'app.title';
///
///   /// {@template app.messages}
///   /// Keys for messages displayed in the UI.
///   /// {@endtemplate}
///   _AppMessagesKeys get messages => const _AppMessagesKeys._();
/// }
///
/// class _AppMessagesKeys {
///   const _AppMessagesKeys._();
///
///   /// Hello, World!
///   String get hello => 'app.messages.hello';
///
///   /// Goodbye!
///   String get goodbye => 'app.messages.goodbye';
/// }
/// ```
///
/// **Note:** The underscore prefix in the names of generated nested classes ensures they
/// do not conflict with top-level classes and minimizes the risk of naming collisions.
class KeysBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.keys.yaml': ['.keys.dart'],
    '.keys.yml': ['.keys.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Generate the Dart code from the provided YAML file.
    final result = await _generate(buildStep);

    // If no code was generated (e.g., the file is empty or invalid), skip writing.
    if (result.isEmpty) return;

    // Write the generated Dart code to the corresponding .dart file.
    await buildStep.writeAsString(buildStep.inputId.changeExtension('.dart'), result);
  }

  /// Reads the input YAML file, parses it, and generates the corresponding Dart classes.
  ///
  /// This method identifies valid key files (those ending with `.keys.yaml` or
  /// `.keys.yml`), extracts the base name for class naming, and delegates to
  /// [_generateClassesIterative] to construct the class hierarchy.
  ///
  /// Returns an empty string if the input file does not match the expected pattern
  /// or contains no content.
  Future<String> _generate(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final path = inputId.path;

    // Only process `.keys.yaml` or `.keys.yml` files.
    if (!path.endsWith('.keys.yml') && !path.endsWith('.keys.yaml')) return '';

    // Derive the base name from the input file name.
    final baseName =
        inputId.pathSegments.last.replaceAll('.keys.yaml', '').replaceAll('.keys.yml', '');

    // Convert the base name into a class name by capitalizing and appending "Keys".
    final className = '${_capitalize(_toCamelCase(baseName))}Keys';

    // Read and parse the YAML content.
    final content = await buildStep.readAsString(inputId);
    if (content.trim().isEmpty) {
      return '';
    }
    final yamlMap = loadYaml(content) as YamlMap;

    // Generate classes using an iterative approach (avoiding recursion).
    final classes = _generateClassesIterative(
      className: className,
      map: yamlMap,
      scope: baseName,
    );

    // Prepare the final output buffer.
    final buffer = StringBuffer()..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND\n');
    for (final classDefinition in classes) {
      buffer.writeln(classDefinition);
    }

    return buffer.toString();
  }

  /// Iteratively generates Dart classes and their fields from a YAML map.
  ///
  /// Unlike a recursive approach, this method uses a stack to manage nested
  /// structures. Each [ClassInfo] object on the stack represents a class to
  /// generate.
  ///
  /// **Parameters:**
  /// - [className]: The name of the root class.
  /// - [map]: The parsed YAML map representing the keys.
  /// - [scope]: The top-level scope of the keys, typically derived from the base file name.
  ///
  /// **Returns:**
  /// A list of strings, each representing a Dart class definition.
  List<String> _generateClassesIterative({
    required String className,
    required YamlMap map,
    required String scope,
  }) {
    // Initialize a stack with the root class information.
    final stack = <ClassInfo>[];
    stack.add(
      ClassInfo(
        className: className,
        map: map,
        scope: scope,
        currentPath: '',
        docTemplateName: '',
      ),
    );

    // Accumulate all class definitions here.
    final allClasses = <String>[];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final generated = _generateClassFromInfo(current);

      // Add any nested classes to the stack for processing.
      stack.addAll(generated.nestedClasses);

      // Add the current class definition to the list.
      allClasses.add(generated.classString);
    }

    return allClasses.toList();
  }

  /// Generates a Dart class definition from the given [ClassInfo].
  ///
  /// This method constructs the class structure, including fields and nested
  /// classes, based on the provided YAML map and class information.
  ///
  /// **Returns:**
  /// A tuple containing the class definition as a string and any nested classes
  /// that need to be generated.
  ({
    String classString,
    Iterable<ClassInfo> nestedClasses,
  }) _generateClassFromInfo(ClassInfo current) {
    final classBuffer = StringBuffer();
    final classFields = <String>[];

    // Extract optional documentation from the "_doc_" key.
    final docComment = current.map['_doc_'] is String ? current.map['_doc_'] as String : null;
    final nestedClassesScoped = <ClassInfo>[];

    // Iterate through the keys in the current YAML map.
    current.map.forEach((key, value) {
      if (key == '_doc_') return; // Skip documentation keys from field generation.

      // Compute the full path for nested keys, e.g., "app.messages.hello"
      final fullPath = current.currentPath.isEmpty ? key : '${current.currentPath}.$key';
      final variableValue = current.scope.isNotEmpty ? '${current.scope}.$fullPath' : fullPath;

      // Generate a template name for documentation, using camelCase.
      final templateName = _toCamelCase(variableValue, '.');
      final camelKey = _toCamelCase(key);

      if (value is YamlMap) {
        // For nested YAML maps, generate a nested class.
        // Example: "messages.hello" becomes "_AppMessagesKeys" class.
        final classPath = fullPath.split('.').map(_capitalize).join('_');
        final nestedClassName = '_${_capitalize(_toCamelCase(classPath))}Keys';
        final nestedDoc = value['_doc_'];

        // Add a reference to the nested class as a getter.
        classFields.add(
          "${nestedDoc is String && nestedDoc.isNotEmpty ? '\n  /// $nestedDoc\n' : ''}"
          "  $nestedClassName get $camelKey => const $nestedClassName._();",
        );

        // Push the nested class onto the stack for later processing.
        nestedClassesScoped.add(
          ClassInfo(
            className: nestedClassName,
            map: value,
            scope: current.scope,
            currentPath: fullPath,
            docTemplateName: templateName,
          ),
        );
      } else {
        // For terminal string values, create a property returning the key string.
        classFields.add(
          "${value is String && value.isNotEmpty ? '\n  /// $value\n' : ''}"
          "  String get $camelKey => '$variableValue';",
        );
      }
    });

    // If there is a doc comment and a doc template name, wrap it in a doc template.
    if (docComment != null) {
      classBuffer.writeln('/// $docComment');
    }

    // Define the class with a private constructor.
    classBuffer
      ..writeln('class ${current.className} {')
      ..writeln('  const ${current.className}._();');

    // For the root class, provide a static singleton instance.
    if (current.currentPath.isEmpty) {
      classBuffer.writeln('  static final ${current.className} i = ${current.className}._();');
    }

    // Append all generated fields to the class.
    for (final field in classFields) {
      classBuffer.writeln(field);
    }

    classBuffer.writeln('}');

    // Return the class definition and any nested classes.
    return (
      classString: classBuffer.toString(),
      nestedClasses: nestedClassesScoped,
    );
  }

  /// Converts a string to camelCase. By default, splits on underscores (`_`),
  /// but a custom separator can be provided.
  ///
  /// **Examples:**
  /// - `_toCamelCase("my_example")` returns `"myExample"`
  /// - `_toCamelCase("my.example", ".")` returns `"myExample"`
  String _toCamelCase(String input, [String sep = '_']) {
    final parts = input.split(sep);
    if (parts.isEmpty) return '';
    final head = parts.first;
    final tail = parts.skip(1).map((s) {
      if (s.isEmpty) return '';
      return s[0].toUpperCase() + s.substring(1);
    }).join('');
    return head + tail;
  }

  /// Capitalizes the first character of a string.
  ///
  /// **Example:**
  /// - `_capitalize("example")` returns `"Example"`
  String _capitalize(String input) {
    if (input.isEmpty) return '';
    return input[0].toUpperCase() + input.substring(1);
  }
}

/// A helper class used during iterative class generation.
///
/// Each [ClassInfo] instance represents a single class to be generated, along with the
/// necessary context and metadata. This includes the class name, the subset of the
/// YAML map it represents, the current key path, and any associated documentation.
class ClassInfo {
  /// The name of the Dart class to be generated.
  final String className;

  /// The portion of the YAML map representing this class and its fields.
  final YamlMap map;

  /// The top-level scope (usually the base file name) used to prefix keys.
  final String scope;

  /// The current hierarchical path of keys leading to this class.
  final String currentPath;

  /// The template name used for documentation comments, enabling reusability of doc templates
  /// in nested classes.
  final String docTemplateName;

  /// Constructs a [ClassInfo] instance with the provided parameters.
  ClassInfo({
    required this.className,
    required this.map,
    required this.scope,
    required this.currentPath,
    required this.docTemplateName,
  });
}
