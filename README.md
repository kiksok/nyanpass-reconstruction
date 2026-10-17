# Nyanpass 恢复版发行

这是 Nyanpass 面板与节点恢复版的 **Linux 二进制发行仓库**。仓库仅提供安装脚本、部署文档及 Release 二进制，不公开恢复工程、分析证据、原厂程序或用户数据。

支持 Linux amd64 / arm64、systemd、保留配置更新和离线部署。二进制内置运行时及 TLS helper，目标机器无需安装 Node.js、npm 或 Go。它是恢复版的独立可执行打包，不是原厂 Go 程序。

在目标 Linux 服务器以 root 执行：

```bash
bash <(curl -fLSs https://github.com/kiksok/nyanpass-reconstruction/releases/latest/download/nyanpass-install.sh) rel_backend
```

默认访问 `http://服务器IP:18182`；安装结束显示初始管理员密码。HTTPS 可由现有反向代理提供。

登录面板后创建设备组，点击“对接”，选择在线安装或离线部署。在线对话框支持自动探测线路、GitHub 主线路、服务名、连接地址及可选的系统优化和运维工具安装。生成的命令下载本仓库恢复版节点。

节点安装示例：

```bash
S=nyanpass-node bash <(curl -fLSs https://github.com/kiksok/nyanpass-reconstruction/releases/latest/download/nyanpass-install.sh) rel_nodeclient \
  '-u https://你的面板域名 -t 设备组TOKEN --connect-host 节点可达IP'
```

完整说明见 [DEPLOY.md](DEPLOY.md)。当前版本 **v0.8.0**，下载见 [Releases](https://github.com/kiksok/nyanpass-reconstruction/releases/tag/v0.8.0)。

0.8.0 接入原控制面第三方代理、自动面板 ECH、原 gRPC 运维、流量磁盘 outbox、HTTP Host/path 与 HTTP/2 检查、PROXY UNIX/TLV 透传，并补做未修改原节点的代理、运维与自动反向 TCP/UDP 验证。原 gRPC 使用范围和原中继差异见部署说明。

0.7.0 补齐单端 ws/http/tls_simple 的 TCP 与 UDP、私有多节点和备用出口；接入 UDP 负载均衡、双向限速、共享 IP/连接额度、首报 PROXY v2、多跳计费及源进源出。修复单端创建、权限撤销、令牌重置和协议显示。

**面板与所有节点均须更新。旧 TCP 规则保留原设置，需要 UDP 时，在规则编辑或批量修改中选择“TCP + UDP”。** TLS 入站或入口禁用 UDP 时只监听 TCP。UDP 入站 PROXY 使用独立开关；普通 UDP 客户端应保持关闭。详细语义与验证边界见部署文档。

恢复版支持原生自动配置、同组多机、TCP/UDP、多跳计费、TLS 卸载、PROXY、终端与诊断。原版商业授权远端服务和任意厂商版本组合仍未全部验证；本发行不宣称原私有工程或全功能逐项等价。

第三方组件及许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和二进制展开后的 `licenses/`。

0.6.0 修复设置/通知白屏、跨用户规则搜索与批量操作、诊断、订单兑换收费、邀请返佣、自动续费、统计和节点策略；接入支付/Telegram执行及完整本地JSON编辑器。已有安装请同时更新面板与节点：分别执行对应目录的 `update.sh`。真实商户和Bot需要配置后验收；Cyber保留原版签名订单通知的校验边界，详见部署文档。
