#!/usr/bin/env bash
set -euo pipefail

CATALOG_URL=${XYMEDIA_CATALOG_URL:-https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0/catalog-v1.json}
RELEASE_BASE=${XYMEDIA_RELEASE_BASE:-https://github.com/iceqi/xymedia-releases/releases/download/v2.2.0}
XYMEDIA_MIRROR=${XYMEDIA_MIRROR:-}
if [[ -n $XYMEDIA_MIRROR ]]; then
  XYMEDIA_MIRROR=$(XYMEDIA_MIRROR_INPUT="$XYMEDIA_MIRROR" python3 - <<'PY'
import os
from urllib.parse import urlsplit

value = os.environ['XYMEDIA_MIRROR_INPUT']
parsed = urlsplit(value)
try:
    port = parsed.port
except ValueError:
    raise SystemExit(1)
if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or
        parsed.password is not None or port is not None or parsed.query or
        parsed.fragment or '?' in value or '#' in value or parsed.path not in ('', '/')):
    raise SystemExit(1)
print('https://' + parsed.netloc.rstrip('/'))
PY
  ) || { printf '%s\n' 'XYMEDIA_MIRROR 必须是没有路径、查询、片段、用户信息或端口的 HTTPS origin' >&2; exit 1; }
fi
rewrite_download_url() {
  local original=$1 host
  [[ -n $XYMEDIA_MIRROR ]] || { printf '%s\n' "$original"; return 0; }
  host=$(URL_INPUT="$original" python3 - <<'PY'
import os
from urllib.parse import urlsplit
print(urlsplit(os.environ['URL_INPUT']).hostname or '')
PY
)
  case ${host,,} in
    github.com|raw.githubusercontent.com) printf '%s/%s\n' "$XYMEDIA_MIRROR" "$original";;
    *) printf '%s\n' "$original";;
  esac
}
DOWNLOAD_MAX_TIME=${XYMEDIA_DOWNLOAD_MAX_TIME:-1800}
DOWNLOAD_RETRIES=${XYMEDIA_DOWNLOAD_RETRIES:-5}
if [[ -n $XYMEDIA_MIRROR ]]; then
  DOWNLOAD_MODE="下载模式：镜像 $XYMEDIA_MIRROR"
else
  DOWNLOAD_MODE='下载模式：直连 GitHub'
fi
download_remote_file() {
  local original_url=$1 output=$2 progress_mode=${3:-silent}
  local rewritten_url part attempt curl_progress effective
  rewritten_url=$(rewrite_download_url "$original_url")
  part="$output.part"
  curl_progress=()
  [[ $progress_mode == progress ]] && curl_progress=(--progress-bar)
  mkdir -p "$(dirname -- "$output")"
  for ((attempt=1; attempt<=DOWNLOAD_RETRIES; attempt++)); do
    if effective=$(curl --retry 3 --retry-connrefused --retry-delay 5 \
      --connect-timeout 20 --max-time "$DOWNLOAD_MAX_TIME" --speed-limit 1024 --speed-time 60 \
      --fail --show-error --location --proto '=https' --tlsv1.2 --continue-at - \
      "${curl_progress[@]}" -o "$part" -w '%{url_effective}' "$rewritten_url"); then
      mv -f -- "$part" "$output"
      DOWNLOAD_EFFECTIVE_URL=${effective:-$rewritten_url}
      return 0
    fi
    # A server without Range support may reject resume. Restart cleanly once
    # before the next bounded outer attempt rather than appending stale bytes.
    rm -f -- "$part"
    [[ $attempt -lt $DOWNLOAD_RETRIES ]] && sleep 2
  done
  rm -f -- "$part"
  return 1
}
INSTALL_NONCE=$(date +%s)
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
INSTALL_DIR=${XYMEDIA_INSTALL_DIR:-$PWD}
PG_HOST=${XYMEDIA_POSTGRES_HOST:-}
PG_PORT=${XYMEDIA_POSTGRES_PUBLIC_PORT:-5432}
PG_DB=xymedia
PG_USER=${XYMEDIA_POSTGRES_USER:-xymedia_app}
PG_PASSWORD_FILE=
INSTALL_EXISTING=0
XYMEDIA_POSTGRES_PUBLIC_PORT=${XYMEDIA_POSTGRES_PUBLIC_PORT:-}
PG_HOST_ENV_EXPLICIT=${XYMEDIA_POSTGRES_HOST:+1}
SKIP_COMPONENTS=0
FORCE_UPDATE=${XYMEDIA_FORCE_UPDATE:-0}
FORCE_IMAGE=${XYMEDIA_FORCE_IMAGE:-0}
FORCE_COMPONENTS=${XYMEDIA_FORCE_COMPONENTS:-0}
EXISTING_DB=0
LOCAL_DB=0
PG_HOST_CLI=0
API_PORT=${XYMEDIA_API_PORT:-18080}
WEBDAV_PORT=${XYMEDIA_WEBDAV_PORT:-18081}
TVBOX_PORT=${XYMEDIA_TVBOX_PORT:-18082}
EMBY_PROXY_PORT=${XYMEDIA_EMBY_PROXY_PORT:-18086}
XIAOYA_WEB_PORT=${XYMEDIA_XIAOYA_PORT:-5678}
XIAOYA_ADMIN_PORT=${XYMEDIA_XIAOYA_ADMIN_PORT:-2345}
XIAOYA_PROXY_PORT=${XYMEDIA_XIAOYA_PROXY_PORT:-2346}
TOTAL_STEPS=9
STEP=0
INSTALL_LOG=
TTY_IN=${XYMEDIA_INSTALL_TEST_TTY:-/dev/tty}
TTY_OUT=${XYMEDIA_INSTALL_TEST_TTY_OUTPUT:-/dev/tty}
TTY_TEST_MODE=0
TTY_TEST_INDEX=0
TTY_TEST_LINES=()
if [[ -n ${XYMEDIA_INSTALL_TEST_TTY:-} ]]; then TTY_TEST_MODE=1; mapfile -t TTY_TEST_LINES <"$TTY_IN"; fi
TERMINAL_CAPABLE=0
COLOR_ENABLED=0
TERMINAL_REDRAW=0
COLOR_RESET= COLOR_TITLE= COLOR_RECOMMENDED= COLOR_HINT= COLOR_SECTION= COLOR_WARNING=
ERROR_COLOR= ERROR_RESET=
if [[ -r $TTY_IN && -w $TTY_OUT && -c $TTY_OUT ]]; then
  TERMINAL_CAPABLE=1
fi
if (( TERMINAL_CAPABLE && ! TTY_TEST_MODE )) && [[ -z ${NO_COLOR+x} && ${TERM:-} != dumb ]]; then
  COLOR_ENABLED=1
  TERMINAL_REDRAW=1
  COLOR_RESET=$'\033[0m'
  COLOR_TITLE=$'\033[1;36m'
  COLOR_RECOMMENDED=$'\033[1;32m'
  COLOR_HINT=$'\033[2;37m'
  COLOR_SECTION=$'\033[1;34m'
  COLOR_WARNING=$'\033[1;31m'
  ERROR_COLOR=$'\033[31m'
  ERROR_RESET=$'\033[0m'
