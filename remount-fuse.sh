#!/bin/sh
set -eu

die() { printf 'xymediavault FUSE: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s xymediavault FUSE: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG_FILE"; }

install_dir=${XYMEDIA_INSTALL_DIR:-}
action=restart
path_arg=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --configure) [ "$#" -ge 2 ] || die '--configure requires a path'; action=configure; path_arg=$2; shift 2;;
    --restart) action=restart; shift;;
    --disable) action=disable; shift;;
    --install-dir) [ "$#" -ge 2 ] || die '--install-dir requires a path'; install_dir=$2; shift 2;;
    *) die "unknown option: $1";;
  esac
done
[ -n "$install_dir" ] || install_dir=$(CDPATH='' pwd -P)
case "$install_dir" in ''|/|*[![:print:]]*) die 'installation directory is invalid';; esac
[ -d "$install_dir" ] || die "installation directory does not exist: $install_dir"
install_dir=$(CDPATH='' cd -- "$install_dir" && pwd -P) || die 'cannot canonicalize installation directory'
[ "$(id -u)" -eq 0 ] || die 'FUSE maintenance requires root (euid 0)'
[ -f "$install_dir/.env" ] || die "missing $install_dir/.env"
[ -f "$install_dir/compose.yaml" ] || die "missing $install_dir/compose.yaml"
[ -f "$install_dir/config.yaml" ] || die "missing $install_dir/config.yaml"
[ -f "$install_dir/compose.fuse.yaml" ] || die "missing $install_dir/compose.fuse.yaml"
[ ! -L "$install_dir/.env" ] || die '.env must not be a symlink'
[ ! -L "$install_dir/config.yaml" ] || die 'config.yaml must not be a symlink'
for protected in "$install_dir/.env" "$install_dir/config.yaml"; do
  [ "$(stat -c '%u' "$protected")" -eq 0 ] || die "protected file must be owned by root: $protected"
  protected_mode=$(stat -c '%a' "$protected")
  [ $(( 0$protected_mode & 022 )) -eq 0 ] || die "protected file must not be group/world writable: $protected"
done
state_dir=$install_dir/state
if [ -e "$state_dir" ] && [ -L "$state_dir" ]; then die 'state directory must not be a symlink'; fi
if [ ! -e "$state_dir" ]; then umask 077; mkdir "$state_dir" || die 'cannot create state directory'; fi
[ -d "$state_dir" ] || die 'state path must be a directory'
[ "$(stat -c '%u' "$state_dir")" -eq 0 ] || die 'state directory must be owned by root'
state_mode=$(stat -c '%a' "$state_dir")
[ $(( 0$state_mode & 022 )) -eq 0 ] || die 'state directory must not be group/world writable'
command -v docker >/dev/null 2>&1 || die 'docker is required'
docker compose version >/dev/null 2>&1 || die 'Docker Compose V2 is required'
command -v findmnt >/dev/null 2>&1 || die 'findmnt is required'
command -v mountpoint >/dev/null 2>&1 || die 'mountpoint is required'
case "${DOCKER_HOST:-}" in ''|unix://*|unix:/*) ;; *) die 'remote Docker contexts are not allowed';; esac

read_env() { awk -F= -v wanted="$1" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$install_dir/.env"; }
old_enabled=$(read_env XYMEDIA_FUSE_ENABLED || true)
old_path=$(read_env XYMEDIA_FUSE_HOST_PATH || true)
case "$old_enabled" in true|false) ;; *) old_enabled=false;; esac
mount_id= mount_source= mount_fstype=
inspect_mount() {
  mount_id=; mount_source=; mount_fstype=
  if mountpoint -q "$1" 2>/dev/null; then
    mount_id=$(findmnt -rn -M "$1" -o ID 2>/dev/null || true)
    mount_source=$(findmnt -rn -M "$1" -o SOURCE 2>/dev/null || true)
    mount_fstype=$(findmnt -rn -M "$1" -o FSTYPE 2>/dev/null || true)
    [ -n "$mount_id" ] && [ -n "$mount_source" ] && [ -n "$mount_fstype" ] || return 1
    [ "$mount_id" = "$(findmnt -rn -M "$1" -o ID 2>/dev/null)" ] || return 1
  fi
}
owned_mount() {
  inspect_mount "$1" || die "mount identity is unstable: $1"
  [ -z "$mount_id" ] || { [ "$mount_source" = xymediavault ] && { [ "$mount_fstype" = fuse.xymediavault ] || [ "$mount_fstype" = fuse ]; }; } || die "refusing foreign or unknown mount at $1"
}
valid_path() {
  PATH_TO_CHECK=$1 python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ['PATH_TO_CHECK'])
