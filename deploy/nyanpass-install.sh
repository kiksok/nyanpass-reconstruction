#!/usr/bin/env bash
# Public binary installer. No vendor download service or system Node.js needed.
set -Eeuo pipefail
umask 077

REPOSITORY=${NYANPASS_REPOSITORY:-kiksok/nyanpass-reconstruction}
VERSION=${NYANPASS_VERSION:-latest}
SERVICE=${S:-nyanpass}
PREFIX=${NYANPASS_PREFIX:-}
SYSTEMD_DIR=${NYANPASS_SYSTEMD_DIR:-/etc/systemd/system}
SYSCTL_DIR=${NYANPASS_SYSCTL_DIR:-/etc/sysctl.d}
SYSCTL_BIN=${NYANPASS_SYSCTL_BIN:-sysctl}
PRODUCT=${1:-}
[[ $# -eq 0 ]] || shift
ACTION=install
NO_SYSTEMD=0
LOCAL_BINARY=${NYANPASS_RELEASE_FILE:-}
LOCAL_SUMS=${NYANPASS_CHECKSUM_FILE:-}
CONFIG_FILE=
DOWNLOAD_SOURCE=${NYANPASS_DOWNLOAD_SOURCE:-auto}
OFFLINE=${NYANPASS_OFFLINE:-0}
WORK=
OLD_CURRENT=
SWITCHED=0
OPTIMIZATION_APPLIED=0
MIGRATE_ORIGINAL=0
MIGRATION_WRITES=0
DEFER_RESTART=0
NODE_ARGS=()

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
usage() {
  cat <<'EOF'
使用方式（Linux x86_64 / arm64，glibc 系统）：
  bash nyanpass-install.sh rel_backend [选项]
  bash nyanpass-install.sh rel_nodeclient '-u https://panel.example -t TOKEN' [选项]
  bash nyanpass-install.sh rel_nodeclient --native-config /path/native.json [选项]
  bash nyanpass-install.sh rel_backend update --service nyanpass
  bash nyanpass-install.sh rel_backend uninstall --service nyanpass
选项：
  --service NAME       服务名，默认 nyanpass，也支持环境变量 S
  --prefix PATH        安装目录，默认 /opt/服务名
  --version TAG        GitHub Release 标签，默认 latest
  --download-source X  auto 自动实测切换；github、api 或自定义下载目录 URL
  --binary-file FILE   使用本地独立二进制（--release-file 为兼容别名）
  --checksum-file FILE 本地 SHA256SUMS，必须与 --binary-file 同时传入
  --native-config FILE 原生数据面 JSON 配置（首次复制，更新保留）
  --no-systemd         只生成文件，以 start.sh 前台运行，无需 root
  --migrate-original   校验已知原版节点与服务布局后保留原启动参数迁移
  --defer-restart      安装后由调用方安排重启（供节点更新回执使用）
OPTIMIZE=1 显式安装并应用本服务的 sysctl 优化，可在卸载时恢复。
INSTALL_TOOLS=1 显式安装常用运维工具，支持 apt-get / dnf / yum。
NYANPASS_DOWNLOAD_SOURCES 可按空格、逗号或换行指定候选源（github api URL）。
自定义 URL 可含 {asset}、{version}、{repository}；不含占位符时追加文件名。
公开仓库无需令牌；私有分支可使用 GH_TOKEN / GITHUB_TOKEN，仅用于下载。
EOF
}

[[ $PRODUCT != --help && $PRODUCT != -h && -n $PRODUCT ]] || { usage; exit 0; }
[[ $PRODUCT == rel_backend || $PRODUCT == rel_nodeclient ]] || die '产品须为 rel_backend 或 rel_nodeclient'
while (($#)); do
  case $1 in
    update|uninstall) ACTION=$1; shift ;;
    --service|--prefix|--version|--release-file|--binary-file|--checksum-file|--native-config|--download-source)
      (($# >= 2)) || die "$1 缺少值"
      case $1 in
        --service) SERVICE=$2 ;; --prefix) PREFIX=$2 ;; --version) VERSION=$2 ;;
        --release-file|--binary-file) LOCAL_BINARY=$2 ;;
        --checksum-file) LOCAL_SUMS=$2 ;; --native-config) CONFIG_FILE=$2 ;;
        --download-source) DOWNLOAD_SOURCE=$2 ;;
      esac; shift 2 ;;
    --no-systemd) NO_SYSTEMD=1; shift ;;
    --migrate-original) MIGRATE_ORIGINAL=1; shift ;;
    --defer-restart) DEFER_RESTART=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; NODE_ARGS+=("$@"); break ;;
    *) NODE_ARGS+=("$1"); shift ;;
  esac
