#!/usr/bin/env bash
# ベンダリング先 (third_party/) に当てている patch が消失していないかを検査する。
# CI と上流追従の差分確認の両方で使う想定。
#
# 失敗時は exit 1。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

check_patch() {
  local file="$1"
  local anchor="$2"
  local description="$3"

  if [[ ! -f "$repo_root/$file" ]]; then
    echo "FATAL: $file が存在しない (vendor 自体が消えている?)" >&2
    return 1
  fi

  if ! grep -q "$anchor" "$repo_root/$file"; then
    echo "FATAL: $description の patch anchor が消失している" >&2
    echo "  file: $file" >&2
    echo "  anchor: $anchor" >&2
    echo "  -> README の「ベンダー依存」節の手順で再適用してください。" >&2
    return 1
  fi
  echo "[ok] $description"
}

echo "verifying vendored patches..."
check_patch \
  "third_party/universal_ble/lib/src/universal_ble_web/universal_ble_web.dart" \
  "\[KUBI-PATCH\] skip watchAdvertisements" \
  "universal_ble: skip watchAdvertisements (Chrome renderer crash workaround)"

echo "all patches intact."
