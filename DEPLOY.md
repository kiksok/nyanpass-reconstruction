# Linux 部署

支持现代 glibc Linux amd64 / arm64；推荐 Debian 11+、Ubuntu 22.04+。Alpine/musl 不受当前内置 Node 运行时支持。需要 bash、curl、CA 证书、sha256sum；离线包另需 unzip。systemd 安装使用 root；无 root 可用 `--no-systemd --prefix /home/用户名/nyanpass`。

## 面板

```bash
bash <(curl -fLSs https://github.com/kiksok/nyanpass-reconstruction/releases/latest/download/nyanpass-install.sh) rel_backend
```

安装目录默认 `/opt/nyanpass`，服务名 `nyanpass`，监听 `0.0.0.0:18182`。首次安装显示随机管理员密码，配置保存在 `env.sh`，SQLite 位于 `data/panel.sqlite`。安装前可设置 `NYANPASS_HOST`、`NYANPASS_PORT`、`NYANPASS_ADMIN_USER`、`NYANPASS_ADMIN_PASSWORD`。

公网使用时为域名配置有效 HTTPS。反向代理应支持 WebSocket；可以将整个网站代理到面板 HTTP 监听地址。

## 节点

在设备组页面选择“对接”，设置服务名、下载线路、可选连接地址，复制生成的命令到节点机器执行。同组多机使用同一 token，每台机器保留独立 UUID。多网卡或 NAT 环境请填写可被入口访问的 `--connect-host`；默认网卡地址未必是公网地址。

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

Release 提供四个 ELF 文件：`rel_backend_linux_amd64`、`rel_backend_linux_arm64`、`rel_nodeclient_linux_amd64`、`rel_nodeclient_linux_arm64`；另含安装脚本、两种架构的离线包、SHA256SUMS 和发行元数据。安装时无需 GitHub 令牌。

源码与分析工程保留在本地和独立私有归档，公开仓库的 Git 自动源码压缩包只包含本仓库的脚本与文档。
