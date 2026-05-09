#!/system/bin/sh
# 配置读写辅助函数
# 用于操作 KEY=VALUE 格式的配置文件（如 module.conf）
# 依赖 common.sh 中的 require_file

#######################################
# 去除配置值中的引号和 Windows 换行符
#######################################
strip_quotes() {
  printf "%s" "${1:-}" | tr -d '"' | tr -d '\r'
}

#######################################
# 读取配置值
# 从文件中查找 KEY=VALUE 行，返回去引号后的值
# 未找到时返回默认值
#######################################
read_conf() {
  local file="$1"
  local key="$2"
  local default="${3:-}"
  local line value

  if [ -f "$file" ]; then
    line="$(grep -m 1 "^${key}=" "$file" 2> /dev/null || true)"
    if [ -n "$line" ]; then
      value="${line#*=}"
      strip_quotes "$value"
      return 0
    fi
  fi

  printf "%s" "$default"
}

#######################################
# 写入配置值
# 如果 KEY 已存在则原地替换，否则追加到文件末尾
#######################################
set_conf() {
  local file="$1"
  local key="$2"
  local value="$3"

  require_file "$file" "配置文件不存在: $file"

  # 转义 sed 分隔符和特殊字符，避免 value 中的 | & / \ 破坏替换
  local escaped_value
  escaped_value="$(printf '%s' "$value" | sed 's/[|&/\]/\\&/g')"

  if grep -q "^${key}=" "$file" 2> /dev/null; then
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$file"
  fi
}

#######################################
# 为配置值补双引号
#######################################
quote_conf() {
  printf '"%s"' "$1"
}

################################################################################
# 空格分隔列表操作
# 用于管理 PRESERVE_USER_FILES、EXECUTABLE_FILES 等空格分隔的列表值
################################################################################

#######################################
# 判断列表是否包含指定值
#######################################
list_contains() {
  local list="$1"
  local item="$2"
  local value

  for value in $list; do
    [ "$value" = "$item" ] && return 0
  done

  return 1
}

#######################################
# 向列表追加值（已存在则不重复添加）
#######################################
list_add() {
  local list="$1"
  local item="$2"

  if list_contains "$list" "$item"; then
    printf "%s" "$list"
  elif [ -n "$list" ]; then
    printf "%s %s" "$list" "$item"
  else
    printf "%s" "$item"
  fi
}

#######################################
# 从列表移除值
#######################################
list_remove() {
  local list="$1"
  local item="$2"
  local value output=""

  for value in $list; do
    [ "$value" = "$item" ] && continue
    if [ -n "$output" ]; then
      output="$output $value"
    else
      output="$value"
    fi
  done

  printf "%s" "$output"
}
