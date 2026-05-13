#!/system/bin/sh
# NetProxy Xray 服务管理脚本 (TProxy 模式)
# 负责 Xray 进程的生命周期管理和透明代理规则的联动
# 用法: service.sh {start|stop|restart|status}

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly XRAY_BIN="$MODDIR/bin/xray"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly XRAY_DIR="$MODDIR/config/xray"
readonly DEFAULT_XRAY_CONFIG="$XRAY_DIR/config.json"
readonly XRAY_LOG_FILE="$MODDIR/logs/xray.log"
readonly TPROXY_SCRIPT="$MODDIR/scripts/network/tproxy.sh"
readonly GEO_UPDATE_SCRIPT="$MODDIR/scripts/core/geo_update.sh"

# SIGTERM 等待超时（秒），超时后升级为 SIGKILL
readonly KILL_TIMEOUT=5
# 启动后等待进程存活的检查次数（每次间隔 1 秒）
readonly STARTUP_CHECK_COUNT=3
# 启动失败时随同错误日志附带的 xray.log 末尾行数
readonly XRAY_LOG_TAIL_LINES=20

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

export PATH="$MODDIR/bin:$PATH"

readonly BUSYBOX="$(detect_busybox)"

XRAY_CONFIG="$DEFAULT_XRAY_CONFIG"

#######################################
# 加载服务配置
#######################################
load_service_config() {
  XRAY_CONFIG="$(read_conf "$MODULE_CONF" "XRAY_CONFIG" "$DEFAULT_XRAY_CONFIG")"
  [ -n "$XRAY_CONFIG" ] || XRAY_CONFIG="$DEFAULT_XRAY_CONFIG"
}

#######################################
# 检查服务运行环境
#######################################
verify_environment() {
  local mode="${1:-start}"

  load_service_config

  require_file "$XRAY_BIN" "Xray 二进制不存在: $XRAY_BIN"
  require_file "$MODULE_CONF" "模块配置文件不存在: $MODULE_CONF"
  require_dir "$XRAY_DIR" "Xray 配置目录不存在: $XRAY_DIR"

  if [ "$mode" = "start" ]; then
    require_file "$XRAY_CONFIG" "Xray 配置文件不存在: $XRAY_CONFIG"
    require_file "$TPROXY_SCRIPT" "TProxy 脚本不存在: $TPROXY_SCRIPT"
  fi

  ensure_dir "$MODDIR/logs" "无法创建日志目录: $MODDIR/logs"
}

#######################################
# 记录 Xray 版本信息到 service.log
# `xray version` 通常输出 3 行，全部记录便于排查
#######################################
log_xray_version() {
  local line
  if [ ! -x "$XRAY_BIN" ]; then
    log "WARN" "Xray 二进制不可执行: $XRAY_BIN"
    return 1
  fi

  "$XRAY_BIN" version 2> /dev/null | while IFS= read -r line; do
    [ -n "$line" ] && log "INFO" "Xray 版本: $line"
  done
}

#######################################
# 启动失败时把 xray.log 末尾几行追加到 service.log
# 方便用户只看一处日志就能定位问题
#######################################
log_xray_tail() {
  [ -f "$XRAY_LOG_FILE" ] || return 0

  log "ERROR" "—— xray.log 末尾 $XRAY_LOG_TAIL_LINES 行 ——"
  tail -n "$XRAY_LOG_TAIL_LINES" "$XRAY_LOG_FILE" 2> /dev/null | while IFS= read -r line; do
    [ -n "$line" ] && log "ERROR" "  $line"
  done
  log "ERROR" "—— xray.log 末尾结束 ——"
}

#######################################
# 等待进程存活确认
# 连续检查 $STARTUP_CHECK_COUNT 次（每次 1 秒），
# 如果进程提前退出则认为启动失败
#######################################
wait_for_process() {
  local pid="$1" check=0

  while [ "$check" -lt "$STARTUP_CHECK_COUNT" ]; do
    sleep 1
    if ! kill -0 "$pid" 2> /dev/null; then
      return 1
    fi
    check=$((check + 1))
  done
}

