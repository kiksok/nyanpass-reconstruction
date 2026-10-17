# 第三方组件

本发行的 Linux 可执行程序封装恢复版 JavaScript 服务、Node.js v24.15.0、ws 和独立 Go TLS helper。启动时会展开内置运行文件；它不是将原厂二进制改名发布，也不声称恢复了原作者的完整私有源码。

0.8.0 使用 ws 8.22.0、hpack.js 2.1.6 及其 MIT 依赖，包内保留完整许可。节点额外封装未修改官方 sing-box v1.12.10（GPL-3.0）独立进程，恢复服务经标准认证 SOCKS5 与它交互，不链接其 Go 代码。

节点内置 `licenses/sing-box-corresponding-source.tar.gz`，包含对应未改主模块、108个精确版本依赖、许可证、校验和构建来源，SHA256为 `30e13e3685977117d16930a27de614c8e7f339a06298e665752ad985424e9881`。运行 `rel_nodeclient --third-party-source > source.tar.gz` 可提取，无需启动节点。该归档只含第三方上游源码，不含恢复工程或用户配置。上游版本见 [sing-box v1.12.10](https://github.com/SagerNet/sing-box/releases/tag/v1.12.10)。

Node.js 与 ws 使用各自的 MIT 许可。Go 运行时及 TLS helper 的第三方模块保留其 BSD、MIT 等原许可。前端第三方库保留原有许可通知。完整通知随二进制一起封装在运行目录中的 `licenses/`、Node 的许可文件及前端 vendor 许可文件中。

原始发布前端的著作权属于各自权利人；恢复版新增代码与对接实现不改变原有权利归属。

离线JSON编辑器使用 Monaco Editor 0.45.0（MIT），完整加载器、worker和字体随面板封装，保留 `vendor/monaco-editor-0.45.0/LICENSE` 和 `ThirdPartyNotices.txt`。
