# !/bin/bash

dart run build_runner build
dart run pigeon --input pigeon/message.dart
dart run tool/ffigen.dart
flutter pub upgrade --major-versions
flutter pub upgrade --tighten

sudo setcap cap_net_admin,cap_net_raw+eip OneXrayCore
