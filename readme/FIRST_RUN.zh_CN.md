# 本地开发环境

[English](./FIRST_RUN.md) · [简体中文](./FIRST_RUN.zh_CN.md) · [Русский](./FIRST_RUN.ru.md)

只准备一个目标平台并运行 Flutter Debug。打包与商店部署统一参阅
[构建与发布](../build_scripts/README.md)，不属于本文的调试步骤。

## 1. 工具与仓库

安装 Flutter stable，其 Dart SDK 须满足 [pubspec.yaml](../pubspec.yaml)；
另需 Git、Python 3.12+、满足 libXray `go.mod` 的 Go，以及 FFI 使用的 LLVM/libclang。
将 Flutter、Go 和 Go 工具安装目录（`GOBIN`，未设置时为 `GOPATH/bin`）加入 `PATH`。

| 目标 | 额外要求 |
| --- | --- |
| iOS / macOS | macOS、完整 Xcode、目标 SDK／模拟器 runtime。 |
| Android | [Gradle 配置](../android/app/build.gradle.kts)指定的 Android SDK/NDK，以及与 [Gradle wrapper](../android/gradle/wrapper/gradle-wrapper.properties)兼容的 JDK；设置 `ANDROID_HOME`、`ANDROID_NDK_HOME`。 |
| Linux | Linux 原生工具链及下文的 GTK／插件依赖。 |
| Windows | Windows 原生主机、Visual Studio C++ 工具、Windows SDK、Rust、`uv` 和架构匹配的 Go/C 编译工具；见 [Windows 准备](../build_scripts/README.md#windows)。 |

在工作空间中只 clone 尚未准备的仓库：

```shell
git clone https://github.com/YuanDevTeam/OneXray.git
git clone https://github.com/XTLS/libXray.git
cd OneXray
```

两个仓库放在同一级；Windows 另需 Vole，目录规则见[构建手册](../build_scripts/README.md#prepare-the-workspace)。下文命令均从 App 根目录
执行。使用与 App 匹配的依赖，CI 引用见 [Build workflow](../.github/workflows/build.yml)，
无需额外 clone Xray-core。先检查 `flutter doctor -v`。Flutter/Dart 命令跨终端也须
串行；生成或检查前停止正在运行的 `flutter run`。

## 2. 原生库与 Geodata

只执行目标平台对应小节。以下 libXray 命令准备原生产物和 `../libXray/dat/`，
不会发布 App。

### iOS / macOS

```shell
python3 ../libXray/build/main.py apple go
rsync -a --delete ../libXray/LibXray.xcframework/ swift/All/LibXray.xcframework/
```

只替换该生成 framework，保留 `swift/All/` 中其他文件。Apple 工程使用 SwiftPM，
无需准备 Podfile 或执行 `pod install`；Flutter 会生成插件包。若曾全局禁用，使用
`flutter config --enable-swift-package-manager` 开启。

### Android

```shell
python3 ../libXray/build/main.py android
mkdir -p android/app/libs
cp ../libXray/libXray.aar ../libXray/libXray-sources.jar android/app/libs/
```

Windows 使用对应 PowerShell 命令。App 支持 arm64-v8a／x86_64；本地 Debug 使用
调试 keystore，不需要 Play 上传凭据。

### Linux

Debian／Ubuntu：

```shell
sudo apt-get install -y build-essential clang libclang-dev cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libblkid-dev libsecret-1-dev libayatana-appindicator3-dev libcap2-bin procps file
python3 ../libXray/build/main.py linux
mkdir -p linux/app
cp ../libXray/linux_so/libXray.so linux/app/
cp ../libXray/bin/xray linux/app/OneXrayCore
chmod +x linux/app/OneXrayCore
```

### Windows

按[构建手册](../build_scripts/README.md#windows)准备完整原生 bundle。两种模式都需要
Core、Wintun 和 Vole，仅复制 libXray 不足以运行。`windows/app/` 就绪后，普通
Debug 默认使用 EXE 模式。

### 复制完整 Geodata

手动构建必须同时复制 `.dat`、JSON 索引和时间戳：

```shell
mkdir -p assets/dat
cp -R ../libXray/dat/. assets/dat/
```

PowerShell：先执行 `New-Item -ItemType Directory -Force assets/dat`，再执行
`Copy-Item ../libXray/dat/* assets/dat/ -Force`。该目录被 Git 忽略，新 clone 需要这些
内置数据；App 打包脚本已包含复制。原生产物架构必须与 App 一致。

## 3. 生成并运行

```shell
flutter pub get
flutter gen-l10n
dart run tool/ffigen.dart
flutter devices
flutter run -d DEVICE_ID
```

将 `DEVICE_ID` 换为实际设备 ID，桌面对应主机可用 `macos`／`windows`。本地化和 FFI
输出被 Git 忽略，Apple／Android 也须生成，因为共享 Dart 代码引用了它们。
FFI 头文件与配置见 `pubspec.yaml`；已入库的模型、数据库、资源和 Pigeon 输出仅在
源文件变化后重新生成。

- Apple 签名：将 Runner/tunnel Bundle ID、App Group 和
  [Swift 标识](../swift/All/Constants.swift)同步到自己的开发团队；真机需要开发签名
  与 Network Extension 能力。
- iOS 模拟器由 Swift 自动使用本地 SOCKS 并跳过 VPN 授权，不代表真实系统 VPN 验收。
- Linux：先生成 Debug bundle，再授予实际 Core 网络能力：
  ```shell
  flutter build linux --debug
  sudo setcap cap_net_admin,cap_net_raw+eip build/linux/x64/debug/bundle/OneXrayCore
  flutter run -d linux --no-enable-impeller
  ```
  ARM64 将 `x64` 改为 `arm64`；重新构建替换 Core 后重新授予能力。
- Windows MSIX 须运行已安装且签名的开发包；参阅
  [开发签名](../build_scripts/README.md#msix-and-development-signing)，不能用裸 EXE 或
  单独的 `msix:create` 替代包身份与集成。

## 4. 修改源码后

| 源文件 | 重新生成 |
| --- | --- |
| ARB | `flutter gen-l10n` |
| JSON/Drift 模型或声明的资源 | `dart run build_runner build --delete-conflicting-outputs` |
| `pigeon/message.dart` | `dart run pigeon --input pigeon/message.dart` |
| FFI 头文件／配置 | `dart run tool/ffigen.dart` |

重新构建并替换原生库后完整重启，热重载不能替换它们。隔离测试数据放在工作空间
`references/`，不要使用主数据库。行为、验证与桥接合同分别见
[App](../docs/app.md)、[验证](../docs/validation.md)、[外部接口](../docs/external-interfaces.md)。
普通 Debug 不需要 `BUILD_NUMBER`、Fastlane 或商店上传凭据；平台开发签名另行准备。
打包时转到构建手册。

[返回 README](./README.zh_CN.md)
