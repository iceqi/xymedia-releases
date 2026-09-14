# XyMediaVault 公开发布与安装（v2.2.0）

> 本仓库提供 XyMediaVault 的安装入口、部署模板与公开组件目录。
>
> 日常安装、升级、状态查看和本地媒体 FUSE 挂载维护，均从 `install.sh` 进入。本仓库不包含应用源码。

---

## 文档导航

- [安装](docs/installation.md)：准备条件、模式和首次检查
- [连接与端口](docs/connections-and-ports.md)：本地/远程小雅和网络要求
- [升级](docs/upgrade.md)：备份、重跑安装器和恢复边界
- [FUSE](docs/fuse.md)：宿主机媒体挂载维护
- [组件](docs/components.md)：TMM、Title 和 Controller
- [恢复](docs/recovery.md) · [排障](docs/troubleshooting.md)

## 安装前确认

| 项目 | 说明 |
| --- | --- |
| 执行环境 | 在 Linux 主机上执行，并使用具备 Docker 管理权限的管理员账户。 |
| 基础依赖 | 需要 Docker 及其编排工具；本地媒体 FUSE 维护额外需要第二代编排命令。 |
| 安装目录 | 脚本会创建应用配置、数据库目录、密钥文件和容器。请选择你拥有管理权限的目录。 |
| 已有小雅 | 已有 Alist 或 Xiaoya 时，先确认数据目录和当前用途；安装器可复用已有服务，也可单独创建一套受管理的小雅。 |
| 敏感信息 | 不要公开 `.env`、`secrets/`、控制器密钥、数据库密码、阿里云授权信息或完整安装日志。 |

> **操作提醒**
>
> 清理、重建、挂载变更和数据库维护都可能影响正在使用的服务。执行前请确认影响范围，并为重要数据准备备份。

---

## 开始安装

进入希望作为安装目录的位置后执行。默认安装目录就是当前工作目录，脚本会显示交互菜单。

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo bash
```

### 指定安装目录

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo bash -s -- --install-dir /opt/xymedia
```

安装器会从 GitHub Release `catalog-v1.json` 下载与主机架构匹配的制品。默认固定为 v2.2.0；未来版本可通过 `XYMEDIA_CATALOG_URL` 和 `XYMEDIA_RELEASE_BASE` 覆盖，避免修改脚本。

### 强制更新选项

升级已有安装时可使用以下不带值选项，也支持对应环境变量：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env XYMEDIA_MIRROR=https://gh-proxy.org bash -s -- --force-update
```

| 选项 | 作用 |
| --- | --- |
| `--force-update` | 强制重新下载当前版本应用、Controller、TMM、Title、模板和目录，并使用 `--pull always --force-recreate` 更新相关容器；环境变量：`XYMEDIA_FORCE_UPDATE=1`。 |
| `--force-image` | 不重新下载文件，只强制检查/拉取 Bootstrap 镜像并重建相关容器；环境变量：`XYMEDIA_FORCE_IMAGE=1`。 |
| `--force-components` | 只强制重新下载、校验和提取 TMM、Title；环境变量：`XYMEDIA_FORCE_COMPONENTS=1`。 |

`--force-update` 覆盖另外两个选项的重叠语义。所有强制模式都保留 `data/`、`.env`、`secrets/`、数据库和 Xiaoya 数据；下载仍经临时文件与 SHA-256 校验后原子替换。

Compose 的 `--force-recreate` 强制重新创建容器，`--pull always` 强制检查并拉取镜像；两者只用于 `up`，不会用于数据库迁移的 `compose run`。

### 可选下载镜像

默认情况下，GitHub Release 文件直接从 GitHub 下载。网络无法直接访问 GitHub 时，可只设置一个 HTTPS origin 作为 URL 镜像（这不是 HTTP/HTTPS 代理）：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env XYMEDIA_MIRROR=https://gh-proxy.org bash
```

也可以在指定安装目录的命令中使用同样的 `sudo env XYMEDIA_MIRROR=... bash -s -- ...` 形式。启动后安装器会显示 `下载模式：直连 GitHub` 或 `下载模式：镜像 <origin>`。镜像变量会把 GitHub Release 下载地址按当前配置的前缀改写；Bootstrap 默认直连 `ghcr.io/iceqi/xymedia-bootstrap:1`，设置镜像后才改为 `gh-proxy.org/docker/ghcr.io/iceqi/xymedia-bootstrap:1` 这样的 Docker 镜像引用。普通文件下载会使用临时 `.part` 文件、断点续传和有限重试，完成后再原子替换目标文件；慢速连接仍受限时退出，不会把不完整文件当作完成。`XYMEDIA_MIRROR` 必须是没有路径、查询参数、片段、用户信息或端口的 HTTPS origin；不设置或设置为空时回退到直连。镜像下载失败时不会静默切换到 GitHub，请取消设置 `XYMEDIA_MIRROR` 后重试。显式设置 `XYMEDIA_BOOTSTRAP_IMAGE` 时不会改写该镜像。

