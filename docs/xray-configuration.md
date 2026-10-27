# Xray 配置与运行

## 配置边界

普通模式使用 App 节点与智能/常规自定义路由；高级自定义是仍复用 App 节点的 JSON 模板；
专家模式使用自带节点的个人 Raw JSON。订阅完整配置使用独立 Remnawave 类型，固定或自动选中后执行整份提供方图，
不要求切到专家模式、不占用个人 Raw 配额。高级模板不提供逐字段表单，不与常规表单双向转换。
常规/高级自定义共用三份上限，已有记录类型不可切换。Raw 新增最多三份，旧库超额行完整保留、可选和可编辑。
持久化、升级和导入事务见 [数据管理](data-management.md) 与 [服务器及分享](subscriptions-and-sharing.md)。

普通运行直接构造 `XrayJson` 及嵌套模型，最终一次序列化；不先拼完整 Map 再 `fromJson → toJson`。
模型只定义必要字段及标准序列化，不承担构造或协议解析。节点 outbound 保持完整 Map。
高级模板/Raw 使用独立 Map 编译路径，分别按模板边界或完整配置保留用户字段，不经普通模型裁剪。
Raw 与提供方完整配置共用 VPN 必要配置补充和 Raw 运行注入，提供方另有入口适配；保存原图不写入运行字段。
编译器是纯值转换：不读库、分配端口、写文件或启动 Core；App 运行字段只由对应编译路径生成。

Xray 字段有效性以 libXray 为准，App 不重复维护协议、算法、网络、端口或重复 tag 等内核校验。
App 保留自身名称、资产数量/交换格式、文件链接安全、事务和平台网络策略检查。
分享解析/生成及测速直接采用 libXray 对应 API；手写节点、路由、Raw 保存使用 `testXray`。
连接启动不重复预检，实际加载、构造和启动错误由启动路径返回。

## 普通配置编译

