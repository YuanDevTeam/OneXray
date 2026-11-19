import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/launch/storage_preparation.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup creates a missing database and retains its initial signal',
    () async {
      final root = await Directory(
        '../references/onexray-refactor-validation/test-fixtures',
      ).absolute.create(recursive: true);
      final directory = await root.createTemp('startup-creation-');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _IsolatedPaths(directory.path);
      addTearDown(() async {
        await AppDatabase.resetAfterOpenFailure();
        PathProviderPlatform.instance = oldPaths;
        await directory.delete(recursive: true);
      });

      final file = await AppDatabase.databaseFile;
      expect(await file.exists(), isFalse);
      final ready = StoragePreparation.ensureReady();
      expect(StoragePreparation.ensureReady(), same(ready));
      expect(await ready, isTrue);
      expect(await file.exists(), isTrue);
      expect(
        (await AppDatabase().customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        10,
      );
      expect(await AppDatabase().subscriptionDao.allRows, isEmpty);
      expect(StoragePreparation.ensureReady(), same(ready));
      expect(await StoragePreparation.ensureReady(), isTrue);
    },
  );
}
