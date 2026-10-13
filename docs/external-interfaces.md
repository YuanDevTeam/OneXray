# 外部接口

桌面 HTTP API 与 Android 广播是独立接口：Token、保存位置、协议及操作权限互不通用。
两者默认关闭，不提供远程控制、公开取凭据入口或通用 invoke；设备 Token 不进入连接配置备份。
App 生命周期见 [App](app.md)，配置/校验语义见 [Xray 配置](xray-configuration.md)。

## 本地配置 HTTP API

桌面“高级 → Xray → 本地 API”管理启用、端口、Token 复制/重置；移动端无入口或路由。
App 完成服务准备后监听，隐藏窗口不停止，退出进程接口不可用，即使 VPN 仍运行。
默认 `127.0.0.1:18587`，仅 IPv4 loopback，端口 1024–65535；监听或偏好保存失败保留原地址/凭据。
桌面自动 SOCKS/metrics 分配排除已保存 API 端口，即使 API 关闭，并继续避开用户入站；
常规模式及自定义路由额外避开启用的局域网共享端口，完整 Raw 不预留共享端口，不改写手动端口。
API 端口与已启用的共享端口不可相同；两者修改时均检查冲突，API 始终保持本机监听。
连接准备会拒绝与已启用 API 的 IPv4 loopback TCP 监听冲突的用户入站，涵盖普通自定义路由、Raw 和提供方完整配置；
不改写原入站，API 关闭、独立监听地址或仅 UDP 监听不因此受限。

首次启用生成 32 随机字节 Base64URL Token，设备偏好持久保存；关闭保留，重置立即撤销旧值。
每次请求必须 `Authorization: Bearer <token>`。用户经复制按钮交给可信工具，不扫描 App 沙箱凭据。
Token 不进 URL、命令行参数、AI 提示词或日志；调用工具自行保护凭据，此鉴权不能防御已控制同一账户的恶意程序。
清理数据删除 API 偏好和内存凭据并关闭监听，恢复不携带或改写 API 设置。
Host 必须精确为实际 `127.0.0.1:端口`；拒绝 Origin、查询参数和代理绝对 URI，无 CORS。
调用工具直连，禁用环境代理及自动重定向，避免泄露凭据。

### 请求合同

`apiVersion: 1` 独立于 App 与 libXray 版本：

| 方法/路径 | 结果 |
| --- | --- |
| GET `/api/v1/info` | API/App/Core 版本、宿主平台和输入类型，不返回凭据或资产 |
| POST `/api/v1/config/validate` | App 验证投影及现有 `testXray` |
| POST `/api/v1/config/compile` | `ConnectionCompiler` 运行配置预览，不调用内核 |

POST 为 `application/json`，请求体上限 16 MiB；`text` 是原文字符串，不能先解析重编码，否则位置变化。
必须显式给 `kind`，可选 `name` 遵循对应输入类型，不能混同节点 tag：

| kind | text |
| --- | --- |
| outbound | 单个 outbound 对象 |
| routing | 常规自定义路由，包含空接入槽 |
| advanced-routing | 独立字段边界的高级模板 |
| raw | 完整 JSON，不施加普通/高级白名单 |

