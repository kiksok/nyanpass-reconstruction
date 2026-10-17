# Linux 部署

支持现代 glibc Linux amd64 / arm64；推荐 Debian 11+、Ubuntu 22.04+。Alpine/musl 不受当前内置 Node 运行时支持。需要 bash、curl、CA 证书、sha256sum；离线包另需 unzip。systemd 安装使用 root；无 root 可用 `--no-systemd --prefix /home/用户名/nyanpass`。

## 面板

```bash
bash <(curl -fLSs https://github.com/kiksok/nyanpass-reconstruction/releases/latest/download/nyanpass-install.sh) rel_backend
```

安装目录默认 `/opt/nyanpass`，服务名 `nyanpass`，监听 `0.0.0.0:18182`。首次安装显示随机管理员密码，配置保存在 `env.sh`，SQLite 位于 `data/panel.sqlite`。安装前可设置 `NYANPASS_HOST`、`NYANPASS_PORT`、`NYANPASS_ADMIN_USER`、`NYANPASS_ADMIN_PASSWORD`。

公网使用时为域名配置有效 HTTPS。反向代理应支持 WebSocket；可以将整个网站代理到面板 HTTP 监听地址。

## 节点

在设备组页面选择“对接”，设置服务名、下载线路、可选连接地址，复制生成的命令到节点机器执行。同组多机使用同一 token，每台机器保留独立 UUID。通配监听时节点自动探测公网IPv4/IPv6和地区并缓存；显式 `--connect-host` 或DNS连接地址优先。多网卡或NAT环境仍应核对入口实际可达性，可用 `--no-public-discovery` 关闭外部发现。没有地区证据时显示未知。

```bash
S=nyanpass-node bash <(curl -fLSs https://github.com/kiksok/nyanpass-reconstruction/releases/latest/download/nyanpass-install.sh) rel_nodeclient \
  '-u https://你的面板域名 -t 设备组TOKEN --connect-host 节点可达IP'
```

支持 `-u/-t/-o`、`--connect-host`、`--direct-port`、`--tls-port`、`--ws-port`、`--udp-port`、`--default-weight`。实际入口/出口角色由面板设备组决定。使用多个服务时必须选择不同服务名和安装目录；面板和节点同机也须使用不同服务名。

## 下载线路

自动模式按可达候选下载并校验 SHA-256，失败后尝试下一条。从面板复制的自动安装命令优先通过面板中转，再尝试 GitHub Release 直连和 GitHub API；均提供本仓库恢复版文件，不调用原厂调度服务。面板中转按固定文件白名单下载并缓存，不向上游传递节点 token。独立运行安装器时默认尝试 GitHub 直连/API；主线路模式固定使用 GitHub Release 下载。

可传 `--download-source auto`、`--download-source github` 或 `--download-source api`。有自建镜像时，可用 `NYANPASS_DOWNLOAD_SOURCES` 指定候选。面板生成的自动命令从面板本身取得 bootstrap 脚本，可用于节点无法直连 GitHub 而面板能够访问 GitHub 的场景。如果所有线路均不可达，应从其他联网机器取得离线包，通过 SFTP 等方式传入。

## 系统优化与运维工具

默认关闭。可在面板对接窗口勾选，或显式运行：

```bash
OPTIMIZE=1 INSTALL_TOOLS=1 S=nyanpass-node bash nyanpass-install.sh rel_nodeclient \
  '-u https://你的面板域名 -t 设备组TOKEN'
```

`OPTIMIZE=1` 应用本安装器管理的网络及资源参数，按内核能力处理 BBR 等设置，保存恢复信息。`INSTALL_TOOLS=1` 通过系统包管理器安装诊断、终端和监控所需工具。离线模式不安装软件包；需要这些工具时应提前安装。安装器不修改防火墙规则。

## 离线部署

面板“对接 → 离线部署”提供 amd64 / arm64 下载链接及本设备组的部署命令。离线包包含该架构的面板和节点二进制、脚本及 SHA256SUMS；无需在目标服务器下载 Node 或依赖。

将正确架构的包上传并重命名为 `offline.zip`，在其所在目录执行面板生成的命令。独立安装方式：