if not p.is_absolute() or str(p) == '/' or any(ord(c) < 32 or not c.isprintable() for c in str(p)):
    raise SystemExit(1)
if not p.is_dir(): raise SystemExit(1)
cur = pathlib.Path(p.root)
for part in p.parts[1:]:
    cur /= part
    if cur.is_symlink(): raise SystemExit(1)
print(p.resolve(strict=True))
PY
}
if [ "$action" = configure ]; then
  new_path=$(valid_path "$path_arg") || die '目标路径必须是存在的、非根、绝对且不含符号链接的目录'
  inspect_mount "$new_path" || die '无法稳定识别目标路径挂载状态'
  if [ -n "$mount_id" ]; then owned_mount "$new_path"; else [ -z "$(find "$new_path" -mindepth 1 -maxdepth 1 -print -quit)" ] || die '目标目录必须为空'; fi
else
  if [ -n "$old_path" ]; then new_path=$(valid_path "$old_path") || die '已配置的 FUSE 主机路径无效'; else new_path=; fi
fi
if [ -n "$old_path" ]; then
  old_path=$(valid_path "$old_path" 2>/dev/null) || die '已配置的 FUSE 主机路径无效'
elif [ "$old_enabled" = true ]; then
  die 'FUSE 已启用但未配置主机路径'
fi
if [ "$action" != disable ] && [ -z "$new_path" ]; then die '未配置 FUSE 主机路径'; fi

print_preflight() {
  printf 'xymediavault FUSE: preflight diagnostics\n' >&2
  printf '  install_dir: %s\n' "$install_dir" >&2
  printf '  configured host path: %s\n' "${new_path:-${old_path:-<none>}}" >&2
  if [ -e /dev/fuse ]; then
    printf '  host /dev/fuse: %s (%s)\n' "$( [ -c /dev/fuse ] && printf present || printf 'wrong type' )" "$(stat -c '%F' /dev/fuse 2>/dev/null || printf 'unreadable')" >&2
  else
    printf '  host /dev/fuse: missing\n' >&2
  fi
  printf '  compose.fuse.yaml: %s\n' "$( [ -f "$install_dir/compose.fuse.yaml" ] && printf present || printf missing )" >&2
}
print_preflight
[ -e /dev/fuse ] && [ -c /dev/fuse ] || die '/dev/fuse character device is required'

compose_check_env=${new_path:-$old_path}
if [ "$action" = disable ] || [ -z "$compose_check_env" ]; then
  docker compose --project-directory "$install_dir" --env-file "$install_dir/.env" -f "$install_dir/compose.yaml" config -q || die 'compose configuration is invalid'
else
  XYMEDIA_FUSE_HOST_PATH=$compose_check_env docker compose --project-directory "$install_dir" --env-file "$install_dir/.env" -f "$install_dir/compose.yaml" -f "$install_dir/compose.fuse.yaml" config -q || die 'compose configuration is invalid'
fi

lock_dir=$install_dir/.install.lock
mkdir "$lock_dir" 2>/dev/null || die '已有安装或 FUSE 维护正在进行'
umask 077
tmp_parent=${TMPDIR:-/tmp}
 [ -d "$tmp_parent" ] && [ ! -L "$tmp_parent" ] || die 'TMPDIR must be an existing non-symlink directory'
