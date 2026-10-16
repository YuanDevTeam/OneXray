import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  const functions = {
    'CGoInvoke',
    'CGoFree',
    'VoleWindowsVpnInvoke',
    'VoleFree',
  };

  final generator = FfiGenerator(
    input: Input(
      entryPoints: [
        packageRoot.resolve('c/include/libXray.h'),
        packageRoot.resolve('c/include/vole.h'),
        packageRoot.resolve('c/include/vole_windows_uwp.h'),
      ],
      // Emit the Windows-only entry point on every generation host.
      compilerOptions: ['-D_WIN32'],
      appendCompilerOptions: true,
    ),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/core/ffi/generated_bindings.dart'),
      ),
      style: const DynamicLibraryBindings(
        wrapperName: 'NativeLibrary',
        wrapperDocComment: 'Generated native bindings for libXray and Vole.',
      ),
    ),
    visitors: [
      Visitor(
        func: (node) => node.isIncluded = functions.contains(node.originalName),
      ),
    ],
  );
  await generator.generate();
}
