#!/system/bin/sh
# TProxy 透明代理网络规则管理
# 参考 NetProxy-Magisk 实现
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ TPROXY 透明代理数据流                                              │
# │                                                                     │
# │ 【本机出站流量】                                                    │
# │   App → OUTPUT → PROXY_OUTPUT                                       │
# │         ├─ conntrack REPLY 方向 → 跳过（已有连接的回包）            │
# │         ├─ owner match 代理进程 → 跳过（防止回环）                  │
# │         ├─ 目标为保留地址 → 跳过（局域网/回环等）                   │
# │         └─ 其余流量 → MARK 打标记                                   │
# │              ↓                                                      │
# │   ip rule: fwmark → 路由表 → local default dev lo                   │
# │              ↓                                                      │
# │   流量重路由到 lo → 重新进入 PREROUTING                             │
# │                                                                     │
# │ 【PREROUTING（含重路由和外部入站）】                                │
# │   → PROXY_PREROUTING                                                │
# │     ├─ conntrack REPLY 方向 → 跳过                                  │
# │     ├─ 目标为保留地址 → 跳过                                        │
# │     └─ 其余流量 → TPROXY 劫持到代理端口                             │
# │              ↓                                                      │
# │   Xray (端口 PROXY_PORT) 处理流量                                   │
# └─────────────────────────────────────────────────────────────────────┘

set -u

export TZ=Asia/Shanghai

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

################################################################################
# 常量
################################################################################

# 代理进程用户/组（与 service.sh 中 setuidgid 一致）
readonly CORE_USER="root"
readonly CORE_GROUP="net_admin"

readonly PROXY_PORT="12345"

# fwmark 标记值，ip rule 据此将流量导入自定义路由表
readonly MARK=20
readonly TABLE_ID=100

# RFC 保留地址段 — 这些地址不应走代理
# 包括：回环、私有网段（RFC1918）、运营商级NAT（RFC6598）、
# 链路本地、组播、保留实验段等
readonly RESERVED_IPV4="\
0.0.0.0/8 \
10.0.0.0/8 \
100.64.0.0/10 \
127.0.0.0/8 \
169.254.0.0/16 \
172.16.0.0/12 \
192.0.0.0/24 \
192.168.0.0/16 \
224.0.0.0/4 \
240.0.0.0/4 \
255.255.255.255/32"

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
# iptables / ip 命令封装
# 统一添加 -w 100 等待锁，并记录调试日志
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
# 如果链已存在则仅清空规则，不报错
################################################################################

safe_chain_create() {
  local table="$1" chain="$2"
  iptables -t "$table" -N "$chain" 2>/dev/null || true
  iptables -t "$table" -F "$chain"
}

################################################################################
# 清理 — 移除所有透明代理规则，恢复干净状态
################################################################################

cleanup() {
  log "INFO" "清理透明代理规则..."

  # 从主链摘除跳转
  iptables -t mangle -D PREROUTING -p tcp -j PROXY_PREROUTING 2>/dev/null || true
  iptables -t mangle -D PREROUTING -p udp -j PROXY_PREROUTING 2>/dev/null || true
  iptables -t mangle -D OUTPUT -p tcp -j PROXY_OUTPUT 2>/dev/null || true
  iptables -t mangle -D OUTPUT -p udp -j PROXY_OUTPUT 2>/dev/null || true

  # 清空并删除自定义子链
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
# 启动 — 分为三个阶段：策略路由 → PREROUTING 链 → OUTPUT 链
################################################################################

# 阶段 1: 策略路由
# 将带有 fwmark 标记的流量导入自定义路由表，
# 路由表将流量发回 lo，使其重新经过 PREROUTING 被 TPROXY 劫持
setup_routing() {
  log "INFO" "配置策略路由 (fwmark=$MARK → table=$TABLE_ID → lo)..."

  ip_rule add fwmark "$MARK" table "$TABLE_ID" || {
    log "ERROR" "ip rule add 失败"; return 1
  }
  ip_route add local default dev lo table "$TABLE_ID" || {
    log "ERROR" "ip route add 失败"; return 1
  }
  echo 1 > /proc/sys/net/ipv4/ip_forward
}

# 阶段 2: PREROUTING 链
# 处理从外部到达或经策略路由重路由回来的流量
setup_prerouting_chain() {
  log "INFO" "配置 PREROUTING 链..."
  local cidr

  safe_chain_create mangle PROXY_PREROUTING

  iptables -t mangle -A PROXY_PREROUTING -m conntrack --ctdir REPLY -j RETURN

  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A PROXY_PREROUTING -d "$cidr" -j RETURN
  done

  iptables -t mangle -A PROXY_PREROUTING -p tcp -j TPROXY \
    --on-port "$PROXY_PORT" --tproxy-mark "$MARK"
  iptables -t mangle -A PROXY_PREROUTING -p udp -j TPROXY \
    --on-port "$PROXY_PORT" --tproxy-mark "$MARK"

  iptables -t mangle -I PREROUTING -p tcp -j PROXY_PREROUTING
  iptables -t mangle -I PREROUTING -p udp -j PROXY_PREROUTING
}

# 阶段 3: OUTPUT 链
# 处理本机出站流量，给需要代理的流量打标记
setup_output_chain() {
  log "INFO" "配置 OUTPUT 链..."
  local cidr

  safe_chain_create mangle PROXY_OUTPUT

  iptables -t mangle -A PROXY_OUTPUT -m conntrack --ctdir REPLY -j RETURN

  # 绕过代理进程自身流量，防止回环
  iptables -t mangle -A PROXY_OUTPUT -m owner \
    --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j RETURN

  for cidr in $RESERVED_IPV4; do
    iptables -t mangle -A PROXY_OUTPUT -d "$cidr" -j RETURN
  done

  # 剩余流量打标记 → 经 ip rule 重路由到 lo → 回到 PREROUTING → TPROXY
  iptables -t mangle -A PROXY_OUTPUT -p tcp -j MARK --set-mark "$MARK"
  iptables -t mangle -A PROXY_OUTPUT -p udp -j MARK --set-mark "$MARK"

  iptables -t mangle -I OUTPUT -p tcp -j PROXY_OUTPUT
  iptables -t mangle -I OUTPUT -p udp -j PROXY_OUTPUT
}

# 验证 — 输出当前 iptables 和路由规则用于调试
verify_rules() {
  log "INFO" "透明代理规则已加载，验证中..."

  local chain_name
  for chain_name in PREROUTING PROXY_PREROUTING OUTPUT PROXY_OUTPUT; do
    log "DEBUG" "--- $chain_name ---"
    command iptables -w 100 -t mangle -L "$chain_name" -n 2>&1 | while IFS= read -r line; do
      log "DEBUG" "  $line"
    done
  done

  log "DEBUG" "--- ip rule ---"
  command ip rule show 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
}

start() {
  log "INFO" "加载透明代理规则 (端口=$PROXY_PORT, 标记=$MARK, 绕过=$CORE_USER:$CORE_GROUP)..."

  setup_routing || return 1
  setup_prerouting_chain
  setup_output_chain
  verify_rules

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
