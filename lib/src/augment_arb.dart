// ignore_for_file: prefer_collection_literals

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Аугментация ARB из YAML с учетом порядка ключей и комментариев для групп.
/// Порядок:
/// 1. На верхнем уровне @@locale всегда первый.
/// 2. Если есть описание для группы (arb['@']), оно идёт сразу после @@locale (если есть) или первым.
/// 3. Ключи в том порядке, в котором они указаны в YAML.
/// 4. Ключи, отсутствующие в YAML, но присутствующие в ARB, идут в конце, отсортированные по алфавиту.
/// 5. Описания для отдельных ключей (@$key) идут сразу после соответствующего ключа.
/// Если при повторной генерации изменится порядок ключей в YAML, порядок в ARB тоже изменится.

void augmentArbFromYaml(String yamlPath, String arbPath) {
  final yamlFile = File(yamlPath);
  if (!yamlFile.existsSync()) {
    throw Exception('YAML file not found: $yamlPath');
  }

  final arbFile = File(arbPath);
  if (!arbFile.existsSync()) {
    arbFile.createSync(recursive: true);
  }

  // Читаем ARB
  LinkedHashMap<String, dynamic> arbContent;
  final content = arbFile.readAsStringSync();
  arbContent = content.trim().isNotEmpty
      ? LinkedHashMap.from(jsonDecode(content))
      : LinkedHashMap();

  // Устанавливаем @@locale, если нет
  if (!arbContent.containsKey('@@locale')) {
    arbContent['@@locale'] = '';
  }

  // Читаем YAML
  final yamlRoot = loadYaml(yamlFile.readAsStringSync());

  /// Преобразуем YamlNode в обычные структуры Dart с сохранением порядка.
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

  /// Извлекает ключи из YAML-списка в порядке появления.
  List<String> extractKeysFromYamlList(List yamlList) {
    final result = <String>[];
    for (var item in yamlList) {
      if (item is String) {
        if (item.startsWith('//')) {
          continue; // комментарий
        }
        final key =
            item.contains(' // ') ? item.split(' // ')[0].trim() : item.trim();
        if (key.isNotEmpty && !key.startsWith('//')) {
          result.add(key);
        }
      } else if (item is Map || item is List) {
        // В списках вложенные структуры не добавляют ключи на этом уровне,
        // их порядок будет учтён рекурсивно при сортировке.
      }
    }
    return result;
  }

  /// Находим соответствующую YAML-структуру для ключа k в списке YAML
  dynamic findYamlForKeyInList(List yamlList, String k) {
    for (var item in yamlList) {
      if (item is Map && item.containsKey(k)) {
        return item[k];
      } else if (item is List) {
        // Если нужно более глубокое распознавание, можно добавить логику тут.
      }
    }
    return null;
  }

  /// Обрабатываем YAML для добавления/обновления ключей в ARB.
  /// Здесь же обрабатываем _doc_ и комментарии для групп, записывая их в arb['@'].
  void processYaml(dynamic yaml, LinkedHashMap<String, dynamic> arb,
      [String? parentDoc]) {
    if (yaml is Map<String, dynamic>) {
      // Если есть _doc_, добавляем описание для группы
      if (yaml.containsKey('_doc_') && !arb.containsKey('@')) {
        arb['@'] = {'description': yaml['_doc_']};
      }

      yaml.forEach((key, value) {
        if (key == '_doc_') return; // Пропускаем служебный ключ
        if (value is Map<String, dynamic> || value is List) {
          // Вложенная структура
          if (!arb.containsKey(key)) {
            arb[key] = LinkedHashMap<String, dynamic>();
          }
          processYaml(value, arb[key],
              value is Map<String, dynamic> ? value['_doc_'] : null);
        } else {
          // Скалярное значение - описание ключа
          if (!arb.containsKey(key)) {
            arb[key] = "";
          }
          if (value is String &&
              value.trim().isNotEmpty &&
              !arb.containsKey('@$key')) {
            arb['@$key'] = {'description': value};
          }
        }
      });
    } else if (yaml is List) {
      // Список
      String? currentParentDoc = parentDoc;
      if (parentDoc != null && !arb.containsKey('@')) {
        arb['@'] = {'description': parentDoc};
      }

      for (var item in yaml) {
        if (item is String) {
          if (item.startsWith('//')) {
            // Комментарий для группы
            currentParentDoc = item.substring(2).trim();
            arb['@'] = {'description': currentParentDoc};
            continue;
          }

          // "ключ // описание"
          if (item.contains(' // ')) {
            final parts = item.split(' // ');
            final key = parts[0].trim();
            final description = parts[1].trim();
            if (!arb.containsKey(key)) {
              arb[key] = "";
            }
            if (!arb.containsKey('@$key')) {
              arb['@$key'] = {'description': description};
            }
          } else if (item.trim().isNotEmpty) {
            // Просто ключ
            if (!arb.containsKey(item)) {
              arb[item] = "";
            }
          }
        } else {
          // Вложенная структура
          processYaml(item, arb, currentParentDoc);
        }
      }
    }
  }

  /// Рекурсивная сортировка ARB в соответствии с порядком из YAML.
  /// - @@locale на верхнем уровне всегда первый
  /// - Если есть описание группы arb['@'], оно идёт сразу после @@locale (если есть) или первым
  /// - Ключи из YAML в указанном порядке
  /// - Ключи, отсутствующие в YAML, по алфавиту в конце
  /// - Описания ключей (@$key) после ключей
  void sortArbAccordingToYaml(dynamic yaml, dynamic arb,
      {bool isTopLevel = false}) {
    if (arb is! Map<String, dynamic>) return;
    if (yaml is! Map && yaml is! List) return;

    final arbKeys =
        arb.keys.where((k) => !k.startsWith('@') && k != '@@locale').toList();
    final hasLocale = isTopLevel && arb.containsKey('@@locale');
    final hasGroupDoc = arb.containsKey('@'); // описание для самой группы

    List<String> yamlOrder = [];
    if (yaml is Map<String, dynamic>) {
      yamlOrder = yaml.keys
          .where((k) => k != '_doc_')
          .map((k) => k.toString())
          .toList();
    } else if (yaml is List) {
      yamlOrder = extractKeysFromYamlList(yaml);
    }

    final keysFromYaml = arbKeys.where((k) => yamlOrder.contains(k)).toList();
    final extraKeys = arbKeys.where((k) => !yamlOrder.contains(k)).toList();
    extraKeys.sort();

    // Формируем новый порядок
    final newOrder = <String>[];

    // @@locale всегда первый, если есть
    if (hasLocale) {
      newOrder.add('@@locale');
    }

    // @ для группы (описание группы), если есть
    // Добавляем сразу после @@locale или первым, если @@locale нет
    if (hasGroupDoc) {
      newOrder.add('@');
    }

    // Ключи из YAML в порядке их появления
    for (var yk in yamlOrder) {
      if (keysFromYaml.contains(yk)) {
        newOrder.add(yk);
      }
    }

    // Остальные ключи по алфавиту
    newOrder.addAll(extraKeys);

    // Пересобираем карту
    final newMap = LinkedHashMap<String, dynamic>();
    for (var k in newOrder) {
      newMap[k] = arb[k];
      if (k != '@' && arb.containsKey('@$k')) {
        // Описания для отдельных ключей
        newMap['@$k'] = arb['@$k'];
      }
    }

    arb
      ..clear()
      ..addAll(newMap);

    // Рекурсивная сортировка вложенных структур
    for (var k in newOrder) {
      // Если k - не @, то сортируем вложенные структуры
      if (k != '@') {
        sortArbAccordingToYaml(
          yaml is Map ? yaml[k] : findYamlForKeyInList(yaml, k),
          arb[k],
          isTopLevel: false,
        );
      }
    }
  }

  // Обновляем ARB на основе YAML
  processYaml(parsedYaml, arbContent);

  // Сортируем ARB согласно YAML
  sortArbAccordingToYaml(parsedYaml, arbContent, isTopLevel: true);

  // Записываем результат
  final encoder = JsonEncoder.withIndent('  ');
  final formattedContent = encoder.convert(arbContent);
  arbFile.writeAsStringSync(formattedContent);

  print('ARB successfully augmented and sorted: $arbPath');
}
