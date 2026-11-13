<p align="center">
  <img src="../assets/logo.png" width="96" alt="Логотип OneXray">
</p>

<h1 align="center">OneXray</h1>

<p align="center">
  Клиент Xray-core с открытым исходным кодом для телефонов, планшетов и компьютеров.
</p>

<p align="center">
  <a href="../README.md">English</a> · <a href="./README.zh_CN.md">简体中文</a> · Русский
</p>

<p align="center"><strong>Скачайте из официальных магазинов</strong></p>

<p align="center">
  <a href="https://apps.apple.com/us/app/onexray/id6745748773"><img src="./store-badges/ru/app-store.svg" height="48" align="middle" alt="Загрузить в App Store"></a>&nbsp;
  <a href="https://play.google.com/store/apps/details?id=net.yuandev.onexray"><img src="./store-badges/ru/google-play.png" height="64" align="middle" alt="Скачать в Google Play"></a>&nbsp;
  <a href="https://apps.microsoft.com/detail/9NJ0MVHW215D"><img src="./store-badges/ru/microsoft-store.svg" height="48" align="middle" alt="Скачать из Microsoft Store"></a>
</p>

<p align="center">
  <a href="#системные-требования">Системные требования</a> · <a href="#linux">Linux</a> · <a href="#onexrayse">OneXraySE</a> · <a href="#другие-варианты-загрузки">Другие варианты загрузки</a>
</p>

<p align="center">
  Если OneXray вам полезен, поставьте этому репозиторию ⭐ <strong>Star</strong>, чтобы поддержать дальнейшую разработку.
</p>

<p align="center">
  <a href="https://github.com/YuanDevTeam/OneXray"><img src="https://img.shields.io/github/stars/YuanDevTeam/OneXray?style=social" alt="Звёзды на GitHub"></a>
  <a href="https://github.com/YuanDevTeam/OneXray/releases/latest"><img src="https://img.shields.io/github/v/release/YuanDevTeam/OneXray?display_name=tag&sort=semver" alt="Последний релиз"></a>
</p>

**Добавьте свои серверы или подписку.** OneXray не предоставляет доступ к VPN или прокси-серверы.