自动或来源选择先按路由要求选择 1–3 个健康的普通接入节点；固定节点及全部使用 VPN 使用一个。
普通节点按延迟、ID 选择；数量不足或无法取得足量健康节点时，在同一范围内按 ID 升序选择首份可读取的活动提供方完整配置。
只有候选缺少、数量不足或健康不足可触发该选择；取消、读取、测速服务异常及配置、编译、权限或启动错误直接报告，不重试其它提供方。
完整配置不进入普通节点组合、最终出口或单 outbound 测速，也不与普通节点比较延迟。
自动或来源意图仍保存在设置中，实际选中的完整配置只进入运行快照，不改成固定选择。
已运行节点不因后台测速或订阅更新热替换；节点命名见 [服务器及分享](subscriptions-and-sharing.md)，
显示排序独立于自动候选选择，见 [数据管理](data-management.md#数据显示顺序)。

代理规则固定使用 `balancerTag: proxy`，单节点同样使用 balancer。selector 填完整运行 tag，
默认轮询使用 `roundRobin`，其 fallback 为第一条完整代理链，未命中走第一个 outbound。
可选最低延迟使用 `leastPing`；只有本次连接至少两条代理链时才启动观察，并在用户规则末尾为托管
`tunIn` 和已启用的 `app-lan-proxy` 添加代理兜底。其 fallback 为第一条完整代理链，无结果或全失败
仍尝试代理，由实际请求报告错误，不自动直连；单节点保留偏好但不额外探测。不为选路额外增加 loopback。
无最终出口时接入节点按顺序位于最顶部；智能路由有最终出口时，每条接入各生成出口副本，
副本的 `dialerProxy` 指向对应接入，出口副本按顺序置顶，接入节点随后。
balancer 选择这些完整链路，接入选择排除最终出口；自定义路由不绑定具体节点或最终出口。
系统出站随后追加，固定 tag 为 `direct`、`block`、`dnsOut`。
普通出站先移除原 settings/sockopt 的 `domainStrategy`，再按有效 [服务器拨号](#服务器拨号) 策略生成物理连接设置；
Raw 用户字段不适用此删减。

智能/常规自定义固定 `routing.domainStrategy: IPIfNonMatch`：域名首轮未命中再解析 IP 重匹配。
全部使用 VPN 为 `AsIs`，高级/Raw 保留用户值。App 生成规则省略可选 `type: field`。
智能路由把直连域名/IP 分别去重合并为一条规则，无条件时省略对应规则。
顺序为广告阻断、Windows 开关对应的 GitHub 代理、合并域名直连、合并 IP 直连。
Windows 服务直连使用 Microsoft/Bing 分类，同时优先代理 GitHub；该开关在所有平台显示。
直连地区来自安装的官方分类与随包映射。广告、FakeDNS、Fragment 默认关闭，其余智能开关默认开启；保留已保存值。

### DNS

智能和常规自定义分别保存代理/直连主 resolver 地址及同出口有序备用列表。
旧设置缺新增字段时两组主地址均为 `8.8.8.8`，全局缓存开启，
相同出口备用默认关闭。智能直连 DNS 关闭保留已填值，运行不派生直连 DNS 匹配。
使用固定 `app-dns-proxy` / `app-dns-direct` tag 区分出口，DNS 规则来自同一份有序路由规则。
只投影无 IP/端口/网络/协议/系统/入站等附加条件的 proxy/direct 域名规则，因为查询不掌握后续连接条件。
代理例外先于宽泛直连分类；代理策略块末尾的真实 resolver 使用 `finalQuery`，不回退到直连 DNS。
直连默认允许失败后尝试代理备用；“备用 DNS 使用相同出口”开启时只尝试本策略 resolver，
不会在失败后切换其他出口。直连 resolver 不充当未匹配域名的通用备用。

普通设置保留 root `disableCache` 全局开关，resolver 只保存地址，其余参数沿用 Core 默认值。
普通设置不开放 resolver `timeoutMs/disableCache`、`expectedIPs/unexpectedIPs`、
`serveStale/serveExpiredTTL` 或 `enableParallelQuery`。
这些 Core 原生字段及 JSON 编辑提示保留，高级/Raw DNS Map 可配置，不受普通表单覆盖。
已保存的普通数据库配置在内部读取时剔除旧字段；外部普通导入仍明确拒绝这些超出边界的字段，
避免静默丢失用户配置。Geodata 资源引用仍沿用依赖扫描与分享附件。

全部使用 VPN 的业务 DNS 只走代理，非 A/AAAA 的 `dnsOut` 转发同样走代理；
按需生成的服务器域名引导 DNS 独立直连，见 [服务器拨号](#服务器拨号)。
智能与常规自定义各自保存“其它 DNS 查询”策略，缺省为代理，包括旧设置和旧普通分享。
A/AAAA 始终劫持到内置 DNS；其它记录可选代理、显式直连或返回 NOERROR 空答案。
代理保留原查询目标，经 `app-dns-forward` loopback 和前置同名入站规则进入已有 `proxy` balancer，
不改用代理 resolver 地址，也不受智能直连 DNS 开关影响；局域网 resolver 需用户自行选择可达的出口。
该辅助出站不进入节点映射或观察范围，不监听端口；普通代理选路失败不隐式回退 direct。
普通模式的查询地址族仍由 App IPv6 设置管理，不额外生成根级 hosts/queryStrategy。
高级模板和 Raw 不应用这些普通 DNS 设置；模板 DNS 保持其原有管理边界。
Raw 与提供方完整配置缺少 Core DNS 服务器时，使用[完整配置的 VPN 适配](#完整配置的-vpn-适配)中的隧道 DNS 缺省策略。

### 服务器拨号

服务器拨号为本机平台策略，统一用于智能、常规自定义和全部使用 VPN，不按路由配置另存一份。
默认系统解析且 Happy Eyeballs 关闭，保留原 `AsIs` 拨号路径，不新增引导 resolver；
未保存过新设置的用户不会因此改变服务器地址解析。Raw、Remnawave 完整配置与高级模板不应用此全局设置，
保留各自编译边界，也不因保存停用偏好而重连。

显式策略使用 Core DNS 解析服务器，可选择地址族或地址族优先次序；`Use` 策略解析失败仍可能回退系统解析，
不承诺严格禁止另一地址族。拨号策略、`dns.queryStrategy` 与路由匹配的 `routing.domainStrategy` 是不同层次，
不互相替代。Happy Eyeballs 只在 IPv6 开启且选择系统默认或双栈解析时应用，系统默认同时开启它会使用 `UseIP`。
App 设置 250 ms 竞速延迟，其余竞速参数由 Core 管理；关闭开关不移除系统拨号器自身的双栈回退。
关闭时清理托管物理连接中原有的 HE 设置，包括 XHTTP 实际下载连接和 Fragment 辅助出站；
系统默认策略仍不新增引导 DNS，也不因此覆盖其它 socket 字段。
单地址族与有先后顺序的解析不应用此开关，但保留保存值，IPv6 交互见 [IPv6 策略](#ipv6-策略)。

运行副本只修改实际打开物理 socket 的代理出站，不改 TLS SNI、HTTP Host 或存储中的节点原文。
代理链的后续节点继续由上游代理解析，策略落在物理接入；使用 Fragment 时落到最终辅助出站。
XHTTP 独立下载按实际生效的配置对象处理自己的地址与 socket，`extra` 替换和 `penetrate` 继承沿用 Core 语义；
XDrive fronting 使用实际物理地址。普通 direct 出站和无物理拨号的中间链不统一覆盖。
WireGuard 使用 `peers[].endpoint` 的 host，保留其端口、本机隧道地址与 `remoteDNS`。
Core 在发送 UDP 前使用 WireGuard 自身的 socket 策略本地解析 peer，即使通过代理链也应用地址族策略与引导 DNS；
其 UDP 连接不应用仅适用于 TCP 的 HE 竞速，共享 Fragment 的 TCP 连接仍可使用 HE。

显式拨号需要解析域名时，App 从实际物理端点收集去重后的精确域名，前置专用 bootstrap resolver，
复用隧道 DNS 的 IPv4 地址和启用时的 IPv6 地址，并用独立 tag 的前置规则固定直连。
这些精确匹配不成为通用备用，最后一个引导 resolver 截止普通代理/FakeDNS 回退，
避免连接代理前又经该代理解析其地址。匹配按域名而非请求调用者区分，App 查询恰好相同域名时也使用引导 DNS；
这会优先于该域名原有的业务 DNS 规则。仅 IP 字面端点不增加引导 resolver 或规则。

设置保存在现有连接配置 JSON，无需改变数据库结构；运行使用启动时快照。
未连接时保存不启动 VPN；已连接且有效值变化才确认并先停后启，取消不保存。
不同偏好产生相同有效值时仅保存，下次切回适用条件再使用原选择；其它平台策略仍独立按原规则比较并重连。

### FakeDNS

智能与各常规自定义分别保存 FakeDNS 开关，全部使用 VPN 不受影响。
开启后添加 `app-dns-fake`，直连域名仍使用真实直连 DNS，其余经 dnsOut 的 A/AAAA 可返回虚拟地址。
代理域名块按 FakeDNS、真实代理 resolver 排列，只在最后一个真实 resolver 截断，
`IPIfNonMatch` 的真实解析跳过 FakeDNS 后仍有真实 resolver。连接仍按完整规则，不保证拦截应用自带 DoH/DoT。
普通池为 `198.19.0.0/16`、`2001:2::/48`，各 32768，始终成对生成；IPv6 关闭时由 DNS `UseIPv4` 限制查询。
FakeDNS 池独立于 TUN 接口地址，后者继续使用 `fc00::1/64`。
托管入站默认 HTTP/TLS/QUIC 嗅探增加 `fakedns` 以还原域名。

高级/Raw/Remnawave 的显式池和 DNS 保留用户配置，根级 `fakeDns`/`fakedns` 两种写法均识别。
Raw 只给新建 tunIn 添加默认还原，已有 sniffing 不自动修改；高级模板省略 sniffing 时使用默认值，显式填写整对象保留。
池映射随 Core 销毁，重启后的缓存虚拟地址可能无法还原；App 不清系统 DNS 缓存或改用户排除路由。

### 嗅探

智能/常规自定义共用 `RoutingSniffingSettings`，用于托管 TUN、MSIX 私有 SOCKS 与普通 LAN SOCKS。
默认 enabled=true、routeOnly=false，识别 HTTP/TLS/QUIC；metadataOnly=false。
页面开放启用、仅用于路由；metadataOnly 位于更多项，开启后不读取 HTTP/TLS/QUIC 内容。
停用时保留 routeOnly/metadataOnly 偏好；FakeDNS 要求嗅探开启。
普通模型和表单不保存 `domainsExcluded/ipsExcluded`，高级/Raw 原生支持及 JSON 字段提示保留。
旧 Smart 设置、本机普通数据库与备份内部读取忽略这些退休字段，不改原文；外部普通 JSON/分享导入仍拒绝。
高级/Raw 中匹配 FakeDNS 域名或池的排除规则可能阻止目标恢复，不由普通表单改写。
高级模板显式 sniffing 完整保留，省略沿用默认；Raw 的原对象不由普通设置覆盖。

### 运行自动选路

轮询/最低延迟属于每份智能/常规配置，独立于连接前节点选择和手动测速。运行仅观察本次已选代理链，
无最终出口观察 `app-entry-i`，有最终出口观察 `app-exit-i`，覆盖出口、接入和 Fragment 的完整链路。
selector 与 subjectSelector 来自实际完整运行 tag，不把辅助出站混入。代理 DNS 使用相同 proxy balancer；
直连 DNS 仍走 direct。新连接按观察结果选择，既有 TCP/UDP 会话不迁移，不把全列表节点动态加入 Core。

默认探测 URL 为 `https://www.google.com/generate_204`，间隔 60s，并发探测开启。
普通页面提供 30/60/300 秒，导入/高级参数接受至少 10 秒的有限 Go duration；URL 必须为合法 HTTP(S)。
停止/重连后的旧观测不混入新运行。连接页复用 metrics 展示链路未知、可用、失败、延迟和最近探测时间；
无报告或 metrics 暂不可读显示未知，不判定 VPN 已断开，不写入手动测速缓存。
Alive 只表示探测 URL 的 HTTP 可达性，不表示 Netflix 解锁、AI 服务可用、带宽或已有连接实际出口。

### Fragment

智能与各常规自定义分别保存 Fragment 开关，默认关闭，全部使用 VPN 不受影响。
开启时使用 `protocol: freedom`、`tag: fragment` 的辅助出站；默认 `settings.fragment` 为
`packets: tlshello`、`length: 100-200`、`interval: 10-20`。
运行把接入节点接到该出站；智能最终出口链路保持 `最终出口 → 接入 → fragment`，balancer 仍选择完整链路。
Windows/Linux 给 fragment 的物理 socket 绑定已选网卡。

常规路由导入后保留辅助出站的自定义参数，编辑其他字段不重写它们。
高级模板存在该 freedom 出站即开启，填槽时自动接入所选节点，参数仍由模板管理。
Raw 保留用户链路，App 不根据 fragment tag 自动接线。

## 常规自定义路由

`RoutingProfile` 经 Base64 解码为 `XrayJson`，再转换 `RoutingProfileState` 供业务/UI 使用。
持久化/导出的 outbounds 以 1–3 个空接入槽开始，随后可有一个 [Fragment](#fragment) freedom 辅助出站；
其它非空节点（含 direct/block）拒绝导入，不兼容转换。
direct/block 只在校验/运行时生成，规则的动作引用保留。名称存于表列，交换 JSON 根部可用 `name`。

规则支持域名、目标 IP、目标端口、网络、协议和 localOS；不同条件为 AND，列表/反选遵循内核语义，建议填单一条件。
名称使用 `ruleTag`，顺序决定匹配，无自定义停用字段。
动作仅 `balancerTag: proxy` 或 `outboundTag: direct|block`。
协议是嗅探到的流量协议而非节点协议；localOS 是 Core 所在系统。
逐条域名/IP 输入使用实际安装 Geodata 补全；协议/系统位于“更多匹配条件”，已有值展开并保留。
普通模型不开放 process、来源 IP/端口、HTTP attrs 或额外入站等高级匹配。
不支持的结构拒绝导入，不静默丢字段；更多能力使用高级模板或 Raw。

DNS 使用标准 servers，固定 proxy/direct tag 保存主 resolver 与有序备用地址，
root 保存全局缓存和同出口备用；`app-dns-fake` 表示 FakeDNS。运行池、domains、派生
finalQuery 和平台 queryStrategy 编译时产生，不另存第二套规则。旧单直连地址读入主直连 resolver。
嗅探通过唯一 `inbounds:[{tag:"tunIn",sniffing:{...}}]` 占位保存，开放 enabled/routeOnly/metadataOnly，
destOverride 由 App 固定管理；普通文档不开放实际监听、平台 settings 或嗅探排除列表。
选路通过唯一 tag 为 proxy 的 strategy.type，以及 observatory 的 probeURL/probeInterval/enableConcurrency 保存；
运行 selector/fallback/subjectSelector 由 App 生成，导出不包含它们。
其它 DNS 查询缺省代理；显式直连/空答案通过空槽及可选 Fragment 后的受控 `dnsOut` 辅助出站保存，
只含 A/AAAA hijack 和 direct/return 两条固定规则，不包含 socket、改写目标或运行 loopback。
其余缺省沿用原默认；不支持的结构仍明确拒绝，不依赖数组位置标记 DNS resolver 角色。
`geodata.assets` 仅为交换依赖元数据，导入后从存储 JSON 删除，省略默认文件，详见 [数据管理](data-management.md)。

规则子页只改草稿，不重复验证内核字段。保存/导入用 freedom 占位替换空槽，补齐相同 proxy balancer、
Observatory、direct/block、DNS 和资产路径，再由 libXray 构造验证；嗅探保留在安全 SOCKS 投影中，
移除真实 TUN/平台依赖，不选真实节点、不启动 VPN。
依赖发布和失败回滚复用导入事务，实际节点组合由运行 Core 处理。

## 高级自定义路由

高级模板保留 Map，类型存于 `RoutingProfile.advanced`，不嵌入 JSON；共享名称、数量和保存流程。
outbounds 以 1–3 个连续空槽开始，后续只开放 freedom/blackhole/dns 辅助出站。
运行以真实节点替换槽并置顶，随后用户辅助出站，最后 App direct/block；固定节点选择替换整个槽区。
App 添加 proxy balancer、完整 selector 与运行观测范围。模板有限开放 strategy.type 的
roundRobin/leastPing，以及 observatory 的探测 URL/interval/concurrency；selector/fallback/subjectSelector
仍由 App 生成，不能定义任意额外 balancer。轮询 direct 回退，最低延迟回退首条完整代理链。
模板不能定义 direct/block/proxy 或引用内部 app-entry/app-exit tag，dialerProxy 不支持 balancer。

模板完整管理 DNS、routing.domainStrategy、rules 顺序与 ruleTag，不隐式补 DNS server、53/853 规则。
轮询不追加兜底；最低延迟只在用户规则之后为托管 tunIn 和启用的 app-lan-proxy 增加代理兜底。
额外高级入站由模板显式使用 balancerTag:proxy，不自动纳入兜底。
App 管理日志、metrics、统计、policy、env、运行 balancer/observatory 范围、出口网卡和 DNS 查询策略。
额外入站开放 socks/http/tunnel；tunIn 只开放 tag/sniffing，平台部分由 App 生成。
额外规则开放 inboundTag/localIP/localPort，不开放 process、source/sourceIP/sourcePort、attrs 或 user。
辅助出站 streamSettings 仅开放 sockopt.dialerProxy。其他当前字段边界由模板解析器维护，不推广到完整 Raw。

校验使用同一填槽逻辑与本地 freedom，保留 DNS/辅助出站/额外入站/规则，tunIn sniffing 用安全 SOCKS 验证。
不测速、不 Start、不加启动预检；保存、依赖发布、回滚与普通路由共享。
导出只含槽和用户配置，依赖声明仍仅为交换元数据。

## 完整配置的 VPN 适配

个人 Raw 与提供方完整配置在深副本上共用 `VpnConfigAdapter`，补齐 VPN 入口与 DNS 链路。
高级模板不使用这套补充；普通模式继续按自身 DNS 与路由设置编译。
已有节点、首出站、代理链、业务规则、balancer、observatory 和显式 DNS 保持原有语义，新增辅助出站追加到末尾。

可移植适配按需补充 `tunIn`，新建时使用现有默认嗅探及 FakeDNS 识别；已有入口的 sniffing 保留。
若已有显式单值 `port: 53` 的规则，且 `inboundTag` 缺省、为空列表或包含 `tunIn`，即尊重该 DNS 声明。
判断接受数字或字符串 53，不推断 network、domain/IP 条件、端口范围、规则优先级或目标协议是否覆盖全部 DNS。
缺少声明时复用第一个 DNS 出站，或新增一个，再前置限定 `tunIn + TCP/UDP 53` 的规则。
已有 DNS 出站的设置与目标不改写；新建 DNS 出站劫持 A/AAAA，其它查询类型直连转发，
通过专属 `app-vpn-dns-direct` freedom 出站拨号，不依赖用户代理链。
Raw 新建 DNS 出站使用 `app-vpn-dns`，提供方沿用 `app-remna-dns`；复用无 tag 的 DNS 出站时补上对应 tag。
这些补充不增加通用代理、DoT 或 TUN catch-all 规则。

运行编译时，`dns` 缺失或为 `null`，以及 `dns.servers` 缺失、为 `null` 或空列表时，
使用本次隧道 IPv4 DNS 和启用 IPv6 时的隧道 IPv6 DNS 补齐服务器，保留同一对象的 hosts、缓存及其它字段。
新增服务器使用 `app-vpn-default-dns` tag，并用限定该 tag 的前置规则直连 `app-vpn-dns-direct`，
避免连接域名代理前又通过该代理解析地址。仅 App 新增的缺省 DNS 采用此出口；
已有非空列表完整保留，包括显式 `localhost`、DoH 和 FakeDNS，查询地址族仍由 App 平台策略管理。
错误类型不转换成缺省配置，继续交给 libXray 验证。

保存校验和复制/分享复用可移植适配，不写入本机 DNS、TUN FD、运行端口、资源路径或网卡。
运行注入只改副本；`app-vpn-dns-direct` 与 `app-vpn-default-dns` 为 App 补充 DNS 使用的保留 tag。
需要补缺省 DNS 时，保存与导入同步检查这两个 tag 的冲突，不在校验副本中注入本机或占位 DNS。
系统 DNS、Core DNS 与 Go resolver 属于不同层次，补齐 Core DNS 不表示接管应用自带 DoH/DoT。

## 提供方完整配置

`CoreConfigType.Remnawave` 归属于订阅，每项数组对象是一条完整配置。名称与来源身份在行元数据保存，
固定选择或自动选择均编译一份完整图，不按 App 接入数量拆分、测速或拼节点；缺行、来源或 mode 不兼容明确失败。
服务器和托盘仍只提供原有选择入口，完整配置来源可以浏览并逐项固定选择；自动选择策略固定，不新增选项。
导入和双缓存合同见 [订阅](subscriptions-and-sharing.md#完整-xray-json)。

运行顺序为提供方原始配置 → `RemnawaveAdapter`（包含共享 VPN 适配）→ 共享 Raw 编译。适配和编译只修改深副本，
Raw 管理资源路径、Geodata、日志、metrics、stats/policy、IPv6 DNS 查询策略、物理网卡、端口与平台 TUN 字段。
不叠加 Smart/Custom 业务规则、地区直连、App Fragment 或 LAN 共享。
已有入站/出站的相对顺序、原 routing 规则顺序/domainStrategy、DNS、balancers、observatory 和链式引用保留，
仅调整接入 TUN 的 tag 与直接相关的入口规则，按需增加系统入口、出站及 DNS 规则；
共享 Raw 的 App 托管字段仍按下节覆盖，不能把运行称为原文逐字透传。

`RemnawaveAdapter` 在共享 VPN 适配前处理提供方入口与必要系统出站，保存校验、运行、复制个人 Raw 和完整分享使用同一适配：

- 已有 `protocol=tun` 时优先复用 `tag=tunIn` 的入站，否则复用第一个 TUN。保留其位置、设置和 sniffing，
  将选中入口的 tag 统一为 `tunIn`，只在 `routing.rules.inboundTag` 中同步原 tag。
  没有 TUN 才在入站首位新建。平台字段仍由共享 Raw 注入，Android/Apple 使用原生 FD，MSIX 使用私有 SOCKS/TUN 后端。
- 新 TUN 沿用 Raw 的默认嗅探与 FakeDNS 识别；第一个 SOCKS/HTTP 入站提供 sniffing 时，
  将该对象完整深复制到新 TUN，保留显式关闭等设置。已有 TUN 不从其它入口复制或补充 sniffing。
  原 SOCKS/HTTP 入站保留，限定这些入口的规则向 `inboundTag` 补 `tunIn`，其它条件与原 tag 保留。
- 按 tag 检查 `direct` 和 `block`；已有定义保留，缺少时分别在末尾补 `protocol=freedom` 和 `protocol=blackhole` 出站。
- 随后复用[完整配置的 VPN 适配](#完整配置的-vpn-适配)，按需补充 DNS 出站和入口规则；设备 DNS 缺省在运行编译时补齐。
- 适配后的配置交由既有 libXray 校验与启动流程处理。除接入 TUN 的入口规则外，不重写其余图的 tag、
  链式引用、balancer selector 或观察 subjectSelector，不增加第二套内核合法性校验或通用补全。

`IPIfNonMatch`、默认首出站和 provider 已有兜底仍遵循 Core 语义；App 不把 balancer 存在当作默认出口。
按需新增的 DNS 规则只接管 TUN 的 TCP/UDP 53；其它流量保持 provider 业务规则，不补通用 proxy/direct/DoT 或 TUN catch-all。

编译结果和 start metadata 保存 profile ID/source ID/name/type，准备、待启动和运行引用都保护完整配置原行。
更新和 mode 切换不热替换运行；连接页仍使用启动时名称快照。App 路由控件停用并解释偏好保留，
Smart/Custom 保存只更新未应用偏好，不为提供方会话重连；平台隧道等有效设置仍沿原确认重连规则。
提供方内部 balancer/observatory 由 Core 执行，不显示为 App 手动延迟或普通自动链路观察。

## Raw JSON

Raw 保存原文，不经过 `XrayJson` 或常规 State，运行只改深副本。
App 共用[完整配置的 VPN 适配](#完整配置的-vpn-适配)，接管 tunIn 的有限平台设置、metrics、统计、日志、
DNS 查询策略、资源路径及出口网卡；其余内容保留。Raw 只补新增配置实际引用的辅助出站，不统一补 direct/block。
不允许额外 TUN、重复 tunIn 或占用 App 保留端口。运行端口分配避开用户入站及本地 HTTP API 的保存端口；
完整 Raw 不应用局域网共享设置，也不为共享预留端口或限制其入站 tag。

已有 tunIn 保持数组位置、sniffing（含缺省/关闭）和非托管设置；仅覆盖 name、mtu、gateway、dns、
autoSystemRoutingTable、autoOutboundsInterface。原生 TUN 平台生成六项，Apple/Android 仅 name/mtu，移除其余托管项。
无 tunIn 才新建。MSIX 转为私有 loopback SOCKS，保留不需转换的内容。
Windows EXE 默认补 autoSystemWfpBlockLeak，显式列表保留；Linux autoSystemDnsToGateway 保留用户值。
来源 `env` 中的 `xray.tun.fd` 和 `XRAY_TUN_FD` 在校验与运行副本中删除，Apple/Android 原生启动时注入本次真实 FD；
其它未知 env 保留，桌面配置不携带来源中的旧 FD。
系统 DNS/TUN 特定要求见 [隧道与平台策略](#隧道与平台策略)。

iOS 模拟器完全由 Swift 判断，将 tunIn 转为 SOCKS，原子写回 run/start.json，再用同一 coreInvokeText 调用 libXray。
写入失败不启动，数据库/编译输入不变；状态使用 getXrayState 和原生通知，启停直接调用 libXray。
真机和 macOS 使用系统 VPN，Dart 无 debug 模式分支。

保存校验先应用同一可移植 VPN 适配，再裁剪 App 托管项：去除下载任务/metrics，关闭日志与采集，tunIn 转最小 SOCKS 但保留待检 sniffing。
保留用户节点、路由、DNS 和必要模块依赖，stats 使用最小对象避免 API 假错误；不删除整个 policy/DNS/streamSettings。
原文及运行配置不受投影影响。
`testXray` 执行 LoadConfig → New → Close，不 Start；允许进程级副作用，不做环境快照恢复。
通过只证明投影能构造/关闭，不保证监听、TUN、授权或连通性；必要本地文件缺失直接报错，不下载兜底。
同进程已有受管理 Core 时 testXray 拒绝，需重连的编辑遵循先停后校验，不绕过生命周期。
Android VPN 的 :native、Apple 真机 extension 和桌面 session Core 与 UI 的串行 Invoke 通道隔离，
因此不按全局 VPN 状态预先禁止完整订阅校验；iOS Simulator 的代理 Core 可在同一 App 进程，仍保留已有拒绝。
刷新通过不表示真实 VPN/网络/平台已验收，需对应环境验证隔离及当前会话持续运行。

## 局域网代理共享

Device platform policy stores the sharing switch and port, defaulting to disabled and `11024`.
These settings are not embedded in intelligent/custom routes or Raw source, and connection backups
do not transfer them between devices. On the next App-compiled start/restart, enabled sharing adds
one `app-lan-proxy` inbound to normal/custom routing, including advanced templates:
`protocol: socks`, `listen: 0.0.0.0`, `auth: noauth`, `udp: true`. No separate HTTP inbound is created.
The listening address is fixed. The port supports HTTP, including CONNECT, and SOCKS5;
UDP uses SOCKS5 UDP ASSOCIATE. Core allocates UDP relay ports dynamically, so allowing only
`11024/UDP` does not guarantee UDP connectivity.

This is an explicit proxy, not a gateway or hotspot traffic capture. Clients use the device's actual
network address and sharing port. `0.0.0.0` is a wildcard listener, not an access restriction:
any reachable client can use it without authentication. Enable it only on trusted networks.
The App HTTP API and metrics remain loopback-only. Shared traffic follows the compiled routing;
the App does not force proxying or rewrite user `inboundTag`. Rules limited to `tunIn` do not match
the shared inbound. Managed sniffing includes FakeDNS restoration when required.

Saving the switch or port only persists policy. It does not prompt for a restart, start/stop VPN,
modify the current runtime, invalidate/rewrite `run/start.json`, change Apple's provider request
or on-demand rules, or create a saved-start protection marker. The change takes effect only when
an App start/restart compiles fresh input. Widget, Tile, Android automation and Apple on-demand
starts keep the last generated configuration until that happens, including its sharing setting.
Turning sharing off in settings therefore does not close an existing listener. Stopping VPN closes
that running listener but leaves the saved input unchanged; a background start can still reuse it.
Other platform-policy changes retain their existing reconnect behavior.

Complete Raw JSON and provider configurations are unaffected by managed sharing. In these modes, saving sharing settings only
stores them for other modes; no inbound is added and no sharing-specific tag/port conflict is imposed.
Inactive advanced-template conflicts are not checked when a provider configuration is selected or running.
The configured sharing port is `1024–65535`. In applicable modes, enabling sharing checks the saved
HTTP API port and the selected advanced template's inbound ports/tags; user inbounds are not silently
replaced. HTTP API port edits also avoid enabled sharing's configured port. Actual external port
occupation is reported by Xray startup. These input checks do not modify any existing runtime.

Cross-platform UI/configuration support is not equivalent to device acceptance. Apple explicitly
does not support hosting listeners/proxy servers in Packet Tunnel Providers; the extension-based
implementation retains platform-support and review risks, and the iOS main App is not a reliable
long-running background proxy. See [Apple TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers).
Cross-device connectivity, UDP, firewalls, lock screen and signed channels require platform testing.

## 隧道与平台策略

TUN 地址只读，隧道 IPv4/IPv6 DNS 与 Apple DoT 域名可编辑，独立于路由 DNS，保存在平台策略 JSON。
原生 DNS 必须是对应地址族 IP；DoT 域名不是搜索域，需与服务器证书匹配。
有效设置变化按已连接确认重连；停用的域名/IPv6 设置保留，不因其变化重连。
Windows/Linux 给 Xray 明确绑定已选网卡，Vole 不新增绑定要求，Raw 不能覆盖。
Windows EXE 使用 Xray 原生 TUN/Wintun，MSIX 使用私有 SOCKS 和 Vole UWP 系统隧道。

EXE 默认 autoSystemWfpBlockLeak: [dns]，Raw 可用 [] 关闭；不启用 misconfigtun，也不承诺阻断所有 DoH。
Linux 不默认接管系统 DNS；Raw 的 autoSystemDnsToGateway 依赖可工作的 systemd-resolved/resolvectl、
独立 Core DNS 及相应 DNS 出站规则，App 不探测发行版或失败回退。
强杀后系统 DNS 可能需手动恢复；这些 Core 平台能力不在 Dart 重复实现。

### Apple 路由与 VPN 图标

排除网段仅在关闭 includeAllNetworks 时传入 NE excludedRoutes，默认空，不自动加私网或修改 Xray/DNS。
开启全流量时保留但不校验/应用停用列表，其变化不重连；关闭 IPv6 同样不传对应路由。
保存只检查原生 CIDR/网络地址要求，不沿用 Windows 限制，不提供企业 Split DNS。
iOS/iPadOS 隐藏图标默认关闭，仅非全流量时生效：运行副本追加 0.0.0.0/31，IPv6 开启另加 ::/127。
不写回用户列表，不改变状态来源；依赖系统路由行为，可能影响网络切换，不保证所有系统版本隐藏。

### IPv6 策略

关闭时 Apple/Android/Linux/EXE 不配置隧道 IPv6 地址、路由和 DNS；MSIX/Vole 保留自身处理。
DNS 查询关闭时设为 UseIPv4，开启 UseIP；普通按 server，Raw 同时根级和对象 server。
全局服务器拨号的显式非系统策略在关闭 IPv6 时按 UseIPv4 生效，Happy Eyeballs 停用，保存的策略与开关不变；
系统默认仍保留原 AsIs 路径，不因关闭 IPv6 额外强制 Core 解析。
不额外屏蔽 IPv6 流量、不加 ForceIPv4/hosts，也不拒绝 IPv6 字面节点；Raw 用户其他 IPv6 字段保留。

## JSON 编辑辅助

节点、高级模板与 Raw 共用 re_editor、本地诊断和轻量补全，常规路由继续表单。
语法错误按原文 UTF-16 offset 给出行列；App 结构错误可给明确字段路径，歧义不强行定位。
libXray 原始原因完整可复制，不猜字段，不把投影行号当原文位置。
改文本清除旧错误，光标移动不清除；迟到结果不标记新草稿，保存期间的新编辑保留并提示未保存。
停顿只查本地语法，显式保存才走既有验证/依赖流程，不自动重连或修复用户 JSON。
补全按类型/位置过滤常用字段、枚举、tag 和安装的 Geodata，不作白名单、不猜凭据。
保留引用与撤销历史，组字/非折叠选区不补全；候选支持点击与键盘，内容 LTR、文案跟随语言。
文件/剪贴板错误完整展示，仅原 JSON 语法错误提供原文位置，不把链接/下载失败伪装成编辑位置。
提示按字段所在模块区分 DNS 查询、路由匹配与拨号策略，支持 Core 的地址族优先次序、Force 策略和 Happy Eyeballs 对象；
DNS 查询不提示拨号的地址族顺序，保留 UseSystem。XDNS、MASQUE WARP、TLS 和 DNS/嗅探仍按原生结构提示。
高级模板只提示其可保存的策略/探测字段，不提示运行 selector/fallback/subjectSelector；Raw 保留完整模块提示。
MASQUE/XDrive 的 XMUX 与出站 mux 分开提示；XDNS resolver 的 TLS/QUIC 与普通 TLS/ECH 复用对应模块提示，限定各自归属。
XDrive template 提示限定在节点/Raw 的原生传输对象，覆盖认证、操作和重试；`hrefPath/hrefMethod` 只提示在操作对象。
HTTP 方法仅给常用候选，headers/form、URL、JSON 路径、模板变量和未知字段保持自由编辑，保存及分享不投影嵌套 Map。
Lua 不属于 JSON 编辑提示、普通模型或资源管理范围。

## 运行协调与统计

`ConnectionCoordinator` 串行停止并确认旧运行，再准备/启动/确认新运行，最后提交设置。
run/start.json 是唯一原生启动请求：coreInvokeText 为实际输入，metadataJson 仅还原运行描述、资产保护和起始时间。
旧 metadata 缺 profile 仍能恢复；提供方 profile 字段与 nodeIds 保护完整配置，不因 entries 为空而丢失身份。
不另存 App 计划、快照或跨进程提交日志。文件队列在连接命令取得执行权后进入；只读状态/metrics 不入队。
停止失败不继续准备；启停已开始后的失败尽力停止本次运行并进入 failed，不恢复旧连接/输入。
不能确认停止时仍以原生状态为准，缺少 metrics 或描述不等于断开。

桌面启动前在旧 Core 停止后清理 core-inputs，生成本次唯一输入和 error 文件，通过 -error-file 获取加载/构造/启动原因，
无诊断才用通用错误，不再运行 testXray。发布需包含支持该参数的 Core。
MSIX snapshotToken 只验证 Vole 宿主会话，不是可删的 App 快照。
EXE/Linux 按精确 Core 进程名管理全部匹配实例，不保存 PID/路径归属记录；停止可影响其他安装的同名 Core。
只有确认全部退出才断开，查询/提权/监测失败不伪装空闲；过期查询不更新状态。
Geodata 始终使用唯一平铺 datDir，启动不复制文件；SE 跨容器传输见 [数据管理](data-management.md)。

### 状态同步

先订阅再读原生状态，必要授权见 [App 启动](app.md#平台前置条件与权限)；回前台/可见或重新获焦时校准。
业务层无统一状态轮询或启停缓存，操作前查询平台；UI 状态只展示。
Apple 使用 NE 状态通知，Android 使用资源查询/生命周期广播/进程退出通知；EXE 用进程句柄退出，
Linux 用自身 exitCode 或接管 pidfd（不支持时报错，不降级轮询）。
仅 MSIX 内部每 5 秒检查系统 VPN，启停有界快速确认，不随隐藏/失焦停止。
startVpn/stopVpn 成功返回已确认状态，不仅是“提交命令”；只读返回不通过回调绕行，每次同步只读一次 start.json。

Android 每次原生启动使用内部单调 request ID，启动 Intent、Binder 查询和状态广播携带相同身份，
不关联订阅或配置记录。App 在交付启动前绑定本次身份，旧运行迟到的成功、断开和错误广播不完成或拒绝新命令。
启动中的广播只用于建立 Binder 退出订阅，Core 成功后才确认已连接；本次启动失败、取消或进程退出仍及时失败。
Widget/Tile 与 saved-start 使用同一身份合同，无 App 待处理命令时也能同步其新运行。

### 本次流量

可见连接页且已连接时共享一个秒级 metrics 采样器；resumed/inactive 均可见，失焦不重置基线。
无可见连接页、隐藏/后台或断开停止；重新显示建立新速率基线。仅重建流量区域，高级时长用独立本地时钟。
GET /debug/vars 仅统计 stats.inbound 的 `tunIn` 本次上下行，局域网共享及其它入站均不计入；
相邻有效样本算速率，未创建计数按零。Android 通知/Widget 使用相同范围。
失败保留内存计数、速率不可用，恢复重建基线。断开清空，无累计持久化/清零/独立 libXray 统计服务。
运行描述定位 metrics 端口，不以读取成功判断连接状态。

Android OneVpnService 独立秒级采样供通知/Widget，亮屏运行、熄屏暂停清速率，失败不重连。
不使用额外前台服务/WorkManager/闹钟；正常停止、撤权、销毁取消，强杀不保证即时 Widget 刷新。
Provider 与 VPN 同处 :native，流量只在内存传递，不写文件/Preferences。仅 localhost 开放 metrics 明文例外。
Widget 使用系统语言/主题、4×2 紧凑布局；语言/尺寸变化只刷新展示，不启动采样。

Widget/Tile 共享原生 saved-start：完整 start.json 且权限就绪则直接启动 VPNService，不打开 Flutter。
缺输入/权限才复用 App 启动入口；不重复预检或下载，重复启动按服务自身资源处理。
复用最后生成的配置/端口/节点，不读库重选或测速，更新会话时间并重新创建 TUN/fd；失败通知，不自动重试。
关闭直接原生停止，数据区只打开 App。广播自动化复用此入口但有独立授权及清理阻断，见 [外部接口](external-interfaces.md)。