```bash
unzip offline.zip -d ./nyanpass-offline
bash ./nyanpass-offline/offline.sh rel_backend
# 或安装节点
S=nyanpass-node bash ./nyanpass-offline/offline.sh rel_nodeclient \
  '-u https://你的面板域名 -t 设备组TOKEN'
```

## 管理、更新与卸载

```bash
systemctl status nyanpass
systemctl restart nyanpass
journalctl -fu nyanpass
bash /opt/nyanpass/update.sh
bash /opt/nyanpass/uninstall.sh
```

更新保留环境配置、数据库、节点 UUID 和证书。下载完成并校验后原子切换程序；systemd 启动失败时回退到上一程序版本。卸载保留数据，安装器管理的系统优化按记录恢复；数据库不会自动回滚。备份时请保存整个安装目录中的配置、数据库及身份材料。

二进制为内置运行时的 ELF 启动程序，首次运行会在安装状态目录的 `.runtime/` 展开并校验运行文件，因此首次启动需要额外磁盘空间。节点终端需要 python3，ping/tracepath 等诊断需要相应系统工具。

## 发行内容

0.8.1 的新充值订单使用原路径 `/api/v1/guest/payment/支付类型/notify`；已生成的无 `/notify` 地址和按通道名回调的扩展地址继续有效，均需验签后入账。

反向代理后的验证码需要显式配置可信代理地址。首次安装面板前可设置 `NYANPASS_TRUSTED_PROXIES='127.0.0.1/32,::1/128'`；已有安装在面板目录 `env.sh` 增加同名 `export` 后重启面板。只填写实际反代的 IP/CIDR；默认不信任任何转发头。多级代理从 socket 来源向左逐跳验证，遇到未受信任地址即停止。

原 gRPC 节点状态页的更新 URL 由面板转换为下载和安装步骤。已使用恢复安装器的节点保留原服务配置；已核验的 nc20260412 原节点可保留启动参数、UUID、原环境文件和启动脚本备份迁移。未知原二进制或不匹配的目录明确拒绝，管理员可通过运维 API 显式指定命令。安装文件后延后安排 systemd 重启以发送回执，仍须用重新上线的版本确认完成；没有 systemd 的安装需由原进程管理器重启。本轮原 ELF 验证使用临时目录，没有重启生产服务。

Release 提供四个 ELF 文件：`rel_backend_linux_amd64`、`rel_backend_linux_arm64`、`rel_nodeclient_linux_amd64`、`rel_nodeclient_linux_arm64`；另含安装脚本、两种架构的离线包、SHA256SUMS 和发行元数据。安装时无需 GitHub 令牌。

源码与分析工程保留在本地和独立私有归档，公开仓库的 Git 自动源码压缩包只包含本仓库的脚本与文档。

## 0.5.1 节点状态修复

面板与节点均需更新。分别在对应机器运行其安装目录中的 `update.sh`：默认面板为 `bash /opt/nyanpass/update.sh`，默认节点为 `bash /opt/nyanpass-node/update.sh`；自定义服务名时使用实际路径。更新保留账号、数据库、设备组token、节点UUID及证书。面板管理员也可在节点状态页下发恢复版节点的受控更新。

更新后刷新状态页面。新旧两页均能独立初始化，不要求先打开首页或依赖旧浏览器更新缓存。CPU与网卡速率在下一次心跳后得到有效差值；首次采样或旧节点没有上报的指标显示 `--`。无地区数据时显示未知，不推测国家。


## 0.6.0 巡检修复与升级

分别更新面板和所有恢复版节点，使用各自安装目录的 `update.sh`；自定义服务名使用实际目录。更新后刷新浏览器。

```bash
# 面板服务器，默认目录
bash /opt/nyanpass/update.sh
# 节点服务器，默认目录
bash /opt/nyanpass-node/update.sh
```

本版修复站点设置/个人通知白屏、跨用户规则搜索与批量操作、诊断显示、订单与兑换收费、邀请与自动续费、统计与节点权重/离线策略。新增支付回调/补单、Telegram通知与返佣执行；Monaco编辑器资源全部本地化。更新保留数据库和节点身份；有财务历史的账户/套餐删除受保护，可停用/隐藏以保留账务。

配置支付通道需要真实商户资料和网关可达地址。设置回调Host，或在面板 `env.sh` 设置 `NYANPASS_PUBLIC_URL=https://面板域名` 后重启面板。网关回调路径为 `/api/v1/guest/shop/payment/callback/通道名`。Telegram需配置有效Bot并按个人关联提示完成绑定。未配置服务不会伪造付款、关联或通知成功。

