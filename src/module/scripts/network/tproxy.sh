#!/system/bin/sh
# TProxy 透明代理网络规则管理（IPv4 + IPv6）
# 参考 NetProxy-Magisk 旧版 iptables 实现（AndroidTProxyShell）
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ TPROXY 透明代理数据流（iptables / ip6tables 各一套，结构相同）     │
# │                                                                     │
# │ 【本机出站流量】                                                    │
# │   App → OUTPUT → PROXY_OUTPUT                                       │
# │         ├─ conntrack REPLY 方向 → 跳过（已有连接的回包）            │
# │         ├─ owner match 代理进程 → 跳过（防止回环）                  │
# │         ├─ 目标为保留地址 → 跳过（发往局域网的 DNS 除外）           │
# │         ├─ PROXY_APP 分应用黑/白名单 → 不代理的应用跳过             │
# │         └─ 其余流量 → MARK 打标记                                   │
# │              ↓                                                      │
# │   ip rule: fwmark → 路由表 → local default dev lo                   │
# │              ↓                                                      │
# │   流量重路由到 lo → 重新进入 PREROUTING                             │
# │                                                                     │
# │ 【PREROUTING（lo 重路由 + 热点/USB 共享下游）】                     │
# │   → PROXY_PREROUTING                                                │
# │     ├─ conntrack REPLY 方向 → 跳过                                  │
# │     ├─ 目标为保留地址 → 跳过（发往局域网的 DNS 除外）               │
# │     ├─ 入接口为 lo 或共享接口 → PROXY_TPROXY                        │
# │     └─ 其他接口（上游入站） → 跳过                                  │
# │              ↓                                                      │
# │   Xray (端口 TPROXY_PORT) 处理流量                                  │
# └─────────────────────────────────────────────────────────────────────┘
#
# 规则通过 iptables-restore --noflush 一次性提交：同一地址族的规则
# 要么全部生效、要么全部不生效，不会留下加了一半的规则。

set -u

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
readonly MODDIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly RUN_DIR="$MODDIR/run"
readonly PACKAGES_LIST="/data/system/packages.list"

. "$MODDIR/scripts/utils/config.sh"

################################################################################
# 常量
################################################################################

# 代理进程用户/组（与 service.sh 中 setuidgid 一致）
readonly CORE_USER="root"
readonly CORE_GROUP="net_admin"

# fwmark 标记值，ip rule 据此将流量导入自定义路由表
readonly MARK=20
readonly TABLE_ID=100
# ip rule 优先级：需小于 Android netd 规则（从 10000 开始），确保先于系统规则匹配
readonly RULE_PREF=9000

readonly DEFAULT_TPROXY_PORT=12345
readonly DEFAULT_HOTSPOT_INTERFACES="wlan2 ap+ swlan0 rndis+ ncm+"

# 回环地址：完全绕过，包括 DNS
readonly LOOPBACK_IPV4="127.0.0.0/8"
readonly LOOPBACK_IPV6="::1/128"

# RFC 保留地址段 — 不走代理，但 UDP 53 仍然劫持，
# 否则连 WiFi 后发往路由器的 DNS 会绕过 Xray 的 dns-out
readonly RESERVED_IPV4="\
0.0.0.0/8 \
10.0.0.0/8 \
100.64.0.0/10 \
169.254.0.0/16 \
172.16.0.0/12 \
192.0.0.0/24 \
192.168.0.0/16 \
224.0.0.0/4 \
240.0.0.0/4 \
255.255.255.255/32"

# 含 NAT64 前缀 64:ff9b::/96：464XLAT 下 clatd 转换后的流量不重复处理
readonly RESERVED_IPV6="\
::/128 \
::ffff:0:0/96 \
64:ff9b::/96 \
100::/64 \
2001:db8::/32 \
fc00::/7 \
fe80::/10 \
ff00::/8"

# 本脚本创建的全部自定义链（清理时无论配置如何都全部尝试删除）
readonly CHAINS="PROXY_PREROUTING PROXY_OUTPUT PROXY_TPROXY PROXY_APP"
# 旧版本遗留的链，仅用于清理
readonly LEGACY_CHAINS="PROXY_DIVERT"

################################################################################
# 日志
# DEBUG 级别只在 module.conf 设置 LOG_LEVEL=debug 时输出
################################################################################

DEBUG_LOG=0

log() {
  local level="$1" message="$2"
  local ts

  [ "$level" = "DEBUG" ] && [ "$DEBUG_LOG" != "1" ] && return 0
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')"
  printf '%s\n' "[$ts] [$level] $message" >&2
}

################################################################################
# iptables / ip 命令封装
################################################################################

