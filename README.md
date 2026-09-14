# XyMediaVault

> 当前公开版本：**v2.2.1**
>
> 本仓库只提供公开安装器、部署模板、组件成品和用户文档，不包含项目源码。

## 快速开始

### 直连 GitHub

```bash
curl -fsSL \
  https://github.com/iceqi/xymedia-releases/releases/latest/download/install.sh \
  | sudo bash
```

安装器会自动查询并安装最新稳定版；如需固定版本，可设置 `XYMEDIA_RELEASE_TAG=v2.2.1`。

### 使用下载镜像

下面的示例使用 `proxy.151513.xyz`。外层 `curl` 负责下载安装器，`XYMEDIA_MIRROR` 会传给安装器，使后续 App、TMM、Title、Controller 等成品也使用同一个镜像：

```bash
curl -fsSL \
  https://proxy.151513.xyz/github.com/iceqi/xymedia-releases/releases/latest/download/install.sh \
  | sudo env XYMEDIA_MIRROR=https://proxy.151513.xyz bash
```

`XYMEDIA_MIRROR` 是 URL 镜像地址，不是 HTTP 代理。未设置时直连 GitHub；镜像地址格式由服务提供方决定。

## 安装前准备

- Linux 主机和 Docker Compose。
- 具备 Docker 管理权限的管理员账户，通常使用 `root`。
- 可写且空间充足的安装目录。
- 首次安装前备份重要数据、数据库和小雅配置。
- 如果复用已有小雅，请确认其数据目录、容器归属和端口。

安装器会保留已有的 `.env`、`data/`、`secrets/`、数据库和小雅数据。请勿公开这些文件或安装日志中的密码、Token、Cookie 和授权信息。

## 下载镜像行为

| 配置 | 普通文件 | Bootstrap 镜像 |
| --- | --- | --- |
| 未设置 `XYMEDIA_MIRROR` | 直连 GitHub Release | `ghcr.io/iceqi/xymedia-bootstrap:1` |
| `XYMEDIA_MIRROR=https://proxy.151513.xyz` | 使用 `proxy.151513.xyz/github.com/...` | `proxy.151513.xyz/ghcr.io/iceqi/xymedia-bootstrap:1` |

镜像服务不可用时，取消 `XYMEDIA_MIRROR` 后重试直连，或更换其他镜像。安装器不会静默切换下载源。

## 强制更新

升级已有安装时，可以使用以下参数：

| 参数 | 作用 | 环境变量 |
| --- | --- | --- |
| `--force-update` | 重新下载当前版本全部成品和模板，并重新拉取镜像、重建相关容器 | `XYMEDIA_FORCE_UPDATE=1` |
| `--force-image` | 只检查/拉取 Bootstrap 镜像并重建相关容器 | `XYMEDIA_FORCE_IMAGE=1` |
| `--force-components` | 只重新下载、校验和提取 TMM 与 Title | `XYMEDIA_FORCE_COMPONENTS=1` |

完整强制更新示例：

```bash
curl -fsSL \
  https://proxy.151513.xyz/github.com/iceqi/xymedia-releases/releases/latest/download/install.sh \
  | sudo env XYMEDIA_MIRROR=https://proxy.151513.xyz bash -s -- --force-update
```

`--force-update` 会覆盖另外两个强制选项的重叠语义。下载使用临时文件、断点续传、重试和 SHA-256 校验，校验成功后才替换现有文件。

Compose 参数含义：

- `--force-recreate`：即使配置没有变化，也重新创建容器。
- `--pull always`：启动时强制检查并拉取镜像。

强制更新不会删除数据库、`data/`、`secrets/`、`.env` 或小雅数据。

## 安装模式

| 菜单 | 说明 |
| ---: | --- |
| `1` | 安装或升级管理平台，并安装或复用本机小雅 |
| `2` | 仅安装管理平台 |
| `3` | 安装管理平台并连接远程小雅控制器 |
| `4` | 仅安装小雅控制器 |
| `5` | 查看状态、诊断和维护 |
| `6` | 查看控制器地址和密钥 |
| `7` | 查看数据库连接信息 |
| `0` | 退出 |

### 本机小雅

选择模式 `1` 后，安装器会发现已有的 Alist/Xiaoya 容器：

- **复用已有容器**：保留原容器和数据，不接管或删除。
- **独立安装**：创建由 XyMediaVault 管理的独立小雅实例。

请选择正确的数据目录，并确认端口没有冲突。

### 远程控制器

1. 在小雅所在主机选择模式 `4`，安装控制器。
2. 在管理平台主机选择模式 `3`，填写控制器地址、Token 和显示名称。
3. 确保两台主机网络互通，并用防火墙限制控制器端口访问来源。

## 默认端口

| 服务 | 端口 |
| --- | ---: |
| 管理后台/API | `18080` |
| WebDAV | `18081` |
| TVBox | `18082` |
| Emby 反向代理 | `18086` |
| 小雅 Web | `5678` |
| 小雅管理 | `2345` |
| 小雅代理 | `2346` |
| 小雅控制器 | `19090` |

常用端口可以通过环境变量调整，例如：

```bash
XYMEDIA_API_PORT=28080 \
XYMEDIA_WEBDAV_PORT=28081 \
XYMEDIA_TVBOX_PORT=28082 \
XYMEDIA_CONTROLLER_PORT=29090 \
curl -fsSL \
  https://github.com/iceqi/xymedia-releases/releases/latest/download/install.sh \
  | sudo -E bash
```

## 安装后检查

```bash
docker ps --filter name=xymedia
curl -fsS http://127.0.0.1:18080/api/health
docker logs --tail=200 xymedia-app
```

如果升级后出现：

```text
exec: "/releases/current/bin/xymediavault": permission denied
```

请使用最新公开安装器执行 `--force-update`。安装器会在解压 App 后恢复 `xymediavault` 和 `xymedia-supervisor` 的执行权限。

## 文档

- [安装](docs/installation.md)
- [连接与端口](docs/connections-and-ports.md)
- [升级](docs/upgrade.md)
- [FUSE 挂载](docs/fuse.md)
- [组件](docs/components.md)
- [恢复](docs/recovery.md)
- [排障](docs/troubleshooting.md)

## 安全提醒

请勿公开以下内容：

- `.env`
- `secrets/`
- 数据库密码
- 小雅或控制器 Token
- 阿里云授权信息
- 完整安装日志

提交问题时只提供操作系统、CPU 架构、Docker/Compose 版本、安装模式和脱敏后的错误信息。