if [ "$(id -u)" -eq 0 ]; then
  [ "$(stat -c '%u' "$tmp_parent")" -eq 0 ] || die 'TMPDIR must be owned by root when running as root'
  [ $(( $(stat -c '%a' "$tmp_parent") & 022 )) -eq 0 ] || [ $(( $(stat -c '%a' "$tmp_parent") & 1000 )) -ne 0 ] || die 'TMPDIR must not be group/world writable unless sticky'
fi
private_tmp=$(mktemp -d "$tmp_parent/xymedia-fuse.XXXXXX") || { rmdir "$lock_dir" 2>/dev/null || true; die 'cannot create private temporary directory'; }
chmod 700 "$private_tmp"
log_file=$(mktemp "$private_tmp/remount.log.XXXXXX") || { rm -rf "$private_tmp"; rmdir "$lock_dir" 2>/dev/null || true; die 'cannot create private log'; }
chmod 600 "$log_file"
env_snapshot=$(mktemp "$private_tmp/env.snapshot.XXXXXX") || { rm -rf "$private_tmp"; rmdir "$lock_dir" 2>/dev/null || true; die 'cannot create private environment snapshot'; }
config_snapshot=$(mktemp "$private_tmp/config.snapshot.XXXXXX") || { rm -rf "$private_tmp"; rmdir "$lock_dir" 2>/dev/null || true; die 'cannot create private config snapshot'; }
cp "$install_dir/.env" "$env_snapshot"; cp "$install_dir/config.yaml" "$config_snapshot"
LOG_FILE=$log_file
env_tmp= config_tmp=
log_pid=
cleanup() {
  status=$?
  trap - 0 1 2 3 15
  if [ -n "$log_pid" ]; then
    kill "$log_pid" 2>/dev/null || true
    wait "$log_pid" 2>/dev/null || true
  fi
  rm -f "$env_tmp" "$config_tmp"
  rm -rf "$private_tmp"
  rmdir "$lock_dir" 2>/dev/null || true
  exit "$status"
}
trap cleanup 0 1 2 3 15

compose() { docker compose --project-directory "$install_dir" --env-file "$install_dir/.env" -f "$install_dir/compose.yaml" "$@"; }
compose_old() { if [ "$old_enabled" = true ]; then compose -f "$install_dir/compose.fuse.yaml" "$@"; else compose "$@"; fi; }
restore_old() {
  cp "$env_snapshot" "$install_dir/.env"; cp "$config_snapshot" "$install_dir/config.yaml"
  compose_old up -d app >/dev/null 2>&1 || true
}
fail_restore() { log "operation failed: $*"; restore_old; die "$*; configuration and app recovery attempted (log: $log_file)"; }
if [ "$action" = disable ]; then enabled=false; else enabled=true; fi
inspect_mount "${old_path:-$new_path}" || fail_restore 'old mount identity is unstable'
old_mount_id=$mount_id; old_mount_source=$mount_source; old_mount_fstype=$mount_fstype
if [ -n "$old_mount_id" ]; then owned_mount "${old_path:-$new_path}"; fi
compose_old stop app >/dev/null 2>&1 || fail_restore 'failed to stop app'
if [ -n "$old_mount_id" ]; then
  inspect_mount "${old_path:-$new_path}" || fail_restore 'mount changed before unmount'
  [ "$mount_id" = "$old_mount_id" ] && [ "$mount_source" = "$old_mount_source" ] && [ "$mount_fstype" = "$old_mount_fstype" ] || fail_restore 'mount identity changed before unmount'
  if command -v fusermount3 >/dev/null 2>&1; then fusermount3 -u "${old_path:-$new_path}" || fail_restore 'unable to unmount owned FUSE mount'
  elif command -v fusermount >/dev/null 2>&1; then fusermount -u "${old_path:-$new_path}" || fail_restore 'unable to unmount owned FUSE mount'
  else umount "${old_path:-$new_path}" || fail_restore 'fusermount is required to unmount FUSE safely'; fi
  inspect_mount "${old_path:-$new_path}" || fail_restore 'mount identity is unstable after unmount'
  [ -z "$mount_id" ] || fail_restore 'FUSE path is still mounted'