fi
XIAOYA_DIR=${XYMEDIA_XIAOYA_DIR:-}
XIAOYA_CONTAINER_EXPLICIT=${XYMEDIA_XIAOYA_CONTAINER:+1}
XIAOYA_CONTAINER=${XYMEDIA_XIAOYA_CONTAINER:-xymedia-xiaoya}
BOOTSTRAP_IMAGE_ENV_EXPLICIT=${XYMEDIA_BOOTSTRAP_IMAGE+x}
OPTION2_XIAOYA_PENDING=0
OPTION2_XIAOYA_CHOICE=
XIAOYA_FOUND=0
XIAOYA_STANDALONE=0
CONTROLLER_ONLY=0
MENU_PROFILES=
CONTROLLER_URL=${XYMEDIA_XIAOYA_CONTROLLER_URL:-}
CONTROLLER_BIND_ADDRESS=${XYMEDIA_CONTROLLER_BIND_ADDRESS:-0.0.0.0}
CONTROLLER_PORT=${XYMEDIA_CONTROLLER_PORT:-19090}
REMOTE_MODE=0
REMOTE_TOKEN=
CONTROLLER_BIND_EXPLICIT=${XYMEDIA_CONTROLLER_BIND_ADDRESS:+1}
CONTROLLER_PORT_EXPLICIT=${XYMEDIA_CONTROLLER_PORT:+1}
MAINTENANCE_ACTION=
FUSE_PATH_INPUT=
CLEANUP_CHOICE=
XYMEDIA_INSTANCE_ID=${XYMEDIA_INSTANCE_ID:-}
cleanup_interrupted=0
cleanup_journal=
confirm_fuse_action() {
  local confirmation
  confirmation=$(prompt_tty '该操作将停止并重新启动应用，输入 1 继续，其他内容取消： ')
  [[ $confirmation == 1 ]] || die '已取消挂载操作'
}
require_public_app_installation() {
  local missing=()
  [[ -f "$INSTALL_DIR/.env" ]] || missing+=(.env)
  [[ -f "$INSTALL_DIR/compose.yaml" ]] || missing+=(compose.yaml)
  [[ -f "$INSTALL_DIR/config.yaml" ]] || missing+=(config.yaml)
  [[ -f "$INSTALL_DIR/compose.fuse.yaml" ]] || missing+=(compose.fuse.yaml)
  grep -Eq '^  app:' "$INSTALL_DIR/compose.yaml" 2>/dev/null || missing+=(app-service)
  if ((${#missing[@]})); then
    printf '不支持 FUSE 维护：缺少完整 app 安装（%s）。\n' "${missing[*]}" >>$TTY_OUT
    return 1
  fi
  return 0
}
refresh_remount_script() {
  local tmp url
  tmp=$(mktemp "$INSTALL_DIR/.remount-fuse.sh.XXXXXX") || die '无法创建挂载脚本临时文件'
  if ! download_remote_file "$RELEASE_BASE/remount-fuse.sh?installer=$INSTALL_NONCE" "$tmp" silent; then
    rm -f "$tmp"
    die '无法下载最新 remount-fuse.sh'
  fi
  chmod 700 "$tmp"
  mv -f "$tmp" "$INSTALL_DIR/remount-fuse.sh"
}
read_install_env() {
  awk -F= -v wanted="$1" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$INSTALL_DIR/.env" 2>/dev/null || true
}
print_fuse_status() {
  local enabled path mount_id source fstype health
  enabled=$(read_install_env XYMEDIA_FUSE_ENABLED)
  path=$(read_install_env XYMEDIA_FUSE_HOST_PATH)
  printf 'FUSE 状态：XYMEDIA_FUSE_ENABLED=%s\n' "${enabled:-未配置}" >>$TTY_OUT
  printf 'FUSE 路径：XYMEDIA_FUSE_HOST_PATH=%s\n' "${path:-未配置}" >>$TTY_OUT
  if [[ -z $path ]]; then
    printf '挂载身份：未配置路径\n' >>$TTY_OUT
  elif ! command -v mountpoint >/dev/null 2>&1 || ! command -v findmnt >/dev/null 2>&1; then
    printf '挂载身份：无法确认（mountpoint/findmnt 不可用）\n' >>$TTY_OUT
  elif ! mountpoint -q "$path" 2>/dev/null; then
    printf '挂载身份：未挂载\n' >>$TTY_OUT
  else
    mount_id=$(findmnt -rn -M "$path" -o ID 2>/dev/null || true)
    source=$(findmnt -rn -M "$path" -o SOURCE 2>/dev/null || true)
    fstype=$(findmnt -rn -M "$path" -o FSTYPE 2>/dev/null || true)
    if [[ -n $mount_id && $source == xymediavault ]] && { [[ $fstype == fuse.xymediavault ]] || [[ $fstype == fuse ]]; }; then
      printf '挂载身份：owned xymediavault/fuse.xymediavault（ID=%s）\n' "$mount_id" >>$TTY_OUT
    elif [[ -n $mount_id ]]; then
      printf '挂载身份：外部或未知（ID=%s 来源=%s 类型=%s）\n' "$mount_id" "$source" "$fstype" >>$TTY_OUT
    else
      printf '挂载身份：无法确认\n' >>$TTY_OUT
    fi
  fi
  health=$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${API_PORT}/api/health" 2>/dev/null || true)
  [[ $health =~ ^[0-9]{3}$ ]] || health='无法连接'
  printf '应用健康状态：%s\n' "$health" >>$TTY_OUT
}
print_controller_info() {
  local env_file="$INSTALL_DIR/.env" token_file address port token
  [[ -f $env_file ]] || { printf '未找到安装配置，请先完成安装。\n' >>$TTY_OUT; return 1; }
  address=$(awk -F= '$1 == "XYMEDIA_HOST_ADDRESSES" {print $2; exit}' "$env_file" | cut -d, -f1)
  port=$(awk -F= '$1 == "XYMEDIA_CONTROLLER_PORT" {print $2; exit}' "$env_file")
  token_file="$INSTALL_DIR/secrets/xiaoya-controller-token"
  token=$(cat "$token_file" 2>/dev/null || true)
  [[ -n $address ]] || address=$(awk -F= '$1 == "XYMEDIA_CONTROLLER_BIND_ADDRESS" {print $2; exit}' "$env_file")
  [[ -n $address && $address != 0.0.0.0 && $address != :: ]] || address='127.0.0.1'
  [[ -n $port ]] || port=19090
  [[ -n $token ]] || { printf '未找到控制器密钥，请先完成控制器安装。\n' >>$TTY_OUT; return 1; }
  printf '小雅控制器地址：http://%s:%s\n小雅控制器密钥：%s\n' "$address" "$port" "$token" >>$TTY_OUT
}
print_database_info() {
  local env_file="$INSTALL_DIR/.env" host port db user password_file password local_db
  [[ -f $env_file ]] || { printf '未找到安装配置，请先完成安装。\n' >>$TTY_OUT; return 1; }
  host=$(read_install_env XYMEDIA_POSTGRES_HOST)
  port=$(read_install_env XYMEDIA_POSTGRES_PORT)
  db=$(read_install_env XYMEDIA_POSTGRES_DATABASE)
  user=$(read_install_env XYMEDIA_POSTGRES_USER)
  if [[ $host == *:* && $host != \[*\] ]]; then host="[$host]"; fi
  printf 'PostgreSQL 地址：%s:%s\nPostgreSQL 数据库：%s\nPostgreSQL 用户：%s\n' "$host" "$port" "$db" "$user" >>$TTY_OUT
  password_file="$INSTALL_DIR/secrets/xymedia-postgres-password"
  local_db=$(read_install_env XYMEDIA_POSTGRES_LOCAL_DB)
  if [[ $local_db == 1 || $host == postgres || $LOCAL_DB == 1 ]] && [[ -s $password_file ]]; then
    password=$(cat "$password_file")
    printf 'PostgreSQL 密码：%s\n' "$password" >>$TTY_OUT
  else
    printf 'PostgreSQL 密码：外部数据库密码由用户自行保管，不在安装器显示。\n' >>$TTY_OUT
  fi
}
validate_cleanup_root() {
  [[ $INSTALL_DIR = /* && $INSTALL_DIR != / && -d $INSTALL_DIR && ! -L $INSTALL_DIR ]] || die '清理要求安装目录是已存在的非符号链接绝对目录'
  INSTALL_PATH="$INSTALL_DIR" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ['INSTALL_PATH'])
current = pathlib.Path(p.root)
for part in p.parts[1:]:
    current /= part
    info = current.lstat()
    if info.st_uid != 0 or info.st_mode & 0o022 or current.is_symlink(): raise SystemExit(1)
if p.resolve(strict=True) == pathlib.Path('/'):
    raise SystemExit(1)
PY
  [[ -f "$INSTALL_DIR/.env" && ! -L "$INSTALL_DIR/.env" ]] || die '清理要求安装目录存在非符号链接 .env；无法确认实例所有权'
  local recorded_dir recorded_id
  recorded_dir=$(cleanup_read_env XYMEDIA_INSTALL_DIR)
  recorded_id=$(cleanup_read_env XYMEDIA_INSTANCE_ID)
  [[ $recorded_dir == "$INSTALL_DIR" ]] || die '安装配置中的实例目录与当前目录不一致，拒绝清理'
  [[ $recorded_id =~ ^[a-z0-9_-]+$ ]] || die '安装配置缺少有效 XYMEDIA_INSTANCE_ID，拒绝清理旧实例'
  XYMEDIA_INSTANCE_ID=$recorded_id
}
cleanup_read_env() { awk -F= -v wanted="$1" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$INSTALL_DIR/.env" 2>/dev/null || true; }
cleanup_canonical_child() {
  [[ -n $1 && -d $1 && ! -L $1 ]] || return 1
  CLEANUP_PATH_INPUT="$1" CLEANUP_ROOT="$2" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ['CLEANUP_PATH_INPUT'])
root = pathlib.Path(os.environ['CLEANUP_ROOT']).resolve(strict=True)
if not p.is_absolute() or any((p.root.joinpath(*p.parts[1:i+1])).is_symlink() for i in range(len(p.parts)-1)): raise SystemExit(1)
canonical = p.resolve(strict=True)
try: canonical.relative_to(root)
except ValueError: raise SystemExit(1)
if canonical == root: raise SystemExit(1)
print(canonical)
PY
}
cleanup_unmount_owned_fuse() {
  local path mount_id source fstype
  path=$(cleanup_read_env XYMEDIA_FUSE_HOST_PATH)
  [[ -n $path ]] || return 0
  path=$(cleanup_canonical_child "$path" /) || die 'FUSE 路径无效，已停止清理'
  command -v mountpoint >/dev/null 2>&1 && command -v findmnt >/dev/null 2>&1 || die '无法验证 FUSE 挂载身份，已停止清理'
  mountpoint -q "$path" 2>/dev/null || return 0
  mount_id=$(findmnt -rn -M "$path" -o ID 2>/dev/null || true); source=$(findmnt -rn -M "$path" -o SOURCE 2>/dev/null || true); fstype=$(findmnt -rn -M "$path" -o FSTYPE 2>/dev/null || true)
  [[ -n $mount_id && $source == xymediavault && ( $fstype == fuse.xymediavault || $fstype == fuse ) ]] || die 'FUSE 路径不是可确认的 XyMediaVault 挂载，已停止清理'
  if command -v fusermount3 >/dev/null 2>&1; then fusermount3 -u "$path" || die '受管 FUSE 卸载失败，未删除任何数据'; elif command -v fusermount >/dev/null 2>&1; then fusermount -u "$path" || die '受管 FUSE 卸载失败，未删除任何数据'; else umount "$path" || die '缺少安全卸载命令，未删除任何数据'; fi
  mountpoint -q "$path" 2>/dev/null && die 'FUSE 卸载后仍处于挂载状态，未删除任何数据' || true
}
cleanup_inspect_ok() {
  local expected=$1 inspected=$2 require_mount=$3
  INSPECTED_JSON="$inspected" EXPECTED_NAME="$expected" EXPECTED_ID="$XYMEDIA_INSTANCE_ID" EXPECTED_DIR="$INSTALL_DIR" REQUIRE_MOUNT="$require_mount" python3 - <<'PY'
import json, os, pathlib
try:
    item = json.loads(os.environ['INSPECTED_JSON'])[0]
    labels = (item.get('Config') or {}).get('Labels') or {}
    if (item.get('Name') or '').lstrip('/') != os.environ['EXPECTED_NAME']: raise SystemExit(1)
    if labels.get('com.xymediavault.managed') != 'true': raise SystemExit(1)
    if labels.get('com.xymediavault.instance_id') != os.environ['EXPECTED_ID']: raise SystemExit(1)
    if labels.get('com.xymediavault.install_dir') != os.environ['EXPECTED_DIR']: raise SystemExit(1)
    if os.environ['REQUIRE_MOUNT'] == '1':
        data = pathlib.Path(os.environ['EXPECTED_DATA']).resolve(strict=True)
        matched = False
        for mount in item.get('Mounts') or []:
            if mount.get('Type') == 'bind' and mount.get('Destination') in ('/data', '/www/data'):
                source = pathlib.Path(mount.get('Source', '')).resolve(strict=True)
                if source == data: matched = True
        if not matched: raise SystemExit(1)
except (ValueError, IndexError, TypeError, AttributeError, OSError): raise SystemExit(1)
PY
}
cleanup_container() {
  local name=$1 require_mount=${2:-0} expected_data=${3:-} inspected
  inspected=$(docker container inspect "$name" 2>/dev/null) || return 0
  [[ -n $inspected ]] || return 0
  EXPECTED_DATA="$expected_data" cleanup_inspect_ok "$name" "$inspected" "$require_mount" || die "容器 $name 缺少当前实例所有权标签或挂载校验失败，拒绝删除"
  docker rm -f -- "$name" >>"$INSTALL_LOG" 2>&1 || die "删除容器失败：$name（详情见日志）"
}
cleanup_all() {
  local include_xiaoya=$1 marker data_path canonical_data name managed confirm inspected
  validate_cleanup_root
  if [[ -e "$INSTALL_DIR/.cleanup.journal" ]]; then
    [[ -f "$INSTALL_DIR/.cleanup.journal" && ! -L "$INSTALL_DIR/.cleanup.journal" ]] || die '清理日志不是安全的普通文件，拒绝继续'
    [[ $(stat -c '%u' "$INSTALL_DIR/.cleanup.journal") -eq 0 && $(( $(stat -c '%a' "$INSTALL_DIR/.cleanup.journal") & 077 )) -eq 0 ]] || die '清理日志权限不安全，拒绝继续'
    printf '检测到未完成的清理日志：%s\n' "$INSTALL_DIR/.cleanup.journal" >>$TTY_OUT
    confirm=$(prompt_tty '继续未完成清理请输入数字 1，输入 0 取消： ')
    [[ $confirm == 1 ]] || { printf '已取消恢复清理。\n' >>$TTY_OUT; return 0; }
  fi
  marker=$(cleanup_read_env XYMEDIA_XIAOYA_MANAGED); data_path=$(cleanup_read_env XYMEDIA_XIAOYA_DATA_DIR); canonical_data=
  if [[ $include_xiaoya == 1 && $marker != 1 ]]; then
    printf '当前安装未记录本机小雅由安装器创建，选项 2 不可用；未删除任何内容。\n' >>$TTY_OUT
    return 0
  fi
  if [[ $include_xiaoya == 1 && $marker == 1 ]]; then canonical_data=$(cleanup_canonical_child "$data_path" "$INSTALL_DIR") || die '小雅数据未被标记为安装目录内的安全路径，已停止清理'; fi
  local -a containers=(xymedia-app xymedia-postgres xymedia-controller xymedia-aliyuntvtoken)
  if [[ $include_xiaoya == 1 && $marker == 1 ]]; then containers+=(xymedia-xiaoya); fi
  local -a migration_ids=() migration_names=()
  while IFS=$'\t' read -r name id; do
    [[ -n $id ]] || continue
    inspected=$(docker container inspect "$id" 2>/dev/null) || continue
    if [[ $name =~ ^xymedia-app-migrate-[0-9]+$ ]] && cleanup_inspect_ok "$name" "$inspected" 0; then migration_names+=("$name"); migration_ids+=("$id"); fi
  done < <(docker ps -a --filter label=com.xymediavault.managed=true --format '{{.Names}}\t{{.ID}}')
  containers+=("${migration_names[@]}")
  for name in "${containers[@]}"; do
    inspected=$(docker container inspect "$name" 2>/dev/null) || continue
    cleanup_inspect_ok "$name" "$inspected" "$([[ $name == xymedia-xiaoya ]] && printf 1 || printf 0)" || die "容器 $name 缺少当前实例所有权标签，拒绝清理；未删除容器"
  done
  printf '\n将删除以下精确容器（不存在的会跳过）：\n' >>$TTY_OUT; printf '  %s\n' "${containers[@]}" >>$TTY_OUT
  printf '将删除安装器管理数据：%s/data %s/secrets %s/components %s/releases %s/controller %s/state\n' "$INSTALL_DIR" "$INSTALL_DIR" "$INSTALL_DIR" "$INSTALL_DIR" "$INSTALL_DIR" "$INSTALL_DIR" >>$TTY_OUT
  printf '以及受管配置、Compose、日志和状态文件；其他文件、外部小雅数据和未标记小雅容器保留。\n' >>$TTY_OUT
  [[ -z $canonical_data ]] || printf '小雅数据（已确认在安装目录内）：%s\n' "$canonical_data" >>$TTY_OUT
  confirm=$(prompt_tty '确认删除以上内容？请输入数字 1，其他内容取消： '); [[ $confirm == 1 ]] || { printf '已取消清理。\n' >>$TTY_OUT; return 0; }
  [[ ! -L "$INSTALL_DIR/.cleanup.journal" ]] || die '清理日志是符号链接，拒绝清理'
  mkdir "$INSTALL_DIR/.install.lock" 2>/dev/null || die '已有安装或维护操作正在进行，拒绝清理'
  cleanup_lock_dir="$INSTALL_DIR/.install.lock"
  cleanup_journal="$INSTALL_DIR/.cleanup.journal"
  (umask 077; printf 'stage=confirmed\ninstance_id=%s\n' "$XYMEDIA_INSTANCE_ID" >"$cleanup_journal") || die '无法创建清理日志，未删除任何内容'
  cleanup_exit() { local status=$?; rmdir "${cleanup_lock_dir:-}" 2>/dev/null || true; if (( cleanup_interrupted )); then (umask 077; printf 'stage=interrupted\ninstance_id=%s\n' "$XYMEDIA_INSTANCE_ID" >"$cleanup_journal"); printf '清理被中断，已保留恢复日志：%s\n' "$cleanup_journal" >>$TTY_OUT; fi; persist_installer_log; cleanup_installer_tmp; exit "$status"; }
  cleanup_trap() { cleanup_interrupted=1; exit 130; }
  trap cleanup_exit EXIT
  trap cleanup_trap INT TERM
  cleanup_checkpoint() { if (( cleanup_interrupted )); then printf 'stage=%s\n' "$1" >"$cleanup_journal"; return 1; fi; printf 'stage=%s\n' "$1" >"$cleanup_journal"; return 0; }
  cleanup_interrupted=0
  cleanup_unmount_owned_fuse
  for managed in xymedia-app xymedia-postgres xymedia-controller xymedia-aliyuntvtoken xymedia-xiaoya; do [[ " ${containers[*]} " == *" $managed "* ]] || continue; cleanup_checkpoint "before-$managed" || exit 130; cleanup_container "$managed" "$([[ $managed == xymedia-xiaoya ]] && printf 1 || printf 0)" "$canonical_data"; done
  local index; for index in "${!migration_ids[@]}"; do cleanup_checkpoint "before-migration-${migration_names[$index]}" || exit 130; inspected=$(docker container inspect "${migration_ids[$index]}" 2>/dev/null) || continue; cleanup_inspect_ok "${migration_names[$index]}" "$inspected" 0 || continue; docker rm -f -- "${migration_ids[$index]}" >>"$INSTALL_LOG" 2>&1 || die "删除迁移容器失败（详情见日志）"; done
  if [[ -n $canonical_data ]]; then
    [[ ! -L "$canonical_data" ]] || die '小雅数据路径是符号链接，已停止清理'
    rm -rf -- "$canonical_data"
  fi
  for managed in data secrets components releases controller state bootstrap; do [[ ! -L "$INSTALL_DIR/$managed" ]] || die "受管路径是符号链接，已停止清理"; rm -rf -- "$INSTALL_DIR/$managed"; done
  for managed in .env config.yaml compose.yaml compose.fuse.yaml Dockerfile.bootstrap remount-fuse.sh catalog-v1.json install.log; do [[ ! -L "$INSTALL_DIR/$managed" ]] || die "受管文件是符号链接，已停止清理"; rm -f -- "$INSTALL_DIR/$managed"; done
  rm -f -- "$cleanup_journal"; cleanup_journal=; printf '清理完成；安装目录中的其他文件和外部小雅数据已保留。\n' >>$TTY_OUT
}
while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR=${2:?missing value}; shift 2;;
    --force-update) FORCE_UPDATE=1; shift;;
    --force-image) FORCE_IMAGE=1; shift;;
    --force-components) FORCE_COMPONENTS=1; shift;;
    --postgres-host) PG_HOST=${2:?missing value}; PG_HOST_CLI=1; shift 2;;
    --postgres-port) PG_PORT=${2:?missing value}; shift 2;;
    --postgres-db) PG_DB=${2:?missing value}; shift 2;;
    --postgres-user) PG_USER=${2:?missing value}; shift 2;;
    --postgres-password-file) PG_PASSWORD_FILE=${2:?missing value}; shift 2;;
    --skip-components) SKIP_COMPONENTS=1; shift;;
    --existing-db) EXISTING_DB=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "未知选项：$1";;
  esac
done
[[ $FORCE_UPDATE =~ ^[01]$ && $FORCE_IMAGE =~ ^[01]$ && $FORCE_COMPONENTS =~ ^[01]$ ]] || { printf '%s\n' '强制选项环境变量必须是 0 或 1' >&2; exit 1; }
if (( FORCE_UPDATE )); then FORCE_IMAGE=1; FORCE_COMPONENTS=1; fi
FORCE_UP_FLAGS=(--force-recreate)
if (( FORCE_IMAGE )); then FORCE_UP_FLAGS=(--pull always --force-recreate); fi
persist_installer_log() {
  [[ -n ${INSTALL_LOG:-} && -f $INSTALL_LOG ]] || return 0
  [[ -n ${INSTALL_DIR:-} && $INSTALL_DIR = /* && $INSTALL_DIR != / ]] || return 0
  mkdir -p "$INSTALL_DIR" 2>/dev/null || return 0
  [[ ! -L "$INSTALL_DIR/install.log" ]] || return 0
  cp "$INSTALL_LOG" "$INSTALL_DIR/install.log" 2>/dev/null || true
  chmod 600 "$INSTALL_DIR/install.log" 2>/dev/null || true
}
die() { printf '\n%sxymediavault installer: %s%s\n' "$ERROR_COLOR" "$*" "$ERROR_RESET" >&2; persist_installer_log; [[ -f ${INSTALL_DIR:-}/install.log ]] && printf '详情日志：%s/install.log\n' "$INSTALL_DIR" >&2 || { [[ -n $INSTALL_LOG ]] && printf '详情日志：%s\n' "$INSTALL_LOG" >&2; }; exit 1; }
component_cache_test_mode() {
  local catalog=${XYMEDIA_INSTALL_TEST_CATALOG:?} component platform version url sha archive marker_version marker_sha stage downloaded tarball actual
  mkdir -p "$INSTALL_DIR/components" "$INSTALL_DIR/state"
  for component in tmm title; do
    if [[ $component == tmm ]]; then platform=linux-any
    elif [[ -n ${XYMEDIA_INSTALL_TEST_PLATFORM:-} ]]; then platform=$XYMEDIA_INSTALL_TEST_PLATFORM
    else case "$(uname -m)" in x86_64|amd64) platform=linux-amd64;; aarch64|arm64) platform=linux-arm64;; *) die "unsupported host architecture: $(uname -m)";; esac
    fi
    IFS=$'\t' read -r version url sha < <(python3 - "$catalog" "$component" "$platform" <<'PY'
import json, re, sys
from urllib.parse import urlsplit
c = json.load(open(sys.argv[1])); name, platform = sys.argv[2:]
e = c['components'][name]['artifacts'].get(platform) or c['components'][name]['artifacts'].get('linux-any')
if not re.fullmatch(r'[0-9a-fA-F]{64}', e.get('sha256', '')): raise SystemExit(1)
url = e.get('asset_url', '')
parsed = urlsplit(url)
try: port = parsed.port
except ValueError: raise SystemExit(1)
if (parsed.scheme != 'https' or parsed.netloc.lower() not in ('github.com', 'gh-proxy.org') or
    parsed.username is not None or parsed.password is not None or port is not None or
    parsed.query or parsed.fragment or '%' in (parsed.path or '') or
    (re.fullmatch(r'/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*', parsed.path or '') is None and re.fullmatch(r'/https://github\.com/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*', parsed.path or '') is None)):
    raise SystemExit(1)
print(e['version'], e['asset_url'], e['sha256'].lower(), sep='\t')
PY
) || die '公开目录缺少带 SHA-256 的组件制品'
    archive="$INSTALL_DIR/components/$component.tar.zst"; marker_version="$INSTALL_DIR/components/$component.version"; marker_sha="$INSTALL_DIR/components/$component.sha256"
    if (( ! FORCE_COMPONENTS && ! FORCE_UPDATE )) && [[ -s $archive && -f $marker_version && -f $marker_sha && $(<"$marker_version") == "$version" && $(<"$marker_sha") == "$sha" && $(sha256sum "$archive" | cut -d' ' -f1) == "$sha" ]]; then
      printf '%s %s 已安装且完整，跳过下载\n' "$([[ $component == tmm ]] && printf TMM || printf Title)" "$version"; continue
    fi
    stage=$(mktemp -d "$INSTALL_DIR/state/.$component.XXXXXX")
    downloaded="$stage/$component.tar.zst"; tarball="$stage/$component.tar"
    download_remote_file "$url" "$downloaded" silent || die "$component 下载失败"
    actual=$(sha256sum "$downloaded" | cut -d' ' -f1); [[ $actual == "$sha" ]] || die "$component SHA256 校验失败"
    zstd -dc "$downloaded" >"$tarball" || die "$component 解压失败"
    python3 - "$tarball" "$stage/root" <<'PY'
import pathlib, sys, tarfile
archive, target = sys.argv[1:]; pathlib.Path(target).mkdir()
with tarfile.open(archive) as tf:
    members = tf.getmembers()
    for member in members:
        name = member.name.lstrip('./')
        if not name or name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts or member.issym() or member.islnk() or not (member.isfile() or member.isdir()): raise SystemExit(1)
        member.name = name
    try:
        tf.extractall(target, members=members, filter='data')
    except TypeError:
        tf.extractall(target, members=members)
PY
    cp "$downloaded" "$archive.tmp"; printf '%s\n' "$version" >"$marker_version.tmp"; printf '%s\n' "$sha" >"$marker_sha.tmp"
    mv -f "$archive.tmp" "$archive"; mv -f "$marker_version.tmp" "$marker_version"; mv -f "$marker_sha.tmp" "$marker_sha"; rm -rf "$stage"
  done
  exit 0
}
if [[ ${XYMEDIA_INSTALL_TEST_COMPONENT_CACHE_ONLY:-0} == 1 ]]; then
  INSTALL_DIR=${XYMEDIA_INSTALL_DIR:?XYMEDIA_INSTALL_DIR is required}; component_cache_test_mode
fi
INSTALL_TMP_DIR=
RELEASE_ROLLBACK_ACTIVE=0
RELEASE_TARGET=
RELEASE_BACKUP=
cleanup_installer_tmp() {
  if (( RELEASE_ROLLBACK_ACTIVE )) && [[ -n $RELEASE_BACKUP && -d $RELEASE_BACKUP ]]; then
    rm -rf -- "$RELEASE_TARGET" 2>/dev/null || true
    mv -- "$RELEASE_BACKUP" "$RELEASE_TARGET" 2>/dev/null || true
    ln -sfn "releases/$(basename "$RELEASE_TARGET")" "$INSTALL_DIR/releases/current" 2>/dev/null || true
    printf '%s\n' '应用 release 失败，已尝试恢复旧 release' >>"${INSTALL_LOG:-/dev/null}"
    "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" stop app >/dev/null 2>&1 || true
    "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" up -d app >/dev/null 2>&1 || true
  fi
  persist_installer_log; [[ -z ${INSTALL_TMP_DIR:-} ]] || rm -rf -- "$INSTALL_TMP_DIR"
}
trap cleanup_installer_tmp EXIT
init_installer_log() {
  local tmp_parent=${TMPDIR:-/tmp} mode
  [[ -d $tmp_parent && ! -L $tmp_parent ]] || die '临时目录必须存在且不能是符号链接目录'
  if (( EUID == 0 )); then
    mode=$(stat -c '%a' "$tmp_parent")
    [[ $(stat -c '%u' "$tmp_parent") -eq 0 ]] || die '以管理员权限运行时，临时目录必须由 root 所有'
    [[ $((mode & 022)) -eq 0 || $((mode & 1000)) -ne 0 ]] || die '临时目录不能允许组用户或其他用户写入，除非启用了粘滞位'
  fi
  umask 077
  INSTALL_TMP_DIR=$(mktemp -d "$tmp_parent/xymediavault-install.XXXXXX") || die '无法创建私有安装临时目录'
  chmod 700 "$INSTALL_TMP_DIR"
  INSTALL_LOG=$(mktemp "$INSTALL_TMP_DIR/install.XXXXXX.log") || die '无法创建安装日志'
  chmod 600 "$INSTALL_LOG"
}
guard_existing_install_tree() {
  [[ $INSTALL_DIR = /* && $INSTALL_DIR != / ]] || return 0
  INSTALL_DIR=$(INSTALL_PATH="$INSTALL_DIR" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ['INSTALL_PATH'])
print(p.resolve(strict=False))
PY
) || die '无法规范化安装目录路径'
  [[ $INSTALL_DIR != / ]] || die '安装目录不能是根目录'
  if [[ -e $INSTALL_DIR ]]; then
    [[ -d $INSTALL_DIR && ! -L $INSTALL_DIR ]] || die '安装目录必须是普通目录'
  fi
  [[ ! -e "$INSTALL_DIR/.env" || ! -L "$INSTALL_DIR/.env" ]] || die '.env must not be a symlink'
}
ensure_instance_id() {
  [[ -n "$XYMEDIA_INSTANCE_ID" ]] || XYMEDIA_INSTANCE_ID=$(awk -F= '$1 == "XYMEDIA_INSTANCE_ID" {print $2; exit}' "$INSTALL_DIR/.env" 2>/dev/null || true)
  if [[ -z "$XYMEDIA_INSTANCE_ID" ]]; then
    XYMEDIA_INSTANCE_ID=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ -n "$XYMEDIA_INSTANCE_ID" ]] || XYMEDIA_INSTANCE_ID="install-${INSTALL_NONCE}"
  fi
  [[ $XYMEDIA_INSTANCE_ID =~ ^[a-z0-9_-]+$ ]] || die 'XYMEDIA_INSTANCE_ID 格式无效'
}
progress() {
  STEP=$((STEP + 1))
  terminal_status "[$STEP/$TOTAL_STEPS] $1" 1
  if [[ -n $INSTALL_LOG ]]; then
    printf '[%d/%d] %s\n' "$STEP" "$TOTAL_STEPS" "$1" >>"$INSTALL_LOG"
  fi
}
terminal_status() {
  if (( TERMINAL_REDRAW )); then
    printf '\033[2K\r%s' "$1"
    [[ ${2:-0} == 1 ]] && printf '\n'
  else
    printf '%s\n' "$1"
  fi
}
run_logged() {
  if "$@" >>"$INSTALL_LOG" 2>&1; then
    return 0
  fi
  return 1
}
run_visible_logged() {
  "$@" 2>&1 | tee -a "$INSTALL_LOG"
  return "${PIPESTATUS[0]}"
}
start_app_after_migration() {
  local helper="$INSTALL_TMP_DIR/start-app-after-migration.sh"
  cat >"$helper" <<'START_APP_HELPER'
#!/usr/bin/env bash
set +e

install_dir=$1
install_log=$2
shift 2
tty_out=${XYMEDIA_INSTALL_TEST_TTY_OUTPUT:-/dev/tty}
emit() {
  printf '%s\n' "$1"
  printf '%s\n' "$1" >>"$install_log" 2>/dev/null || true
}

emit '正在启动 XyMediaVault 应用...'

if "$@" >>"$install_log" 2>&1; then
  app_rc=0
else
  app_rc=$?
fi
emit "应用启动命令退出码：$app_rc"
return_code=$app_rc
exit "$return_code"
START_APP_HELPER
  chmod 700 "$helper" 2>/dev/null || true
  bash "$helper" "$INSTALL_DIR" "$INSTALL_LOG" "$@"
  return $?
}
if [[ ${XYMEDIA_INSTALL_TEST_POST_MIGRATION_ONLY:-0} == 1 ]]; then
  INSTALL_DIR=${XYMEDIA_INSTALL_DIR:-$PWD}
  mkdir -p "$INSTALL_DIR"
  INSTALL_LOG="$INSTALL_DIR/install.log"
  : >"$INSTALL_LOG"
  COMPOSE=(docker)
  COMPOSE_FUSE=()
  MENU_PROFILES=${XYMEDIA_INSTALL_TEST_MENU_PROFILES:-}
  set +e
  migration_rc=0
  printf '数据库迁移退出码：%s\n' "$migration_rc"
  printf '数据库迁移退出码：%s\n' "$migration_rc" >>"$INSTALL_LOG"
  printf '[安装流程] 已完成数据库迁移，继续启动应用\n'
  printf '[安装流程] 已完成数据库迁移，继续启动应用\n' >>"$INSTALL_LOG"
  printf '数据库初始化完成\n'
  printf '数据库初始化完成\n' >>"$INSTALL_LOG"
  if [[ $MENU_PROFILES == *xiaoya-control* ]]; then
    printf '正在将本机小雅 Controller 同步到管理平台数据库...\n'
    printf '正在将本机小雅 Controller 同步到管理平台数据库...\n' >>"$INSTALL_LOG"
    run_visible_logged "${COMPOSE[@]}" --profile migration --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" run --rm -T --no-deps app-migrate bootstrap-controller --config /app/config.yaml </dev/null
  fi
  progress '启动 XyMediaVault 服务' || true
  start_app_after_migration "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" up -d "${FORCE_UP_FLAGS[@]}" app
  app_start_rc=$?
  if (( app_start_rc != 0 )); then
    persist_installer_log || true
    printf 'XyMediaVault 启动失败（退出码：%s）\n' "$app_start_rc" >&2
    exit 1
  fi
  if [[ $MENU_PROFILES == *xiaoya-control* ]]; then
    if print_controller_info; then
      :
    else
      printf '控制器连接信息暂时不可读取，请安装完成后通过菜单 6 查看。\n'
    fi
  fi
  set -e
  exit 0
fi
usage() { sed -n '1,20p' "$0"; }
read_tty() { if ((TTY_TEST_MODE)); then [[ $TTY_TEST_INDEX -lt ${#TTY_TEST_LINES[@]} ]] || return 1; printf -v "$1" '%s' "${TTY_TEST_LINES[$TTY_TEST_INDEX]}"; TTY_TEST_INDEX=$((TTY_TEST_INDEX + 1)); else IFS= read -r "$1" <"$TTY_IN"; fi; }
prompt_tty() { [[ -r $TTY_IN && -w $TTY_OUT ]] || die '交互菜单需要终端，请在终端中运行安装器'; printf '%s' "$1" >>$TTY_OUT; read_tty value || die '无法读取终端输入'; printf '%s' "$value"; }
prompt_tty_into() { [[ -r $TTY_IN && -w $TTY_OUT ]] || die '交互菜单需要终端，请在终端中运行安装器'; printf '%s' "$2" >>$TTY_OUT; read_tty "$1" || die '无法读取终端输入'; }
controller_token_file() { printf '%s/secrets/xiaoya-controller-token' "$INSTALL_DIR"; }
ensure_xiaoya_dir() {
  local required=${1:-0}
  [[ -n $XIAOYA_DIR ]] || prompt_tty_into XIAOYA_DIR "小雅安装/数据目录 [${INSTALL_DIR}/xiaoya]: "
  [[ -n $XIAOYA_DIR || $required != 1 ]] || die '小雅目录不能为空'
  [[ -n $XIAOYA_DIR ]] || XIAOYA_DIR="$INSTALL_DIR/xiaoya"
  [[ $XIAOYA_DIR = /* && $XIAOYA_DIR != / ]] || die '小雅目录必须是绝对路径且不能是根目录'
  if [[ -d $XIAOYA_DIR ]] && [[ -n $(find "$XIAOYA_DIR" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    printf '检测到已有非空小雅目录：%s\n' "$XIAOYA_DIR" >>$TTY_OUT
    printf '请选择：1) 继续使用此目录  0) 返回：' >>$TTY_OUT
    read_tty choice || die '无法读取终端输入'
    [[ $choice == 1 || $choice == 0 ]] || die '无效选择，已停止以保护已有数据'
    [[ $choice != 0 ]] || exit 0
  fi
  mkdir -p "$XIAOYA_DIR" "$INSTALL_DIR/secrets"
}
validate_xiaoya_ports() {
  local port
  for port in "$XIAOYA_WEB_PORT" "$XIAOYA_ADMIN_PORT" "$XIAOYA_PROXY_PORT"; do
    [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || die '小雅主机端口必须是 1 到 65535 之间的数字'
  done
  [[ $XIAOYA_WEB_PORT != "$XIAOYA_ADMIN_PORT" && $XIAOYA_WEB_PORT != "$XIAOYA_PROXY_PORT" && $XIAOYA_ADMIN_PORT != "$XIAOYA_PROXY_PORT" ]] || die '小雅三个主机端口不能重复'
  for port in "$XIAOYA_WEB_PORT" "$XIAOYA_ADMIN_PORT" "$XIAOYA_PROXY_PORT"; do
    if ! python3 - "$port" <<'PY'
import socket, sys
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(('0.0.0.0', int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
    then die "小雅主机端口已被占用：$port"; fi
  done
}
next_free_xiaoya_port() {
  XIAOYA_PORT_START=$1 XIAOYA_PORT_USED=${2:-} python3 - <<'PY'
import os, socket
port = int(os.environ['XIAOYA_PORT_START'])
used = set(filter(None, os.environ.get('XIAOYA_PORT_USED', '').split(',')))
while port <= 65535:
    if str(port) not in used:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.bind(('0.0.0.0', port)); print(port); break
        except OSError: pass
        finally: sock.close()
    port += 1
else: raise SystemExit(1)
PY
}
select_xiaoya_ports() {
  local default_port choice used=
  default_port=$(next_free_xiaoya_port 5678) || die '无法选择小雅 Web 主机端口'
  prompt_tty_into choice "小雅 Web 主机端口 [$default_port]："; XIAOYA_WEB_PORT=${choice:-$default_port}; used=$XIAOYA_WEB_PORT
  default_port=$(next_free_xiaoya_port 2345 "$used") || die '无法选择小雅 2345 主机端口'
  prompt_tty_into choice "小雅 2345 主机端口 [$default_port]："; XIAOYA_ADMIN_PORT=${choice:-$default_port}; used="$XIAOYA_WEB_PORT,$XIAOYA_ADMIN_PORT"
  default_port=$(next_free_xiaoya_port 2346 "$used") || die '无法选择小雅 2346 主机端口'
  prompt_tty_into choice "小雅 2346 主机端口 [$default_port]："; XIAOYA_PROXY_PORT=${choice:-$default_port}
  validate_xiaoya_ports
}
write_controller_token() {
  local file; mkdir -p "$INSTALL_DIR/secrets"; file=$(controller_token_file)
  if [[ ! -s $file ]]; then umask 077; if command -v openssl >/dev/null; then openssl rand -hex 32 >"$file"; else od -An -N32 -tx1 /dev/urandom | tr -d ' \n' >"$file"; fi; chmod 600 "$file"; fi
}
menu() {
  [[ $# -eq 0 ]] || return 0
  [[ -r $TTY_IN && -w $TTY_OUT ]] || die '没有可用终端：安装菜单不能通过非交互管道运行'
  while :; do
    printf '\n%sXyMediaVault 安装器%s\n%s----------------------------------------%s\n%s1) 安装或升级：管理平台和本机小雅（新用户、单机部署、默认推荐）%s\n2) 仅安装管理平台（只需要平台，暂不接入小雅）\n3) 安装管理平台并连接远程小雅控制器（小雅在另一台机器）\n4) 仅安装小雅控制器（这台机器只负责运行小雅控制器）\n%s----------------------------------------%s\n%s5) 状态/诊断/维护%s\n6) 查看小雅控制器地址和密钥\n7) 查看数据库连接信息\n0) 退出\n%s提示：首次本机部署或升级已有本机部署请选择 1；已有本机 Alist/小雅可在 1 中选择复用或独立安装。%s\n选择：' "$COLOR_TITLE" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_RECOMMENDED" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_HINT" "$COLOR_RESET" >>$TTY_OUT
    read_tty choice || die '无法读取终端输入'
    case "$choice" in
      1) write_controller_token; CONTROLLER_URL='http://xymedia-controller:19090'; OPTION2_XIAOYA_PENDING=1; return 0;;
      2) return 0;;
      3) local url name key; url=$(prompt_tty '控制器地址：'); key=$(prompt_tty '控制器密钥：'); name=$(prompt_tty '显示名称：'); [[ $url == https://* || ${ALLOW_HTTP:-0} == 1 ]] || die '远程连接默认要求 HTTPS；设置 ALLOW_HTTP=1 后才允许 HTTP'; curl --fail --silent --show-error --location --max-time 10 -H "X-XyMedia-Controller-Token: $key" "${url%/}/health" >/dev/null || die '控制器健康检查失败，未保存连接'; REMOTE_MODE=1; REMOTE_TOKEN=$key; CONTROLLER_URL="${url%/}"; printf '远程连接 %s (%s) 校验成功，配置已保存；控制器密钥不会显示。\n' "$name" "$CONTROLLER_URL" >>$TTY_OUT; return 0;;
      4) ensure_xiaoya_dir 1; if [[ ${XYMEDIA_INSTALL_TEST_DISCOVERY_ONLY:-0} != 1 && -z $CONTROLLER_BIND_EXPLICIT ]]; then prompt_tty_into CONTROLLER_BIND_ADDRESS "控制器监听地址 [${CONTROLLER_BIND_ADDRESS}]: "; CONTROLLER_BIND_ADDRESS=${CONTROLLER_BIND_ADDRESS:-0.0.0.0}; fi; if [[ ${XYMEDIA_INSTALL_TEST_DISCOVERY_ONLY:-0} != 1 && -z $CONTROLLER_PORT_EXPLICIT ]]; then prompt_tty_into CONTROLLER_PORT "控制器端口 [${CONTROLLER_PORT}]: "; CONTROLLER_PORT=${CONTROLLER_PORT:-19090}; fi; write_controller_token; CONTROLLER_ONLY=1; printf '小雅控制器安装目录已准备。\n' >>$TTY_OUT; MENU_PROFILES='xiaoya-control'; return 0;;
      5) while :; do
            printf '\n%s维护菜单%s\n%s----------------------------------------%s\n1) 查看状态\n2) 一键挂载本地媒体库\n3) 启动/重启已配置挂载\n4) 停用本地媒体库挂载\n%s[!] 清理 XyMediaVault 容器及数据%s\n%s----------------------------------------%s\n0) 返回\n选择：' "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_WARNING" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" >>$TTY_OUT
           read_tty maintenance_choice || die '无法读取终端输入'
           case "$maintenance_choice" in
             1) require_public_app_installation || continue; print_fuse_status;;
             2) require_public_app_installation || continue; prompt_tty_into FUSE_PATH_INPUT '宿主机媒体库目录（必须为空）：'; confirm_fuse_action; MAINTENANCE_ACTION=configure; return 0;;
             3) require_public_app_installation || continue; confirm_fuse_action; MAINTENANCE_ACTION=restart; return 0;;
              4) require_public_app_installation || continue; confirm_fuse_action; MAINTENANCE_ACTION=disable; return 0;;
              5) printf '%s清理选项：%s\n%s----------------------------------------%s\n%s1) 只清理 XyMediaVault%s\n%s2) 清理 XyMediaVault 和本机安装的小雅%s\n0) 取消\n选择：' "$COLOR_WARNING" "$COLOR_RESET" "$COLOR_SECTION" "$COLOR_RESET" "$COLOR_WARNING" "$COLOR_RESET" "$COLOR_WARNING" "$COLOR_RESET" >>$TTY_OUT; read_tty cleanup_choice || die '无法读取终端输入'; case "$cleanup_choice" in 1) CLEANUP_CHOICE=1; return 0;; 2) CLEANUP_CHOICE=2; return 0;; 0) continue;; *) printf '无效选择\n' >>$TTY_OUT;; esac;;
             0) continue 2;; *) printf '无效选择\n' >>$TTY_OUT;;
           esac
          done;;
     6) print_controller_info || true;;
     7) print_database_info || true;;
      0) exit 0;; *) printf '无效选项\n' >>$TTY_OUT;;
    esac
  done
}
if [[ -f "$INSTALL_DIR/.env" ]]; then
  [[ -n ${XYMEDIA_XIAOYA_DIR:-} ]] || XIAOYA_DIR=$(read_install_env XYMEDIA_XIAOYA_DATA_DIR)
  if [[ -z ${XYMEDIA_XIAOYA_CONTAINER:-} ]]; then
    existing_xiaoya_container=$(read_install_env XYMEDIA_XIAOYA_CONTAINER)
    if [[ -n $existing_xiaoya_container ]]; then
      XIAOYA_CONTAINER=$existing_xiaoya_container
      XIAOYA_CONTAINER_EXPLICIT=1
    fi
  fi
  if [[ -z ${XYMEDIA_XIAOYA_PORT:-} ]]; then value=$(read_install_env XYMEDIA_XIAOYA_PORT); [[ -z $value ]] || XIAOYA_WEB_PORT=$value; fi
  if [[ -z ${XYMEDIA_XIAOYA_ADMIN_PORT:-} ]]; then value=$(read_install_env XYMEDIA_XIAOYA_ADMIN_PORT); [[ -z $value ]] || XIAOYA_ADMIN_PORT=$value; fi
  if [[ -z ${XYMEDIA_XIAOYA_PROXY_PORT:-} ]]; then value=$(read_install_env XYMEDIA_XIAOYA_PROXY_PORT); [[ -z $value ]] || XIAOYA_PROXY_PORT=$value; fi
  if [[ -z ${XYMEDIA_EMBY_PROXY_PORT:-} ]]; then value=$(read_install_env XYMEDIA_EMBY_PROXY_PORT); [[ -z $value ]] || EMBY_PROXY_PORT=$value; fi
fi
menu "$@"
validate_controller_settings() {
  [[ $CONTROLLER_PORT =~ ^[0-9]+$ && $CONTROLLER_PORT -ge 1 && $CONTROLLER_PORT -le 65535 ]] || die '控制器端口必须是 1 到 65535 之间的数字'
  [[ $CONTROLLER_BIND_ADDRESS != *$'\r'* && $CONTROLLER_BIND_ADDRESS != *$'\n'* ]] || die '控制器监听地址不能包含换行'
  case "$CONTROLLER_BIND_ADDRESS" in
    ''|localhost|0.0.0.0|::) return 0;;
  esac
  if ! python3 - "$CONTROLLER_BIND_ADDRESS" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
PY
  then
    die '控制器监听地址必须是 IPv4、IPv6、0.0.0.0、:: 或 localhost'
  fi
}
validate_container_name() {
  [[ $XIAOYA_CONTAINER =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,254}$ ]] || die '小雅容器名称不合法，不能包含换行或 Compose 特殊字符'
}
progress '检查安装环境'
[[ $INSTALL_DIR = /* && $INSTALL_DIR != / ]] || die '安装目录必须是绝对路径且不能是根目录'
guard_existing_install_tree
if [[ -f "$INSTALL_DIR/.env" ]]; then INSTALL_EXISTING=1; fi
if (( INSTALL_EXISTING )); then
  if [[ -z ${XYMEDIA_XIAOYA_DIR:-} ]]; then
    XIAOYA_DIR=$(read_install_env XYMEDIA_XIAOYA_DATA_DIR)
  fi
  if [[ -z ${XYMEDIA_XIAOYA_CONTAINER:-} ]]; then
    existing_xiaoya_container=$(read_install_env XYMEDIA_XIAOYA_CONTAINER)
    if [[ -n $existing_xiaoya_container ]]; then
      XIAOYA_CONTAINER=$existing_xiaoya_container
      XIAOYA_CONTAINER_EXPLICIT=1
    fi
  fi
fi
init_installer_log
printf '%s\n' "$DOWNLOAD_MODE" >>$TTY_OUT
if (( FORCE_UPDATE )); then printf '%s\n' '强制更新：已启用' >>$TTY_OUT; fi
if (( FORCE_IMAGE )); then printf '%s\n' '强制镜像更新：已启用' >>$TTY_OUT; fi
if (( FORCE_COMPONENTS )); then printf '%s\n' '强制组件更新：已启用' >>$TTY_OUT; fi
command -v docker >/dev/null || die '需要安装 Docker'
if docker compose version >/dev/null 2>&1; then COMPOSE=(docker compose); elif command -v docker-compose >/dev/null; then COMPOSE=(docker-compose); else die '需要安装 Docker Compose'; fi
docker info >/dev/null 2>&1 || die '无法连接 Docker，请确认 Docker 已启动'
command -v curl >/dev/null || die '需要安装 curl'
command -v zstd >/dev/null || die '需要安装 zstd，用于解压发布包'
command -v python3 >/dev/null || die '需要安装 python3，用于安全解压发布包'
if [[ -n $CLEANUP_CHOICE ]]; then
  (( EUID == 0 )) || die '清理要求 root 权限'
  cleanup_all "$([[ $CLEANUP_CHOICE == 2 ]] && printf 1 || printf 0)"
  exit 0
fi
ensure_instance_id
if (( ! CONTROLLER_ONLY )) && (( INSTALL_EXISTING )); then
  old_host=$(read_install_env XYMEDIA_POSTGRES_HOST)
  old_port=$(read_install_env XYMEDIA_POSTGRES_PORT)
  old_db=$(read_install_env XYMEDIA_POSTGRES_DATABASE)
  old_user=$(read_install_env XYMEDIA_POSTGRES_USER)
  [[ -n $old_host && -z $PG_HOST_ENV_EXPLICIT && $PG_HOST_CLI -eq 0 ]] && PG_HOST=$old_host
  [[ -n $old_port ]] && PG_PORT=$old_port
  [[ -n $old_db ]] && PG_DB=$old_db
  [[ -n $old_user ]] && PG_USER=$old_user
  old_local=$(read_install_env XYMEDIA_POSTGRES_LOCAL_DB)
  if [[ $old_local == 1 || ( $old_host == postgres && $EXISTING_DB != 1 ) ]]; then
    LOCAL_DB=1
    [[ -n $PG_HOST_ENV_EXPLICIT || $PG_HOST_CLI -eq 1 ]] || PG_HOST=$old_host
  fi
fi
if [[ -n $MAINTENANCE_ACTION ]]; then
  require_public_app_installation || die '维护操作仅支持已有完整 app 安装'
  refresh_remount_script
  case "$MAINTENANCE_ACTION" in
    configure) exec env XYMEDIA_INSTALL_DIR="$INSTALL_DIR" sh "$INSTALL_DIR/remount-fuse.sh" --configure "$FUSE_PATH_INPUT";;
    restart) exec env XYMEDIA_INSTALL_DIR="$INSTALL_DIR" sh "$INSTALL_DIR/remount-fuse.sh" --restart;;
    disable) exec env XYMEDIA_INSTALL_DIR="$INSTALL_DIR" sh "$INSTALL_DIR/remount-fuse.sh" --disable;;
  esac
fi
discover_xiaoya_container() {
  local id record selected choice image state
  local -a ids=() candidates=() ordered=()
  if [[ -n ${XIAOYA_CONTAINER_EXPLICIT:-} ]] && (( ! OPTION2_XIAOYA_PENDING )); then
    docker container inspect "$XIAOYA_CONTAINER" >/dev/null 2>&1 || die "未找到小雅容器：$XIAOYA_CONTAINER"
    XIAOYA_FOUND=1
    printf '使用指定的小雅容器：%s（Docker inspect 已确认）\n' "$XIAOYA_CONTAINER" >>$TTY_OUT
    return 0
  fi
  mapfile -t ids < <(docker ps -a -q)
  for id in "${ids[@]}"; do
    record=$(docker inspect "$id" 2>/dev/null | python3 -c '
import json, re, sys
try:
    item = json.load(sys.stdin)[0]
    config = item.get("Config") or {}
    name = (item.get("Name") or "").lstrip("/")
    image = config.get("Image") or item.get("Image") or ""
    labels = config.get("Labels") or {}
    haystack = " ".join([name, image] + [str(k) + "=" + str(v) for k, v in labels.items()]).lower()
    if not re.search(r"(?:alist|xiaoya|xymedia/xiaoya)", haystack):
        raise SystemExit(0)
    print(name + "\t" + image + "\t" + ((item.get("State") or {}).get("Status") or "unknown"))
except (ValueError, IndexError, TypeError, AttributeError):
    raise SystemExit(1)
') || true
    [[ -n $record ]] && candidates+=("$record")
  done
  for record in "${candidates[@]}"; do [[ $record == *$'\trunning' ]] && ordered+=("$record"); done
  for record in "${candidates[@]}"; do [[ $record == *$'\trunning' ]] || ordered+=("$record"); done
  if ((${#ordered[@]} == 0)); then
    if (( OPTION2_XIAOYA_PENDING )); then
      XIAOYA_FOUND=0
      OPTION2_XIAOYA_CHOICE=standalone
      XIAOYA_STANDALONE=1
      XIAOYA_CONTAINER=xymedia-xiaoya
      return 0
    fi
    prompt_tty_into selected '未自动发现小雅容器，请输入容器名称（将执行 Docker inspect）：'
    [[ -n $selected ]] || die '小雅容器名称不能为空'
    docker container inspect "$selected" >/dev/null 2>&1 || die "容器不存在或无法 inspect：$selected"
    XIAOYA_CONTAINER=$selected
    XIAOYA_FOUND=1
    printf '已确认手动指定的小雅容器：%s\n' "$XIAOYA_CONTAINER" >>$TTY_OUT
  elif ((${#ordered[@]} == 1)); then
    IFS=$'\t' read -r selected image state <<<"${ordered[0]}"
    if (( OPTION2_XIAOYA_PENDING )); then
      printf '发现已有小雅容器：%s（镜像：%s，状态：%s）\n' "$selected" "$image" "$state" >>$TTY_OUT
      prompt_tty_into choice '请选择：1) 复用该容器  2) 安装独立小雅  0) 取消：'
      case "$choice" in
        1) XIAOYA_CONTAINER=$selected; XIAOYA_FOUND=1; OPTION2_XIAOYA_CHOICE=reuse;;
        2) XIAOYA_CONTAINER=xymedia-xiaoya; XIAOYA_FOUND=0; XIAOYA_STANDALONE=1; OPTION2_XIAOYA_CHOICE=standalone; return 0;;
        0) exit 0;;
        *) die '无效选择，请输入 1、2 或 0';;
      esac
    else
      XIAOYA_CONTAINER=$selected
      XIAOYA_FOUND=1
      printf '自动发现小雅容器：%s（镜像：%s，状态：%s）\n' "$XIAOYA_CONTAINER" "$image" "$state" >>$TTY_OUT
    fi
    [[ $state == running ]] || printf '警告：小雅容器当前已停止；仍允许安装控制器，状态页会提示。\n' >>$TTY_OUT
  else
    printf '发现多个可能的小雅容器（运行中的优先）：\n' >>$TTY_OUT
    local index=1
    for record in "${ordered[@]}"; do
      IFS=$'\t' read -r name image state <<<"$record"
      printf '%d) %s（镜像：%s，状态：%s）\n' "$index" "$name" "$image" "$state" >>$TTY_OUT
      index=$((index + 1))
    done
    if (( OPTION2_XIAOYA_PENDING )); then
      prompt_tty_into choice '请选择：1) 复用已有容器  2) 安装独立小雅  0) 取消：'
    else
      prompt_tty_into choice '请选择容器编号：'
      [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#ordered[@]} ]] || die '无效的小雅容器编号'
      IFS=$'\t' read -r XIAOYA_CONTAINER image state <<<"${ordered[$((choice - 1))]}"
      XIAOYA_FOUND=1
      printf '已选择小雅容器：%s（镜像：%s，状态：%s）\n' "$XIAOYA_CONTAINER" "$image" "$state" >>$TTY_OUT
      [[ $state == running ]] || printf '警告：小雅容器当前已停止；仍允许安装控制器，状态页会提示。\n' >>$TTY_OUT
      return 0
    fi
    case "$choice" in
      1) prompt_tty_into choice '请选择容器编号：'; [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#ordered[@]} ]] || die '无效的小雅容器编号'; IFS=$'\t' read -r XIAOYA_CONTAINER image state <<<"${ordered[$((choice - 1))]}"; XIAOYA_FOUND=1; OPTION2_XIAOYA_CHOICE=reuse;;
      2) XIAOYA_CONTAINER=xymedia-xiaoya; XIAOYA_FOUND=0; XIAOYA_STANDALONE=1; OPTION2_XIAOYA_CHOICE=standalone; return 0;;
      0) exit 0;;
      *) die '无效选择，请输入 1、2 或 0';;
    esac
    printf '已选择小雅容器：%s（镜像：%s，状态：%s）\n' "$XIAOYA_CONTAINER" "$image" "$state" >>$TTY_OUT
    [[ $state == running ]] || printf '警告：小雅容器当前已停止；仍允许安装控制器，状态页会提示。\n' >>$TTY_OUT
  fi
}
prepare_option2_xiaoya() {
  (( OPTION2_XIAOYA_PENDING )) || return 0
  discover_xiaoya_container
  validate_container_name
  if (( XIAOYA_FOUND )); then
    ensure_xiaoya_dir 1
    validate_xiaoya_data_dir
    XYMEDIA_XIAOYA_MANAGED=0
    OPTION2_XIAOYA_CHOICE=reuse
    MENU_PROFILES='xiaoya-control'
    printf '检测到已有小雅容器：%s，将复用，不创建新的小雅容器。\n' "$XIAOYA_CONTAINER" >>$TTY_OUT
  else
    XIAOYA_STANDALONE=1
    XIAOYA_DIR=$INSTALL_DIR/xiaoya
    XYMEDIA_XIAOYA_MANAGED=1
    OPTION2_XIAOYA_CHOICE=standalone
    MENU_PROFILES='xiaoya xiaoya-control'
    select_xiaoya_ports
    printf '将安装独立的小雅容器：%s（数据目录：%s）。\n' "$XIAOYA_CONTAINER" "$XIAOYA_DIR" >>$TTY_OUT
  fi
}
validate_xiaoya_data_dir() {
  local inspect_json
  [[ -d $XIAOYA_DIR && $XIAOYA_DIR = /* && $XIAOYA_DIR != / ]] || die '小雅数据目录必须是已存在的绝对目录'
  inspect_json=$(docker inspect "$XIAOYA_CONTAINER" 2>/dev/null) || die "无法 inspect 小雅容器：$XIAOYA_CONTAINER"
  XIAOYA_DIR=$(XIAOYA_DIR_INPUT="$XIAOYA_DIR" python3 -c '
import json, os, pathlib, sys

value = os.environ["XIAOYA_DIR_INPUT"]
path = pathlib.Path(value)
if not path.is_absolute() or not path.is_dir():
    raise SystemExit("小雅数据目录不存在或不是目录")
current = pathlib.Path(path.root)
for part in path.parts[1:]:
    current /= part
    if current.is_symlink():
        raise SystemExit("小雅数据目录及其父目录不能包含符号链接")
canonical = str(path.resolve(strict=True))
try:
    payload = json.load(sys.stdin)
    item = payload[0]
    mounts = item.get("Mounts") or []
except (ValueError, IndexError, TypeError, AttributeError):
    raise SystemExit("Docker inspect 返回无效数据")

binds = []
for mount in mounts:
    if not isinstance(mount, dict) or mount.get("Type") != "bind":
        continue
    destination = mount.get("Destination")
    source = mount.get("Source")
    if destination not in ("/data", "/www/data") or not isinstance(source, str) or not source.startswith("/"):
        continue
    source_path = pathlib.Path(source)
    if not source_path.is_dir():
        continue
    source_current = pathlib.Path(source_path.root)
    for part in source_path.parts[1:]:
        source_current /= part
        if source_current.is_symlink():
            raise SystemExit("Docker 挂载源不能包含符号链接")
    binds.append((destination, str(source_path.resolve(strict=True))))

if not binds:
    raise SystemExit("所选容器没有 /data 或 /www/data 的主机目录挂载")
unique = {}
for destination, source in binds:
    unique.setdefault(destination, set()).add(source)
if "/data" in unique:
    if len(unique["/data"]) != 1:
        raise SystemExit("所选容器的 /data 挂载源不唯一")
    selected = next(iter(unique["/data"]))
elif len(unique.get("/www/data", set())) == 1:
    selected = next(iter(unique["/www/data"]))
else:
    raise SystemExit("所选容器的 /www/data 挂载源不唯一")
if canonical != selected:
    raise SystemExit("小雅数据目录与所选容器的 Docker 挂载源不一致")
print(canonical)
' <<<"$inspect_json") || die "小雅数据目录必须与容器 /data 或 /www/data 的 Docker 主机挂载源一致"
  printf '已校验小雅数据目录与容器挂载一致：%s\n' "$XIAOYA_DIR" >>$TTY_OUT
}
if (( CONTROLLER_ONLY )); then
  validate_controller_settings
  [[ $CONTROLLER_BIND_ADDRESS == :: ]] && CONTROLLER_BIND_ADDRESS='[::]'
  if [[ $CONTROLLER_BIND_ADDRESS == *:* && $CONTROLLER_BIND_ADDRESS != \[*\] ]]; then
    CONTROLLER_BIND_ADDRESS="[$CONTROLLER_BIND_ADDRESS]"
  fi
  discover_xiaoya_container
  validate_container_name
  [[ ${XYMEDIA_INSTALL_TEST_DISCOVERY_ONLY:-0} == 1 ]] && exit 0
  validate_xiaoya_data_dir
fi
prepare_option2_xiaoya
if [[ ${XYMEDIA_INSTALL_TEST_MENU_ONLY:-0} == 1 || ${XYMEDIA_INSTALL_TEST_OPTION2_ONLY:-0} == 1 ]]; then
  printf 'TEST_MENU_PROFILES=%s\nTEST_XIAOYA_CONTAINER=%s\nTEST_XIAOYA_MANAGED=%s\n' "$MENU_PROFILES" "$XIAOYA_CONTAINER" "${XYMEDIA_XIAOYA_MANAGED:-0}" >>$TTY_OUT
  exit 0
fi
if (( ! CONTROLLER_ONLY )) && (( PG_HOST_CLI )) && [[ $PG_HOST != postgres && $EXISTING_DB != 1 ]]; then die 'an external database requires --existing-db confirmation'; fi
if (( ! CONTROLLER_ONLY )) && (( PG_HOST_CLI )) && [[ $PG_HOST != postgres && -z $PG_PASSWORD_FILE ]]; then die 'an external database requires --postgres-password-file'; fi
validate_app_ports() {
  local port; local -a ports=("$API_PORT" "$WEBDAV_PORT" "$TVBOX_PORT" "$EMBY_PROXY_PORT")
  for port in "${ports[@]}"; do [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || die '应用主机端口必须是 1 到 65535 之间的数字'; done
  [[ ${#ports[@]} -eq $(printf '%s\n' "${ports[@]}" | sort -u | wc -l) ]] || die '应用主机端口不能重复'
}
validate_app_ports
if (( ! CONTROLLER_ONLY )) && ! [[ $PG_PORT =~ ^[0-9]+$ && $PG_PORT -ge 1024 && $PG_PORT -le 65535 && $PG_DB =~ ^[A-Za-z0-9_]+$ && $PG_USER =~ ^[A-Za-z0-9._-]+$ ]]; then die 'invalid PostgreSQL connection values'; fi
if (( ! CONTROLLER_ONLY )) && [[ -n $PG_HOST ]] && ! python3 - "$PG_HOST" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    if not __import__('re').fullmatch(r'[A-Za-z0-9.-]+', sys.argv[1]): raise SystemExit(1)
PY
then die 'PostgreSQL 主机必须是 IPv4、IPv6 或合法主机名'; fi
progress '准备安装目录与数据库凭据'
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR"/{state,secrets,config}
if (( ! CONTROLLER_ONLY )); then
  mkdir -p "$INSTALL_DIR"/{data/postgres,data,components,releases}
  write_controller_token
  PG_PASSWORD_FILE="$INSTALL_DIR/secrets/xymedia-postgres-password"
  if [[ ! -s $PG_PASSWORD_FILE ]]; then
    umask 077
    if (( INSTALL_EXISTING )) && [[ -s "$INSTALL_DIR/secrets/postgres-password" ]]; then
      cp "$INSTALL_DIR/secrets/postgres-password" "$PG_PASSWORD_FILE"
    elif [[ -n ${PG_PASSWORD_FILE_INPUT:-} ]]; then
      cp "$PG_PASSWORD_FILE_INPUT" "$PG_PASSWORD_FILE"
    elif command -v openssl >/dev/null; then
      openssl rand -hex 32 >"$PG_PASSWORD_FILE"
    else
      od -An -N32 -tx1 /dev/urandom | tr -d ' \n' >"$PG_PASSWORD_FILE"
    fi
    chmod 600 "$PG_PASSWORD_FILE"
  fi
fi
if (( CONTROLLER_ONLY )); then
  umask 077
  chmod 700 "$INSTALL_DIR/secrets"
fi
if (( REMOTE_MODE )); then
  umask 077
  printf '%s' "$REMOTE_TOKEN" >"$INSTALL_DIR/secrets/xiaoya-controller-token"
  chmod 600 "$INSTALL_DIR/secrets/xiaoya-controller-token"
fi
discover_host_addresses() {
  XYMEDIA_HOST_OVERRIDE="${XYMEDIA_HOST_ADDRESSES:-}" python3 - <<'PY'
import ipaddress, os, re, socket, subprocess

def valid(value):
    try:
        ip = ipaddress.ip_address(value.strip())
    except ValueError:
        return None
    if ip.is_loopback or ip.is_link_local or ip.is_unspecified or ip.is_multicast:
        return None
    return str(ip)

raw = os.environ.get('XYMEDIA_HOST_OVERRIDE', '')
values = re.split(r'[\r\n,]+', raw) if raw.strip() else []
if not values:
    try:
        route = subprocess.check_output(['ip', 'route', 'get', '1.1.1.1'], text=True, stderr=subprocess.DEVNULL)
        match = re.search(r'\bsrc\s+(\S+)', route)
        if match:
            values.append(match.group(1))
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        addr = subprocess.check_output(['ip', '-o', 'addr', 'show', 'scope', 'global'], text=True, stderr=subprocess.DEVNULL)
        values.extend(re.findall(r'\binet6?\s+([^/\s]+)', addr))
    except (OSError, subprocess.SubprocessError):
        pass
    if not values:
        for family, target in ((socket.AF_INET, ('1.1.1.1', 80)), (socket.AF_INET6, ('2606:4700:4700::1111', 80, 0, 0))):
            sock = socket.socket(family, socket.SOCK_DGRAM)
            try:
                sock.connect(target)
                values.append(sock.getsockname()[0])
            except OSError:
                pass
            finally:
                sock.close()
seen = set()
for value in values:
    normalized = valid(value)
    if normalized and normalized not in seen:
        seen.add(normalized)
        print(normalized)
PY
}
HOST_ADDRESSES_INITIAL="$(discover_host_addresses || true)"
postgres_host_is_container_ip() {
  local container_ips
  [[ $1 == postgres ]] && return 0
  container_ips=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' xymedia-postgres 2>/dev/null || true)
  [[ " $container_ips " == *" $1 "* ]]
}
if (( ! CONTROLLER_ONLY )) && (( LOCAL_DB )); then
  if [[ -z $HOST_ADDRESSES_INITIAL && -z $PG_HOST_ENV_EXPLICIT ]]; then
    die '未检测到可用宿主机 IP，请设置 XYMEDIA_POSTGRES_HOST 后重试'
  fi
  if [[ -z $PG_HOST_ENV_EXPLICIT && $PG_HOST_CLI -eq 0 ]]; then
    PG_HOST=$(printf '%s\n' "$HOST_ADDRESSES_INITIAL" | head -n 1)
    printf '本地数据库将使用宿主机地址：%s\n' "$PG_HOST" >>$TTY_OUT
  fi
fi
select_random_postgres_port() {
  local requested=${XYMEDIA_POSTGRES_PUBLIC_PORT:-}
  if [[ -n $requested ]]; then
    [[ $requested =~ ^[0-9]+$ && $requested -ge 1024 && $requested -le 65535 ]] || die 'XYMEDIA_POSTGRES_PUBLIC_PORT 必须是 1024 到 65535 之间的数字'
    printf '%s\n' "$requested"
    return 0
  fi
  python3 - <<'PY'
import random, socket
for _ in iter(int, 1):
    port = random.randint(20000, 40000)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(('0.0.0.0', port))
        print(port)
        break
    except OSError:
        pass
    finally:
        sock.close()
PY
}
postgres_port_is_owned() {
  local published
  published=$(docker inspect --format '{{range $p, $bindings := .NetworkSettings.Ports}}{{if eq $p "5432/tcp"}}{{range $bindings}}{{.HostPort}}{{end}}{{end}}{{end}}' xymedia-postgres 2>/dev/null || true)
  [[ -n $published && $published == "$PG_PORT" ]]
}
postgres_port_is_available() {
  PG_PORT_CHECK=$1 python3 - <<'PY'
import os, socket
port = int(os.environ['PG_PORT_CHECK'])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(('0.0.0.0', port))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
}
random_postgres_user() {
  python3 - <<'PY'
import secrets, string
print('x' + ''.join(secrets.choice(string.ascii_lowercase + string.digits + '_') for _ in range(15)))
PY
}
if (( ! CONTROLLER_ONLY )) && (( ! INSTALL_EXISTING )) && (( ! PG_HOST_CLI )); then
  if [[ -z ${XYMEDIA_POSTGRES_HOST:-} && -z $PG_HOST_ENV_EXPLICIT ]]; then
    [[ -n $HOST_ADDRESSES_INITIAL ]] || die '未检测到可用宿主机 IP，请设置 XYMEDIA_POSTGRES_HOST 后重试'
    PG_HOST=$(printf '%s\n' "$HOST_ADDRESSES_INITIAL" | head -n 1)
  fi
  PG_PORT=$(select_random_postgres_port) || die '无法选择 PostgreSQL 对外端口，请稍后重试'
  XYMEDIA_POSTGRES_PUBLIC_PORT=$PG_PORT
  PG_USER=$(random_postgres_user) || die '无法生成 PostgreSQL 用户名'
  LOCAL_DB=1
fi
if (( ! CONTROLLER_ONLY )) && (( LOCAL_DB )) && (( ! PG_HOST_CLI )); then
  [[ -n ${XYMEDIA_POSTGRES_PUBLIC_PORT:-} ]] && PG_PORT=$XYMEDIA_POSTGRES_PUBLIC_PORT
  if ! postgres_port_is_owned && { [[ $PG_PORT == 5432 ]] || ! postgres_port_is_available "$PG_PORT"; }; then
    PG_PORT=$(select_random_postgres_port) || die '无法选择 PostgreSQL 对外端口，请稍后重试'
    XYMEDIA_POSTGRES_PUBLIC_PORT=$PG_PORT
    printf '检测到 PostgreSQL 端口被其他服务占用，已改用随机端口：%s\n' "$PG_PORT" >>$TTY_OUT
  fi
fi
if (( ! CONTROLLER_ONLY )) && (( LOCAL_DB )); then
  [[ -n $PG_HOST ]] || die '本机 bundled PostgreSQL 必须使用宿主机 IP，请设置 XYMEDIA_POSTGRES_HOST 后重试'
  python3 - "$PG_HOST" <<'PY' || die 'PostgreSQL 主机必须是 IPv4、IPv6 或合法主机名'
import ipaddress, re, sys
try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    if not re.fullmatch(r'[A-Za-z0-9.-]+', sys.argv[1]): raise SystemExit(1)
PY
fi
if (( CONTROLLER_ONLY )) || [[ $MENU_PROFILES == *xiaoya-control* ]]; then
  if [[ ! -e "$INSTALL_DIR/config/XYMEDIA_HOST_ADDRESSES" ]]; then
  umask 077
  printf '%s\n' "$HOST_ADDRESSES_INITIAL" >"$INSTALL_DIR/config/XYMEDIA_HOST_ADDRESSES"
  chmod 600 "$INSTALL_DIR/config/XYMEDIA_HOST_ADDRESSES"
  fi
fi
write_probe="$INSTALL_DIR/xymediavault-write-probe-$$"
if ! touch "$write_probe" || ! rm -f "$write_probe"; then
  die "安装目录不可写：$INSTALL_DIR；请使用 --install-dir 指定本机可写目录，例如 /opt/xymediavault"
fi
chmod 700 "$INSTALL_DIR/secrets"
  if (( ! CONTROLLER_ONLY )) && [[ -n $PG_PASSWORD_FILE ]]; then
  [[ -r $PG_PASSWORD_FILE ]] || die 'password file is not readable'
  if [[ "$PG_PASSWORD_FILE" != "$INSTALL_DIR/secrets/xymedia-postgres-password" ]]; then
    cp "$PG_PASSWORD_FILE" "$INSTALL_DIR/secrets/xymedia-postgres-password"
    PG_PASSWORD_FILE="$INSTALL_DIR/secrets/xymedia-postgres-password"
  fi
elif (( ! CONTROLLER_ONLY )); then
  PG_PASSWORD_FILE="$INSTALL_DIR/secrets/xymedia-postgres-password"
  if [[ ! -s $PG_PASSWORD_FILE ]]; then
    umask 077
    if (( INSTALL_EXISTING )) && [[ -s "$INSTALL_DIR/secrets/postgres-password" ]]; then cp "$INSTALL_DIR/secrets/postgres-password" "$PG_PASSWORD_FILE"
    elif command -v openssl >/dev/null; then openssl rand -hex 32 >"$PG_PASSWORD_FILE"
    else od -An -N32 -tx1 /dev/urandom | tr -d ' \n' >"$PG_PASSWORD_FILE"; fi
  fi
fi
if (( ! CONTROLLER_ONLY )); then chmod 600 "$PG_PASSWORD_FILE"; fi
if (( LOCAL_DB )) && [[ -z ${XYMEDIA_POSTGRES_PUBLIC_PORT:-} ]]; then XYMEDIA_POSTGRES_PUBLIC_PORT=$PG_PORT; fi
# Keep the legacy secret for existing administrators and old installations.
TEMPLATE_DIR="$INSTALL_DIR/bootstrap"
mkdir -p "$TEMPLATE_DIR"
template_file() {
  local name=$1 downloaded="$TEMPLATE_DIR/$1"
  if (( ! FORCE_UPDATE )) && [[ -s $downloaded ]]; then
    printf '%s\n' "$downloaded"
    return 0
  fi
  download_remote_file "$RELEASE_BASE/$name?installer=$INSTALL_NONCE" "$downloaded" silent || die "无法下载模板：$name"
  printf '%s\n' "$downloaded"
}
if (( CONTROLLER_ONLY )); then
  COMPOSE_TEMPLATE=$(template_file compose-controller.yaml)
else
  CONFIG_TEMPLATE=$(template_file config.yaml)
  COMPOSE_TEMPLATE=$(template_file compose.yaml)
  DOCKERFILE_TEMPLATE=$(template_file Dockerfile.bootstrap)
  COMPOSE_FUSE_TEMPLATE=$(template_file compose.fuse.yaml)
  REMOUNT_FUSE_TEMPLATE=$(template_file remount-fuse.sh)
fi
umask 077
HOST_ADDRESSES_ENV="$(printf '%s' "$HOST_ADDRESSES_INITIAL" | tr '\r\n' ',,' | sed 's/,,*/,/g; s/^,//; s/,$//')"
if [[ "$HOST_ADDRESSES_ENV" == *$'\r'* || "$HOST_ADDRESSES_ENV" == *$'\n'* ]]; then die 'invalid host address value'; fi
[[ ! -L "$INSTALL_DIR/.env" ]] || die '.env must not be a symlink'
env_tmp=$(mktemp "$INSTALL_DIR/.env.tmp.XXXXXX") || die '无法创建安全的 .env 临时文件'
chmod 600 "$env_tmp"
  if [[ -f "$INSTALL_DIR/.env" ]]; then cp "$INSTALL_DIR/.env" "$env_tmp"; fi
XIAOYA_MANAGED_ENV=$(awk -F= '$1 == "XYMEDIA_XIAOYA_MANAGED" {print $2; exit}' "$env_tmp" 2>/dev/null || true)
if [[ -z $OPTION2_XIAOYA_CHOICE ]]; then
  [[ ${XYMEDIA_XIAOYA_MANAGED:-0} == 1 ]] || XYMEDIA_XIAOYA_MANAGED=${XIAOYA_MANAGED_ENV:-0}
fi
FUSE_ENABLED=$(awk -F= '$1 == "XYMEDIA_FUSE_ENABLED" {print $2; exit}' "$env_tmp" 2>/dev/null || true)
FUSE_HOST_PATH=$(awk -F= '$1 == "XYMEDIA_FUSE_HOST_PATH" {print $2; exit}' "$env_tmp" 2>/dev/null || true)
[[ $FUSE_ENABLED == true || $FUSE_ENABLED == false ]] || FUSE_ENABLED=false
python3 - "$env_tmp" "$INSTALL_DIR" "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$API_PORT" "$WEBDAV_PORT" "$TVBOX_PORT" "$EMBY_PROXY_PORT" "$CONTROLLER_URL" "${XIAOYA_DIR:-$INSTALL_DIR/xiaoya}" "$XIAOYA_CONTAINER" "$HOST_ADDRESSES_ENV" "$CONTROLLER_BIND_ADDRESS" "$CONTROLLER_PORT" "$FUSE_ENABLED" "$FUSE_HOST_PATH" "${XYMEDIA_XIAOYA_MANAGED:-0}" "$XYMEDIA_INSTANCE_ID" "$LOCAL_DB" "$XYMEDIA_POSTGRES_PUBLIC_PORT" "$XIAOYA_WEB_PORT" "$XIAOYA_ADMIN_PORT" "$XIAOYA_PROXY_PORT" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1])
keys=('XYMEDIA_INSTALL_DIR','XYMEDIA_POSTGRES_HOST','XYMEDIA_POSTGRES_PORT','XYMEDIA_POSTGRES_DATABASE','XYMEDIA_POSTGRES_USER','XYMEDIA_API_PORT','XYMEDIA_WEBDAV_PORT','XYMEDIA_TVBOX_PORT','XYMEDIA_EMBY_PROXY_PORT','XYMEDIA_XIAOYA_CONTROLLER_URL','XYMEDIA_XIAOYA_DATA_DIR','XYMEDIA_XIAOYA_CONTAINER','XYMEDIA_HOST_ADDRESSES','XYMEDIA_CONTROLLER_BIND_ADDRESS','XYMEDIA_CONTROLLER_PORT','XYMEDIA_FUSE_ENABLED','XYMEDIA_FUSE_HOST_PATH','XYMEDIA_XIAOYA_MANAGED','XYMEDIA_INSTANCE_ID','XYMEDIA_POSTGRES_LOCAL_DB','XYMEDIA_POSTGRES_PUBLIC_PORT','XYMEDIA_XIAOYA_PORT','XYMEDIA_XIAOYA_ADMIN_PORT','XYMEDIA_XIAOYA_PROXY_PORT')
values=dict(zip(keys, sys.argv[2:]))
seen=set(); output=[]
for line in p.read_text().splitlines():
    key=line.split('=',1)[0] if '=' in line else ''
    if key in values:
        output.append(key+'='+values[key]); seen.add(key)
    else:
        output.append(line)
output.extend(key+'='+value for key,value in values.items() if key not in seen)
p.write_text('\n'.join(output)+'\n')
PY
[[ ! -L "$INSTALL_DIR/.env" ]] || die '.env became a symlink during update'
mv -f "$env_tmp" "$INSTALL_DIR/.env"
if [[ -z ${BOOTSTRAP_IMAGE_ENV_EXPLICIT:-} ]] && ! grep -q '^XYMEDIA_BOOTSTRAP_IMAGE=' "$INSTALL_DIR/.env"; then
  if [[ -n $XYMEDIA_MIRROR ]]; then
    export XYMEDIA_BOOTSTRAP_IMAGE="${XYMEDIA_MIRROR#https://}/ghcr.io/iceqi/xymedia-bootstrap:1"
  fi
fi
progress '下载公开版本目录（读取 App、TMM、Title 当前版本）'
catalog_sep='?'
case "$CATALOG_URL" in *\?*) catalog_sep='&';; esac
if (( FORCE_UPDATE )) || [[ ! -s $INSTALL_DIR/catalog-v1.json ]]; then
  download_remote_file "${CATALOG_URL}${catalog_sep}installer=$INSTALL_NONCE" "$INSTALL_DIR/catalog-v1.json" silent || die '公开版本目录下载失败；如需直连 GitHub，请取消设置 XYMEDIA_MIRROR 后重试'
fi
python3 - "$INSTALL_DIR/catalog-v1.json" <<'PY' || die 'invalid public catalog'
import json, sys
import re
catalog = json.load(open(sys.argv[1]))
assert catalog.get("schema_version") == 1
for component in ("app", "tmm", "title", "controller"):
    assert isinstance(catalog.get("components", {}).get(component, {}).get("artifacts"), dict)
    for entry in catalog["components"][component]["artifacts"].values():
        assert isinstance(entry, dict) and re.fullmatch(r"[0-9a-fA-F]{64}", entry.get("sha256", ""))
PY
case "$(uname -m)" in x86_64|amd64) PLATFORM=linux-amd64;; aarch64|arm64) PLATFORM=linux-arm64;; *) die "unsupported host architecture: $(uname -m)";; esac
artifact() {
  python3 - "$INSTALL_DIR/catalog-v1.json" "$1" "$2" <<'PY'
import json, sys
catalog, component, platform = sys.argv[1:]
artifacts = json.load(open(catalog))["components"][component]["artifacts"]
entry = artifacts.get(platform) or artifacts.get("linux-any")
import re
if not isinstance(entry, dict) or not isinstance(entry.get("version"), str) or not isinstance(entry.get("asset_url"), str) or not isinstance(entry.get("sha256"), str) or re.fullmatch(r"[0-9a-fA-F]{64}", entry["sha256"]) is None:
    raise SystemExit(1)
url = entry["asset_url"]
from urllib.parse import urlsplit
parsed = urlsplit(url)
try:
    port = parsed.port
except ValueError:
    raise SystemExit(1)
if (
    parsed.scheme != "https"
    or parsed.netloc.lower() not in ("github.com", "gh-proxy.org")
    or parsed.username is not None
    or parsed.password is not None
    or parsed.query
    or parsed.fragment
    or port is not None
    or "%" in (parsed.path or "")
      or (re.fullmatch(r"/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*", parsed.path or "") is None and re.fullmatch(r"/https://github\.com/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*", parsed.path or "") is None)
):
    raise SystemExit(1)
print(entry["version"] + "\t" + url + "\t" + entry["sha256"].lower())
PY
}
download_extract() {
  local component=$1
  local version=$2
  local url=$3
  local expected_sha=$4
  local target=$5
  local work archive tarball effective actual
  work=$(mktemp -d "$INSTALL_TMP_DIR/${component}.XXXXXX")
  archive="$work/$component.archive"
  printf '    正在下载 %s %s（%s）\n' "$component" "$version" "${url##*/}"
  download_remote_file "$url" "$archive" progress || die "$component 下载失败；如需直连 GitHub，请取消设置 XYMEDIA_MIRROR 后重试"
  effective=${DOWNLOAD_EFFECTIVE_URL:-$url}
  XYMEDIA_MIRROR_HOST="${XYMEDIA_MIRROR#https://}" python3 - "$effective" <<'PY' || die "$component 下载重定向不在 canonical Generic Package URL"
import os, re, sys
from urllib.parse import urlsplit
url = sys.argv[1]
parsed = urlsplit(url)
try:
    port = parsed.port
except ValueError:
    raise SystemExit(1)
if (
    parsed.scheme != "https"
    or parsed.netloc.lower() not in ("github.com", "gh-proxy.org", os.environ.get("XYMEDIA_MIRROR_HOST", "").lower())
    or parsed.username is not None
    or parsed.password is not None
    or parsed.query
    or parsed.fragment
    or port is not None
    or "%" in (parsed.path or "")
      or (re.fullmatch(r"/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*", parsed.path or "") is None and re.fullmatch(r"/https://github\.com/iceqi/xymedia-releases/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?/[A-Za-z0-9][A-Za-z0-9._-]*", parsed.path or "") is None)
):
    raise SystemExit(1)
PY
  actual=$(sha256sum "$archive" | cut -d' ' -f1); [[ $actual == "$expected_sha" ]] || die "$component SHA256 校验失败"
  printf '    正在解压 %s %s\n' "$component" "$version"
  local tarball="$archive.tar"
  if [[ $url == *.tar.gz || $url == *.tgz ]]; then gzip -dc "$archive" >"$tarball"; else zstd -dc "$archive" >"$tarball"; fi
  python3 - "$tarball" "$target" <<'PY'
import pathlib, sys, tarfile
archive, target = sys.argv[1:]
pathlib.Path(target).mkdir(parents=True, exist_ok=True)
with tarfile.open(archive, 'r:*') as tf:
    members = tf.getmembers()
    executable_members = set()
    for m in members:
        name = m.name.lstrip('./')
        if not name or name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts:
            raise SystemExit('archive contains traversal path')
        if m.issym() or m.islnk() or not (m.isfile() or m.isdir()):
            raise SystemExit('archive contains link or special file')
        m.name = name
        # A restrictive umask can remove execute bits while tar extracts. Keep
        # the archive's executable intent so binaries below a bin directory
        # are repaired without making arbitrary archive files executable.
        if m.isfile() and (m.mode & 0o111) and 'bin' in pathlib.PurePosixPath(name).parts[:-1]:
            executable_members.add(name)
    try:
        tf.extractall(target, members=members, filter='data')
    except TypeError:
        tf.extractall(target, members=members)
for m in members:
    path = pathlib.Path(target, m.name)
    required = m.name in executable_members or (
        m.isfile() and pathlib.PurePosixPath(m.name).parts[-2:] in {
            ('bin', 'xymediavault'), ('bin', 'xymedia-supervisor')
        }
    )
    if not required:
        continue
    if not path.is_file() or path.is_symlink():
        raise SystemExit('executable archive member was not extracted as a regular file')
    path.chmod(path.stat().st_mode | 0o500)
PY
  if [[ $component == app ]]; then
    app_root=$(find "$target" -mindepth 2 -maxdepth 3 -type d -name bin -print -quit)
    [[ -n $app_root ]] || die 'app package entrypoint directory is missing'
    for entrypoint in "$app_root/xymediavault" "$app_root/xymedia-supervisor"; do
      [[ -f $entrypoint && ! -L $entrypoint ]] || die "app package entrypoint is not a regular file: ${entrypoint##*/}"
      chmod 755 "$entrypoint" || die "无法恢复 app entrypoint 执行权限：${entrypoint##*/}"
    done
  fi
  cp "$archive" "$target/.download.archive"
  rm -f "$tarball"
  rm -rf "$work"
}
install_controller_binary() {
  local source=$1 target="$INSTALL_DIR/controller/xymedia-edge" staged
  mkdir -p "$INSTALL_DIR/controller"
  staged=$(mktemp "$INSTALL_DIR/controller/.xymedia-edge.XXXXXX") || die '无法准备控制器更新文件'
  chmod 600 "$staged"
  if ! cp "$source" "$staged"; then rm -f "$staged"; die '控制器文件复制失败'; fi
  chmod 755 "$staged"
  if [[ -e $target ]] && docker container inspect xymedia-controller >/dev/null 2>&1; then
    run_logged "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" stop xiaoya-control || { rm -f "$staged"; die '无法停止旧的小雅控制器'; }
  fi
  [[ ! -L $target ]] || { rm -f "$staged"; die '控制器文件不能是符号链接'; }
  if ! mv -f "$staged" "$target"; then rm -f "$staged"; die '控制器文件替换失败'; fi
  chmod 755 "$target"
}
if (( CONTROLLER_ONLY )); then
    IFS=$'\t' read -r controller_version controller_url controller_sha < <(artifact controller "$PLATFORM") || die '公开目录没有当前架构的 controller 制品'
  progress "下载小雅控制器 $controller_version ($PLATFORM)"
    download_extract controller "$controller_version" "$controller_url" "$controller_sha" "$INSTALL_DIR/controller-stage"
  edge=$(find "$INSTALL_DIR/controller-stage" -type f -name xymedia-edge -perm -u+x -print -quit)
  [[ -n $edge ]] || die 'controller archive lacks executable xymedia-edge'
  install_controller_binary "$edge"
  [[ -s "$INSTALL_DIR/secrets/xiaoya-controller-token" ]] || write_controller_token
  cp "$COMPOSE_TEMPLATE" "$INSTALL_DIR/compose.yaml"
  progress '启动小雅控制器'
  run_logged "${COMPOSE[@]}" --profile xiaoya-control --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" up -d "${FORCE_UP_FLAGS[@]}" xiaoya-control || die '小雅控制器启动失败'
  printf '小雅控制器已安装，监听地址：%s:%s；请按防火墙配置访问，控制器密钥不会显示。\n' "$CONTROLLER_BIND_ADDRESS" "$CONTROLLER_PORT"
  exit 0