# 按地址族执行 iptables / ip6tables，统一添加 -w 100 等待 xtables 锁
ipt() {
  local family="$1"
  shift
  log "DEBUG" "[EXEC] ip${family#4}tables -w 100 $*"
  if [ "$family" = "6" ]; then
    command ip6tables -w 100 "$@"
  else
    command iptables -w 100 "$@"
  fi
}

# 按地址族执行 ip / ip -6
ipcmd() {
  local family="$1"
  shift
  log "DEBUG" "[EXEC] ip -$family $*"
  command ip "-$family" "$@"
}

# 按地址族执行 iptables-restore / ip6tables-restore（从标准输入读取规则）
ipt_restore() {
  local family="$1"
  local cmd="iptables-restore"

  [ "$family" = "6" ] && cmd="ip6tables-restore"
  # 旧版 iptables-restore（< 1.6.2）不支持 -w
  if "$cmd" --help 2>&1 | grep -q -- '--wait'; then
    command "$cmd" -w 100 --noflush
  else
    command "$cmd" --noflush
  fi
}

################################################################################
# 配置
################################################################################

# 只接受 0/1，其他值回退默认值
read_switch() {
  local value
  value="$(read_conf "$MODULE_CONF" "$1" "$2")"
  case "$value" in
    0 | 1) printf '%s' "$value" ;;
    *) printf '%s' "$2" ;;
  esac
}

load_log_level() {
  [ "$(read_conf "$MODULE_CONF" "LOG_LEVEL" "info")" = "debug" ] && DEBUG_LOG=1
  return 0
}

load_config() {
  TPROXY_PORT="$(read_conf "$MODULE_CONF" "TPROXY_PORT" "$DEFAULT_TPROXY_PORT")"
  case "$TPROXY_PORT" in
    '' | *[!0-9]*)
      log "WARN" "TPROXY_PORT 无效（${TPROXY_PORT}），使用默认值 $DEFAULT_TPROXY_PORT"
      TPROXY_PORT="$DEFAULT_TPROXY_PORT"
      ;;
  esac

  PROXY_IPV6="$(read_switch "PROXY_IPV6" 1)"
  PROXY_HOTSPOT="$(read_switch "PROXY_HOTSPOT" 1)"
  HOTSPOT_INTERFACES="$(read_conf "$MODULE_CONF" "HOTSPOT_INTERFACES" "$DEFAULT_HOTSPOT_INTERFACES")"

  APP_PROXY_MODE="$(read_conf "$MODULE_CONF" "APP_PROXY_MODE" "off")"
  case "$APP_PROXY_MODE" in
    off | blacklist | whitelist) ;;
    *)
      log "WARN" "APP_PROXY_MODE 无效（${APP_PROXY_MODE}），按 off 处理"
      APP_PROXY_MODE="off"
      ;;
  esac
  APP_PROXY_LIST="$(read_conf "$MODULE_CONF" "APP_PROXY_LIST" "" | tr ',' ' ')"
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
  for cmd in ip iptables iptables-restore; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR" "缺少必要命令: $cmd (PATH=$PATH)"
      exit 1
    fi
  done

  HAS_IP6TABLES=0
  command -v ip6tables >/dev/null 2>&1 && command -v ip6tables-restore >/dev/null 2>&1 && HAS_IP6TABLES=1

  mkdir -p "$RUN_DIR" 2>/dev/null || true
  load_log_level
}

################################################################################
# 分应用代理：把 [用户ID:]包名 解析为 UID
# UID = 用户ID * 100000 + appId，appId 取自 packages.list 第 2 列
################################################################################

resolve_app_uids() {
  [ -n "$APP_PROXY_LIST" ] || return 0

  if [ ! -r "$PACKAGES_LIST" ]; then
    log "WARN" "无法读取 ${PACKAGES_LIST}，分应用代理未生效"
    return 0
  fi

  awk -v tokens="$APP_PROXY_LIST" '
    BEGIN {
      n = split(tokens, list, " ")
      for (i = 1; i <= n; i++) {
        if (list[i] ~ /:/) { split(list[i], p, ":"); user[i] = p[1]; pkg[i] = p[2] }
        else { user[i] = 0; pkg[i] = list[i] }
        wanted[pkg[i]] = 1
      }
    }
    ($1 in wanted) && $2 ~ /^[0-9]+$/ { appid[$1] = $2 }
    END {
      for (i = 1; i <= n; i++) {
        if (pkg[i] in appid) print user[i] * 100000 + appid[pkg[i]]
        else print "missing:" user[i] ":" pkg[i] > "/dev/stderr"
      }
    }
  ' "$PACKAGES_LIST" 2>"$APP_MISSING_FILE"
}

################################################################################
# 清理 — 移除所有透明代理规则，恢复干净状态
# 不依赖当前配置：两个地址族、所有链都尝试删除，避免改配置后残留
################################################################################

