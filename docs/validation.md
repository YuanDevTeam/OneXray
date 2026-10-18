# 验证

以当前源码和[行为合同](README.md)为准。测试验证操作与结果，而不是实现写法；
旧提交的通过记录不代表当前代码通过。全局执行限制见[工程规则](../AGENTS.md#verification)。

## 场景测试

优先复用生产实现，以小型内存数据库、隔离文件、真实本地 HTTP 和可控的原生替身
组织以下场景。替身不代表内核、操作系统或云端已经验收。

| 场景 | 主要结果 |
| --- | --- |
| 启动与恢复 | 服务就绪后首页可用；缺库或默认资源丢失可离线恢复 |
| 导入与选择 | 普通节点与完整数组入库、活动方式计数、列表 Stream、普通测速与完整配置选择符合类型 |
| 订阅更新 | 双缓存事务更新，保留准备/待启动/运行/固定/收藏原行与来源身份；切换不热重连 |
| 配置与连接 | 普通/高级/Raw/提供方配置的保存、适配、分享与编译；先停止旧连接再启动 |
| 数据操作 | Geodata 发布、备份恢复、自动周期、清理后的重新使用 |
| 外部入口 | 页面、托盘、快捷入口、HTTP 和 Android 广播调用各自生产路径 |

- 每项先覆盖正常操作与最终状态，再保留真实风险：无效用户 JSON、空订阅保旧、
  权限拒绝、停止失败、过期异步结果、事务/文件回滚、鉴权和破坏性操作准入。
- 同一业务结果在负责层完整验证；页面验证点击、导航、loading 和反馈，不复制服务断言。
  协议往返和关键模型单测保留，分层 lint 独立于 App 场景测试。
- 不用源码字符串、私有函数调用次数或固定测试数量代替行为验证。
  删除旧功能测试；人工破坏本地数据等不可达组合不扩展为产品场景矩阵。
- 每个业务 case 应能对应页面、后台任务、系统事件或公开入口，以及该入口实际产生的数据。
  不为覆盖内部防护，手工添加迁移冲突列/索引、改写私有文件或传入生产方不可能生成的参数。
  用户 JSON、分享链接、备份和网络响应属于真实输入；权限、I/O 与事务失败可在实际依赖边界模拟。
  删除不可达 case 不等于删除生产防护，已发布数据库升级与历史数据保留仍需验证。
- UI 保留主题关键尺寸、颜色、安全区、长文案及 RTL 验证，使用代表性尺寸/语言组合，
  不降低高保真标准，也不全面交叉所有状态。
- fixture 仅共享确实重复的数据库、文件和节点样本；不引入通用场景 DSL 或大型测试基类。
  先补齐等价行为覆盖再删除重复测试，不按正负比例或数量衡量完成。

## 完整配置与模式边界

以下是当前功能的验证合同，不记录某次构建或设备通过状态；执行结果保存在独立验收材料。

- 在隔离库验证 schema 1–7 升至 8、新安装和重复打开：ID、JSON、Age/HWID、订阅及旧 Raw 保留，
  旧地区列删除、panel/mode 缺省正确，未知选择统一回退，退休 full 不激活。
  旧来源 UA 为空；显式 UA 只覆盖当前订阅请求，添加、刷新、编辑清空、分享及备份往返保持原始 URL，
  不影响其它来源、Geodata 或普通下载请求；所有下载默认统一使用带 OneXray 版本的 v2rayN 前缀及完整 OneXray UA。
  新增及已有空 UA 的编辑表单显示同一默认值，展示与取消不保存；已有或异步输入的自定义值保留，
  切换面板不清空 UA；UA 变更使迟到请求失效，失败保留既有配置。
- Remnawave 的 JSON（含仅 outbounds）进入完整解析；有效 JSON 的结构/内核错误不触发转换。
  非 JSON 先确认，再把同一份 Age 解密明文交给 libXray；新增与刷新成功后原子保存 generic/appManaged，
  取消、无前台确认、普通解析失败及确认期间来源变化均保留旧数据，受保护的运行/选择行继续保留。
- 同一脱敏完整数组含普通 host 与 chain/balancer 图：逐项保存通过校验的完整 Map，名称与原图分离；
  Age 解密先于分类，非对象、无法适配和 Core 拒绝的配置跳过，继续检查后续项；失败配置不产生完整或派生缓存。
  部分成功按当前 mode 正常提交并刷新套餐，全部失败、空结果或 native 校验服务异常保留完整旧缓存及来源信息；
  运行服务异常不能被当作单项无效配置忽略。完整配置不降级为普通节点解析，也不拆删出站来挽救失败的配置图。
- 两种 mode 的活动列表、自动候选、最终出口、批测和计数统一过滤；离线切换不下载、重连或清套餐，
  缺缓存与固定选择不兼容有明确反馈，旧菜单和迟到响应再次复查真实来源/模式。
- 刷新保护 preparing/pending/running profile ID 及固定/最终出口/收藏原行，保留旧 JSON 并插新结果；
  失败、来源删除和请求策略改变不覆盖缓存或套餐。删除来源清理两类缓存且按运行引用停机/重连。
- 保存校验与编译使用同一纯配置适配，验证已有 TUN 的选取、tag 与入口规则同步、缺少时的新建入口，
  以及显式 53 规则的保留、缺少时复用或新增 DNS 出站并前置有界 DNS 规则。
  覆盖有无内置 DNS、FakeDNS、多个 SOCKS/HTTP 入站及显式嗅探关闭。已有 TUN 的设置和嗅探保留；
  已有 DNS 出站不删除，提供方的条件规则和非 DNS 目标不被 App 改写。源对象不变，其余入站/出站相对顺序、
  原业务规则、链式引用、balancer/observatory 和 domainStrategy 保留；配置有效性交由既有 libXray 流程验证。
  验证缺少的 direct/block 补齐，已有同 tag 定义保留；缺少或为空的原始 outbounds 经导入验证后可列表展示和选择，
  来源、资产与 JSON 可读取检查仍保留。
  Raw 复制/分享补同一入口语义，个人 Raw 配额与原图查看不互相混淆。
- 连接页显示 provider 名称快照与完整路由说明，不伪装成 App 多入口或单节点延迟；
  App Smart/Custom/LAN 偏好保存不影响 provider 会话，平台策略有效变更保持原重连流程。
- 备份 panel/mode 往返、旧文件缺省与未知字段容忍；订阅缓存排除，恢复不联网、不自动连接，正常刷新重新获取。

目标测试分别位于 `test/core/db/subscription_migration_test.dart`、`test/service/servers/subscription/`、
`test/service/shared/xray/remnawave_test.dart`、`test/service/connect/`、`test/pages/servers/`、
`test/pages/connect/` 和 `test/service/shared/menu/tray/`，按负责层验证业务结果，不复制测试实现。

原生 `testXray` 只构造并关闭，mock 和 JSON 对比不能证明 DNS、FakeDNS、IPIfNonMatch 第二轮匹配或网络链路。
Android :native、Apple 真机 extension 与桌面 Core 的 UI 校验通道有进程隔离；同进程 managed Core 防线仍保留，
iOS Simulator 不能通过绕过它来验证刷新。设备验收需要检查 VPN 持续运行、native Invoke 新入口、真实 DNS/路由/代理请求。

## 自动验证

按改动选择生成、格式化、分析和测试，命令从 App 根目录执行：

```shell
flutter gen-l10n
dart run build_runner build
dart run tool/ffigen.dart
dart run tool/check_layer_dependencies.dart
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze
flutter test
git diff --check
```

Pigeon、FFI、Drift 或本地化变更先生成对应输出；只改测试时不重复生成无关代码。
只改文档时检查路径、锚点和 diff，不运行 App 测试。

- 构建脚本：在 `build_scripts/` 执行 `python -m unittest discover -s tests`（仅需 Python 标准库）。
  外部打包工具替身证明编排，不证明生成包能安装；渠道发布还需实际产物检查。
- macOS SE 文件交接：`bash tool/test_dat_file_transfer.sh` 编译生产 Swift，
  验证完整清单、空集合、消息往返与发布回滚，不启动 App/VPN。
- Apple 文件备份：`bash tool/test_backup_file_store.sh` 编译生产文件存储实现，验证首字节内容探测、绑定不覆盖、替换写入、
  新实例重新访问、解绑保留文件及大小限制。命令行使用普通 bookmark，持久沙盒授权需在签名 App 中核对。
- macOS SE 激活：`bash tool/test_system_extension_activation.sh` 编译生产 Swift，
  验证并发请求合并及完成后的重新激活；使用可控系统回复，不申请真实扩展授权或启动 VPN。
- Android 原生：在 `android/` 执行 `./gradlew :app:testDebugUnitTest`，
  Robolectric 调用正式 Receiver、保存配置、Widget 资源与 VPN 状态桥；
  状态桥回归使用真实 command/changed 与可控 Binder 重演停止确认后旧事件迟到，
  并区分当前错误/退出、旧绑定回调和外部启动；不替代真实 VPN 与桌面验收。
- Android Manifest/网络 XML 变更补跑 `./gradlew :app:lintVitalRelease`；
  发布相关修复还需本地 Release AAB 构建，不调用会上传商店的部署脚本。
- 原生桥合同变更验证实际序列化/消费方与对应平台构建；
  `dart run tool/check_native_model_contract.dart` 只检查字段名，不代替行为验证。

## 平台验收

Android 模拟器直接使用当前分支构建覆盖已经安装的 OneXray，保留已有数据，不另建测试包或 applicationId。
验证使用脱敏输入或临时响应替身，调用真实原生解析；完成后只清理本轮新增的测试数据。

- Android UI 用模拟器验证；系统导入、导出和扫码可记录跳过。Widget 检查 4×2 最小尺寸、
  缩放、旋转、主题、语言与启动/停止。通知和真实代理请求需运行 VPN 后验证。
- Android 自动化需普通第三方 UID 的后台启停、冷进程、Token 撤销和清理/恢复阻断，
  至少联调一款真实工具；shell 广播不等于工具联调。
- macOS 桌面 UI 使用 Flutter Debug 验证；VPN、Apple 授权、按需连接、SE 跨容器交接
  和签名包需单独人工验收，不以纯 Dart/Swift 测试替代。
- Windows/Linux 在对应环境验收；Windows 区分 EXE/ZIP 与 MSIX 的启动、退出、权限和数据根。
- 云备份需真实提供商的授权、文件覆盖、重新打开及跨设备恢复；本地写入成功不等于云端同步完成。
- 完成后区分自动测试、模拟器、真机、签名渠道及未测项；测试输入使用脱敏数据，并保留原有数据。
