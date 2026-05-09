#!/system/bin/sh
# NetProxy Xray 服务管理脚本 (TProxy 模式)
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
readonly KILL_TIMEOUT=5

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

  log "INFO" "Xray 配置文件: $XRAY_CONFIG"
  log "INFO" "Xray 资源目录: $XRAY_DIR"
  log "INFO" "正在启动 Xray 进程..."

  export XRAY_LOCATION_ASSET="$XRAY_DIR"
  export XRAY_LOCATION_CONFIG="$XRAY_DIR"

  cd "$XRAY_DIR" || die "无法进入 Xray 配置目录: $XRAY_DIR"
  nohup "$BUSYBOX" setuidgid root:net_admin "$XRAY_BIN" run -config "$XRAY_CONFIG" > "$XRAY_LOG_FILE" 2>&1 &

  new_pid=$!

  local wait_count=0
  while [ "$wait_count" -lt 3 ]; do
    sleep 1
    if ! kill -0 "$new_pid" 2> /dev/null; then
      die "Xray 启动失败，请检查日志: $XRAY_LOG_FILE"
    fi
    wait_count=$((wait_count + 1))
  done

  log "INFO" "Xray 启动成功 (PID: $new_pid)"

  log "INFO" "正在加载透明代理规则..."
  if ! "$TPROXY_SCRIPT" start >> "$LOG_FILE" 2>&1; then
    kill "$new_pid" 2> /dev/null || true
    die "透明代理规则加载失败，已停止 Xray 进程"
  fi

  log "INFO" "========== Xray 服务启动完成 =========="
}

#######################################
# 停止服务
#######################################
do_stop() {
  local pid count

  log "INFO" "========== 开始停止 Xray 服务 =========="
  verify_environment stop

  # 无论 Xray 是否在运行，都清理 iptables 规则
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

  if kill "$pid" 2> /dev/null; then
    count=0
    while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
      sleep 1
      count=$((count + 1))
    done

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