fi
IFS=$'\t' read -r APP_VERSION APP_URL APP_SHA < <(artifact app "$PLATFORM")
APP_STAGE=$(mktemp -d "$INSTALL_TMP_DIR/app.XXXXXX")
if (( FORCE_IMAGE )) && (( ! FORCE_UPDATE )) && [[ -L $INSTALL_DIR/releases/current ]]; then
  APP_ROOT=$(readlink -f -- "$INSTALL_DIR/releases/current")
  [[ -x $APP_ROOT/bin/xymediavault ]] || die '当前 release 不完整，无法执行仅镜像更新'
else
  progress "下载应用包 $APP_VERSION ($PLATFORM)"
  download_extract app "$APP_VERSION" "$APP_URL" "$APP_SHA" "$APP_STAGE"
  APP_ROOT="$APP_STAGE/xymediavault-$APP_VERSION-$PLATFORM"
fi
[[ -x $APP_ROOT/bin/xymediavault && -x $APP_ROOT/bin/xymedia-supervisor && -d $APP_ROOT/web/dist && -f $APP_ROOT/release.json ]] || die "app package $APP_VERSION lacks the required xymedia-supervisor; use a newer public app package"
app_platform=$(python3 - "$APP_ROOT/release.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as release_file:
        release = json.load(release_file)
except (OSError, ValueError):
    raise SystemExit(1)
platform = release.get('platform')
if not isinstance(platform, str):
    raise SystemExit(1)
print(platform)
PY
) || die "app package $APP_VERSION has invalid release.json platform metadata; use a linux-$([[ $PLATFORM == linux-arm64 ]] && printf arm64 || printf amd64) app package/release"
[[ $app_platform == "$PLATFORM" ]] || die "app package $APP_VERSION is for $app_platform, but this host requires $PLATFORM; use a linux-$([[ $PLATFORM == linux-arm64 ]] && printf arm64 || printf amd64) app package/release"
if [[ -x $APP_ROOT/bin/xymedia-edge ]]; then
  install_controller_binary "$APP_ROOT/bin/xymedia-edge"