`validate` 不接受 `options/outbounds`；模板使用 freedom 占位，不要求真实节点或证明其运行组合。
`compile` 必须给 `options`：`platform`（ios/macos/android/windows/linux）、
`sessionDirectory/metricsPort/socksPort/ipv6`；Windows 另需 `windowsMode: exe|msix`，Windows/Linux 需 `interfaceName`。
目录必须非空，两个预览端口为 1–65535 且不同；这些是输入检查，不证明端口/网卡在目标系统可用。
可选 `tunDnsIpv4Address/tunDnsIpv6Address/logEnabled/logFilesSupported/logLevel/dnsLog/maskAddress/lanProxyEnabled/lanProxyPort`
使用 `RuntimeOptions` 默认值，不读当前用户策略。
共享预览默认 `lanProxyEnabled: false`、`lanProxyPort: 11024`；常规/高级路由开启时追加 App 管理的混合 HTTP/SOCKS5 入站，
端口须为 1024–65535，且不与显式给出的 metrics/SOCKS 预览端口或用户入站冲突，用户不得定义同名托管入站。
`compile` 不分配或替换这些端口，也不读取设备 API 设置；共享运行边界见 [局域网代理共享](xray-configuration.md#局域网代理共享)。
`kind: raw` 忽略共享预览参数，不增加共享入站或施加共享 tag/端口限制。
routing/advanced-routing 另给与槽数一致的真实 `outbounds`；outbound/raw 不接受该数组。
预览使用当前 App 资源目录，不检查端口空闲/网卡存在、不创建目录、不写运行文件；
跨平台 JSON 不证明资源在目标设备可用。

### 结果与执行边界

结果包含 `status: passed|failed|notRun`、`stage: input|compile|kernel`、`diagnostics`；
HTTP 200 不等于配置正确，compile 通过不等于内核通过。
诊断提供稳定 code 和原始 message，可带属性名/整数索引组成的 path、offset/line/column。
offset/column 为 Dart UTF-16 code unit，offset 从 0、行列从 1 开始；无可靠原文位置就省略，不从内核文字猜字段或套用副本位置。
`validationConfig/compiledConfig` 是可能含凭据的 JSON 文本，`limitations` 表明未覆盖范围；
服务不写输出文件，工具保存须使用明确目标并保护敏感内容。
401 鉴权失败、403 Origin、409 忙碌、413 超限、503 暂停/不可用；未执行不算通过。

最多一个配置请求运行，其他立即忙碌；Native 使用已有串行机制，Geodata 进入文件队列，不新增全局业务锁。
清理/恢复暂停新请求并等待已接收请求结束；读取完请求体后复核凭据与服务状态。
断开、超时或关闭接口不能取消已进入 Native 的校验，也不自动重试。
API 不下载/导入/保存资产、不检查 DB 重名/数量、不选择节点、不启停 VPN。

校验仍在 App 进程，不是沙箱：Core 构造可能读取文件、改变 Go 全局状态或创建协议资源；
不承诺所有进程崩溃都能返回 HTTP 错误。成功只证明验证副本完成构造/关闭，不证明完整配置可保存、启动或联网。

## Android 外部自动化

“高级 → VPN 隧道 → Android 系统 VPN → 外部自动化”在当前 Tab 打开详情；
开关立即保存、重置需确认，不重连、不改按应用分流草稿。非 Android 不注册入口或路由。

### 广播合同

| 字段 | 值 |
| --- | --- |
| 类型 | Broadcast Receiver |
| Package | `net.yuandev.onexray` |
| Class | `net.yuandev.onexray.automation.VpnAutomationReceiver` |
| START | `net.yuandev.onexray.action.START_VPN` |
| STOP | `net.yuandev.onexray.action.STOP_VPN` |
| Extra | `token`，精确 String |

仅接受两个动作，不接受配置路径、节点选择、回调或调用者自报身份。
未知动作、关闭、损坏授权、缺失/错误类型/不匹配 Token 静默拒绝，鉴权前不查询权限或改运行状态。
Token 不是 HTTP Header，无公开 Token 查询或状态广播；用户参数与工具填写见 [文档站](https://onexray.com/zh/docs/advanced/android/#automation)。

### 原生运行边界

Receiver 在已有 `:native` 进程复用 `VpnController/OneVpnService`，不创建 Flutter 引擎、Activity、第二套编译器或后台队列。
START 使用最近生成的完整 `run/start.json`，不是“最后成功连接”，也不追随后来 DB 选择；改配置后须从 App 正常连接一次。
LAN sharing edits likewise leave this input unchanged: automation, Widget/Tile and Apple on-demand
starts retain the last compiled sharing setting. Only an App start/restart compiles the newly saved
policy; see [LAN proxy sharing](xray-configuration.md#局域网代理共享). Sharing edits do not add an
automation or saved-start block; the separate cleanup/restore admission below remains in place.
顺序为鉴权 → 清理/恢复阻断 → 启动请求外层读取 → VPN/LAN 权限 → 原生交付；
文件检查在 `VpnService.prepare()` 前，实际配置/资源错误交 Core。
合法失败只反馈具体原因和通知点击入口，不自动拉起 App、下载、重试或恢复旧连接；通知不可见仍保留原生日志。

STOP 不读启动文件、不检查启动权限、不受 START 阻断；重复 START 不重启已运行 Core，重复 STOP 可接受，启动中 STOP 复用释放流程。
发送/交付不等于已连接/断开，实际状态由原生资源、App/Widget/Tile/通知体现，不承诺不同发送进程的全局顺序。
force-stop、未解锁、Doze/OEM 省电及其他 always-on/lockdown VPN 是系统边界，不承诺绕过；
Widget/Tile 的缺输入打开 App 回退不用于广播。

### 设备授权与数据操作

`AutomationStore` 在私有 `noBackupFilesDir` 保存设备授权，主 App Android Pigeon 桥是唯一写入入口；
同目录写入/同步/原子替换，Receiver 每次重读正式文件，不使用跨进程缓存；不存在、损坏、超限或半成品按关闭处理。
首次启用生成 `ox_` 加 32 随机字节 URL-safe Token；关闭保留，再开复用，显式重置才更换。
关闭/重置只影响后续鉴权，不撤销已交付命令、不停止 VPN。Token 不进 DB、配置、日志、错误详情或备份；
只有主动复制才写剪贴板，分享工具任务须删实际 Token。

清理/恢复在停止 VPN 与替换数据前建立跨进程 START 阻断，建立失败不进入破坏性操作。
期间授权 STOP 可执行，设置桥不允许同时启用或重置；`OneVpnService` 再检查阻断，覆盖交付后尚未处理窗口。
清理全部数据删除授权，备份恢复保留目标设备授权；临界区正常退出解除标记。
异常退出遗留标记在下次 `ServiceManager` 存储/协调器就绪后解除，不依赖 Setup、不自动连接，
也不把此标记扩展成 VPN 状态缓存或普通保存/测速锁。

## 平台检查

检查遵循 [验证边界](validation.md)：HTTP 需签名 App 的实际监听/Native 链路及 Windows MSIX/Linux 环境；
Android 需普通第三方 UID 的真正后台 START/STOP、代理请求、冷原生进程、Token 撤销和清理/恢复阻断，并至少联调一款真实工具。
单元/回环注入测试、shell 广播或工具“已发送”不能替代平台运行证据；系统版本/OEM/工具差异单独核对。
