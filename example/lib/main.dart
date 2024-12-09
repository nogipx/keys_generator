import 'dart:developer' as developer;

import 'package:example/example.keys.dart';
import 'package:example/example_nodoc.keys.dart';

Future<void> main() async {
  final info = await developer.Service.getInfo();
  print(info.serverUri);
  await Future.delayed(const Duration(seconds: 10));

  const max = 100000;
  var i = 0;
  while (i < max) {
    _printExample();
    _printExampleNodoc();
    await Future.delayed(const Duration(milliseconds: 5));
    i++;
  }
}

void _printExample() {
  [
    ExampleKeys.i.title,
    ExampleKeys.i.group.list.requiredDate,
    ExampleKeys.i.group.list.requiredMoney,
    ExampleKeys.i.map.requiredDate,
    ExampleKeys.i.map.requiredMoney,
  ].forEach(print);
}

void _printExampleNodoc() {
  [
    ExampleNodocKeys.i.title,
    ExampleNodocKeys.i.group.list.requiredDate,
    ExampleNodocKeys.i.group.list.requiredMoney,
    ExampleNodocKeys.i.map.requiredDate,
    ExampleNodocKeys.i.map.requiredMoney,
  ].forEach(print);
}
