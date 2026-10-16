# Локальная среда разработки

[English](./FIRST_RUN.md) · [简体中文](./FIRST_RUN.zh_CN.md) · [Русский](./FIRST_RUN.ru.md)

Подготовьте одну платформу для Flutter Debug. Упаковка и публикация в магазинах
описаны в едином руководстве [Build and release](../build_scripts/README.md).

## 1. Инструменты и репозитории

Установите Flutter stable с Dart SDK, соответствующим [pubspec.yaml](../pubspec.yaml),
Git, Python 3.12+, Go согласно `go.mod` libXray и LLVM/libclang для FFI.
Добавьте Flutter, Go и каталог инструментов Go (`GOBIN`, иначе `GOPATH/bin`) в `PATH`.

| Платформа | Дополнительные требования |
| --- | --- |
| iOS / macOS | macOS, полный Xcode, SDK и среда нужного симулятора. |
| Android | Android SDK/NDK из [настроек Gradle](../android/app/build.gradle.kts) и JDK, совместимый с [Gradle wrapper](../android/gradle/wrapper/gradle-wrapper.properties). Задайте `ANDROID_HOME` и `ANDROID_NDK_HOME`. |
| Linux | Нативные инструменты Linux и пакеты GTK/плагинов ниже. |
| Windows | Нативная Windows, инструменты Visual Studio C++, Windows SDK, Rust, `uv` и инструменты Go/C нужной архитектуры; см. [подготовку Windows](../build_scripts/README.md#windows). |

В рабочем каталоге клонируйте только отсутствующие репозитории:

```shell
git clone https://github.com/YuanDevTeam/OneXray.git
git clone https://github.com/XTLS/libXray.git
cd OneXray
```

Репозитории должны быть соседними; для Windows нужен также Vole — см. [структуру каталогов](../build_scripts/README.md#prepare-the-workspace).
Все команды ниже выполняются из корня приложения. Совместимые версии зависимостей
определены в [Build workflow](../.github/workflows/build.yml); отдельный Xray-core
не нужен. Сначала проверьте `flutter doctor -v`. Выполняйте Flutter/Dart последовательно,
включая разные терминалы; перед генерацией/проверками остановите `flutter run`.

## 2. Нативные библиотеки и Geodata

Выполните только раздел своей платформы. Эти команды libXray подготавливают
нативные файлы и `../libXray/dat/`, но не публикуют приложение.

### iOS / macOS

```shell
python3 ../libXray/build/main.py apple go
rsync -a --delete ../libXray/LibXray.xcframework/ swift/All/LibXray.xcframework/
```

Заменяйте только этот сгенерированный framework, сохраняя остальные файлы `swift/All/`.
Apple использует SwiftPM: Podfile и `pod install` для настройки не нужны. Flutter
создаёт пакет плагинов; если SwiftPM отключён глобально, включите его командой
`flutter config --enable-swift-package-manager`.

### Android

```shell
python3 ../libXray/build/main.py android
mkdir -p android/app/libs
cp ../libXray/libXray.aar ../libXray/libXray-sources.jar android/app/libs/
```

В Windows используйте эквиваленты PowerShell. Приложение поддерживает arm64-v8a/x86_64;
локальный Debug использует debug keystore, без данных для загрузки в Play.

### Linux

В Debian/Ubuntu:

```shell
sudo apt-get install -y build-essential clang libclang-dev cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libblkid-dev libsecret-1-dev libayatana-appindicator3-dev libcap2-bin procps file
python3 ../libXray/build/main.py linux
mkdir -p linux/app
cp ../libXray/linux_so/libXray.so linux/app/
cp ../libXray/bin/xray linux/app/OneXrayCore
chmod +x linux/app/OneXrayCore
```

### Windows

Подготовьте полный нативный bundle по [руководству сборки](../build_scripts/README.md#windows).
Текущий комплект обоих режимов включает Core, Wintun и Vole; одного libXray недостаточно.
После подготовки `windows/app/` обычный Debug использует режим EXE.

### Скопируйте весь каталог Geodata

При ручной сборке копируйте JSON-индексы и временную метку вместе с `.dat`:

```shell
mkdir -p assets/dat
cp -R ../libXray/dat/. assets/dat/
```

В PowerShell выполните `New-Item -ItemType Directory -Force assets/dat`, затем
`Copy-Item ../libXray/dat/* assets/dat/ -Force`. Каталог исключён из Git; свежему клону
нужны эти встроенные данные. Скрипт упаковки уже копирует их. Архитектура нативных
файлов должна совпадать с приложением.

## 3. Генерация и запуск

```shell
flutter pub get
flutter gen-l10n
dart run tool/ffigen.dart
flutter devices
flutter run -d DEVICE_ID
```

Замените `DEVICE_ID` настоящим ID; на соответствующем компьютере можно использовать
`macos` / `windows`. Локализация и FFI исключены из Git: генерируйте их и для
Apple/Android, поскольку общий Dart-код импортирует их. Настройки FFI находятся
в `pubspec.yaml`. Включённые в Git модели, код БД, ресурсов и Pigeon требуют
генерации только после изменения исходников.

- Подпись Apple: согласуйте Bundle ID Runner/tunnel, App Groups и
  [идентификаторы Swift](../swift/All/Constants.swift) со своей командой разработчиков.
  Реальному устройству нужны подпись для разработки и возможности Network Extension.
- iOS Simulator использует локальный SOCKS в Swift и пропускает авторизацию VPN;
  это не проверка настоящего системного VPN.
- Linux: сначала соберите Debug bundle и выдайте сетевые возможности его Core:
  ```shell
  flutter build linux --debug
  sudo setcap cap_net_admin,cap_net_raw+eip build/linux/x64/debug/bundle/OneXrayCore
  flutter run -d linux --no-enable-impeller
  ```
  Для ARM64 замените `x64` на `arm64`; после замены Core выдайте возможности заново.
- Windows MSIX запускается как установленный подписанный пакет с идентичностью;
  см. [подпись для разработки](../build_scripts/README.md#msix-and-development-signing).
  Отдельный EXE или `msix:create` не заменяет интеграцию пакета.

## 4. После изменения исходников

| Исходники | Генерация |
| --- | --- |
| ARB | `flutter gen-l10n` |
| Модели JSON/Drift или объявленные ресурсы | `dart run build_runner build --delete-conflicting-outputs` |
| `pigeon/message.dart` | `dart run pigeon --input pigeon/message.dart` |
| Заголовки/настройки FFI | `dart run tool/ffigen.dart` |

После замены нативных библиотек полностью перезапустите приложение: hot reload
не обновляет их. Изолированные тестовые данные храните в `references/` рабочего
каталога, а не в основной базе. Контракты описаны в [App](../docs/app.md),
[Validation](../docs/validation.md) и [External interfaces](../docs/external-interfaces.md).
Обычный Debug не требует `BUILD_NUMBER`, Fastlane или данных для загрузки в магазины;
подпись платформы для разработки — отдельное требование. Для упаковки используйте
руководство сборки.

[Вернуться к README](./README.ru.md)