# 当前地址族是否存在本脚本创建的链（不存在时跳过逐条删除，加快启动）
has_proxy_chains() {
  ipt "$1" -t mangle -S 2>/dev/null | grep -q -E -- '^-N PROXY_'
}

cleanup_family() {
  local family="$1" chain proto i

  if has_proxy_chains "$family"; then
    for proto in tcp udp; do
      ipt "$family" -t mangle -D PREROUTING -p "$proto" -j PROXY_PREROUTING 2>/dev/null || true
      ipt "$family" -t mangle -D OUTPUT -p "$proto" -j PROXY_OUTPUT 2>/dev/null || true
    done
    for chain in $CHAINS $LEGACY_CHAINS; do
      ipt "$family" -t mangle -F "$chain" 2>/dev/null || true
    done
    for chain in $CHAINS $LEGACY_CHAINS; do
      ipt "$family" -t mangle -X "$chain" 2>/dev/null || true
    done
  fi

  # 旧版本添加的规则没有 pref，逐条删除直到不存在（最多 10 次防止死循环）
  i=0
  while [ "$i" -lt 10 ] && ipcmd "$family" rule del fwmark "$MARK" table "$TABLE_ID" 2>/dev/null; do
    i=$((i + 1))
  done
  if [ "$family" = "6" ]; then
    ipcmd 6 route del local ::/0 dev lo table "$TABLE_ID" 2>/dev/null || true
  else
    ipcmd 4 route del local default dev lo table "$TABLE_ID" 2>/dev/null || true
  fi
}

cleanup() {
  log "INFO" "清理透明代理规则..."
  cleanup_family 4
  [ "$HAS_IP6TABLES" = "1" ] && cleanup_family 6
  log "INFO" "透明代理规则已清理"
}

################################################################################
# 规则生成（iptables-restore 格式）
################################################################################

# 保留地址绕过：回环完全跳过，其余保留段只放行非 DNS 流量
emit_reserved_bypass() {
  local family="$1" chain="$2" loopback reserved cidr

  if [ "$family" = "6" ]; then
    loopback="$LOOPBACK_IPV6"
    reserved="$RESERVED_IPV6"
  else
    loopback="$LOOPBACK_IPV4"
    reserved="$RESERVED_IPV4"
  fi

  echo "-A $chain -d $loopback -j RETURN"
  for cidr in $reserved; do
    echo "-A $chain -d $cidr -p tcp -j RETURN"
    echo "-A $chain -d $cidr -p udp ! --dport 53 -j RETURN"
  done
}

build_rules() {
  local family="$1" chain iface uid

  echo "*mangle"
  for chain in $CHAINS; do
    echo ":$chain - [0:0]"
  done

  # 实际的 TPROXY 目标
  echo "-A PROXY_TPROXY -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $MARK"
  echo "-A PROXY_TPROXY -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $MARK"

  # PREROUTING：只劫持 lo（本机重路由回来的流量）和共享网络下游接口
  echo "-A PROXY_PREROUTING -m conntrack --ctdir REPLY -j RETURN"
  emit_reserved_bypass "$family" PROXY_PREROUTING
  echo "-A PROXY_PREROUTING -i lo -j PROXY_TPROXY"
  if [ "$PROXY_HOTSPOT" = "1" ]; then
    for iface in $HOTSPOT_INTERFACES; do
      echo "-A PROXY_PREROUTING -i $iface -j PROXY_TPROXY"
    done
  fi

  # 分应用链：ACCEPT 表示不代理（结束 mangle OUTPUT 处理），RETURN 表示继续打标记
  if [ "$APP_PROXY_MODE" != "off" ]; then
    for uid in $APP_UIDS; do
      if [ "$APP_PROXY_MODE" = "blacklist" ]; then
        echo "-A PROXY_APP -m owner --uid-owner $uid -j ACCEPT"
      else
        echo "-A PROXY_APP -m owner --uid-owner $uid -j RETURN"
      fi
    done
    [ "$APP_PROXY_MODE" = "whitelist" ] && echo "-A PROXY_APP -j ACCEPT"
  fi

  # OUTPUT：本机出站流量，需要代理的打标记
  echo "-A PROXY_OUTPUT -m conntrack --ctdir REPLY -j RETURN"
  # 绕过代理进程自身流量，防止回环
  echo "-A PROXY_OUTPUT -m owner --uid-owner $CORE_USER --gid-owner $CORE_GROUP -j RETURN"
  emit_reserved_bypass "$family" PROXY_OUTPUT
  echo "-A PROXY_OUTPUT -j PROXY_APP"
  # 剩余流量打标记 → 经 ip rule 重路由到 lo → 回到 PREROUTING → TPROXY
  echo "-A PROXY_OUTPUT -j MARK --set-mark $MARK"

  # 挂入主链
  echo "-I PREROUTING -p tcp -j PROXY_PREROUTING"
  echo "-I PREROUTING -p udp -j PROXY_PREROUTING"
  echo "-I OUTPUT -p tcp -j PROXY_OUTPUT"
  echo "-I OUTPUT -p udp -j PROXY_OUTPUT"

  echo "COMMIT"
}

