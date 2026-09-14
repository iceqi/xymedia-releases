# 安装指南

## 1. 准备环境

- Linux 主机。
- Docker 和 Docker Compose。
- 具备 Docker 管理权限的管理员账户。
- 可写且空间充足的安装目录。

安装器会创建或更新 `.env`、`data/`、`secrets/`、`releases/`、`components/` 和容器。已有安装请先备份数据库和重要配置。

## 2. 执行安装

进入安装目录后，直连 GitHub：

```bash
curl -fsSL \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo bash
```

使用镜像：

```bash
curl -fsSL \
  https://proxy.151513.xyz/github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env XYMEDIA_MIRROR=https://proxy.151513.xyz bash
```

外层 URL 和 `XYMEDIA_MIRROR` 都要配置：前者用于下载安装器，后者用于让安装器下载后续 App、Controller、TMM、Title 和配置文件。

指定安装目录：

```bash
curl -fsSL \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo bash -s -- --install-dir /opt/xymedia
```

未设置 `XYMEDIA_MIRROR` 时普通文件直连 GitHub，Bootstrap 使用：

```text
ghcr.io/iceqi/xymedia-bootstrap:1
```

设置 `XYMEDIA_MIRROR=https://proxy.151513.xyz` 时，Bootstrap 使用：

```text
proxy.151513.xyz/ghcr.io/iceqi/xymedia-bootstrap:1
```

镜像 URL 格式由服务提供方决定，其他镜像站不一定使用相同路径。

## 3. 选择模式

安装器菜单：

| 菜单 | 用途 |
| ---: | --- |
| `1` | 管理平台 + 本机小雅，或升级已有安装 |
| `2` | 仅管理平台 |
| `3` | 管理平台 + 远程小雅控制器 |
| `4` | 仅小雅控制器 |
| `5` | 状态、诊断和维护 |
| `6` | 查看控制器信息 |
| `7` | 查看数据库信息 |
| `0` | 退出 |

已有小雅时，模式 `1` 会让你选择复用已有容器还是创建独立实例。复用前请确认数据目录和容器属于你要管理的服务。

## 4. 强制更新

```bash
curl -fsSL \
  https://proxy.151513.xyz/github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env XYMEDIA_MIRROR=https://proxy.151513.xyz bash -s -- --force-update
```

- `--force-update`：重新下载全部当前版本资产、重新拉取镜像并重建相关容器。
- `--force-image`：只强制检查/拉取 Bootstrap 镜像并重建相关容器。
- `--force-components`：只强制重新下载 TMM 和 Title。

对应环境变量为 `XYMEDIA_FORCE_UPDATE=1`、`XYMEDIA_FORCE_IMAGE=1` 和 `XYMEDIA_FORCE_COMPONENTS=1`。

安装器内部使用：

- `--force-recreate`：强制重新创建容器。
- `--pull always`：强制检查并拉取镜像。

这些操作不会删除 `.env`、`data/`、`secrets/`、数据库或小雅数据。App 归档解压后会恢复 `bin/xymediavault` 和 `bin/xymedia-supervisor` 的 `755` 执行权限。

## 5. 安装后检查

```bash
docker ps --filter name=xymedia
curl -fsS http://127.0.0.1:18080/api/health
docker logs --tail=200 xymedia-app
```

控制器默认监听 `19090`。远程连接时，应使用控制器主机可访问的地址和 Token，并限制防火墙来源。

## 6. 常见问题

### 下载超时

取消 `XYMEDIA_MIRROR` 后直连重试，或更换可用镜像。安装器会使用临时文件、断点续传和有限重试，不会把半截文件当作完整成品。

### `permission denied`

在原安装目录重新执行 `--force-update`。不要删除数据库或 `secrets/`。

### Bootstrap 镜像拉取失败

确认镜像地址格式与镜像站文档一致。直连使用 `ghcr.io/iceqi/xymedia-bootstrap:1`；`proxy.151513.xyz` 使用 `proxy.151513.xyz/ghcr.io/iceqi/xymedia-bootstrap:1`，不包含 `/docker/`。
