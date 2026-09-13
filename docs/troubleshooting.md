# 排障

## 通用检查

在安装目录执行：

```bash
docker compose version
docker logs --tail=200 xymedia-app
curl -fsS http://127.0.0.1:18080/api/health
```

确认 Docker 服务运行、当前用户有权限、磁盘空间足够，且应用、数据库和所需端口没有被其他服务占用。不要把包含密码、Token、Cookie 或授权信息的输出提交给别人。

## 下载、目录和校验

目录或 catalog 下载失败时，确认主机能访问公开 Release 的 HTTPS URL，时间和 DNS 正常。SHA-256 失败表示资产可能损坏、版本不匹配或镜像返回了错误内容：删除临时失败文件后从公开 Release 直连重试，或取消 `XYMEDIA_MIRROR` 后重试。镜像只是用户选择的 URL origin，不是保证可用的代理。

## 连接失败

远程控制器失败时，在控制器主机确认容器运行、监听端口可达、管理平台能访问 `${控制器URL}/health`，并确认 Token 完整且没有泄露。HTTPS、反向代理和防火墙规则必须允许平台到控制器的连接。

FUSE 失败时确认 `/dev/fuse`、root 权限、目标目录为空且不是符号链接，并使用菜单 `5` 的状态和重启选项；不要手工删除不确定归属的挂载或数据。

升级后失败时保留旧 release、备份和日志，停止反复重启，按 [恢复](recovery.md) 处理。若清理操作已经确认执行，相关数据可能无法由安装器恢复。