fi
env_tmp=$(mktemp "$install_dir/.env.write.XXXXXX") || fail_restore 'cannot create environment write file'
config_tmp=$(mktemp "$install_dir/.config.write.XXXXXX") || fail_restore 'cannot create config write file'
chmod 600 "$env_tmp" "$config_tmp"
if ! FUSE_ENABLED=$enabled FUSE_PATH=${new_path:-${old_path:-}} python3 - "$install_dir/.env" "$install_dir/config.yaml" "$env_tmp" "$config_tmp" <<'PY'
import os, pathlib
import stat, sys
env = pathlib.Path(sys.argv[1]); config = pathlib.Path(sys.argv[2])
env_tmp = pathlib.Path(sys.argv[3]); config_tmp = pathlib.Path(sys.argv[4])
values = {'XYMEDIA_FUSE_ENABLED': os.environ['FUSE_ENABLED'], 'XYMEDIA_FUSE_HOST_PATH': os.environ['FUSE_PATH']}
lines = env.read_text().splitlines(); seen=set(); out=[]
for line in lines:
    key=line.split('=',1)[0] if '=' in line else ''
    if key in values: out.append(key+'='+values[key]); seen.add(key)
    else: out.append(line)
out += [k+'='+v for k,v in values.items() if k not in seen]
if env.is_symlink() or config.is_symlink(): raise SystemExit('protected config file is a symlink')
if not stat.S_ISREG(env.stat().st_mode) or not stat.S_ISREG(config.stat().st_mode): raise SystemExit('protected config file is not regular')
env_tmp.write_text('\n'.join(out)+'\n'); os.chmod(env_tmp, 0o600); os.replace(env_tmp, env)
text=config.read_text(); import re
text=re.sub(r'(?m)^(  auto_mount:)\s*.*$', r'\1 '+('true' if values['XYMEDIA_FUSE_ENABLED']=='true' else 'false'), text)
text=re.sub(r'(?m)^(  mount_path:)\s*.*$', r'\1 /mnt/xymediavault', text)
config_tmp.write_text(text); os.chmod(config_tmp, 0o600); os.replace(config_tmp, config)
PY
then
  fail_restore 'failed to update environment or config'
fi
startup_since=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
if [ "$enabled" = true ]; then
  if ! compose -f "$install_dir/compose.fuse.yaml" up -d app >/dev/null; then
    fail_restore 'failed to start app: docker compose up failed'
  fi
else
  if ! compose up -d app >/dev/null; then
    fail_restore 'failed to start app: docker compose up failed'
  fi