fi
if (( ! FORCE_IMAGE || FORCE_UPDATE )); then
mkdir -p "$INSTALL_DIR/releases/releases"
if [[ -e "$INSTALL_DIR/releases/releases/$APP_VERSION" ]]; then
  progress '停止旧版本应用以替换同版本 release'
  run_logged "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" stop app || die '无法停止旧版本应用'
fi
release_target="$INSTALL_DIR/releases/releases/$APP_VERSION"
release_backup="$INSTALL_DIR/releases/.${APP_VERSION}.old.$$"
RELEASE_TARGET=$release_target
RELEASE_BACKUP=$release_backup
[[ ! -L "$release_target" ]] || die 'release 目录不能是符号链接'
mv "$APP_ROOT" "$release_target.new.$$" || die '无法准备 release 替换'
if [[ -e "$release_target" ]]; then
  mv "$release_target" "$release_backup" || die '无法备份旧 release'
fi
mv "$release_target.new.$$" "$release_target" || { mv "$release_backup" "$release_target" 2>/dev/null || true; die '无法安装新 release'; }
RELEASE_ROLLBACK_ACTIVE=1
ln -sfn "releases/$APP_VERSION" "$INSTALL_DIR/releases/current"
fi
if (( ! SKIP_COMPONENTS )); then
  progress '下载 TMM 与 Title 组件包'
  for component in tmm title; do
    platform=$([[ $component == tmm ]] && printf linux-any || printf "$PLATFORM")
    IFS=$'\t' read -r version url sha < <(artifact "$component" "$platform")
    archive="$INSTALL_DIR/components/$component.tar.zst"
    marker_version="$INSTALL_DIR/components/$component.version"
    marker_sha="$INSTALL_DIR/components/$component.sha256"
    if (( ! FORCE_COMPONENTS && ! FORCE_UPDATE )) && [[ -s $archive && -f $marker_version && -f $marker_sha ]] && [[ $(<"$marker_version") == "$version" ]] && [[ $(<"$marker_sha") == "$sha" ]] && [[ $(sha256sum "$archive" | cut -d' ' -f1) == "$sha" ]]; then
      printf '%s %s 已安装且完整，跳过下载\n' "$([[ $component == tmm ]] && printf TMM || printf Title)" "$version"
      continue
    fi
    component_stage=$(mktemp -d "$INSTALL_TMP_DIR/$component.XXXXXX")
    download_extract "$component" "$version" "$url" "$sha" "$component_stage"
    archive_tmp="$INSTALL_TMP_DIR/$component.archive"
    cp "$component_stage/.download.archive" "$archive_tmp"
    [[ -s $archive_tmp ]] || die "$component archive was not retained"
    component_root="$component_stage"
    if [[ ! -d "$component_root/payload" ]]; then
      component_root=$(find "$component_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)
      [[ -n $component_root && -d "$component_root/payload" ]] || die "$component archive has no payload directory"
    fi
    if [[ $component == tmm ]]; then
      [[ -f "$component_root/payload/xymedia-api.jar" ]] || die 'TMM archive is missing payload/xymedia-api.jar'
      compgen -G "$component_root/payload/lib/*" >/dev/null || die 'TMM archive is missing payload/lib files'
    else
      for required in payload/python/bin/python payload/service/entrypoint.py payload/service/app.py payload/service/engine.json payload/NOTICE payload/licenses/guessit-LICENSE.txt payload/licenses/flask-LICENSE.txt payload/licenses/gunicorn-LICENSE.txt; do [[ -f "$component_root/$required" ]] || die "Title archive is missing $required"; done
    fi
    cp "$archive_tmp" "$archive.tmp"
    printf '%s\n' "$version" >"$marker_version.tmp"
    printf '%s\n' "$sha" >"$marker_sha.tmp"
    mv -f "$archive.tmp" "$archive"; mv -f "$marker_version.tmp" "$marker_version"; mv -f "$marker_sha.tmp" "$marker_sha"
  done
fi
CONTROLLER_URL="$CONTROLLER_URL" XIAOYA_CONTAINER="$XIAOYA_CONTAINER" PG_HOST="$PG_HOST" PG_PORT="$PG_PORT" PG_DB="$PG_DB" PG_USER="$PG_USER" python3 - "$CONFIG_TEMPLATE" "$INSTALL_DIR/config.yaml" <<'PY'
import os, pathlib, sys
template, output = map(pathlib.Path, sys.argv[1:])
values = {
    "${XYMEDIA_POSTGRES_HOST}": os.environ["PG_HOST"],
    "${XYMEDIA_POSTGRES_PORT}": os.environ["PG_PORT"],
    "${XYMEDIA_POSTGRES_DATABASE}": os.environ["PG_DB"],
    "${XYMEDIA_POSTGRES_USER}": os.environ["PG_USER"],
    "${XYMEDIA_XIAOYA_CONTROLLER_URL}": os.environ["CONTROLLER_URL"],
    "${XYMEDIA_XIAOYA_CONTAINER}": os.environ["XIAOYA_CONTAINER"],
}
content = template.read_text()
for placeholder, value in values.items():
    content = content.replace(placeholder, value)
output.write_text(content)
PY
rm -f "$INSTALL_DIR/compose.yaml" "$INSTALL_DIR/Dockerfile.bootstrap"
cp "$COMPOSE_TEMPLATE" "$DOCKERFILE_TEMPLATE" "$INSTALL_DIR/"
if (( PG_HOST_CLI )) || [[ -n ${XYMEDIA_POSTGRES_HOST:-} ]]; then
  python3 - "$INSTALL_DIR/compose.yaml" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r'\n    extra_hosts:\n      - "host\.docker\.internal:host-gateway"', '', text)
