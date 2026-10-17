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

完整说明见 [DEPLOY.md](DEPLOY.md)。当前版本 **v0.5.1**，下载见 [Releases](https://github.com/kiksok/nyanpass-reconstruction/releases)。

恢复版支持原生节点自动配置、同组多机、TCP/UDP 转发、多跳计费、TLS 卸载、入站 PROXY、终端与诊断。原版商业授权服务和原版 gRPC 运维协议没有完整还原；这份发行不宣称与原版所有功能等价。

第三方组件及许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和二进制展开后的 `licenses/`。

0.5.1 修复两版节点状态页，补齐真实主机CPU、内存、磁盘、网卡流量和运行时间。已有安装请同时更新面板与节点；未更新节点尚未上报的指标显示 `--`，不会伪造为0。
