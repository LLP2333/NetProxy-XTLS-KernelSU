#!/system/bin/sh
# TProxy 透明代理网络规则管理
# 完全参考 NetProxy-Magisk 实现
# iptables mangle TPROXY + owner match + ip rule 策略路由

set -u

export TZ=Asia/Shanghai

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# 代理进程用户/组（与 service.sh 中 setuidgid 一致）
readonly CORE_USER="root"
readonly CORE_GROUP="net_admin"

readonly PROXY_PORT="12345"

readonly MARK=20
readonly TABLE_ID=100

readonly RESERVED_IPV4="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32"

################################################################################
# 日志
################################################################################

log() {
  local level="$1" message="$2"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')"
  printf '%s\n' "[$ts] [$level] $message" >&2
}

################################################################################
# iptables / ip 封装（参考 NetProxy-Magisk）
################################################################################

iptables() {
  log "DEBUG" "[EXEC] iptables -w 100 $*"
  command iptables -w 100 "$@"
}

ip_rule() {
  log "DEBUG" "[EXEC] ip rule $*"
  command ip rule "$@"
}

ip_route() {
  log "DEBUG" "[EXEC] ip route $*"
  command ip route "$@"
}

################################################################################
# 环境检查
################################################################################

setup_env() {
  export PATH="$PATH:/system/bin:/system/xbin:/data/data/com.termux/files/usr/bin"

  local bb
  for bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    if [ -f "$bb" ] && [ -x "$bb" ]; then
      export PATH="$PATH:$(dirname "$bb")"
      break
    fi
  done

  if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
    log "ERROR" "需要 root 权限"
    exit 1
  fi

  local cmd
  for cmd in ip iptables; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR" "缺少必要命令: $cmd (PATH=$PATH)"
      exit 1
    fi
  done
}

################################################################################
# 链创建辅助
################################################################################

safe_chain_create() {
  local table="$1" chain="$2"
  iptables -t "$table" -N "$chain" 2>/dev/null || true
  iptables -t "$table" -F "$chain"
}

################################################################################
# 清理
################################################################################

cleanup() {
  log "INFO" "清理透明代理规则..."

  # 从主链摘除跳转
  iptables -t mangle -D PREROUTING -p tcp -j PROXY_PREROUTING 2>/dev/null || true
  iptables -t mangle -D PREROUTING -p udp -j PROXY_PREROUTING 2>/dev/null || true
  iptables -t mangle -D OUTPUT -p tcp -j PROXY_OUTPUT 2>/dev/null || true
  iptables -t mangle -D OUTPUT -p udp -j PROXY_OUTPUT 2>/dev/null || true

  # 删除子链
  local chain
  for chain in PROXY_PREROUTING PROXY_OUTPUT PROXY_DIVERT; do
    iptables -t mangle -F "$chain" 2>/dev/null || true
    iptables -t mangle -X "$chain" 2>/dev/null || true
  done

  # 清理策略路由
  ip_rule del fwmark "$MARK" table "$TABLE_ID" 2>/dev/null || true
  ip_route del local default dev lo table "$TABLE_ID" 2>/dev/null || true

  log "INFO" "透明代理规则已清理"
}

################################################################################
# 启动
################################################################################

start() {
  log "INFO" "加载透明代理规则 (端口=$PROXY_PORT, 标记=$MARK, 绕过=$CORE_USER:$CORE_GROUP)..."

  local cidr

  # ── 策略路由 ──
  ip_rule add fwmark "$MARK" table "$TABLE_ID" || {
    log "ERROR" "ip rule add 失败"; return 1
  }
  ip_route add local default dev lo table "$TABLE_ID" || {
    log "ERROR" "ip route add 失败"; return 1
  }
  echo 1 > /proc/sys/net/ipv4/ip_forward

  # ── PREROUTING 链 ──
  safe_chain_create mangle PROXY_PREROUTING

  # 已有连接的回复方向跳过
  iptables -t mangle -A PROXY_PREROUTING -m conntrack --ctdir REPLY -j RETURN

  # 保留地址跳过
  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A PROXY_PREROUTING -d "$cidr" -j RETURN
  done

  # TPROXY 劫持
  iptables -t mangle -A PROXY_PREROUTING -p tcp -j TPROXY \
    --on-port "$PROXY_PORT" --tproxy-mark "$MARK"
  iptables -t mangle -A PROXY_PREROUTING -p udp -j TPROXY \
    --on-port "$PROXY_PORT" --tproxy-mark "$MARK"

  # 挂载到主链（-I 插入最前）
  iptables -t mangle -I PREROUTING -p tcp -j PROXY_PREROUTING
  iptables -t mangle -I PREROUTING -p udp -j PROXY_PREROUTING

  # ── OUTPUT 链 ──
  safe_chain_create mangle PROXY_OUTPUT

  # 已有连接的回复方向跳过
  iptables -t mangle -A PROXY_OUTPUT -m conntrack --ctdir REPLY -j RETURN

  # owner match 绕过代理进程自身流量
  iptables -t mangle -A PROXY_OUTPUT -m owner \
    --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j RETURN

  # 保留地址跳过
  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A PROXY_OUTPUT -d "$cidr" -j RETURN
  done

  # 给剩余流量打标记 → ip rule 重路由到 lo → PREROUTING TPROXY
  iptables -t mangle -A PROXY_OUTPUT -p tcp -j MARK --set-mark "$MARK"
  iptables -t mangle -A PROXY_OUTPUT -p udp -j MARK --set-mark "$MARK"

  # 挂载到主链
  iptables -t mangle -I OUTPUT -p tcp -j PROXY_OUTPUT
  iptables -t mangle -I OUTPUT -p udp -j PROXY_OUTPUT

  # ── 验证 ──
  log "INFO" "透明代理规则已加载，验证中..."
  log "DEBUG" "--- PREROUTING ---"
  command iptables -w 100 -t mangle -L PREROUTING -n 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
  log "DEBUG" "--- PROXY_PREROUTING ---"
  command iptables -w 100 -t mangle -L PROXY_PREROUTING -n 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
  log "DEBUG" "--- OUTPUT ---"
  command iptables -w 100 -t mangle -L OUTPUT -n 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
  log "DEBUG" "--- PROXY_OUTPUT ---"
  command iptables -w 100 -t mangle -L PROXY_OUTPUT -n 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
  log "DEBUG" "--- ip rule ---"
  command ip rule show 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done

  log "INFO" "透明代理启动完成"
}

################################################################################
# 入口
################################################################################

main() {
  local cmd="${1:-}"

  case "$cmd" in
    start)
      setup_env
      cleanup
      start
      ;;
    stop)
      setup_env
      cleanup
      ;;
    restart)
      setup_env
      cleanup
      sleep 1
      start
      ;;
    *)
      echo "用法: $0 {start|stop|restart}"
      exit 1
      ;;
  esac
}

main "$@"