Cyber使用原版“订单号+签名通知授权”契约，按已存订单金额入账，额外拦截创建请求重放；原协议未提供独立金额/支付状态/外部流水核验，不应理解为具备这些保证。管理员在原确认窗口中手工补单可用，并独立记录操作者及原因；主动向Cyber网关查询支付状态的协议仍未证明，不伪造查询成功。其他已接入协议包括EPay、EpUSDT、TokenPay、Cryptomus，按各自协议校验。供应商模拟测试不能替代真实商户/Bot验收。

原厂全功能等价、原gRPC运维及原版节点所有版本组合互通仍未证明。ARM64为交叉构建并校验ELF架构，实际运行验证为amd64。

## 0.7.0 单端隧道与 UDP 升级

面板和全部恢复版节点分别执行对应安装目录的 `update.sh`，默认命令如下。保留数据库、账号、设备组令牌及节点身份；升级后刷新浏览器。

```bash
# 面板服务器
bash /opt/nyanpass/update.sh
# 每台节点服务器
bash /opt/nyanpass-node/update.sh
```

新规则默认 TCP + UDP，同一端口分别监听两种协议。**已有 TCP 规则不会自动开放 UDP**，请在单条编辑、用户批量编辑或管理员全局批量编辑中选择“TCP + UDP”。如旧规则使用同一端口分开定义 TCP/UDP，合并前先处理冲突。配置 TLS 入站或设备组禁用 UDP 时，双协议规则只监听 TCP。

单端隧道的 ws、http、tls_simple 支持 TCP 和 UDP，支持同组多机器、下线检测和多级备用出口。入口授权、私有组归属、“禁止单端”及备用组引用均在配置下发时检查；撤权后停止转发。重置组令牌会撤销旧节点发现，须用新令牌重新对接。没有选择隧道协议而保存空配置时，恢复版目前按 direct 处理；原厂后端是否补默认协议尚未证明，建议显式选择上述协议。

UDP 高级行为：

- 负载均衡以每个源 IP + 端口建立的会话选择目标，支持随机、轮询、ip_hash、最小连接数和故障转移；TCP 与 UDP 使用实际活跃连接/会话计数。确认的本地网络错误触发短暂避让和后续会话切换，不重放当前包；无应用层响应的沉默目标不能据此确认故障。
- 规则与用户限速在两个方向生效，IP/连接额度与 TCP 共享；UDP 每个活跃源端点占一个会话，闲置 60 秒后释放。限速队列有界，整包排队或丢弃，不拆成多个数据报。这些共享 UDP 限额是恢复版补齐功能，原版对应路径未证明具备相同限制。
- “发送 Proxy Protocol”中只有 **v2 (TCP+UDP)** 对 UDP 加头，每会话首报包含头，后续是原始应用数据。源地址为可取得的原端点，目标地址为同族零地址、端口 0。首报头 28/52 字节计入 UDP 上行流量；多跳计量排除内部 UDP framing。v1 (TCP)、v2 (TCP) 不会给 UDP 加头。
- 原有“接受 Proxy Protocol”仅作用 TCP。新增“接受 UDP Proxy Protocol v2”是独立扩展：启用后首报必须含 UDP v2 头，后续可裸包；普通 UDP 客户端应保持此项关闭。恢复源地址后才执行额度和 ip_hash，禁止同流中途改源绕过限制。
- UDP-over-mux 可保留入口源端点；原 raw native UDP 格式没有终端源 IP 字段，出口只知道传输对端，不伪造原 IP。
- 普通 UDP 入口接收 1–1500 字节，丢弃零长和超长数据报；内部 raw native UDP 与 UDP-over-TCP 原线格式容量分别是 1956、1984 字节，不能据此发送超过普通入口上限的应用包。
- `BIND_INBOUND=本机IP` 或 `--bind-inbound=本机IP` 控制业务入口绑定；源进源出按相应本机接口绑定。节点之间的 carrier 监听地址仍由各自监听选项控制。

