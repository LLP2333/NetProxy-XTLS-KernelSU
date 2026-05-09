#!/system/bin/sh
# TProxy 透明代理网络规则管理
# 参考 NetProxy-Magisk 实现
# 核心原理：iptables mangle TPROXY + owner match 绕过 + ip rule 策略路由

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly MODULE_CONF="$MODDIR/config/module.conf"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

TPROXY_PORT="$(read_conf "$MODULE_CONF" "TPROXY_PORT" "12345")"

# 代理进程的用户和组（与 service.sh 中 setuidgid 一致）
readonly CORE_USER="root"
readonly CORE_GROUP="net_admin"

# 内部路由标记（仅 iptables/ip rule 使用，Xray 配置无需设置 sockopt.mark）
readonly MARK=20
readonly TABLE_ID=100

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

ipt() {
  command iptables -w 100 "$@"
}

################################################################################
# 规则管理
################################################################################

flush_rules() {
  ipt -t mangle -D PREROUTING -p tcp -j XRAY 2> /dev/null
  ipt -t mangle -D PREROUTING -p udp -j XRAY 2> /dev/null
  ipt -t mangle -F XRAY 2> /dev/null
  ipt -t mangle -X XRAY 2> /dev/null

  ipt -t mangle -D OUTPUT -p tcp -j XRAY_SELF 2> /dev/null
  ipt -t mangle -D OUTPUT -p udp -j XRAY_SELF 2> /dev/null
  ipt -t mangle -F XRAY_SELF 2> /dev/null
  ipt -t mangle -X XRAY_SELF 2> /dev/null

  ip rule del fwmark "$MARK" table "$TABLE_ID" 2> /dev/null
  ip route del local default dev lo table "$TABLE_ID" 2> /dev/null
}

apply_rules() {
  local cidr

  # ── 策略路由 ──
  ip rule add fwmark "$MARK" table "$TABLE_ID"
  ip route add local default dev lo table "$TABLE_ID"
  echo 1 > /proc/sys/net/ipv4/ip_forward

  # ── PREROUTING：对进入的流量做 TPROXY ──
  ipt -t mangle -N XRAY

  # 跳过已建立连接的回复方向包
  ipt -t mangle -A XRAY -m conntrack --ctdir REPLY -j RETURN

  for cidr in $RESERVED_IPV4; do
    ipt -t mangle -A XRAY -d "$cidr" -j RETURN
  done

  ipt -t mangle -A XRAY -p tcp -j TPROXY \
    --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"
  ipt -t mangle -A XRAY -p udp -j TPROXY \
    --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"

  ipt -t mangle -A PREROUTING -p tcp -j XRAY
  ipt -t mangle -A PREROUTING -p udp -j XRAY

  # ── OUTPUT：拦截本机流量 ──
  ipt -t mangle -N XRAY_SELF

  # 跳过已建立连接的回复方向包
  ipt -t mangle -A XRAY_SELF -m conntrack --ctdir REPLY -j RETURN

  # 通过 owner match 绕过代理进程自身流量，防止回环
  ipt -t mangle -A XRAY_SELF -m owner \
    --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j RETURN

  for cidr in $RESERVED_IPV4; do
    ipt -t mangle -A XRAY_SELF -d "$cidr" -j RETURN
  done

  # 给剩余流量打标记 → 触发 ip rule 重路由到 lo → 进入 PREROUTING 的 TPROXY
  ipt -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark "$MARK"
  ipt -t mangle -A XRAY_SELF -p udp -j MARK --set-mark "$MARK"

  ipt -t mangle -A OUTPUT -p tcp -j XRAY_SELF
  ipt -t mangle -A OUTPUT -p udp -j XRAY_SELF
}

################################################################################
# 入口
################################################################################

do_start() {
  log "INFO" "加载透明代理规则 (端口=$TPROXY_PORT, 标记=$MARK, 绕过=$CORE_USER:$CORE_GROUP)..."
  flush_rules
  if apply_rules; then
    log "INFO" "透明代理规则已加载"
  else
    log "ERROR" "透明代理规则加载失败"
    flush_rules
    return 1
  fi
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
