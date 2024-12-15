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
    generateArbFromYaml(yamlPath, outputPath);
    if (formatArb) {
      formatArbFile(outputPath);
    }
  } catch (e) {
    print('Error while generation ARB: $e');
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

/// Генерация ARB из YAML, преобразуя списки и мапы с учётом комментариев
void generateArbFromYaml(String yamlPath, String arbPath) {
  final yamlFile = File(yamlPath);
  if (!yamlFile.existsSync()) {
    throw Exception('YAML file not found for generation ARB: $yamlPath');
  }

  final yamlContent = loadYaml(yamlFile.readAsStringSync());
  final arbContent = <String, dynamic>{};

  // Добавляем локаль
  arbContent['@@locale'] = '';

  /// Рекурсивная функция для обработки YAML
  void processYaml(dynamic input, Map<String, dynamic> arb,
      [String? parentDoc]) {
    if (input is Map) {
      // Если есть _doc_, добавляем описание для группы
      if (input.containsKey('_doc_')) {
        arb['@'] = {'description': input['_doc_']};
      }

      input.forEach((key, value) {
        if (key == '_doc_') return; // Пропускаем служебный ключ
        if (value is Map || value is List) {
          final nested = <String, dynamic>{};
          arb[key] = nested;
          processYaml(value, nested, value is Map ? value['_doc_'] : null);
        } else {
          arb[key] = ""; // Добавляем ключ с пустым значением
          if (value is String && value.trim().isNotEmpty) {
            arb['@$key'] = {'description': value};
          }
        }
      });
    } else if (input is List) {
      // Обработка List
      final nested = <String, dynamic>{};
      if (parentDoc != null) {
        arb['@'] = {'description': parentDoc};
      }
      for (var item in input) {
        if (item is String && item.startsWith('//')) {
          parentDoc = item.substring(2).trim();
          arb['@'] = {'description': parentDoc};
        } else if (item is String && item.contains(' // ')) {
          final parts = item.split(' // ');
          final key = parts[0].trim();
          final description = parts[1].trim();
          nested[key] = "";
          nested['@$key'] = {'description': description};
        } else if (item is String) {
          nested[item] = "";
        }
      }
      arb.addAll(nested);
    }
  }

  processYaml(yamlContent, arbContent);

  // Записываем результат в JSON
  final encoder = JsonEncoder.withIndent('  ');
  final formattedContent = encoder.convert(arbContent);
  final arbFile = File(arbPath);
  arbFile.writeAsStringSync(formattedContent);
  print('ARB successfully generated: $arbPath');
}