Linux amd64 完成 416 项源码回归、实际安装节点同端口 TCP/UDP 与首报 PROXY 验收；ARM64 为交叉构建和 ELF 架构校验。本轮根据原节点 REA 函数和离线指令核对上述原版行为，没有新增原 ELF 全量互通验收。原厂所有功能、私有源码及任意版本组合等价仍未证明。

## 0.8.0 控制面代理、ECH、gRPC 与持久记账

面板和所有恢复节点都更新各自 `update.sh`。旧 TCP 规则仍需显式切到 TCP + UDP。新建或保存站点/单端出口时必须选择协议；不再把空协议默认成 direct。历史已有空配置记录不自动修改，编辑时请补选实际协议。

第三方代理按原 `NYA_PROXY`、`HTTPS_PROXY`、`HTTP_PROXY` 的优先级作用于面板 REST 和 gRPC 控制通信，不改变设备组的原生隧道协议。支持 HTTP/HTTPS、SOCKS、SS、Trojan/Trojan-Go、TUIC，以及已确认的 SS 插件和 Trojan 传输/加密变体；可在节点安装目录 `env.sh` 中配置 `export NYA_PROXY='代理URL'`，重启该节点后生效。代理不支持所需协议或失败时返回错误，不回退直连。部分原 URL 的 TLS 不验证证书语义也被保留，使用时按该 URL 参数选择信任策略。

自动节点接受原参数 `-ech`、`-ech-query-name 名称`，可重复查询名；`--ech-resolver IP:端口`、`--panel-ca CA文件` 可用于明确解析器和私有CA。正常 `-ech` 在发现失败时按原路径使用经过证书验证的 TLS；`--require-ech` 要求 ECH 被实际接受。ECH 与代理组合仍保持面板端到端 SNI/证书验证，适用于配置、流量上报、终端及运维。

原 nzproto gRPC 的任务/系统信息/终端双向流已接入面板，未修改原节点可用原 `/api/v1/client/upgrade_grpc`。恢复节点默认继续 HTTP 受管运维；添加 `--operations-transport=grpc` 可显式使用原 wire。管理员对原节点的更新通过原 UI 提供的 `clientScript` 执行并审计摘要；重启需要明确脚本或面板配置的受管命令，不猜测现有服务名称。恢复节点默认更新仍只执行自身安装目录的标记更新器。

自动节点的 state 目录默认保存 `traffic-outbox/`：重启可恢复已写计量和未确认批次，面板持久收据防止重试重复收费。默认名义 50ms 批量同步；`--traffic-sync-ms=0` 逐笔同步。SIGKILL 与断电界限不同，断电可能丢失最后一次同步后的记录；网络发送到计量回调之间不是原子事务。不要在未核对账目时删除 outbox 或故障锁；损坏、磁盘故障和并发进程占用会停止记账及转发，避免悄悄归零。设备组令牌、面板地址或设备 UUID 改变会使用独立账本范围。

普通 HTTP Host/path、透明 TLS SNI、SOCKS 识别进入实际入口；TLS 卸载后也可检查 HTTP。HTTP/1 每个持久请求和 HTTP/2 每个头块都检查，未知加密应用不会被伪称解密。PROXY v2 UNIX/LOCAL/任意合法 TLV 保留原字节；恢复节点间使用协商扩展，不支持该元数据的原/旧节点明确拒绝该路径，普通 IP 头继续使用原格式。

原反向标准路径 `/ws/<入口group_uuid>` 与原 remotes 下发已接通，mux/direct 均验证真实 TCP/UDP。原控制握手没有恢复 HMAC，兼容入口要求已配置且通过面板注册的设备 UUID、注册 IP 和认证数据回拨；`reverse_require_proof:true` 可仅允许现代 HMAC 控制端。原中继额外 TCP 前缀现象仍保留在兼容模式，正常多跳使用恢复版 clean-chain。

节点二进制内置未改官方 sing-box v1.12.10 独立程序及其完整第三方对应源码，不需要另行下载。提取上游源码而不启动节点：

```bash
/opt/nyanpass-node/current/rel_nodeclient --third-party-source > sing-box-corresponding-source.tar.gz
```

这份归档包含官方主模块、108个固定版本依赖、许可和构建材料，没有恢复版源码、原厂程序或用户配置。GPL/MIT 等许可说明随包保留。ARM64 继续是交叉构建和架构校验，实际运行验收为 Linux amd64；生产服务未由验收脚本重启。
