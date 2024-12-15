import 'package:args/args.dart';
import 'package:keys_generator/src/augment_arb.dart';
import 'dart:convert';
import 'dart:io';

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

  // Extract the base name of the file without the extension.
  final scope = Uri.parse(yamlPath)
      .pathSegments
      .last
      .replaceAll('.keys.yaml', '')
      .replaceAll('.keys.yml', '');

  try {
    augmentArbFromYaml(yamlPath, outputPath, scope);

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
