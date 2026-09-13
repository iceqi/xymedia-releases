# 连接与端口

## 本地小雅

模式 `1` 会在检测到本机 Alist/Xiaoya 容器时提供“复用已有容器”或“独立安装小雅”。复用不会接管、重命名或删除外部容器；必须提供与容器挂载一致的宿主机数据目录。独立安装使用 `xymedia-xiaoya` 和独立数据目录，端口冲突时按提示选择空闲端口。

## 远程控制器

远程连接分两步：小雅所在主机运行模式 `4`，管理平台所在主机运行模式 `3`。模式 `3` 要求填写控制器 URL、Token 和显示名称，并会访问 `${URL}/health` 做健康检查；默认要求 HTTPS，除非管理员明确设置 `ALLOW_HTTP=1`。Token 只在本机受保护的 secrets 文件中保存，不要复制到公开问题或截图。

控制器默认监听 `19090`。远程主机防火墙只应允许管理平台主机访问该端口。浏览器访问管理平台不需要直接暴露控制器端口。

## 默认端口

| 服务 | 默认宿主机端口 | 地址 |
| --- | ---: | --- |
| 管理后台/API | 18080 | `http://服务器IP:18080` |
| WebDAV | 18081 | `http://服务器IP:18081/dav` |
| TVBox | 18082 | `http://服务器IP:18082` |
| Emby 反向代理 | 18086 | `http://服务器IP:18086` |
| 小雅 Web | 5678 | `http://服务器IP:5678` |
| 小雅管理/代理 | 2345 / 2346 | 由小雅使用 |
| 小雅控制器 | 19090 | 平台到控制器 |

首次部署可用 `XYMEDIA_API_PORT`、`XYMEDIA_WEBDAV_PORT`、`XYMEDIA_TVBOX_PORT`、`XYMEDIA_EMBY_PROXY_PORT`、`XYMEDIA_CONTROLLER_PORT` 预设端口；独立小雅对应 `XYMEDIA_XIAOYA_PORT`、`XYMEDIA_XIAOYA_ADMIN_PORT`、`XYMEDIA_XIAOYA_PROXY_PORT`。

只开放确实需要的端口。生产环境建议在 HTTPS 反向代理后提供管理后台、WebDAV、TVBox 和远程控制器，并正确配置 TLS、Host 和转发协议。