---

## 选择安装方式

| 菜单 | 用途 | 适合场景 |
| --- | --- | --- |
| `1` | 安装或升级：管理平台和本机小雅 | 新用户、单机部署、默认推荐；已有部署可直接升级 |
| `2` | 仅安装管理平台 | 只需要平台，暂不接入小雅 |
| `3` | 安装管理平台并连接远程小雅控制器 | 小雅部署在另一台主机 |
| `4` | 仅安装小雅控制器 | 在小雅主机上部署控制器，供另一台管理平台连接 |
| `5` | 状态、诊断与维护 | 查看状态、管理本地 FUSE 挂载、执行清理 |
| `6` | 查看小雅控制器地址和密钥 | 仅限可信管理员查看 |
| `7` | 查看数据库连接信息 | 仅限可信管理员查看 |
| `0` | 退出 | 不执行安装或维护操作 |

### 已有小雅：复用或独立安装

选择模式 `1` 后，若检测到本机已有 Alist 或 Xiaoya 容器，安装器会让你选择：

| 选择 | 行为 |
| --- | --- |
| 复用已有容器 | 不会接管、重命名或删除该容器。请确认你有管理权限，并按提示提供与容器数据挂载一致的宿主机目录。同机已有 Alist/Xiaoya 且希望由平台管理时，请选择模式 `1`。 |
| 独立安装小雅 | 创建由 XyMediaVault 管理的 `xymedia-xiaoya` 容器和独立数据目录。默认端口被占用时，按提示选择其他宿主机端口。 |
| 取消 | 不修改已有容器或安装配置。 |

复用已有服务前，请先确认它不是其他业务正在依赖的生产实例。独立安装不会主动修改已有 Alist/Xiaoya，但端口和目录不能冲突。名称或镜像中不含 `alist` 或 `xiaoya` 的服务不会被安装器自动识别，请勿假定它会被复用。

### 远程小雅控制器

远程部署分两步：

1. 在小雅所在主机选择模式 `4`，配置真实的小雅数据目录和容器名。
2. 在管理平台主机选择模式 `3`，填写控制器地址、Token 和显示名称。

> 两台主机之间必须具备网络连通性，并应使用防火墙限制控制器端口的访问来源。

---

## 服务端口

默认端口如下。应用、WebDAV、TVBox 和控制器端口不会在交互菜单中逐项询问；首次安装需要改端口时，请在运行安装器前通过环境变量传入。端口冲突时不要直接修改正在运行的部署文件。

| 服务 | 宿主机默认端口 | 访问方式 |
| --- | ---: | --- |
| 管理后台/API | `18080` | `http://服务器IP:18080` |
| WebDAV | `18081` | `http://服务器IP:18081/dav` |
| TVBox | `18082` | `http://服务器IP:18082` |
| Emby 反向代理 | `18086` | `http://服务器IP:18086` |
| 小雅 Web | `5678` | `http://服务器IP:5678` |
| 小雅管理 | `2345` | 由小雅使用 |
| 小雅代理 | `2346` | 由小雅使用 |
| 小雅控制器 | `19090` | 远程管理平台连接时使用 |

例如，将应用、WebDAV、TVBox、Emby 反向代理和控制器端口改为其他可用端口后再安装或升级：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env \
      XYMEDIA_API_PORT=28080 \
      XYMEDIA_WEBDAV_PORT=28081 \
      XYMEDIA_TVBOX_PORT=28082 \
      XYMEDIA_EMBY_PROXY_PORT=28086 \
      XYMEDIA_CONTROLLER_PORT=29090 \
      bash