done
[[ $SERVICE =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$ ]] || die '服务名仅接受字母、数字、_、-，最多 63 字符'
PREFIX=${PREFIX:-/opt/$SERVICE}
valid_directory() {
  [[ $1 =~ ^/[a-zA-Z0-9_./-]+$ && $1 != / && $1 != *'/../'* && $1 != */.. && $1 != *'/./'* ]]
}
valid_directory "$PREFIX" || die '安装目录须是无空白绝对路径，不能为 / 或包含相对路径分段'
valid_directory "$SYSTEMD_DIR" || die 'systemd 目录无效'
valid_directory "$SYSCTL_DIR" || die 'sysctl 目录无效'
[[ $(uname -s) == Linux ]] || die '仅支持 Linux'
case $(uname -m) in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) die '不支持该 CPU 架构' ;; esac
if (( !NO_SYSTEMD )); then
  (( EUID == 0 )) || die 'systemd 安装请使用 root 或 sudo；无 root 可传 --no-systemd'
  command -v systemctl >/dev/null || die '未找到 systemd；可传 --no-systemd'
fi
UNIT=$SYSTEMD_DIR/$SERVICE.service
OPTIMIZATION_FILE=$SYSCTL_DIR/90-nyanpass-$SERVICE.conf
[[ ! -L $UNIT ]] || die 'systemd 单元不能是符号链接'
[[ ! -L $PREFIX ]] || die '安装目录不能是符号链接'

# Only restore keys whose current values still equal our applied values. This
# preserves subsequent administrator changes and never reloads global configs.
restore_optimization() {
  local key original applied current other shared
  [[ -f $PREFIX/config/optimization.before ]] || return 0
  [[ ! -L $OPTIMIZATION_FILE ]] || die 'sysctl 文件不能是符号链接'
  if [[ -f $OPTIMIZATION_FILE ]]; then
    [[ $(head -n 1 "$OPTIMIZATION_FILE") == "# Nyanpass managed optimization $SERVICE" ]] || die 'sysctl 文件已被其他程序修改，保留配置，请手动处理'
  fi
  while IFS=$'\t' read -r key original applied; do
    [[ $key =~ ^[a-zA-Z0-9_.]+$ && -n $original && -n $applied ]] || continue
    shared=0
    for other in "$SYSCTL_DIR"/90-nyanpass-*.conf; do
      [[ -f $other && $other != "$OPTIMIZATION_FILE" ]] || continue
      [[ $(head -n 1 "$other") == '# Nyanpass managed optimization '* ]] || continue
      if awk -F '[[:space:]]*=[[:space:]]*' -v key="$key" '$1==key {found=1} END {exit !found}' "$other"; then shared=1; break; fi
    done
    (( !shared )) || continue
    if [[ -f $SYSCTL_DIR/.nyanpass-original-values ]]; then
      saved=$(awk -F '\t' -v key="$key" '$1==key {print $2}' "$SYSCTL_DIR/.nyanpass-original-values")
      [[ -z $saved ]] || original=$saved
    fi
    current=$("$SYSCTL_BIN" -n "$key" 2>/dev/null | awk '{$1=$1;print}') || continue
    if [[ $current == "$applied" ]]; then "$SYSCTL_BIN" -q -w "$key=$original" || return 1; fi
    if [[ -f $SYSCTL_DIR/.nyanpass-original-values ]]; then
      awk -F '\t' -v key="$key" '$1!=key' "$SYSCTL_DIR/.nyanpass-original-values" >"$PREFIX/config/optimization.remaining"
      cat "$PREFIX/config/optimization.remaining" >"$SYSCTL_DIR/.nyanpass-original-values"
      rm -f -- "$PREFIX/config/optimization.remaining"
    fi
  done <"$PREFIX/config/optimization.before"
  if [[ -f $PREFIX/config/optimization.previous.conf ]]; then
    cp -- "$PREFIX/config/optimization.previous.conf" "$OPTIMIZATION_FILE"
    rm -f -- "$PREFIX/config/optimization.previous.conf"
  else rm -f -- "$OPTIMIZATION_FILE"; fi
  rm -f -- "$PREFIX/config/optimization.before"
  [[ ! -f $SYSCTL_DIR/.nyanpass-original-values || -s $SYSCTL_DIR/.nyanpass-original-values ]] || rm -f -- "$SYSCTL_DIR/.nyanpass-original-values"
  info '已移除本服务的 sysctl 优化配置，并恢复仍由本服务管理的参数。'
}

