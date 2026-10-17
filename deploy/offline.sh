#!/usr/bin/env bash
# All inputs are local. No download, package-manager or Node bootstrap path.
set -Eeuo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case $(uname -m) in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) printf '不支持该 CPU 架构\n' >&2; exit 1 ;; esac
PRODUCT=rel_nodeclient
if [[ ${1:-} == rel_backend || ${1:-} == rel_nodeclient ]]; then PRODUCT=$1; shift; fi
[[ -f $HERE/nyanpass-install.sh && -f $HERE/SHA256SUMS && -f $HERE/${PRODUCT}_linux_$ARCH ]] || { printf '离线包缺少安装脚本、SHA256SUMS 或匹配架构的二进制\n' >&2; exit 1; }
export NYANPASS_OFFLINE=1
exec bash "$HERE/nyanpass-install.sh" "$PRODUCT" --binary-file "$HERE/${PRODUCT}_linux_$ARCH" --checksum-file "$HERE/SHA256SUMS" "$@"
