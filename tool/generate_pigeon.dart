import 'dart:io';

Future<void> main() async {
  final packageRoot = Directory.fromUri(Platform.script.resolve('../'));

  Future<bool> run(List<String> arguments) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: packageRoot.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result == 0) return true;
    exitCode = result;
    return false;
  }

  if (!await run(['run', 'pigeon', '--input', 'pigeon/message.dart'])) return;
  if (!await run(['format', 'lib/core/pigeon/messages.g.dart'])) return;

  // Normalize our generated bindings without changing upstream templates.
  for (final path in const [
    'lib/core/pigeon/messages.g.dart',
    'android/app/src/main/kotlin/net/yuandev/onexray/pigeon/Messages.g.kt',
    'swift/App/pigeon/Messages.g.swift',
  ]) {
    final file = File.fromUri(packageRoot.uri.resolve(path));
    final source = await file.readAsString();
    final normalized = source
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n');
    if (normalized != source) await file.writeAsString(normalized);
  }
}