################################################################################
# 启动 — 每个地址族：一次性提交规则 → 策略路由
################################################################################

# 策略路由
# 将带有 fwmark 标记的流量导入自定义路由表，
# 路由表将流量发回 lo，使其重新经过 PREROUTING 被 TPROXY 劫持
setup_routing() {
  local family="$1"

  log "INFO" "IPv$family: 配置策略路由 (fwmark=$MARK → table=$TABLE_ID → lo, pref=$RULE_PREF)..."

  ipcmd "$family" rule add fwmark "$MARK" table "$TABLE_ID" pref "$RULE_PREF" || {
    log "ERROR" "IPv$family: ip rule add 失败"; return 1
  }
  if [ "$family" = "6" ]; then
    ipcmd 6 route add local ::/0 dev lo table "$TABLE_ID"
  else
    ipcmd 4 route add local default dev lo table "$TABLE_ID"
  fi || {
    log "ERROR" "IPv$family: ip route add 失败"; return 1
  }
}

setup_family() {
  local family="$1"
  local rules_file="$RUN_DIR/tproxy_rules.v$family"
  local err

  build_rules "$family" > "$rules_file"
  log "DEBUG" "IPv$family: 规则文件 $rules_file（$(wc -l < "$rules_file" | tr -d ' ') 行）"

  # 任何一条规则不被内核支持（如缺少 IPv6 TPROXY）时整体失败，不会留下部分规则
  if ! err="$(ipt_restore "$family" < "$rules_file" 2>&1)"; then
    log "ERROR" "IPv$family: 规则提交失败: ${err:-未知错误}"
    return 1
  fi

  setup_routing "$family"
}

# 验证 — 输出当前 iptables 和路由规则用于调试（仅 LOG_LEVEL=debug）
verify_rules() {
  local family="$1" chain_name line

  [ "$DEBUG_LOG" = "1" ] || return 0
  for chain_name in PREROUTING PROXY_PREROUTING OUTPUT PROXY_OUTPUT PROXY_APP; do
    log "DEBUG" "--- IPv$family $chain_name ---"
    ipt "$family" -t mangle -L "$chain_name" -n 2>&1 | while IFS= read -r line; do
      log "DEBUG" "  $line"
    done
  done

  log "DEBUG" "--- ip -$family rule ---"
  command ip "-$family" rule show 2>&1 | while IFS= read -r line; do
    log "DEBUG" "  $line"
  done
}

start() {
  local line

  load_config

  APP_UIDS=""
  APP_MISSING_FILE="$RUN_DIR/app_missing.$$"
  if [ "$APP_PROXY_MODE" != "off" ]; then
    APP_UIDS="$(resolve_app_uids | sort -un | tr '\n' ' ' | sed 's/ *$//')"
    if [ -s "$APP_MISSING_FILE" ]; then
      while IFS= read -r line; do
        log "WARN" "分应用: 未找到应用 ${line#missing:}"
      done < "$APP_MISSING_FILE"
    fi
    rm -f "$APP_MISSING_FILE"
    log "INFO" "分应用代理: $APP_PROXY_MODE（UID: ${APP_UIDS:-无}）"
    if [ "$APP_PROXY_MODE" = "whitelist" ] && [ -z "$APP_UIDS" ]; then
      log "WARN" "白名单为空，本机应用流量都不会被代理"
    fi
  fi

  log "INFO" "加载透明代理规则 (端口=$TPROXY_PORT, 标记=$MARK, IPv6=$PROXY_IPV6, 共享网络=$PROXY_HOTSPOT, 绕过=$CORE_USER:$CORE_GROUP)..."
  [ "$PROXY_HOTSPOT" = "1" ] && log "INFO" "共享网络接口: $HOTSPOT_INTERFACES"

  if ! setup_family 4; then
    cleanup_family 4
    return 1
  fi
  verify_rules 4
  log "INFO" "IPv4: 透明代理规则已加载"

  if [ "$PROXY_IPV6" = "1" ]; then
    if [ "$HAS_IP6TABLES" != "1" ]; then
      log "WARN" "缺少 ip6tables / ip6tables-restore，IPv6 流量不会被代理"
    elif setup_family 6; then
      verify_rules 6
      log "INFO" "IPv6: 透明代理规则已加载"
    else
      cleanup_family 6
      log "WARN" "IPv6 透明代理加载失败，已回滚；IPv6 流量不会被代理"
    fi
  else
    log "INFO" "PROXY_IPV6=0，IPv6 流量不经过代理"
  fi

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