p.write_text(text)
PY
fi
cp "$COMPOSE_FUSE_TEMPLATE" "$REMOUNT_FUSE_TEMPLATE" "$INSTALL_DIR/"
chmod 700 "$INSTALL_DIR/remount-fuse.sh"
FUSE_ENABLED=$(awk -F= '$1 == "XYMEDIA_FUSE_ENABLED" {print $2; exit}' "$INSTALL_DIR/.env")
COMPOSE_FUSE=()
if [[ $FUSE_ENABLED == true ]]; then COMPOSE_FUSE=(-f "$INSTALL_DIR/compose.fuse.yaml"); fi
FUSE_ENABLED="$FUSE_ENABLED" python3 - "$INSTALL_DIR/config.yaml" <<'PY'
import os, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
enabled = os.environ['FUSE_ENABLED'] == 'true'
text = re.sub(r'(?m)^(  auto_mount:)\s*.*$', r'\1 ' + ('true' if enabled else 'false'), text)
text = re.sub(r'(?m)^(  mount_path:)\s*.*$', r'\1 /mnt/xymediavault', text)
tmp = p.with_name(p.name + '.tmp')
tmp.write_text(text)
tmp.replace(p)
PY
if [[ -n $MENU_PROFILES ]]; then
  if [[ ${XYMEDIA_XIAOYA_MANAGED:-0} == 1 ]]; then
    [[ ${XYMEDIA_INSTALL_CONFIRM:-} == INSTALL_XIAOYA ]] || { confirm=$(prompt_tty '安装小雅将创建并启动相关容器，输入 1 继续，其他内容取消： '); [[ $confirm == 1 ]] || die '已取消小雅安装'; }
  fi
  for profile in $MENU_PROFILES; do
    case "$profile" in
      xiaoya) profile_service=xiaoya-alist;;
      xiaoya-control) profile_service=xiaoya-control;;
      *) die "未知小雅 profile：$profile";;
    esac
    if [[ $profile == xiaoya ]]; then
      printf '正在创建并启动小雅容器：%s\n' "$XIAOYA_CONTAINER"
    else
      printf '正在创建并启动小雅控制器：xymedia-controller\n'
    fi
    if ! run_logged "${COMPOSE[@]}" --profile "$profile" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" up -d --no-deps "${FORCE_UP_FLAGS[@]}" "$profile_service"; then
      if [[ $profile == xiaoya ]]; then
        profile_state=$(docker inspect --format '{{.State.Status}}' "$XIAOYA_CONTAINER" 2>>"$INSTALL_LOG" || true)
      else
        profile_state=$(docker inspect --format '{{.State.Status}}' xymedia-controller 2>>"$INSTALL_LOG" || true)
      fi
      if [[ $profile_state == running ]]; then
        printf '小雅 profile 启动命令返回异常，但目标容器已运行，继续安装：%s\n' "$profile"
        printf '小雅 profile 启动命令返回异常，但目标容器已运行，继续安装：%s\n' "$profile" >>"$INSTALL_LOG"
      else
        die "小雅 profile 启动失败：$profile"
      fi
    fi
    if [[ $profile == xiaoya ]]; then
      printf '小雅容器已启动：%s\n' "$XIAOYA_CONTAINER"
    else
      printf '小雅控制器已启动：xymedia-controller\n'
    fi
  done
  if [[ $MENU_PROFILES == *xiaoya-control* ]]; then
    controller_state=$(docker inspect --format '{{.State.Status}}' xymedia-controller 2>>"$INSTALL_LOG" || true)
    [[ $controller_state == running ]] || die '本机小雅控制器未正常运行'
  fi
