// GENERATED CODE - DO NOT MODIFY BY HAND (keys_generator)
// SOURCE YAML - package:example/example.keys.yml
// ignore_for_file: library_private_types_in_public_api

/// Dartdoc for entrypoint instance
class ExampleKeys {
  const ExampleKeys._();
  static const ExampleKeys i = ExampleKeys._();

  /// Top-level keys (example.title)
  String get title => 'example_title';
  _ExampleTestSnakeKeys get testSnake => const _ExampleTestSnakeKeys._();
  _ExampleGroupKeys get group => const _ExampleGroupKeys._();

  /// Map-based dartdoc for group of keys (example.map)
  _ExampleMapKeys get map => const _ExampleMapKeys._();
}

/// Map-based dartdoc for group of keys (example.map)
class _ExampleMapKeys {
  const _ExampleMapKeys._();

  /// Map-based dartdoc for particular key (example.map.required_date)
  String get requiredDate => 'example_map_requiredDate';
  String get requiredMoney => 'example_map_requiredMoney';
}

class _ExampleGroupKeys {
  const _ExampleGroupKeys._();

  /// List-based dartdoc for group of keys (example.group.list)
  _ExampleGroupListKeys get list => const _ExampleGroupListKeys._();
}

/// List-based dartdoc for group of keys (example.group.list)
class _ExampleGroupListKeys {
  const _ExampleGroupListKeys._();

  /// List-based dartdoc for particular key (example.group.list.required_date)
  String get requiredDate => 'example_group_list_requiredDate';
  String get requiredMoney => 'example_group_list_requiredMoney';
}

class _ExampleTestSnakeKeys {
  const _ExampleTestSnakeKeys._();

  /// Some value
  String get snakeStr1 => 'example_testSnake_snakeStr1';
}

