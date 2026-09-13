# 安装

## 准备

在 Linux 主机上使用有 Docker 管理权限的管理员账户。准备一个可写且有足够空间的安装目录，并确认 Docker Compose 可用。不要把 `.env`、`secrets/`、数据库密码、控制器 Token 或完整日志发给他人。

安装器默认使用公开 v2.2.0 Release：

```text
https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0
```

## 运行安装器

进入安装目录后执行：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh | sudo bash
```

也可以指定目录：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo bash -s -- --install-dir /opt/xymedia
```

网络不能直连 GitHub 时，可选择一个 HTTPS URL 镜像 origin；`XYMEDIA_MIRROR` 未设置或为空时直连。它是 URL 改写选项，不是 HTTP/HTTPS 代理：

```bash
curl -fsSL --proto '=https' --proto-redir '=https' \
  https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/install.sh \
  | sudo env XYMEDIA_MIRROR=https://gh-proxy.org bash
```

镜像是用户自行选择的服务，不保证可用性；失败时取消该变量重试直连，或更换镜像。不要把密钥放进 URL。

## 模式

菜单 `1` 安装或升级管理平台和本机小雅；`2` 仅安装管理平台；`3` 安装平台并连接远程控制器；`4` 仅安装小雅控制器；`5` 查看状态、诊断和维护；`6` 查看控制器地址和密钥；`7` 查看数据库连接信息；`0` 退出。

首次安装按提示完成目录、端口和小雅连接选择。已有小雅可在模式 `1` 中复用已识别容器，或创建独立的受管理实例；复用前应确认数据挂载和业务归属。

## 首次登录与健康检查

安装完成后从菜单 `5` 查看状态，再打开管理后台 `http://服务器IP:18080`。如需直接检查：

```bash
curl -fsS http://127.0.0.1:18080/api/health
docker ps --filter name=xymedia
```

按应用实际提示完成首次登录。健康检查失败时先查看 [排障](troubleshooting.md)，不要公开配置或凭据。
