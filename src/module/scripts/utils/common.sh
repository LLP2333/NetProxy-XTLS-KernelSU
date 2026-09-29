#!/system/bin/sh
# 通用辅助函数
# 被 service.sh、customize.sh、action.sh 等脚本 source 引用
# 依赖调用方预先设置 LOG_FILE 变量

#######################################
# 写入标准日志
# 支持两种调用方式:
#   log "消息"              → 默认 INFO 级别
#   log "LEVEL" "消息"      → 指定级别
# 输出目标:
#   LOG_FILE 不为空时追加写入文件
#   LOG_STDERR != 0 时同时输出到 stderr
#######################################
log() {
  local level="INFO"
  local message="$1"
  local timestamp log_content

  if [ $# -ge 2 ]; then
    level="$1"
    message="$2"
  fi

  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  log_content="[$timestamp] [$level] $message"

  [ -n "${LOG_FILE:-}" ] && printf "%s\n" "$log_content" >> "$LOG_FILE"
  [ "${LOG_STDERR:-1}" = "0" ] || printf "%s\n" "$log_content" >&2
}

#######################################
# 记录错误并退出
#######################################
die() {
  log "ERROR" "$1"
  exit "${2:-1}"
}

#######################################
# 检测 busybox 路径
# 按 KernelSU → APatch → Magisk 的优先级查找，
# 都找不到时回退到 PATH 中的 busybox
#######################################
detect_busybox() {
  local path

  for path in "/data/adb/ksu/bin/busybox" "/data/adb/ap/bin/busybox" "/data/adb/magisk/busybox"; do
    if [ -x "$path" ]; then
      printf "%s\n" "$path"
      return 0
    fi
  done

  printf "%s\n" "busybox"
}

#######################################
# 判断命令是否存在
#######################################
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

#######################################
# 检查文件是否存在
#######################################
require_file() {
  local file="$1"
  local message="${2:-文件不存在: $file}"

  [ -f "$file" ] || die "$message"
}

#######################################
# 检查目录是否存在
#######################################
require_dir() {
  local dir="$1"
  local message="${2:-目录不存在: $dir}"

  [ -d "$dir" ] || die "$message"
}

#######################################
# 创建目录
#######################################
ensure_dir() {
  local dir="$1"
  local message="${2:-无法创建目录: $dir}"

  [ -d "$dir" ] || mkdir -p "$dir" || die "$message"
}

#######################################
# 转义 JSON 字符串
#######################################
json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

#######################################
# 获取指定进程的 PID
# pidof -s 只返回单个 PID，适合守护进程查询；
# 部分精简系统无 pidof，用 pgrep 作为 fallback
#######################################
get_pid() {
  local bin="$1"

  [ -n "$bin" ] || return 1
  pidof -s "$bin" 2> /dev/null || pgrep -f "^$bin" 2> /dev/null | head -1 || true
}

#######################################
# 获取指定 PID 的运行时间（秒）
# 通过 /proc/<pid>/stat 第 22 个字段（starttime，
# 单位为 clock ticks）与系统 uptime 做差计算
#######################################
get_process_uptime() {
  local pid="$1"
  local start_time now_ticks

  [ -n "$pid" ] || { printf "0\n"; return 1; }
  [ -d "/proc/$pid" ] || { printf "0\n"; return 1; }

  # $22 = starttime (clock ticks since boot)
  start_time="$(awk '{print $22}' "/proc/$pid/stat" 2> /dev/null || echo 0)"
  # /proc/uptime 第一个字段为秒，乘 100 转换为 centiseconds 对齐
  now_ticks="$(awk '{print int($1 * 100)}' /proc/uptime 2> /dev/null || echo 0)"

  if [ "$start_time" -gt 0 ] && [ "$now_ticks" -gt 0 ]; then
    printf "%s\n" "$(( (now_ticks - start_time) / 100 ))"
  else
    printf "0\n"
  fi
}

#######################################
# 检测设备主要 IPv4 地址
#######################################
detect_primary_ipv4() {
  ip route get 1.1.1.1 2> /dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1
}

#######################################
# 日志截断：文件超过上限（字节）时就地只保留后半部分
# 不生成 .1 备份，保证日志文件数量不增加；写回同一个 inode，
# 正以 O_APPEND 写入该文件的进程（Xray）不受影响
#######################################
trim_log() {
  local file="$1"
  local max="${2:-1048576}"
  local size

  [ -f "$file" ] || return 0
  size="$(wc -c < "$file" 2> /dev/null | tr -d ' ')"
  [ "${size:-0}" -gt "$max" ] || return 0
  # 丢弃截断处不完整的第一行
  tail -c $((max / 2)) "$file" 2> /dev/null | sed '1d' > "$file.trim" \
    && cat "$file.trim" > "$file"
  rm -f "$file.trim"
}

# 各日志的大小上限（字节）
LOG_LIMIT_SERVICE=1048576
LOG_LIMIT_XRAY=2097152
LOG_LIMIT_ACCESS=5242880

#######################################
# 按上限截断模块的全部日志（需先调用 resolve_xray_log_files）
#######################################
trim_module_logs() {
  local service_log="$1"

  trim_log "$service_log" "$LOG_LIMIT_SERVICE"
  trim_log "$XRAY_STDOUT_LOG" "$LOG_LIMIT_XRAY"
  [ -n "$XRAY_ACCESS_LOG" ] && trim_log "$XRAY_ACCESS_LOG" "$LOG_LIMIT_ACCESS"
  return 0
}

#######################################
# 读取 Xray 配置中 log 对象的字符串字段（access / error）
# log 对象内没有嵌套对象，取出 "log": { ... } 后再匹配键
# 键不存在或为空时输出空串（Xray 语义：输出到 stdout）
#######################################
xray_log_setting() {
  local config="$1"
  local key="$2"

  [ -f "$config" ] || return 0
  tr '\n\r' '  ' < "$config" 2> /dev/null \
    | sed -n 's/.*"log"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' \
    | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

#######################################
# 根据 Xray 配置解析日志文件，设置以下变量：
#   XRAY_ERROR_LOG   error 日志文件（为空表示 stdout 或已关闭）
#   XRAY_ACCESS_LOG  access 日志文件（为空表示 stdout 或已关闭）
#   XRAY_STDOUT_LOG  Xray 标准输出/错误的去向：优先写入 error 日志文件，
#                    error 不是文件时写入默认文件 logs/xray.log
# 相对路径按 Xray 的工作目录（配置目录）解析
# 参数: <配置文件> <配置目录> <默认输出文件>
#######################################
resolve_xray_log_files() {
  local config="$1"
  local base_dir="$2"
  local default_log="$3"
  local key value log_file

  XRAY_ERROR_LOG=""
  XRAY_ACCESS_LOG=""
  for key in error access; do
    value="$(xray_log_setting "$config" "$key")"
    case "$value" in
      '' | none) log_file="" ;;
      /*) log_file="$value" ;;
      *) log_file="$base_dir/$value" ;;
    esac
    if [ "$key" = "error" ]; then
      XRAY_ERROR_LOG="$log_file"
    else
      XRAY_ACCESS_LOG="$log_file"
    fi
  done

  XRAY_STDOUT_LOG="${XRAY_ERROR_LOG:-$default_log}"
}

#######################################
# 检查本机 TCP 端口是否处于监听状态
# 读取 /proc/net/tcp 与 tcp6，本地端口为十六进制、状态 0A 表示 LISTEN
# PROC_NET_DIR 仅供测试覆盖
#######################################
is_tcp_port_listening() {
  local port="$1"
  local dir="${PROC_NET_DIR:-/proc/net}"
  local hex

  hex="$(printf '%04X' "$port" 2> /dev/null)" || return 1
  awk -v p=":$hex" '
    FNR > 1 && $4 == "0A" && substr($2, length($2) - 4) == p { found = 1; exit }
    END { exit !found }
  ' "$dir/tcp" "$dir/tcp6" 2> /dev/null
}

#######################################
# 读取 PID 文件，并确认该进程的命令行包含指定关键字
# 防止 PID 被系统复用后误判或误杀其他进程
#######################################
read_pid_file() {
  local file="$1"
  local keyword="$2"
  local pid

  [ -f "$file" ] || return 1
  pid="$(head -n 1 "$file" 2> /dev/null)"
  case "$pid" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q -- "$keyword" || return 1
  printf '%s\n' "$pid"
}
