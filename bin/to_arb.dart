import 'package:args/args.dart';
import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

void main(List<String> args) {
  final parser = ArgParser();
  parser.addOption('yamlPath', abbr: 'f', mandatory: true);
  parser.addOption('outputPath', abbr: 'o', mandatory: true);
  parser.addFlag('formatArb', defaultsTo: true);

  final result = parser.parse(args);
  final yamlPath = result.option('yamlPath');
  final outputPath = result.option('outputPath');
  final formatArb = result.flag('formatArb');

  try {
    ArgumentError.checkNotNull(yamlPath, 'yamlPath');
    ArgumentError.checkNotNull(outputPath, 'outputPath');
  } on Object {
    print(parser.usage);
  }

  if (yamlPath!.isEmpty || outputPath!.isEmpty) {
    throw ArgumentError('Required fields empty');
  }

  try {
    augmentArbFromYaml(yamlPath, outputPath);

    if (formatArb) {
      formatArbFile(outputPath);
    }
  } catch (e, trace) {
    print('Error while generation ARB: $e');
    print(trace);
  }
}

void formatArbFile(String arbPath) {
  final arbFile = File(arbPath);

  if (!arbFile.existsSync()) {
    throw Exception('ARB file not found for formatting: $arbPath');
  }

  // Читаем содержимое ARB файла
  final content = arbFile.readAsStringSync();
  final jsonData = jsonDecode(content);

  // Форматируем JSON с отступами
  final encoder =
      JsonEncoder.withIndent('  '); // Используем 2 пробела для отступов
  final formattedContent = encoder.convert(jsonData);

  // Перезаписываем файл
  arbFile.writeAsStringSync(formattedContent);
  print('ARB successfully formatted: $arbPath');
}

/// Генерация или аугментация ARB из YAML
void augmentArbFromYaml(String yamlPath, String arbPath) {
  final yamlFile = File(yamlPath);
  if (!yamlFile.existsSync()) {
    throw Exception('YAML file not found for augment ARB: $yamlPath');
  }

  final arbFile = File(arbPath);
  Map<String, dynamic> arbContent = {};

  if (!arbFile.existsSync()) {
    arbFile.createSync(recursive: true);
  }

  // Если ARB файл существует, читаем его содержимое
  final content = arbFile.readAsStringSync();
  arbContent = content.isNotEmpty ? jsonDecode(content) : {};

  // Устанавливаем локаль, если её нет
  if (!arbContent.containsKey('@@locale')) {
    arbContent['@@locale'] = '';
  }

  final yamlContent = loadYaml(yamlFile.readAsStringSync());

  /// Конвертирует YamlMap в Map<String, dynamic>
  dynamic yamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      return Map<String, dynamic>.fromEntries(
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
  void processYaml(dynamic input, Map<String, dynamic> arb,
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
            arb[key] = {};
          }
          processYaml(
            value,
            (arb[key] as Map<dynamic, dynamic>).cast(),
            value is Map<String, dynamic> ? value['_doc_'] : null,
          );
        } else {
          // Если ключ отсутствует, добавляем его с пустым значением
          if (!arb.containsKey(key)) {
            arb[key] = ""; // Добавляем ключ с пустым значением
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
          } else if (item.trim().isNotEmpty) {
            // Элемент списка без комментария
            if (!arb.containsKey(item)) {
              arb[item] = ""; // Добавляем ключ с пустым значением
            }
          }
        }
      }
    }
  }

  processYaml(parsedYaml as Map<String, dynamic>, arbContent);

  // Записываем результат в JSON
  final encoder = JsonEncoder.withIndent('  ');
  final formattedContent = encoder.convert(arbContent);
  arbFile.writeAsStringSync(formattedContent);
  print('ARB successfully augmented: $arbPath');
}
