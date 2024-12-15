import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

void augmentArbFromYaml(String yamlPath, String arbPath, String scope) {
  final yamlFile = File(yamlPath);
  if (!yamlFile.existsSync()) {
    throw Exception('YAML file not found: $yamlPath');
  }

  final arbFile = File(arbPath);
  if (!arbFile.existsSync()) {
    arbFile.createSync(recursive: true);
  }

  // Читаем старый ARB
  LinkedHashMap<String, dynamic> oldArb;
  final content = arbFile.readAsStringSync();
  oldArb = content.trim().isNotEmpty
      ? LinkedHashMap.from(jsonDecode(content))
      : LinkedHashMap();

  // Преобразуем YAML в структуры Dart
  final yamlRoot = loadYaml(yamlFile.readAsStringSync());
  dynamic yamlToDart(dynamic yaml) {
    if (yaml is YamlMap) {
      final map = LinkedHashMap<String, dynamic>();
      for (var key in yaml.keys) {
        map[key.toString()] = yamlToDart(yaml[key]);
      }
      return map;
    } else if (yaml is YamlList) {
      return yaml.map(yamlToDart).toList();
    } else {
      return yaml; // скаляр
    }
  }

  final parsedYaml = yamlToDart(yamlRoot);

  // Начинаем с копии oldArb, чтобы сохранить все старые ключи и значения
  final newArb = LinkedHashMap<String, dynamic>.from(oldArb);

  // @@locale
  if (!newArb.containsKey('@@locale')) {
    newArb['@@locale'] = oldArb['@@locale'] ?? '';
  }

  String toCamelCase(String segment) {
    final parts = segment.split('_');
    if (parts.isEmpty) return segment;
    final first = parts.first.toLowerCase();
    final rest = parts.skip(1).map((p) {
      final lower = p.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    });
    return [first, ...rest].join('');
  }

  final targetScope = toCamelCase(scope);

  String camelCaseKey(String key) {
    if (key.isEmpty) return key;
    final segments = key.split('.');
    final camelSegments = segments.map(toCamelCase).toList();
    return camelSegments.join('.');
  }

  /// Добавляем или обновляем ключ.
  /// Если ключ уже есть, не трогаем его значение, только описание обновляем при наличии нового.
  /// Если ключа нет, добавляем со значением "".
  /// Если есть описание - добавляем/обновляем @key.
  void ensureKeyAndDescription(String rawKey, String? newDesc) {
    final finalKey = '$targetScope.${camelCaseKey(rawKey)}';

    // Если ключа нет - добавляем его с пустым значением.
    if (!newArb.containsKey(finalKey)) {
      newArb[finalKey] = "";
    }

    // Обновляем описание, только если есть новое описание.
    if (newDesc != null && newDesc.trim().isNotEmpty) {
      newArb['@$finalKey'] = {"description": newDesc.trim()};
    }
    // Если описание не указано, но уже было в oldArb, мы его сохраняем как есть.
  }

  void processNode(dynamic node, String prefix) {
    if (node is Map<String, dynamic>) {
      final keys = node.keys.where((k) => k != '_doc_').toList();
      for (var k in keys) {
        final val = node[k];
        final newPrefix = prefix.isEmpty ? k : '$prefix.$k';
        if (val is String) {
          final strVal = val.trim();
          if (strVal.isEmpty || strVal.startsWith('//')) {
            // Игнорируем
          } else if (strVal.contains(' // ')) {
            // "value // desc"
            final parts = strVal.split(' // ');
            final descPart = parts[1].trim();
            ensureKeyAndDescription(newPrefix, descPart);
          } else {
            // Просто значение (описание)
            ensureKeyAndDescription(newPrefix, strVal);
          }
        } else if (val is Map || val is List) {
          processNode(val, newPrefix);
        } else {
          // Скаляр
          ensureKeyAndDescription(newPrefix, null);
        }
      }
    } else if (node is List) {
      for (var item in node) {
        if (item is String) {
          final strItem = item.trim();
          if (strItem.isEmpty || strItem.startsWith('//')) {
            // Игнорируем групповые комментарии
            continue;
          }
          if (strItem.contains(' // ')) {
            // "key // desc"
            final parts = strItem.split(' // ');
            final keyPart = parts[0].trim();
            final descPart = parts[1].trim();
            final finalKey = prefix.isEmpty ? keyPart : '$prefix.$keyPart';
            ensureKeyAndDescription(finalKey, descPart);
          } else {
            // Просто ключ
            final finalKey = prefix.isEmpty ? strItem : '$prefix.$strItem';
            ensureKeyAndDescription(finalKey, null);
          }
        } else if (item is Map || item is List) {
          processNode(item, prefix);
        } else {
          // Скаляры без ключей игнорируем
        }
      }
    } else if (node is String) {
      final strNode = node.trim();
      if (strNode.isEmpty || strNode.startsWith('//')) {
        // Игнорируем
      } else if (strNode.contains(' // ')) {
        final parts = strNode.split(' // ');
        final keyPart = parts[0].trim();
        final descPart = parts[1].trim();
        final finalKey = prefix.isEmpty ? keyPart : '$prefix.$keyPart';
        ensureKeyAndDescription(finalKey, descPart);
      } else {
        // Просто ключ
        final finalKey = prefix.isEmpty ? strNode : '$prefix.$strNode';
        ensureKeyAndDescription(finalKey, null);
      }
    } else {
      // Скаляры игнорируем
    }
  }

  if (parsedYaml != null) {
    processNode(parsedYaml, "");
  }

  // Мы не удаляем старые ключи и не сортируем их.
  // Порядок остаётся таким, в каком они были в oldArb + новые ключи добавятся в порядке обхода YAML в конец.

  // Однако в текущей реализации новые ключи будут добавляться в конец,
  // так как LinkedHashMap сохраняет порядок добавления ключей.
  // Если ключ уже существовал, его позиция не меняется, мы просто обновляем описание.
  // Если ключ новый, он добавляется в конец.

  final encoder = JsonEncoder.withIndent('  ');
  final formattedContent = encoder.convert(newArb);
  arbFile.writeAsStringSync(formattedContent);

  print(
      'ARB successfully generated with camelCase keys, preserving old keys and values: $arbPath');
}
