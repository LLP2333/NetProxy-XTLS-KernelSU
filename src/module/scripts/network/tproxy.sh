#!/system/bin/sh
# TProxy 透明代理网络规则管理
# 通过 iptables mangle 表 + ip rule/route 实现 TPROXY 流量劫持

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly MODULE_CONF="$MODDIR/config/module.conf"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

TPROXY_PORT="$(read_conf "$MODULE_CONF" "TPROXY_PORT" "12345")"
FWMARK="$(read_conf "$MODULE_CONF" "FWMARK" "255")"

readonly TABLE_ID=100
readonly IPV4_CHAIN="XRAY"
readonly IPV4_CHAIN_OUTPUT="XRAY_SELF"

readonly RESERVED_IPV4="
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.168.0.0/16
    224.0.0.0/4
    240.0.0.0/4
    255.255.255.255/32
"

################################################################################
# iptables 规则
################################################################################

flush_rules() {
  iptables -t mangle -D PREROUTING -j "$IPV4_CHAIN" 2> /dev/null
  iptables -t mangle -F "$IPV4_CHAIN" 2> /dev/null
  iptables -t mangle -X "$IPV4_CHAIN" 2> /dev/null

  iptables -t mangle -D OUTPUT -j "$IPV4_CHAIN_OUTPUT" 2> /dev/null
  iptables -t mangle -F "$IPV4_CHAIN_OUTPUT" 2> /dev/null
  iptables -t mangle -X "$IPV4_CHAIN_OUTPUT" 2> /dev/null

  ip rule del fwmark "$FWMARK" table "$TABLE_ID" 2> /dev/null
  ip route del local default dev lo table "$TABLE_ID" 2> /dev/null
}

apply_rules() {
  local cidr

  # 策略路由：被标记的包走本地回环，触发 PREROUTING 链
  ip rule add fwmark "$FWMARK" table "$TABLE_ID"
  ip route add local default dev lo table "$TABLE_ID"

  # ── PREROUTING 链：对进入的流量做 TPROXY ──
  iptables -t mangle -N "$IPV4_CHAIN"

  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A "$IPV4_CHAIN" -d "$cidr" -j RETURN
  done

  iptables -t mangle -A "$IPV4_CHAIN" -p tcp -j TPROXY \
    --on-port "$TPROXY_PORT" --tproxy-mark "$FWMARK"
  iptables -t mangle -A "$IPV4_CHAIN" -p udp -j TPROXY \
    --on-port "$TPROXY_PORT" --tproxy-mark "$FWMARK"

  iptables -t mangle -A PREROUTING -j "$IPV4_CHAIN"

  # ── OUTPUT 链：拦截本机发出的流量 ──
  iptables -t mangle -N "$IPV4_CHAIN_OUTPUT"

  # Xray 自身标记的包直接放行，防止回环
  iptables -t mangle -A "$IPV4_CHAIN_OUTPUT" -m mark --mark "$FWMARK" -j RETURN

  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A "$IPV4_CHAIN_OUTPUT" -d "$cidr" -j RETURN
  done

  # 给剩余流量打标记 → 触发 re-route → 进入 PREROUTING 的 TPROXY
  iptables -t mangle -A "$IPV4_CHAIN_OUTPUT" -p tcp -j MARK --set-mark "$FWMARK"
  iptables -t mangle -A "$IPV4_CHAIN_OUTPUT" -p udp -j MARK --set-mark "$FWMARK"

  iptables -t mangle -A OUTPUT -j "$IPV4_CHAIN_OUTPUT"
}

################################################################################
# 入口
################################################################################

do_start() {
  log "INFO" "加载透明代理规则 (端口=$TPROXY_PORT, 标记=$FWMARK)..."
  flush_rules
  apply_rules
  log "INFO" "透明代理规则已加载"
}

do_stop() {
  log "INFO" "清理透明代理规则..."
  flush_rules
  log "INFO" "透明代理规则已清理"
}

case "${1:-}" in
  start) do_start ;;
  stop) do_stop ;;
  restart) do_stop; do_start ;;
  *)
    echo "用法: $0 {start|stop|restart}"
    exit 1
    ;;
esac