fi
progress '下载 bootstrap runtime'
  if ! run_logged "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" pull app; then
    die 'bootstrap runtime 下载失败；请确认镜像服务可用，或通过 XYMEDIA_BOOTSTRAP_IMAGE 使用直接 GHCR 镜像'
  fi
validate_bootstrap_runtime_platform() {
  local bootstrap_image_expected bootstrap_image_ref bootstrap_image_id runtime_metadata runtime_platform
  bootstrap_image_expected=${XYMEDIA_BOOTSTRAP_IMAGE:-}
  if [[ -z $bootstrap_image_expected && -f $INSTALL_DIR/.env ]]; then
    bootstrap_image_expected=$(awk -F= '$1 == "XYMEDIA_BOOTSTRAP_IMAGE" {sub(/^[^=]*=/, ""); print; exit}' "$INSTALL_DIR/.env")
  fi
  bootstrap_image_expected=${bootstrap_image_expected:-ghcr.io/iceqi/xymedia-bootstrap:1}
  bootstrap_image_ref=$("${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" config --images 2>>"$INSTALL_LOG" | awk -v expected="$bootstrap_image_expected" 'NF && $0 == expected {print; exit}') || true
  if [[ -z $bootstrap_image_ref ]]; then
    bootstrap_image_id=$("${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" images -q app 2>>"$INSTALL_LOG" | awk 'NF {print; exit}') || true
    bootstrap_image_ref=$bootstrap_image_id
  fi
  [[ -n $bootstrap_image_ref ]] || die '无法确定 bootstrap runtime 的本地镜像引用或 ID'

  runtime_metadata=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$bootstrap_image_ref" 2>>"$INSTALL_LOG" || true)
  runtime_metadata=${runtime_metadata//$'\r'/}
  printf 'bootstrap platform detection: ref=%s image-inspect=%s\n' "$bootstrap_image_ref" "${runtime_metadata:-<empty>}" >>"$INSTALL_LOG"
  if [[ ! $runtime_metadata =~ ^[^/]+/[^/]+$ ]]; then
    runtime_metadata=$(docker inspect --type image --format '{{.Os}}/{{.Architecture}}' "$bootstrap_image_ref" 2>>"$INSTALL_LOG" || true)
    runtime_metadata=${runtime_metadata//$'\r'/}
    printf 'bootstrap platform detection: ref=%s docker-inspect=%s\n' "$bootstrap_image_ref" "${runtime_metadata:-<empty>}" >>"$INSTALL_LOG"
  fi
  [[ $runtime_metadata =~ ^[^/]+/[^/]+$ ]] || die 'bootstrap runtime 的本地镜像平台元数据不完整；请查看 install.log 中的 docker image inspect 输出'
  runtime_platform=$runtime_metadata
  case "$runtime_platform" in
    linux/amd64) runtime_platform=linux-amd64;;
    linux/arm64) runtime_platform=linux-arm64;;
    *) die "bootstrap runtime 平台为 $runtime_platform，无法验证；需要 linux-amd64 或 linux-arm64 的 multiarch 镜像";;
  esac
  [[ $runtime_platform == "$PLATFORM" ]] || die "bootstrap runtime 平台为 $runtime_platform，但当前主机需要 $PLATFORM；请使用 multiarch 镜像"
}
validate_bootstrap_runtime_platform
progress '准备 PostgreSQL 连接'
if (( LOCAL_DB )); then
  if ! run_logged "${COMPOSE[@]}" --profile local-db --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" up -d postgres; then
    die 'PostgreSQL 启动失败'
  fi