```

> 小雅 Web、管理和代理端口会在选择独立安装小雅时由安装器提示确认；也可通过 `XYMEDIA_XIAOYA_PORT`、`XYMEDIA_XIAOYA_ADMIN_PORT`、`XYMEDIA_XIAOYA_PROXY_PORT` 预先指定。已有实例需要变更端口时，请先备份安装目录中的 `.env`，确认依赖方已停止或已调整，再使用对应端口变量重新运行安装器。

Emby 反向代理默认使用 `18086`，可通过 `XYMEDIA_EMBY_PROXY_PORT` 自定义；该端口必须与管理后台、WebDAV 和 TVBox 主机端口不同。

Dashboard 的服务地址使用当前浏览器 hostname 和协议，并读取 Compose 注入的 `XYMEDIA_DASHBOARD_*_PORT` 元数据。外部 PostgreSQL 模板保留 `XYMEDIA_API_BIND`、`XYMEDIA_WEBDAV_BIND` 和 `XYMEDIA_TVBOX_BIND` 的兼容映射；如这些映射被自定义，请同时设置对应的纯数字 Dashboard 端口变量，否则 Dashboard 不显示该地址。

---

## 安装后检查

安装完成后，建议先在安装器中选择菜单 `5` 的“查看状态”。也可在安装目录中检查应用健康状态：

```bash
curl -fsS http://127.0.0.1:18080/api/health
```

查看容器：

```bash
docker ps --filter name=xymedia
```

查看应用日志：

```bash
docker logs --tail=200 xymedia-app
```

如果安装目录不是当前目录，请先进入实际安装目录，或在维护命令中使用 `--install-dir`。

---

## 本地媒体 FUSE 挂载

菜单 `5` 提供以下维护项：

| 维护项 | 作用 |
| --- | --- |
| 查看状态 | 查看服务、数据库和当前挂载状态 |
| 一键挂载本地媒体库 | 首次配置宿主机媒体目录并启动 FUSE |
| 启动/重启已配置挂载 | 使用已保存的挂载路径重新启动 |
| 停用本地媒体库挂载 | 停止受管理的 FUSE 挂载并恢复普通应用模式 |
| 清理 XyMediaVault 容器及数据 | 需多次确认的破坏性维护操作 |

启用 FUSE 前，请逐项确认：

- 宿主机存在字符设备 `/dev/fuse`；
- 使用 `root` 执行 FUSE 维护；
- 目标目录是已存在、绝对、非符号链接的目录；
- 首次挂载时目标目录必须为空；
- 目标目录不能是其他应用正在读写的普通数据目录；
- 部署配置能够向 `xymedia-app` 映射 `/dev/fuse` 和 `SYS_ADMIN` 能力。

挂载动作由管理员执行一次即可。挂载成功后，媒体服务应读取挂载后的目录；是否允许普通用户读取仍取决于媒体服务容器的目录映射、挂载传播和自身用户权限。

如果挂载失败，安装器会输出预检、容器设备、应用健康和挂载状态诊断。请保留脱敏后的诊断结果，不要粘贴 `.env` 或密钥文件内容。

---

## 清理与数据安全

维护菜单中的“清理 XyMediaVault 容器及数据”是破坏性操作：

- 它只处理安装器能够确认属于当前实例的受管理资源；
- 不会使用 Docker prune，也不会按名称猜测删除其他容器；
- 选择清理本机小雅时，只会处理明确标记为本安装实例管理的小雅；
- 仍应在执行前自行确认数据库、媒体目录和小雅数据的备份；
- 不要使用 `docker compose down -v` 代替安装器维护流程，除非你明确要永久删除对应数据卷。

---

## 仓库文件说明

| 文件 | 用途 |
| --- | --- |
| `install.sh` | 交互式安装、升级和维护入口 |
| `catalog-v1.json` | 当前公开应用、媒体文件解析服务、媒体管理服务和控制器制品目录 |
| `compose.yaml` | 平台、本地数据库和本机小雅模板 |
| `compose.fuse.yaml` | FUSE 启用时合并的部署覆盖配置 |
| `compose-controller.yaml` | 仅部署控制器时使用的模板 |
| `config.yaml` | 应用默认配置模板 |
| `remount-fuse.sh` | 本地媒体 FUSE 维护脚本，由安装器自动刷新 |
| `Dockerfile.bootstrap` | 应用与控制器启动镜像定义 |

这些文件由发布流程同步。安装实例中的 `.env`、`config.yaml`、`secrets/`、`data/`、`releases/` 和组件目录属于本机状态，不应直接提交回公开仓库。

---

## 获取帮助

排障时请提供以下脱敏信息：

- 使用的安装模式和安装目录；
- 操作系统、CPU 架构、Docker 和 Compose 版本；
- 菜单操作步骤；
- `docker ps --filter name=xymedia` 输出；
- `docker logs --tail=200 xymedia-app` 中去除凭据后的相关部分；
- FUSE 维护输出中的 `preflight diagnostics` 和 `timeout diagnostics`。

请勿提交控制器 Token、数据库密码、阿里云授权信息、Cookie、完整 `.env`、完整 `config.yaml` 或包含内部地址和凭据的截图。
