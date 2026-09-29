#!/system/bin/sh
# NetProxy Xray 看门狗
# 由 service.sh start 在后台启动，stop 时先停止看门狗再停止 Xray。
#
# Xray 意外退出后透明代理规则仍在，所有流量会被送往无人监听的端口，
# 表现为整机断网。看门狗检测到 Xray 退出后：
#   1. 立即清理透明代理规则，恢复直连网络
#   2. WATCHDOG_RESTART=1 时自动重启服务；
#      RESTART_WINDOW 秒内最多重启 RESTART_LIMIT 次，超过后停止重试

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly XRAY_BIN="$MODDIR/bin/xray"
readonly RUN_DIR="$MODDIR/run"
readonly PID_FILE="$RUN_DIR/watchdog.pid"
readonly RESTART_HISTORY="$RUN_DIR/restart_history"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly TPROXY_SCRIPT="$MODDIR/scripts/network/tproxy.sh"

# 检查间隔（秒）
readonly CHECK_INTERVAL="${WATCHDOG_INTERVAL:-5}"
readonly RESTART_LIMIT=3
readonly RESTART_WINDOW=300

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

LOG_STDERR=0

#######################################
# 是否允许再次自动重启
# 记录每次重启的时间戳，只统计 RESTART_WINDOW 秒内的次数
#######################################
allow_restart() {
  local now recent count

  now="$(date +%s)"
  recent="$(awk -v now="$now" -v w="$RESTART_WINDOW" 'now - $1 < w' "$RESTART_HISTORY" 2> /dev/null)"
  count="$(printf '%s\n' "$recent" | grep -c '[0-9]')"

  if [ "$count" -ge "$RESTART_LIMIT" ]; then
    log "ERROR" "看门狗: ${RESTART_WINDOW} 秒内已自动重启 $count 次，停止重试，请检查 xray.log"
    return 1
  fi

  { [ -n "$recent" ] && printf '%s\n' "$recent"; printf '%s\n' "$now"; } > "$RESTART_HISTORY"
  return 0
}

handle_xray_exit() {
  log "WARN" "看门狗: 检测到 Xray 意外退出，清理透明代理规则以恢复网络"
  "$TPROXY_SCRIPT" stop >> "$LOG_FILE" 2>&1 || true
  rm -f "$PID_FILE"

  if [ "$(read_conf "$MODULE_CONF" "WATCHDOG_RESTART" "1")" != "1" ]; then
    log "WARN" "看门狗: WATCHDOG_RESTART=0，不自动重启，当前网络为直连"
    return
  fi

  allow_restart || return
  log "INFO" "看门狗: 自动重启服务..."
  # service.sh start 会启动新的看门狗，当前进程随后退出
  LOG_STDERR=0 sh "$SERVICE_SCRIPT" start > /dev/null 2>&1 || log "ERROR" "看门狗: 自动重启失败，当前网络为直连"
}

main() {
  mkdir -p "$RUN_DIR" 2> /dev/null || true
  printf '%s\n' "$$" > "$PID_FILE"
  log "INFO" "看门狗已启动 (PID: $$，检查间隔 ${CHECK_INTERVAL}s)"

  while :; do
    sleep "$CHECK_INTERVAL"
    [ -n "$(get_pid "$XRAY_BIN")" ] && continue
    handle_xray_exit
    exit 0
  done
}

main "$@"