fi
if (( LOCAL_DB )); then
  wait_for_postgres() {
    local started_at elapsed container_id health
    local previous_int previous_term
    postgres_wait_interrupted=0
    started_at=$(date +%s)
    previous_int=$(trap -p INT || true)
    previous_term=$(trap -p TERM || true)
    trap 'postgres_wait_interrupted=1' INT TERM
    while :; do
      if (( postgres_wait_interrupted )); then
        printf '\n已收到中断信号，正在停止 PostgreSQL 等待。\n'
        printf '%s\n' 'PostgreSQL wait interrupted by signal' >>"$INSTALL_LOG"
        printf '\n--- PostgreSQL 容器日志 ---\n' >>"$INSTALL_LOG"
        "${COMPOSE[@]}" --profile local-db --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" logs postgres >>"$INSTALL_LOG" 2>&1 || true
        [[ -n $previous_int ]] && eval "$previous_int" || trap - INT
        [[ -n $previous_term ]] && eval "$previous_term" || trap - TERM
        return 130
      fi
      elapsed=$(( $(date +%s) - started_at ))
    container_id=$("${COMPOSE[@]}" --profile local-db --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" ps -q postgres 2>>"$INSTALL_LOG" || true)
    health=
    if [[ -n $container_id ]]; then
      health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>>"$INSTALL_LOG" || true)
    fi
    if [[ $health == healthy ]]; then
      terminal_status "[$STEP/$TOTAL_STEPS] PostgreSQL 已就绪（$elapsed 秒）" 1
      [[ -n $previous_int ]] && eval "$previous_int" || trap - INT
      [[ -n $previous_term ]] && eval "$previous_term" || trap - TERM
      return 0
    fi
    terminal_status "[$STEP/$TOTAL_STEPS] 等待 PostgreSQL 就绪（已用 $elapsed 秒，状态：${health:-unknown}）"
    printf 'PostgreSQL status: elapsed=%s health=%s\n' "$elapsed" "${health:-unknown}" >>"$INSTALL_LOG"
    sleep 2
    done
  }
  wait_for_postgres || die 'PostgreSQL 等待被中断，安装未完成'