fi
docker logs -f --since "$startup_since" xymedia-app >&2 &
log_pid=$!
health_result=unavailable
container_status=unknown
container_fuse=unknown
status_mount_source=
status_mount_fstype=
print_status() {
  inspect_mount "${new_path:-${old_path:-/nonexistent}}" || true
  status_mount_source=${mount_source:-absent}
  status_mount_fstype=${mount_fstype:-absent}
  container_status=unknown
  container_fuse=unknown
  inspected_status=$(docker inspect --format '{{.State.Status}}' xymedia-app 2>/dev/null || true)
  case "$inspected_status" in
    created|restarting|running|paused|exited|dead) container_status=$inspected_status;;
    *) container_status=unavailable;;
  esac
  if [ "$container_status" = running ]; then
    if docker exec xymedia-app test -c /dev/fuse >/dev/null 2>&1; then container_fuse=present; else container_fuse=missing; fi
  fi
  printf 'xymediavault FUSE: status attempt %s/60: health=%s, host mount source=%s, fstype=%s, container status=%s, container /dev/fuse=%s\n' \
    "$attempt" "$health_result" "$status_mount_source" "$status_mount_fstype" "$container_status" "$container_fuse" >&2
}
print_timeout_diagnostics() {
  printf 'xymediavault FUSE: timeout diagnostics\n' >&2
  if [ ! -e /dev/fuse ] || [ ! -c /dev/fuse ]; then
    printf '  likely cause: host /dev/fuse is missing or is not a character device\n' >&2
  elif [ "$enabled" = true ] && [ "$container_fuse" = missing ]; then
    printf '  likely cause: compose/container is missing /dev/fuse\n' >&2
  elif [ "$enabled" = true ] && [ "$container_fuse" = unknown ]; then
    printf '  likely cause: app container is unavailable; container /dev/fuse could not be confirmed\n' >&2
  elif [ "$health_result" = unavailable ]; then
    printf '  likely cause: app health unavailable\n' >&2
  elif [ -z "$status_mount_source" ] || [ "$status_mount_source" = absent ]; then
    printf '  likely cause: app is healthy but host FUSE mount is absent\n' >&2
  else
    printf '  likely cause: host mount exists with unexpected source/fstype (source=%s, fstype=%s)\n' "$status_mount_source" "$status_mount_fstype" >&2
  fi
  printf '  recent xymedia-app logs (bounded):\n' >&2
  docker logs --tail 80 xymedia-app 2>&1 | while IFS= read -r line; do printf '    %s\n' "$line"; done >&2 || true
  printf '  application mount config:\n' >&2
  if mount_config=$(curl -fsS --max-time 5 "http://127.0.0.1:${XYMEDIA_API_PORT:-18080}/api/mount/config" 2>&1); then
    printf '%s\n' "$mount_config" | while IFS= read -r line; do printf '    %s\n' "$line"; done >&2
  else
    printf '    unavailable\n' >&2
  fi
  printf '  application mount status:\n' >&2
  if mount_status=$(curl -fsS --max-time 5 "http://127.0.0.1:${XYMEDIA_API_PORT:-18080}/api/mount/status" 2>&1); then
    printf '%s\n' "$mount_status" | while IFS= read -r line; do printf '    %s\n' "$line"; done >&2
  else
    printf '    unavailable\n' >&2
  fi
  printf '  container diagnostics (status and device mapping only):\n' >&2
  docker inspect --format '{{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} devices={{range .HostConfig.Devices}}{{.PathOnHost}}:{{.PathInContainer}} {{end}}' xymedia-app 2>&1 >&2 || true
  printf '  compose configuration validation: ' >&2
  if [ "$enabled" = true ]; then
    compose -f "$install_dir/compose.fuse.yaml" config -q >/dev/null 2>&1 && printf 'passed\n' >&2 || printf 'failed\n' >&2
  else
    compose config -q >/dev/null 2>&1 && printf 'passed\n' >&2 || printf 'failed\n' >&2
  fi
}
attempt=0
while [ "$attempt" -lt 60 ]; do
  attempt=$((attempt+1))
  if curl -fsS --max-time 5 "http://127.0.0.1:${XYMEDIA_API_PORT:-18080}/api/health" >/dev/null 2>&1; then
    health_result=healthy
    if [ "$enabled" = false ]; then log 'FUSE disabled and base app is healthy'; exit 0; fi
    inspect_mount "$new_path" || fail_restore 'mount identity is unstable after start'
    [ "$mount_source" = xymediavault ] && { [ "$mount_fstype" = fuse.xymediavault ] || [ "$mount_fstype" = fuse ]; } && log "FUSE mounted: $new_path" && exit 0
  else
    health_result=unavailable
  fi
  if [ "$attempt" -eq 1 ] || [ $((attempt % 5)) -eq 0 ]; then print_status; fi
  sleep 2
done
print_status
print_timeout_diagnostics
fail_restore 'app health or FUSE mount timed out'