if [[ $ACTION == uninstall ]]; then
  [[ -f $PREFIX/.nyanpass-install ]] || die '该目录不是本安装器创建的服务目录'
  [[ $(cat "$PREFIX/.nyanpass-install") == "$SERVICE" ]] || die '安装目录与服务名不匹配'
  if (( !NO_SYSTEMD )); then
    [[ ! -f $UNIT ]] || grep -Fq "WorkingDirectory=$PREFIX" "$UNIT" || die 'systemd 单元不属于此目录'
    systemctl disable --now "$SERVICE.service" || die '停止服务失败，保留数据'
    rm -f -- "$UNIT"
    systemctl daemon-reload
  fi
  restore_optimization || die '恢复优化参数失败，已保留恢复记录'
  info "服务已卸载。配置、设备身份、证书和数据库保留在 $PREFIX。"
  exit 0
fi

[[ $REPOSITORY =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || die '仓库名称无效'
[[ $VERSION =~ ^[a-zA-Z0-9_.-]+$ ]] || die '版本标签无效'
if [[ -e $PREFIX && ! -f $PREFIX/.nyanpass-install ]]; then
  if (( MIGRATE_ORIGINAL )); then
    [[ $PRODUCT == rel_nodeclient && -d $PREFIX && -O $PREFIX && ! -e $PREFIX/current && ! -L $PREFIX/current && ! -e $PREFIX/service.json && ! -L $PREFIX/service.json && ! -e $PREFIX/start.original.sh && ! -L $PREFIX/start.original.sh && ! -L $PREFIX/.nyanpass-install && ${#NODE_ARGS[@]} -gt 0 ]] || die '原版迁移布局或启动参数无效'
    original_mode=$(stat -c %a "$PREFIX")
    (( (8#$original_mode & 0022) == 0 )) || die '原版安装目录不能允许组或其他用户写入'
    for original_file in rel_nodeclient start.sh env.sh; do
      [[ -f $PREFIX/$original_file && ! -L $PREFIX/$original_file && -O $PREFIX/$original_file ]] || die '原版迁移要求同所有者的常规程序和启动文件'
      original_mode=$(stat -c %a "$PREFIX/$original_file")
      (( (8#$original_mode & 0022) == 0 )) || die '原版安装文件不能允许组或其他用户写入'
    done
    [[ $(sha256sum "$PREFIX/rel_nodeclient" | awk '{print $1}') == e432273ac9d7f29287989f6269ef5c9b8fc1080a365d2879a00973b60441f569 ]] || die '只支持已核验的nc20260412原版节点迁移'
    if (( !NO_SYSTEMD )); then
      [[ -f $UNIT ]] && grep -Fxq "WorkingDirectory=$PREFIX" "$UNIT" && grep -Fxq "ExecStart=/bin/bash $PREFIX/start.sh" "$UNIT" || die '原版systemd服务与安装目录不匹配'
    fi
  else
    [[ -d $PREFIX && -z $(ls -A "$PREFIX") ]] || die '目录非空且没有安装标记，请选择其他 --prefix'
  fi
elif (( MIGRATE_ORIGINAL )); then
  die '原版迁移仅用于已有未标记的原版节点目录'
fi
if [[ -f $PREFIX/.nyanpass-install ]]; then
  [[ $(cat "$PREFIX/.nyanpass-install") == "$SERVICE" ]] || die '服务名与已有安装不匹配'
  ACTION=update
fi
if (( !NO_SYSTEMD )) && [[ -f $UNIT ]]; then
  grep -Fq "WorkingDirectory=$PREFIX" "$UNIT" || die '已有同名 systemd 服务，请改 --service'
fi
for program in sha256sum mktemp awk sed; do command -v "$program" >/dev/null || die "缺少 $program"; done
ASSET_NAME=${PRODUCT}_linux_$ARCH
if [[ ${NO_DOWNLOAD:-0} == 1 && -z $LOCAL_BINARY ]]; then
  LOCAL_BINARY=$PWD/$ASSET_NAME
  LOCAL_SUMS=${LOCAL_SUMS:-$PWD/SHA256SUMS}
  OFFLINE=1
fi
if [[ $OFFLINE == 1 ]]; then
  [[ -n $LOCAL_BINARY && -n $LOCAL_SUMS ]] || die '离线安装须提供本地二进制和 SHA256SUMS'
  [[ ${INSTALL_TOOLS:-0} != 1 ]] || die '离线安装不会访问软件源；请预先安装常用工具，取消 INSTALL_TOOLS=1'
fi
if [[ ${INSTALL_TOOLS:-0} == 1 ]]; then
  (( EUID == 0 )) || die 'INSTALL_TOOLS=1 需要 root 或 sudo'
  info '正在安装常用运维工具（显式 INSTALL_TOOLS=1）'
  if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates wget curl mtr-tiny iftop unzip htop net-tools dnsutils nload psmisc nano screen python3 iputils-ping iputils-tracepath procps
  elif command -v dnf >/dev/null; then
    dnf install -y ca-certificates wget curl mtr iftop unzip htop net-tools bind-utils nload psmisc nano screen python3 iputils procps-ng traceroute
  elif command -v yum >/dev/null; then
    yum install -y ca-certificates wget curl mtr iftop unzip htop net-tools bind-utils nload psmisc nano screen python3 iputils procps-ng traceroute
  else die 'INSTALL_TOOLS=1 暂不支持该系统的软件包管理器（需要 apt-get、dnf 或 yum）'; fi
fi
if [[ -z $LOCAL_BINARY ]]; then command -v curl >/dev/null || die '缺少 curl；可显式使用 INSTALL_TOOLS=1 或先安装 curl'; fi
if [[ ${OPTIMIZE:-0} == 1 ]]; then
  command -v "$SYSCTL_BIN" >/dev/null || die 'OPTIMIZE=1 需要 sysctl（procps）'
  [[ $SYSCTL_DIR != /etc/sysctl.d || $EUID == 0 ]] || die 'OPTIMIZE=1 修改系统参数需要 root 或 sudo'
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/nyanpass-install.XXXXXXXX")
cleanup() {
  local status=$?
  if (( status != 0 && OPTIMIZATION_APPLIED )); then restore_optimization || true; fi
  if (( status != 0 && (SWITCHED || (MIGRATE_ORIGINAL && MIGRATION_WRITES)) )); then
    [[ ! -f $WORK/old-start ]] || cp -- "$WORK/old-start" "$PREFIX/start.sh"
    [[ ! -f $WORK/old-service ]] || cp -- "$WORK/old-service" "$PREFIX/service.json"
    if (( MIGRATE_ORIGINAL )); then
      rm -f -- "$PREFIX/current" "$PREFIX/service.json" "$PREFIX/.nyanpass-install" "$PREFIX/start.original.sh"
      for original_script in update.sh uninstall.sh; do
        if [[ -f $WORK/original-$original_script ]]; then cp -- "$WORK/original-$original_script" "$PREFIX/$original_script"; else rm -f -- "$PREFIX/$original_script"; fi
      done
      if [[ -f $WORK/old-unit ]]; then cp -- "$WORK/old-unit" "$UNIT"; systemctl daemon-reload || true; fi
      if (( !NO_SYSTEMD )); then systemctl restart "$SERVICE.service" || true; fi
      info '迁移失败，已恢复原版启动文件和服务。' >&2
    elif [[ -n $OLD_CURRENT ]]; then
      ln -s "$OLD_CURRENT" "$PREFIX/.rollback-current"
      mv -Tf "$PREFIX/.rollback-current" "$PREFIX/current"
      if [[ -f $WORK/old-unit ]]; then cp -- "$WORK/old-unit" "$UNIT"; systemctl daemon-reload || true; fi
      if (( !NO_SYSTEMD )); then systemctl restart "$SERVICE.service" || true; fi
      info '启动失败，已恢复上一版本。' >&2
    else
      rm -f -- "$PREFIX/current"
      if (( !NO_SYSTEMD )); then
        systemctl disable --now "$SERVICE.service" || true
        rm -f -- "$UNIT"
        systemctl daemon-reload || true
      fi
    fi
  fi
  if (( status != 0 && MIGRATE_ORIGINAL )) && [[ ! -e $PREFIX/current ]]; then rm -f -- "$PREFIX/.nyanpass-install"; fi
  [[ -z $WORK || ! -d $WORK ]] || rm -rf -- "$WORK"
  exit "$status"
}
trap cleanup EXIT

# Auth is restricted to GitHub hosts and kept out of persistent service state.
AUTH_CONFIG=$WORK/auth.curl
GITHUB_AUTH=${GH_TOKEN:-${GITHUB_TOKEN:-}}
if [[ -n $GITHUB_AUTH ]]; then
  [[ $GITHUB_AUTH =~ ^[a-zA-Z0-9_]+$ ]] || die 'GitHub 令牌格式无效'
  printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_AUTH" >"$AUTH_CONFIG"
else : >"$AUTH_CONFIG"; fi
unset GITHUB_AUTH
curl_get() {
  local url=$1; shift
  case $url in
    https://api.github.com/*|https://github.com/*)
      curl --config "$AUTH_CONFIG" -fLSs --retry 1 --connect-timeout 10 --max-time 300 -H 'X-GitHub-Api-Version: 2022-11-28' "$url" "$@" ;;
    *) curl -fLSs --retry 1 --connect-timeout 10 --max-time 300 "$url" "$@" ;;
  esac
}
expected_digest() {
  awk -v name="$1" '{sub(/\r$/, "")} $2==name || $2=="*"name {print $1}' "$WORK/SHA256SUMS"
}
verify_binary() {
  local expected
  expected=$(expected_digest "$ASSET_NAME")
  if [[ ! $expected =~ ^[0-9a-fA-F]{64}$ && -n $LOCAL_BINARY ]]; then expected=$(expected_digest "$(basename "$LOCAL_BINARY")"); fi
  [[ $expected =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s  %s\n' "$expected" "$WORK/app.binary" | sha256sum -c - >/dev/null 2>&1 || return 1
  EXPECTED=$expected
}
# GitHub's asset object places id/name before the nested uploader object. Split
# at JSON object boundaries; names are restricted to our fixed release names.
asset_id() {
  awk -v wanted="$1" 'BEGIN {RS="[{}]"}
  { if (match($0, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
      n=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[[:space:]]*"/,"",n); sub(/"$/,"",n);
      if(n==wanted && match($0,/"id"[[:space:]]*:[[:space:]]*[0-9]+/)) {
        id=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[[:space:]]*/,"",id); print id; exit;
      }
    }
  }' "$WORK/release.json"
}
fetch_asset() {
  local source=$1 name=$2 target=$3 url id
  if [[ $source == api ]]; then
    id=$(asset_id "$name")
    [[ $id =~ ^[0-9]+$ ]] || return 1
    curl_get "https://api.github.com/repos/$REPOSITORY/releases/assets/$id" -H 'Accept: application/octet-stream' -o "$target"
  else
    if [[ $source == github ]]; then
      if [[ $VERSION == latest ]]; then url="https://github.com/$REPOSITORY/releases/latest/download/$name"
      else url="https://github.com/$REPOSITORY/releases/download/$VERSION/$name"; fi
    else
      [[ $source =~ ^https?:// && $source != *'@'* && $source != *'?'* && $source != *'#'* ]] || return 1
      url=${source//\{repository\}/$REPOSITORY}
      url=${url//\{version\}/$VERSION}
      if [[ $url == *'{asset}'* ]]; then url=${url//\{asset\}/$name}; else url=${url%/}/$name; fi
    fi
    curl_get "$url" -o "$target"
  fi
}
if [[ -n $LOCAL_BINARY ]]; then
  [[ -f $LOCAL_BINARY && -f $LOCAL_SUMS ]] || die '本地二进制和校验文件必须同时存在（v0.4 tar.gz 请改用 v0.5 独立二进制）'
  cp -- "$LOCAL_BINARY" "$WORK/app.binary"
  cp -- "$LOCAL_SUMS" "$WORK/SHA256SUMS"
  verify_binary || die '本地二进制摘要校验失败，未切换服务'
else
  [[ $OFFLINE != 1 ]] || die '离线模式禁止下载'
  if [[ $DOWNLOAD_SOURCE == auto ]]; then
    sources=${NYANPASS_DOWNLOAD_SOURCES:-github api}
    # An authenticated private pre-release is only downloadable via API assets.
    [[ -z ${GH_TOKEN:-${GITHUB_TOKEN:-}} || -n ${NYANPASS_DOWNLOAD_SOURCES:-} ]] || sources='api github'
  elif [[ $DOWNLOAD_SOURCE == primary ]]; then sources=github
  else sources=$DOWNLOAD_SOURCE; fi
  sources=${sources//,/ }; sources=${sources//;/ }; sources=${sources//$'\n'/ }
  read -r -a CANDIDATES <<<"$sources"
  ((${#CANDIDATES[@]})) || die '下载候选源为空'
  DOWNLOADED=0
  for source in "${CANDIDATES[@]}"; do
    info "探测下载线路：${source%%\?*}"
    rm -f -- "$WORK/app.binary" "$WORK/SHA256SUMS" "$WORK/release.json"
    if [[ $source == api ]]; then
      if [[ $VERSION == latest ]]; then release_path=latest; else release_path=tags/$VERSION; fi
      curl_get "https://api.github.com/repos/$REPOSITORY/releases/$release_path" -H 'Accept: application/vnd.github+json' -o "$WORK/release.json" || { info '线路不可用，继续尝试下一条。'; continue; }
    fi
    fetch_asset "$source" SHA256SUMS "$WORK/SHA256SUMS" || { info '校验清单下载失败，继续尝试下一条。'; continue; }
    # A successful HTTP probe is insufficient: fetch and verify the real binary.
    if fetch_asset "$source" "$ASSET_NAME" "$WORK/app.binary" && verify_binary; then
      DOWNLOADED=1; SELECTED_SOURCE=$source; break
    fi
    info '二进制下载或 SHA256 校验失败，继续尝试下一条。'
  done
  (( DOWNLOADED )) || die '全部下载线路失败；未修改已有程序。可指定 NYANPASS_DOWNLOAD_SOURCES 或使用离线包。'
fi
chmod 700 "$WORK/app.binary"
"$WORK/app.binary" --binary-info >"$WORK/binary-info.json" || die '二进制无法运行；需要受支持的 Linux glibc 系统及匹配的 CPU 架构'
APP_VERSION=$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"v?([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$WORK/binary-info.json")
INFO_PRODUCT=$(sed -nE 's/.*"product"[[:space:]]*:[[:space:]]*"([a-z_]+)".*/\1/p' "$WORK/binary-info.json")
INFO_ARCH=$(sed -nE 's/.*"arch"[[:space:]]*:[[:space:]]*"([a-z0-9]+)".*/\1/p' "$WORK/binary-info.json")
[[ $APP_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $INFO_PRODUCT == "$PRODUCT" && $INFO_ARCH == "$ARCH" ]] || die '二进制产品、版本或架构信息不匹配'
if [[ -f $PREFIX/service.json ]]; then
  "$WORK/app.binary" --deployment-check-config "$PREFIX/service.json" "$PRODUCT" "$PREFIX/config/native.json" || die '已有服务配置不兼容，未修改配置'
fi
if [[ -n $CONFIG_FILE && ( ! -f $PREFIX/config/native.json || $ACTION != update ) ]]; then
  [[ -f $CONFIG_FILE ]] || die '原生配置文件不存在'
  NATIVE_CONFIG=$CONFIG_FILE
else NATIVE_CONFIG=$PREFIX/config/native.json; fi
if [[ ! -f $PREFIX/service.json || ${#NODE_ARGS[@]} -gt 0 ]]; then
  "$WORK/app.binary" --deployment-config "$WORK/service.json" "$PRODUCT" "$NATIVE_CONFIG" -- "${NODE_ARGS[@]}"
  "$WORK/app.binary" --deployment-check-config "$WORK/service.json" "$PRODUCT" "$NATIVE_CONFIG"
else cp -- "$PREFIX/service.json" "$WORK/service.json"; fi

mkdir -p "$PREFIX/releases" "$PREFIX/config" "$PREFIX/data"
printf '%s\n' "$SERVICE" >"$PREFIX/.nyanpass-install"
[[ ! -f $PREFIX/start.sh ]] || cp -- "$PREFIX/start.sh" "$WORK/old-start"
[[ ! -f $PREFIX/service.json ]] || cp -- "$PREFIX/service.json" "$WORK/old-service"
if (( MIGRATE_ORIGINAL )); then
  for original_script in update.sh uninstall.sh; do [[ ! -f $PREFIX/$original_script ]] || cp -- "$PREFIX/$original_script" "$WORK/original-$original_script"; done
  # Keep the original executable and a private copy of the original launcher.
  cp -- "$PREFIX/start.sh" "$PREFIX/start.original.sh"
  MIGRATION_WRITES=1
fi
if (( !NO_SYSTEMD )) && [[ -f $UNIT ]]; then cp -- "$UNIT" "$WORK/old-unit"; fi
RELEASE_DIR=releases/$APP_VERSION-${EXPECTED:0:12}
if [[ ! -d $PREFIX/$RELEASE_DIR ]]; then
  mkdir -p "$WORK/release/deploy"
  mv -- "$WORK/app.binary" "$WORK/release/$PRODUCT"
  # $0 can be a process-substitution descriptor during one-command installs.
  # Its original script is copied now so installed update/uninstall stay local.
  if [[ -f ${BASH_SOURCE[0]} && ${BASH_SOURCE[0]} != /dev/fd/* ]]; then
    cp -- "${BASH_SOURCE[0]}" "$WORK/release/deploy/nyanpass-install.sh"
  elif [[ $OFFLINE != 1 ]]; then
    # Public fallback is checksum-verified before becoming a future updater.
    SCRIPT_ASSET=nyanpass-install.sh
    if [[ -n ${SELECTED_SOURCE:-} ]]; then
      fetch_asset "$SELECTED_SOURCE" "$SCRIPT_ASSET" "$WORK/release/deploy/nyanpass-install.sh" || die '无法保存安装管理脚本'
      SCRIPT_EXPECTED=$(expected_digest "$SCRIPT_ASSET")
      [[ $SCRIPT_EXPECTED =~ ^[0-9a-fA-F]{64}$ ]] || die '校验清单缺少安装脚本摘要'
      printf '%s  %s\n' "$SCRIPT_EXPECTED" "$WORK/release/deploy/nyanpass-install.sh" | sha256sum -c - >/dev/null || die '安装脚本摘要校验失败'
    else die '使用本地二进制时请将安装脚本保存为文件再运行'; fi
  else die '离线安装脚本必须保存为文件'; fi
  chmod 700 "$WORK/release/$PRODUCT" "$WORK/release/deploy/nyanpass-install.sh"
  mv -- "$WORK/release" "$PREFIX/$RELEASE_DIR"
fi
if [[ -n $CONFIG_FILE && ( ! -f $PREFIX/config/native.json || $ACTION != update ) ]]; then cp -- "$CONFIG_FILE" "$PREFIX/config/native.json"; fi
cp -- "$WORK/service.json" "$PREFIX/service.json"
if [[ ! -f $PREFIX/env.sh ]]; then
  {
    printf '#!/usr/bin/env bash\n'
    if [[ $PRODUCT == rel_backend ]]; then
      ADMIN_PASSWORD=${NYANPASS_ADMIN_PASSWORD:-$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')}
      printf 'export NYANPASS_HOST=%q\n' "${NYANPASS_HOST:-0.0.0.0}"
      printf 'export NYANPASS_PORT=%q\n' "${NYANPASS_PORT:-18182}"
      printf 'export NYANPASS_ADMIN_USER=%q\n' "${NYANPASS_ADMIN_USER:-admin}"
      printf 'export NYANPASS_ADMIN_PASSWORD=%q\n' "$ADMIN_PASSWORD"
      printf 'export NYANPASS_DB=%q\n' "$PREFIX/data/panel.sqlite"
      [[ -z ${NYANPASS_TRUSTED_PROXIES:-} ]] || printf 'export NYANPASS_TRUSTED_PROXIES=%q\n' "$NYANPASS_TRUSTED_PROXIES"
    fi
  } >"$PREFIX/env.sh"
fi
{
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\numask 077\n'
  printf 'cd %q\nsource ./env.sh\n' "$PREFIX"
  printf 'unset GH_TOKEN GITHUB_TOKEN\nexec %q --state %q\n' "$PREFIX/current/$PRODUCT" "$PREFIX"
} >"$PREFIX/start.sh"
for command_name in update uninstall; do
  {
    printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n'
    printf 'exec bash %q %q %q --service %q --prefix %q' "$PREFIX/current/deploy/nyanpass-install.sh" "$PRODUCT" "$command_name" "$SERVICE" "$PREFIX"
    (( !NO_SYSTEMD )) || printf ' --no-systemd'
    printf ' "$@"\n'
  } >"$PREFIX/$command_name.sh"
done
chmod 700 "$PREFIX/start.sh" "$PREFIX/update.sh" "$PREFIX/uninstall.sh"
chmod 600 "$PREFIX/env.sh" "$PREFIX/service.json"
OLD_CURRENT=$(readlink "$PREFIX/current" || true)
ln -s "$RELEASE_DIR" "$PREFIX/.new-current"
mv -Tf "$PREFIX/.new-current" "$PREFIX/current"
SWITCHED=1
cat >"$PREFIX/$SERVICE.service" <<EOF
[Unit]
Description=Nyanpass reconstructed $PRODUCT
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=$PREFIX
ExecStart=/bin/bash $PREFIX/start.sh
Restart=always
RestartSec=3
LimitNOFILE=999999
UMask=0077
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
if (( !NO_SYSTEMD )); then
  mkdir -p "$SYSTEMD_DIR"
  cp -- "$PREFIX/$SERVICE.service" "$UNIT"
  systemctl daemon-reload
  systemctl enable "$SERVICE.service" >/dev/null
  if (( !DEFER_RESTART )); then
    systemctl restart "$SERVICE.service"
    sleep 2
    systemctl is-active --quiet "$SERVICE.service" || die "启动失败，请查看 journalctl -u $SERVICE -n 80"
  fi
fi

apply_optimization() {
  local key value previous available bbr=0 before_tmp=$WORK/optimization.before
  [[ ! -L $OPTIMIZATION_FILE ]] || die 'sysctl 文件不能是符号链接'
  mkdir -p "$SYSCTL_DIR"
  if [[ -f $OPTIMIZATION_FILE && ! -f $PREFIX/config/optimization.before ]]; then
    cp -- "$OPTIMIZATION_FILE" "$PREFIX/config/optimization.previous.conf"
  fi
  available=$("$SYSCTL_BIN" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  [[ " $available " != *' bbr '* ]] || bbr=1
  printf '# Nyanpass managed optimization %s\n' "$SERVICE" >"$WORK/optimization.conf"
  : >"$before_tmp"
  while IFS='=' read -r key value; do
    [[ -n $key ]] || continue
    if [[ $key == net.ipv4.tcp_congestion_control && $bbr != 1 ]]; then info '内核未提供 BBR，保留现有拥塞控制算法。'; continue; fi
    previous=$("$SYSCTL_BIN" -n "$key" 2>/dev/null | awk '{$1=$1;print}') || { info "内核不支持 $key，跳过。"; continue; }
    printf '%s\t%s\t%s\n' "$key" "$previous" "$value" >>"$before_tmp"
    if [[ ! -f $SYSCTL_DIR/.nyanpass-original-values ]] || ! awk -F '\t' -v key="$key" '$1==key {found=1} END {exit !found}' "$SYSCTL_DIR/.nyanpass-original-values"; then
      printf '%s\t%s\n' "$key" "$previous" >>"$SYSCTL_DIR/.nyanpass-original-values"
    fi
    printf '%s = %s\n' "$key" "$value" >>"$WORK/optimization.conf"
  done <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.conf.all.rp_filter=0
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=-2
net.ipv4.tcp_moderate_rcvbuf=1
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=4096
net.ipv4.tcp_abort_on_overflow=1
vm.swappiness=10
fs.file-max=6553560
SYSCTL
  if [[ ! -f $PREFIX/config/optimization.before ]]; then cp -- "$before_tmp" "$PREFIX/config/optimization.before"; fi
  cp -- "$WORK/optimization.conf" "$OPTIMIZATION_FILE"
  OPTIMIZATION_APPLIED=1
  # Unsupported/read-only keys are excluded above. If applying an available key
  # fails, restoration uses the saved values and installation rolls back.
  "$SYSCTL_BIN" -q -p "$OPTIMIZATION_FILE" || die '应用系统优化失败，正在恢复原参数和版本'
  info "已应用本服务的参数优化：$OPTIMIZATION_FILE"
}
if [[ ${OPTIMIZE:-0} == 1 ]]; then apply_optimization; fi
SWITCHED=0
OPTIMIZATION_APPLIED=0
info "安装完成：$PRODUCT $APP_VERSION ($ARCH)，独立二进制，无需安装 Node.js。"
info "安装目录：$PREFIX"
if (( NO_SYSTEMD )); then info "前台启动：bash $PREFIX/start.sh"
else info "管理：systemctl status|restart|stop $SERVICE；日志：journalctl -u $SERVICE -f"; fi
info "保留配置更新：bash $PREFIX/update.sh"
info "卸载并保留数据：bash $PREFIX/uninstall.sh"
if [[ $PRODUCT == rel_backend ]]; then
  info '面板默认 http://服务器IP:18182；监听地址、端口和初始账户保存在 env.sh。'
  [[ -z ${ADMIN_PASSWORD:-} ]] || info "初始管理员：${NYANPASS_ADMIN_USER:-admin} / $ADMIN_PASSWORD"
fi