#######################################
# 启动服务
#######################################
do_start() {
  local pid new_pid

  log "INFO" "========== 开始启动 Xray 服务 =========="
  verify_environment start

  pid="$(get_pid "$XRAY_BIN")"
  if [ -n "$pid" ]; then
    log "WARN" "Xray 已在运行中 (PID: $pid)"
    return 0
  fi

  log_xray_version

  log "INFO" "Xray 配置文件: $XRAY_CONFIG"
  log "INFO" "Xray 资源目录: $XRAY_DIR"
  log "INFO" "正在启动 Xray 进程..."

  export XRAY_LOCATION_ASSET="$XRAY_DIR"
  export XRAY_LOCATION_CONFIG="$XRAY_DIR"

  cd "$XRAY_DIR" || die "无法进入 Xray 配置目录: $XRAY_DIR"
  nohup "$BUSYBOX" setuidgid root:net_admin "$XRAY_BIN" run -config "$XRAY_CONFIG" > "$XRAY_LOG_FILE" 2>&1 &

  new_pid=$!

  if ! wait_for_process "$new_pid"; then
    log_xray_tail
    die "Xray 启动失败，请检查日志: $XRAY_LOG_FILE"
  fi

  log "INFO" "Xray 启动成功 (PID: $new_pid)"

  log "INFO" "正在加载透明代理规则..."
  if ! "$TPROXY_SCRIPT" start >> "$LOG_FILE" 2>&1; then
    kill "$new_pid" 2> /dev/null || true
    die "透明代理规则加载失败，已停止 Xray 进程"
  fi

  log "INFO" "========== Xray 服务启动完成 =========="
}

#######################################
# 停止前尝试在线更新 geoip / geosite
# 此时代理仍在运行，下载更稳定；失败仅警告，绝不阻塞 stop
#######################################
maybe_update_geo_before_stop() {
  local enabled pid

  enabled="$(read_conf "$MODULE_CONF" "GEO_UPDATE_ON_STOP" "1")"
  if [ "$enabled" != "1" ]; then
    return 0
  fi

  pid="$(get_pid "$XRAY_BIN")"
  if [ -z "$pid" ]; then
    log "INFO" "Xray 未运行，跳过 geo 更新"
    return 0
  fi

  if [ ! -x "$GEO_UPDATE_SCRIPT" ] && [ ! -f "$GEO_UPDATE_SCRIPT" ]; then
    log "WARN" "geo-update 脚本不存在，跳过: $GEO_UPDATE_SCRIPT"
    return 0
  fi

  log "INFO" "停止 Xray 前尝试更新 geo 数据..."
  # 失败 / 超时都不阻塞停止流程
  sh "$GEO_UPDATE_SCRIPT" all || log "WARN" "geo 更新失败，继续停止 Xray"
}

#######################################
# 停止服务
# 先清理 iptables 规则（即使 Xray 未运行也要清理，
# 防止残留规则导致网络异常），再停止 Xray 进程
#######################################
do_stop() {
  local pid count

  log "INFO" "========== 开始停止 Xray 服务 =========="
  verify_environment stop

  maybe_update_geo_before_stop

  if [ -f "$TPROXY_SCRIPT" ]; then
    "$TPROXY_SCRIPT" stop >> "$LOG_FILE" 2>&1 || true
  fi

  pid="$(get_pid "$XRAY_BIN")"
  if [ -z "$pid" ]; then
    log "INFO" "未发现运行中的 Xray 进程"
    log "INFO" "========== Xray 服务停止完成 =========="
    return 0
  fi

  log "INFO" "正在停止 Xray 进程 (PID: $pid)..."

  # 先发 SIGTERM 优雅退出，等待 KILL_TIMEOUT 秒
  if kill "$pid" 2> /dev/null; then
    count=0
    while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
      sleep 1
      count=$((count + 1))
    done

    # 超时未退出则强制终止
    if kill -0 "$pid" 2> /dev/null; then
      log "WARN" "进程未响应 SIGTERM，改用 SIGKILL"
      kill -9 "$pid" 2> /dev/null || true
    fi
  fi

  log "INFO" "Xray 进程已停止"
  log "INFO" "========== Xray 服务停止完成 =========="
}

#######################################
# 重启服务
#######################################
do_restart() {
  log "INFO" "========== 开始重启 Xray 服务 =========="
  do_stop
  sleep 1
  do_start
}

#######################################
# 查看状态
#######################################
do_status() {
  local pid uptime version

  pid="$(get_pid "$XRAY_BIN")"
  if [ -n "$pid" ]; then
    printf "Xray 运行中 (PID: %s)\n" "$pid"
    uptime="$(get_process_uptime "$pid")"
    if [ "$uptime" -gt 0 ]; then
      printf "运行时间: %s 秒\n" "$uptime"
    fi
    version="$("$XRAY_BIN" version 2> /dev/null | head -1 || true)"
    [ -n "$version" ] && printf "内核版本: %s\n" "$version"
    return 0
  fi

  printf "Xray 未运行\n"
  return 1
}

#######################################
# 显示帮助
#######################################
show_usage() {
  cat << EOF
用法: $(basename "$0") {start|stop|restart|status}

命令:
  start     启动 Xray 服务
  stop      停止 Xray 服务
  restart   重启 Xray 服务
  status    查看服务状态
EOF
}

#######################################
# 主入口
#######################################
main() {
  case "${1:-}" in
    start)
      do_start
      ;;
    stop)
      do_stop
      ;;
    restart)
      do_restart
      ;;
    status)
      do_status
      ;;
    -h | --help | help)
      show_usage
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
