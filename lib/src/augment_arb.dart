// ignore_for_file: prefer_collection_literals

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Генерация или аугментация ARB из YAML
void augmentArbFromYaml(String yamlPath, String arbPath) {
  final yamlFile = File(yamlPath);
  if (!yamlFile.existsSync()) {
    throw Exception('YAML file not found for augment ARB: $yamlPath');
  }

  final arbFile = File(arbPath);
  LinkedHashMap<String, dynamic> arbContent = LinkedHashMap();

  if (!arbFile.existsSync()) {
    arbFile.createSync(recursive: true);
  }

  // Если ARB файл существует, читаем его содержимое
  final content = arbFile.readAsStringSync();
  arbContent = content.isNotEmpty
      ? LinkedHashMap.from(jsonDecode(content))
      : LinkedHashMap();

  // Устанавливаем локаль, если её нет
  if (!arbContent.containsKey('@@locale')) {
    arbContent['@@locale'] = '';
  }

  final yamlContent = loadYaml(yamlFile.readAsStringSync());

  /// Конвертирует YamlMap в Map<String, dynamic>
  dynamic yamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      return LinkedHashMap<String, dynamic>.fromEntries(
        yaml.entries.map(
          (e) => MapEntry(
            e.key.toString(),
            yamlToMap(e.value), // Рекурсивное преобразование значений
          ),
        ),
      );
    } else if (yaml is YamlList) {
      return yaml.map(yamlToMap).toList(); // Преобразуем список рекурсивно
    } else {
      return yaml; // Для скалярных значений возвращаем их напрямую
    }
  }

  /// Основной парсинг YAML в структуру
  final parsedYaml = yamlToMap(yamlContent);

  /// Рекурсивная функция для обработки YAML и дополнения ARB
  void processYaml(
      dynamic input, LinkedHashMap<String, dynamic> arb, List<String> keyOrder,
      [String? parentDoc]) {
    if (input is Map<String, dynamic>) {
      // Если есть _doc_, добавляем описание для группы, если его ещё нет
      if (input.containsKey('_doc_') && !arb.containsKey('@')) {
        arb['@'] = {'description': input['_doc_']};
      }

      input.forEach((key, value) {
        if (key == '_doc_') return; // Пропускаем служебный ключ
        if (value is Map<String, dynamic> || value is List) {
          // Если вложенный объект, добавляем его и рекурсивно обрабатываем
          if (!arb.containsKey(key)) {
            arb[key] = LinkedHashMap<String, dynamic>();
          }
          if (!keyOrder.contains(key)) {
            keyOrder.add(key);
          }
          processYaml(
            value,
            (arb[key] as LinkedHashMap<String, dynamic>),
            keyOrder,
            value is Map<String, dynamic> ? value['_doc_'] : null,
          );
        } else {
          // Если ключ отсутствует, добавляем его с пустым значением
          if (!arb.containsKey(key)) {
            arb[key] = ""; // Добавляем ключ с пустым значением
          }
          if (!keyOrder.contains(key)) {
            keyOrder.add(key);
          }
          // Если описание отсутствует, добавляем его
          if (value is String &&
              value.trim().isNotEmpty &&
              !arb.containsKey('@$key')) {
            arb['@$key'] = {'description': value};
          }
        }
      });
    } else if (input is List) {
      if (parentDoc != null) {
        arb['@'] = {'description': parentDoc}; // Описание для группы списка
      }

      for (var item in input) {
        if (item is String) {
          if (item.startsWith('//')) {
            // Это комментарий для группы
            parentDoc = item
                .substring(2)
                .trim(); // Удаляем `//` и сохраняем как описание группы
            arb['@'] = {'description': parentDoc};
            continue;
          }

          if (item.contains(' // ')) {
            // Элемент с ключом и комментарием
            final parts = item.split(' // ');
            final key = parts[0].trim();
            final description = parts[1].trim();

            if (!arb.containsKey(key)) {
              arb[key] = ""; // Добавляем ключ с пустым значением
              arb['@$key'] = {'description': description}; // Добавляем описание
            }
            if (!keyOrder.contains(key)) {
              keyOrder.add(key);
            }
          } else if (item.trim().isNotEmpty) {
            // Элемент списка без комментария
            if (!arb.containsKey(item)) {
              arb[item] = ""; // Добавляем ключ с пустым значением
            }
            if (!keyOrder.contains(item)) {
              keyOrder.add(item);
            }
          }
        }
      }
    }
  }

  // Упорядочить ключи, включая существующие и новые
  List<String> keyOrder = [];

  // Добавляем порядок из YAML
  void collectKeys(dynamic yaml, List<String> order) {
    if (yaml is YamlMap) {
      for (var key in yaml.keys) {
        if (!order.contains(key.toString())) {
          order.add(key.toString());
        }
        collectKeys(yaml[key], order);
      }
    } else if (yaml is YamlList) {
      for (var item in yaml) {
        collectKeys(item, order);
      }
    }
  }

  collectKeys(yamlContent, keyOrder);

  // Добавляем порядок существующих ключей ARB
  for (var key in arbContent.keys) {
    if (!keyOrder.contains(key)) {
      keyOrder.add(key);
    }
  }

  processYaml(
      parsedYaml as LinkedHashMap<String, dynamic>, arbContent, keyOrder);

  // Сортировка ключей в соответствии с YAML и сохранение существующих
  LinkedHashMap<String, dynamic> sortKeys(
      LinkedHashMap<String, dynamic> arb, List<String> order) {
    final sorted = LinkedHashMap<String, dynamic>();

    // @@locale всегда должен быть первым
    if (arb.containsKey('@@locale')) {
      sorted['@@locale'] = arb['@@locale'];
    }

    for (var key in order) {
      if (arb.containsKey(key)) {
        sorted[key] = arb[key];
        if (arb.containsKey('@$key')) {
          sorted['@$key'] = arb['@$key'];
        }
      }
    }
    return sorted;
  }

  final sortedArbContent = sortKeys(arbContent, keyOrder);

  // Записываем результат в JSON
  final encoder = JsonEncoder.withIndent('  ');
  final formattedContent = encoder.convert(sortedArbContent);
  arbFile.writeAsStringSync(formattedContent);
  print('ARB successfully augmented and sorted: $arbPath');
}
