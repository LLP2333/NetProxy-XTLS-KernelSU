#!/system/bin/sh
# NetProxy geoip / geosite 数据更新脚本
# 用法: geo_update.sh [geoip|geosite|all]
#
# 设计原则:
#   1. 失败只警告，不退出非零（被 service.sh stop 调用时不能阻塞停止流程）
#   2. 下载到临时文件 → sha256 校验 → 原子 mv 替换，保证旧文件不会损坏
#   3. 纯 POSIX sh + curl + sha256sum/busybox sha256sum，无 bash 依赖

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly XRAY_ASSET_DIR="$MODDIR/config/xray"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

readonly DEFAULT_GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
readonly DEFAULT_GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
readonly DEFAULT_TIMEOUT=60

#######################################
# 读取配置（提供默认值，避免 module.conf 缺项时失败）
#######################################
load_geo_config() {
  GEOIP_URL="$(read_conf "$MODULE_CONF" "GEO_UPDATE_GEOIP_URL" "$DEFAULT_GEOIP_URL")"
  GEOSITE_URL="$(read_conf "$MODULE_CONF" "GEO_UPDATE_GEOSITE_URL" "$DEFAULT_GEOSITE_URL")"
  TIMEOUT="$(read_conf "$MODULE_CONF" "GEO_UPDATE_TIMEOUT" "$DEFAULT_TIMEOUT")"

  [ -n "$GEOIP_URL" ] || GEOIP_URL="$DEFAULT_GEOIP_URL"
  [ -n "$GEOSITE_URL" ] || GEOSITE_URL="$DEFAULT_GEOSITE_URL"
  case "$TIMEOUT" in
    '' | *[!0-9]*) TIMEOUT="$DEFAULT_TIMEOUT" ;;
  esac
}

#######################################
# 探测可用的 sha256 计算命令
# 优先使用系统 sha256sum，没有则尝试 busybox
#######################################
detect_sha256_cmd() {
  if command_exists sha256sum; then
    printf "sha256sum"
    return 0
  fi

  local busybox
  busybox="$(detect_busybox)"
  if [ -x "$busybox" ] || command_exists "$busybox"; then
    printf "%s sha256sum" "$busybox"
    return 0
  fi

  return 1
}

#######################################
# 用 curl 下载到指定路径
# 失败返回非零，调用方自行处理
#######################################
http_download() {
  local url="$1"
  local out="$2"

  command_exists curl || {
    log "WARN" "geo-update: 缺少 curl，无法下载: $url"
    return 1
  }

  # -fSL: 失败时不输出 HTML、显示错误、跟随重定向
  # --retry: 网络抖动时重试，与 Xray-install 行为一致
  if curl -fSL \
    --max-time "$TIMEOUT" \
    --retry 3 --retry-delay 2 \
    -H 'Cache-Control: no-cache' \
    -o "$out" "$url"; then
    return 0
  fi

  return 1
}

#######################################
# 校验下载文件的 sha256
# 期望 sha256 文件格式: "<hex>  <filename>"，与 GitHub release 一致
#######################################
verify_sha256() {
  local data_file="$1"
  local sum_file="$2"
  local sha_cmd expected actual

  sha_cmd="$(detect_sha256_cmd)" || {
    log "WARN" "geo-update: 未找到 sha256sum 命令，跳过校验"
    return 0
  }

  expected="$(awk '{print $1; exit}' "$sum_file" 2> /dev/null)"
  if [ -z "$expected" ]; then
    log "WARN" "geo-update: sha256 文件为空: $sum_file"
    return 1
  fi

  actual="$($sha_cmd "$data_file" 2> /dev/null | awk '{print $1; exit}')"
  if [ -z "$actual" ]; then
    log "WARN" "geo-update: 计算 sha256 失败: $data_file"
    return 1
  fi

  if [ "$expected" != "$actual" ]; then
    log "WARN" "geo-update: sha256 不匹配（期望 $expected 实际 $actual）"
    return 1
  fi

  return 0
}

#######################################
# 更新单个数据文件
# 流程: 下载 .dat → 下载 .sha256sum → 校验 → 原子替换
#######################################
update_one() {
  local url="$1"
  local target_name="$2"
  local target_dir="$XRAY_ASSET_DIR"
  local target="$target_dir/$target_name"
  local tmp_dir="$MODDIR/logs/geo_tmp.$$"
  local tmp_data="$tmp_dir/$target_name"
  local tmp_sum="$tmp_data.sha256sum"

  ensure_dir "$target_dir" "无法创建 Xray 资源目录: $target_dir"
  mkdir -p "$tmp_dir" || {
    log "WARN" "geo-update: 无法创建临时目录: $tmp_dir"
    return 1
  }

  # trap 在子函数里不太可靠，统一在末尾手动清理

  log "INFO" "geo-update: 开始下载 $target_name <- $url"
  if ! http_download "$url" "$tmp_data"; then
    log "WARN" "geo-update: 下载失败 $target_name"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! http_download "${url}.sha256sum" "$tmp_sum"; then
    log "WARN" "geo-update: 下载 sha256 失败 $target_name（跳过校验，仍替换）"
  elif ! verify_sha256 "$tmp_data" "$tmp_sum"; then
    log "WARN" "geo-update: 校验失败，丢弃下载文件 $target_name"
    rm -rf "$tmp_dir"
    return 1
  fi

  # 原子替换：先 mv 到同目录，再删除临时目录
  if mv -f "$tmp_data" "$target"; then
    chmod 0644 "$target" 2> /dev/null || true
    log "INFO" "geo-update: 已更新 $target"
  else
    log "WARN" "geo-update: 替换失败 $target"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  return 0
}

#######################################
# 入口
#######################################
main() {
  local target="${1:-all}"
  local ok=0 fail=0

  load_geo_config

  case "$target" in
    geoip)
      update_one "$GEOIP_URL" "geoip.dat" && ok=$((ok + 1)) || fail=$((fail + 1))
      ;;
    geosite)
      update_one "$GEOSITE_URL" "geosite.dat" && ok=$((ok + 1)) || fail=$((fail + 1))
      ;;
    all | '')
      update_one "$GEOIP_URL" "geoip.dat" && ok=$((ok + 1)) || fail=$((fail + 1))
      update_one "$GEOSITE_URL" "geosite.dat" && ok=$((ok + 1)) || fail=$((fail + 1))
      ;;
    *)
      log "WARN" "geo-update: 未知目标: $target"
      return 1
      ;;
  esac

  log "INFO" "geo-update: 完成 (成功 $ok，失败 $fail)"
  # 任意一项成功就视为 0；全部失败才返回 1
  [ "$ok" -gt 0 ] && return 0
  return 1
}

main "$@"