fi
wait_postgres_external() {
  local started_at elapsed db_network project_name network_name
  local -a client_command
  PG_PASSWORD=$(<"$PG_PASSWORD_FILE")
  [[ -n $PG_PASSWORD ]] || die 'PostgreSQL 密码不能为空'
  if (( LOCAL_DB )); then
    db_network=$(docker inspect --format '{{range $network, $config := .NetworkSettings.Networks}}{{$network}}{{"\n"}}{{end}}' xymedia-postgres 2>>"$INSTALL_LOG" | head -n 1)
  else
    project_name=${COMPOSE_PROJECT_NAME:-$(basename "$INSTALL_DIR")}
    network_name="${project_name}_default"
    db_network=$(docker network ls --filter "label=com.docker.compose.project=$project_name" --format '{{.Name}}' 2>>"$INSTALL_LOG" | head -n 1 || true)
    if [[ -z $db_network ]]; then
      db_network=$network_name
      docker network create --label "com.docker.compose.project=$project_name" --label com.docker.compose.network=default "$db_network" >>"$INSTALL_LOG" 2>&1 || true
    fi
  fi
  [[ -n $db_network ]] || die '无法确定 PostgreSQL 外部连接探测所需的 Compose 网络'
  started_at=$(date +%s)
  while :; do
    client_command=(docker run --rm --network "$db_network" -e "PGPASSWORD=$PG_PASSWORD" postgres:17-bookworm psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c 'SELECT 1')
    if "${client_command[@]}" >>"$INSTALL_LOG" 2>&1; then
      elapsed=$(( $(date +%s) - started_at ))
      terminal_status "[$STEP/$TOTAL_STEPS] PostgreSQL 外部连接已验证（$elapsed 秒）" 1
      return 0
    fi
    elapsed=$(( $(date +%s) - started_at ))
    terminal_status "[$STEP/$TOTAL_STEPS] 数据库外部连接仍在等待（${elapsed}秒）"
    printf 'PostgreSQL external status: elapsed=%s host=%s port=%s\n' "$elapsed" "$PG_HOST" "$PG_PORT" >>"$INSTALL_LOG"
    sleep 2
  done
}
wait_postgres_external || die 'PostgreSQL 外部连接验证失败'
progress '初始化数据库结构'
printf '正在初始化数据库，请稍候...\n'
run_migration() {
  local migration_log migration_rc
  migration_log=$(mktemp "$INSTALL_TMP_DIR/migration.XXXXXX.log") || die '无法创建数据库迁移日志'
  chmod 600 "$migration_log"
  if (( EXISTING_DB )); then
    export XYMEDIA_EXTERNAL_MIGRATION_CONFIRM=YES
    if "${COMPOSE[@]}" --profile migration --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" run --rm -T --no-deps app-migrate migrate --config /app/config.yaml </dev/null >"$migration_log" 2>&1; then
      migration_rc=0
    else
      migration_rc=$?
    fi
  else
    if "${COMPOSE[@]}" --profile migration --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" run --rm -T --no-deps app-migrate migrate --new --config /app/config.yaml </dev/null >"$migration_log" 2>&1; then
      migration_rc=0
    else
      migration_rc=$?
    fi
  fi
  cat "$migration_log"
  cat "$migration_log" >>"$INSTALL_LOG"
  printf '数据库迁移退出码：%s\n' "$migration_rc"
  printf '数据库迁移退出码：%s\n' "$migration_rc" >>"$INSTALL_LOG"
  return "$migration_rc"
}
set +e
run_migration
migration_rc=$?
if [[ $migration_rc -ne 0 ]]; then
  exit_code=1
  persist_installer_log || true
  if (( EXISTING_DB )); then
    printf '已有数据库迁移失败（退出码：%s）\n' "$migration_rc" >&2
  else
    printf '数据库初始化失败（退出码：%s）\n' "$migration_rc" >&2
  fi
  exit "$exit_code"
fi
printf '[安装流程] 已完成数据库迁移，继续启动应用\n'
printf '[安装流程] 已完成数据库迁移，继续启动应用\n' >>"$INSTALL_LOG"
printf '数据库初始化完成\n'
printf '数据库初始化完成\n' >>"$INSTALL_LOG"
bootstrap_local_controller() {
  [[ $MENU_PROFILES == *xiaoya-control* ]] || return 0
  (( REMOTE_MODE == 0 )) || return 0
  printf '正在将本机小雅 Controller 同步到管理平台数据库...\n'
  printf '正在将本机小雅 Controller 同步到管理平台数据库...\n' >>"$INSTALL_LOG"
  if ! run_visible_logged "${COMPOSE[@]}" --profile migration --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" run --rm -T --no-deps app-migrate bootstrap-controller --config /app/config.yaml </dev/null; then
    printf '本机小雅 Controller 数据库同步失败，安装未完成。\n' >&2
    return 1
  fi
}
if bootstrap_local_controller; then
  :
else
  persist_installer_log || true
  exit 1
fi
progress '启动 XyMediaVault 服务' || true
start_app_after_migration "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" up -d "${FORCE_UP_FLAGS[@]}" app
app_start_rc=$?
if (( app_start_rc != 0 )); then
  exit_code=1
  persist_installer_log || true
  printf 'XyMediaVault 启动失败（退出码：%s）\n' "$app_start_rc" >&2
  exit "$exit_code"
fi
set -e
wait_for_app_health() {
  local started_at elapsed app_wait_interrupted=0 previous_int previous_term
  started_at=$(date +%s)
  previous_int=$(trap -p INT || true)
  previous_term=$(trap -p TERM || true)
  trap 'app_wait_interrupted=1' INT TERM
  while :; do
    if (( app_wait_interrupted )); then
      printf '\n已收到中断信号，正在停止应用健康检查。\n'
      printf '%s\n' 'XyMediaVault health wait interrupted by signal' >>"$INSTALL_LOG"
      printf '\n--- XyMediaVault 容器日志 ---\n' >>"$INSTALL_LOG"
      "${COMPOSE[@]}" --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" "${COMPOSE_FUSE[@]}" logs app >>"$INSTALL_LOG" 2>&1 || true
      [[ -n $previous_int ]] && eval "$previous_int" || trap - INT
      [[ -n $previous_term ]] && eval "$previous_term" || trap - TERM
      return 130
    fi
    elapsed=$(( $(date +%s) - started_at ))
    if curl --fail --silent "http://127.0.0.1:$API_PORT/api/health" >/dev/null; then
      [[ -n $previous_int ]] && eval "$previous_int" || trap - INT
      [[ -n $previous_term ]] && eval "$previous_term" || trap - TERM
      return 0
    fi
    terminal_status "[$STEP/$TOTAL_STEPS] 等待 XyMediaVault 健康检查（已用 $elapsed 秒）"
    printf 'XyMediaVault health status: elapsed=%s\n' "$elapsed" >>"$INSTALL_LOG"
    sleep 2
  done
}
if wait_for_app_health; then
  :
else
  printf 'XyMediaVault 健康检查被中断，安装未完成。\n' >&2
  persist_installer_log || true
  exit 1
fi
if (( RELEASE_ROLLBACK_ACTIVE )); then rm -rf -- "$release_backup"; RELEASE_ROLLBACK_ACTIVE=0; fi
cp "$INSTALL_LOG" "$INSTALL_DIR/install.log" 2>/dev/null || true
  terminal_status "[$TOTAL_STEPS/$TOTAL_STEPS] 安装完成：XyMediaVault 已就绪" 1
  management_address=$(printf '%s\n' "$HOST_ADDRESSES_INITIAL" | head -n 1)
  [[ -n $management_address ]] || management_address=127.0.0.1
  if [[ $management_address == *:* ]]; then management_address="[$management_address]"; fi
  printf '管理地址：http://%s:%s\n' "$management_address" "$API_PORT"
  if [[ $MENU_PROFILES == *xiaoya-control* ]]; then
    if print_controller_info; then
      :
    else
      printf '控制器连接信息暂时不可读取，请安装完成后通过菜单 6 查看。\n'
    fi
  fi
  if (( LOCAL_DB )); then
    print_database_info
  else
    printf 'PostgreSQL 地址：%s:%s\nPostgreSQL 数据库：%s\nPostgreSQL 用户：%s\n' "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER"
  fi
  printf '安装日志：%s/install.log\n' "$INSTALL_DIR"
exit 0