[![OneXray на Mac, iPad и iPhone](https://onexray.com/images/screenshots/devices-ru.png?v=20261113)](https://onexray.com/images/screenshots/devices-ru.png?v=20261113)

## Почему OneXray

- **На всех ваших устройствах.** Используйте iPhone, iPad, Mac, Android, Windows или Linux. Доступны светлая и тёмная темы и пять языков интерфейса.
- **Серверы в порядке.** Импортируйте ссылки, Xray JSON и подписки. Объединяйте вручную добавленные узлы в группы и меняйте их порядок перетаскиванием.
- **Маршрутизация под вашим контролем.** Выбирайте умную или пользовательскую маршрутизацию либо используйте полные конфигурации Raw и провайдеров, включая подписки Remnawave.
- **Открытость и конфиденциальность.** Исходный код под GPL-3.0 с [исключением для VPN-провайдеров](#лицензия), без учётных записей, рекламы, аналитики и отслеживания. [Политика конфиденциальности](https://onexray.com/ru/docs/privacy/).

## Системные требования

Текущие официальные пакеты требуют следующих операционных систем и архитектур:

| Платформа | Минимальная операционная система | Поддерживаемые архитектуры |
| --- | --- | --- |
| iPhone / iPad | iOS / iPadOS 16+ | arm64 |
| macOS (Mac App Store) | macOS 13 | Apple silicon (arm64), Intel (x86_64) |
| macOS (OneXraySE) | macOS 13 | Apple silicon (arm64), Intel (x86_64) |
| Android | Android 10 (API 29) | arm64-v8a, x86_64; 32-битные устройства не поддерживаются |
| Windows x64 | Windows 10 20H2 (сборка 19042) | x64 (x86_64) |
| Windows ARM64 | Windows 11 | ARM64 |
| Linux (DEB / ZIP) | Ubuntu 24.04 LTS или совместимые дистрибутивы с ядром Linux 5.3+, glibc 2.39+, GLib 2.80+ и библиотекой GTK 3 | x86_64, arm64 |

Системная библиотека GLib 2.72 в Ubuntu 22.04 не отвечает требованиям текущих официальных пакетов DEB / ZIP. Используйте Ubuntu 24.04 LTS или другой дистрибутив, отвечающий всем требованиям выше.

Подробнее см. в [руководстве по системным требованиям](https://onexray.com/ru/docs/system-requirements/).

## Первые шаги

1. Установите приложение из официального магазина, завершите настройку и предоставьте системные разрешения. На Windows и Linux также нужно выбрать исходящий сетевой интерфейс.
2. Откройте **Серверы** и добавьте подписку, ссылки или Xray JSON. Полные конфигурации провайдеров распознаются при импорте подписки.
3. На странице **Подключение** выберите сервер или полную конфигурацию и запустите VPN. Для узлов, которыми управляет приложение, начните с умной маршрутизации; конфигурации провайдеров используют собственные настройки маршрутизации и DNS.

[Первое подключение](https://onexray.com/ru/docs/getting-started/) · [Импорт серверов](https://onexray.com/ru/docs/servers/import/) · [Руководство по Remnawave](https://onexray.com/ru/docs/servers/remnawave/)

## Загрузка

Проверьте [системные требования](#системные-требования), затем выберите официальный магазин для своего устройства:

- **iPhone / iPad:** [App Store](https://apps.apple.com/us/app/onexray/id6745748773).
- **macOS:** [Mac App Store](https://apps.apple.com/us/app/onexray/id6745748773).
- **Телефоны / планшеты Android:** [Google Play](https://play.google.com/store/apps/details?id=net.yuandev.onexray).
- **Windows:** [Microsoft Store](https://apps.microsoft.com/detail/9NJ0MVHW215D).

### Linux

[DEB · x86_64](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-linux-x86_64.deb) · [DEB · arm64](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-linux-aarch64.deb). Проверьте [системные требования Linux](#системные-требования); зависимости и разрешения описаны в [руководстве по установке на Linux](https://onexray.com/ru/docs/install/#linux).

### OneXraySE

Версия для macOS с System Extension доступна через [Homebrew](https://formulae.brew.sh/cask/onexrayse) или в виде [Universal ZIP](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-macos-universal.zip). Проверьте [системные требования](#системные-требования); разрешение расширения и обновление описаны в [руководстве по установке на macOS](https://onexray.com/ru/docs/install/#macos).

### Другие варианты загрузки

<details>
<summary>Пакеты для прямого скачивания и подробности установки</summary>

| Платформа | Пакеты |
| --- | --- |
| iPhone / iPad | [IPA](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-ios.ipa) |
| Android | [Универсальный APK](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-android-universal.apk) |
| Windows x64 | [EXE через winget](https://onexray.com/ru/docs/install/#windows) · [ZIP](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-windows-amd64.zip) |
| Windows ARM64 | [EXE через winget](https://onexray.com/ru/docs/install/#windows) · [ZIP](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-windows-arm64.zip) |
| Linux x86_64 | [ZIP](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-linux-x86_64.zip) |
| Linux arm64 | [ZIP](https://github.com/YuanDevTeam/OneXray/releases/latest/download/OneXray-linux-aarch64.zip) |

В [руководстве по установке](https://onexray.com/ru/docs/install/) описаны подпись IPA, варианты Windows и отдельное хранение их данных, разрешения и обновление ZIP-версий. [Все релизы](https://github.com/YuanDevTeam/OneXray/releases).

</details>

## Настройка и помощь

- [Документация пользователя](https://onexray.com/ru/docs/) — настройка, маршрутизация, подписки и возможности платформ.
- [Настройка с помощью ИИ](https://onexray.com/ru/docs/ai/) — скопируйте запрос из руководства помощнику, которому доверяете, или прикрепите [полное руководство](https://onexray.com/ru/llms-full.txt). OneXray не содержит встроенного ИИ-сервиса и не отправляет конфигурации помощнику; перед подключением проверьте полученный JSON в приложении.
- [Сообщить об ошибке или предложить функцию](https://github.com/YuanDevTeam/OneXray/issues) — укажите платформу, версии приложения и Xray-core, шаги воспроизведения. Удалите учётные данные из публикуемых конфигураций, ссылок подписок и журналов.
- [Сообщество Telegram](https://t.me/YuanDevTeam).

## Поддержать OneXray

OneXray вам полезен? Поставьте этому репозиторию ⭐ **Star**, чтобы поддержать дальнейшую разработку.

[App Store](https://apps.apple.com/us/app/onexray/id6745748773) · [Google Play](https://play.google.com/store/apps/details?id=net.yuandev.onexray) · [Microsoft Store](https://apps.microsoft.com/detail/9NJ0MVHW215D)

Будем рады изменениям кода, переводам и улучшениям документации. Начните с [настройки среды разработки](./FIRST_RUN.ru.md), [руководства по сборке](../build_scripts/README.md) и [правил работы приложения](../docs/README.md).

## Лицензия

OneXray распространяется под [GNU General Public License v3.0](../LICENSE) с [исключением OneXray для VPN-провайдеров](../LICENSE-EXCEPTION).

Провайдеры VPN могут создавать и распространять специализированные клиенты с закрытым исходным кодом, подключающиеся исключительно к их собственным VPN-сервисам, не выполняя требования GPL этого репозитория в отношении кода, на который распространяется исключение.

Для применения исключения клиент не должен включать универсальные функции пользовательских конфигураций или подписок, в том числе возможность импортировать или использовать произвольные конфигурации сторонних VPN- или прокси-сервисов либо адреса их подписок. Конфигурации и подписки, предоставляемые провайдером исключительно для доступа к его собственному VPN-сервису, допускаются. Если клиент также позволяет подключаться к сторонним сервисам, одного собственного бренда, распространения только среди подписчиков провайдера или выбора его сервиса по умолчанию недостаточно.

Каждый клиент с закрытым исходным кодом, распространяемый на условиях этого исключения, должен содержать в легкодоступном разделе интерфейса, например «О приложении», «Благодарности» или «Лицензии открытого ПО», явное указание, что он основан на проекте OneXray, и ссылку на [проект OneXray](https://github.com/YuanDevTeam/OneXray).

Эти условия определяют применимость исключения. Для других способов использования действуют GPL или иное применимое разрешение.

Yuan Dev Team гарантирует, что не будет добавлять прямые сторонние зависимости, требующие лицензировать соответствующий условиям исключения клиент в целом под GPL или раскрывать его исходный код по GPL. Лицензии сторонних компонентов и относящиеся к ним обязательства сохраняются; исключение охватывает только права, принадлежащие Yuan Dev Team или предоставленные ей для такого лицензирования.

## Деловое сотрудничество

По вопросам делового сотрудничества пишите на [yuan@yuandev.net](mailto:yuan@yuandev.net).
