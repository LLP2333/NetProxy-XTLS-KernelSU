#!/system/bin/sh
# NetProxy Magisk 模块安装脚本

SKIPUNZIP=1

################################################################################
# 常量定义
################################################################################

readonly MODULE_ID="netproxy"
readonly LIVE_DIR="/data/adb/modules/$MODULE_ID"
readonly BACKUP_DIR="$TMPDIR/netproxy_backup"
readonly MANIFEST="$TMPDIR/netproxy_manifest.txt"

PROXY_WAS_RUNNING=false

# 升级时保留的用户配置文件（相对于模块根目录）
readonly PRESERVE_USER_FILES="
    config/module.conf
    config/xray/config.json
"

# 需要设置可执行权限的文件
readonly EXECUTABLE_FILES="
    bin/xray
    action.sh
    scripts/cli
    scripts/core/service.sh
    scripts/network/tproxy.sh
"

# 运行时目录，不参与清单比对和同步（相对于模块根目录）
readonly RUNTIME_DIRS="logs trash"

################################################################################
# 工具函数
################################################################################

print_title() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  $1"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_step() {
  ui_print "▶ $1"
}

print_ok() {
  ui_print "  ✓ $1"
}

print_warn() {
  ui_print "  ⚠ $1"
}

print_error() {
  ui_print "  ✗ $1"
}

dir_not_empty() {
  [ -d "$1" ] && [ "$(ls -A "$1" 2> /dev/null)" ]
}

is_runtime_path() {
  local rel="$1" d
  for d in $RUNTIME_DIRS; do
    case "$rel" in
      "$d"/*) return 0 ;;
    esac
  done
  return 1
}

is_preserved_file() {
  local rel="$1" pf
  for pf in $PRESERVE_USER_FILES; do
    [ "$rel" = "$pf" ] && return 0
  done
  return 1
}

generate_manifest() {
  find "$MODPATH" -type f | while IFS= read -r f; do
    printf '%s\n' "${f#$MODPATH/}"
  done | sort > "$MANIFEST"
}

################################################################################
# 核心函数
################################################################################

backup_config() {
  print_step "检查现有配置..."

  if [ ! -d "$LIVE_DIR" ]; then
    print_ok "全新安装，无需备份"
    return 0
  fi

  print_step "备份用户配置..."
  mkdir -p "$BACKUP_DIR"

  local pf
  for pf in $PRESERVE_USER_FILES; do
    local src="$LIVE_DIR/$pf"
    if [ -f "$src" ]; then
      local dst="$BACKUP_DIR/$pf"
      mkdir -p "$(dirname "$dst")"
      if cp "$src" "$dst" 2> /dev/null; then
        print_ok "已备份: $pf"
      else
        print_warn "备份失败: $pf"
      fi
    fi
  done

  return 0
}

extract_module() {
  print_step "解压模块文件..."

  if ! unzip -o "$ZIPFILE" -x "META-INF/*" -d "$MODPATH" > /dev/null 2>&1; then
    print_error "解压失败"
    return 1
  fi

  generate_manifest
  print_ok "模块文件已解压（清单: $(wc -l < "$MANIFEST") 个文件）"
  return 0
}

restore_config() {
  if ! dir_not_empty "$BACKUP_DIR"; then
    return 0
  fi

  print_step "恢复用户配置..."

  local pf
  for pf in $PRESERVE_USER_FILES; do
    local src="$BACKUP_DIR/$pf"
    if [ -f "$src" ]; then
      local dst="$MODPATH/$pf"
      mkdir -p "$(dirname "$dst")"
      if cp -f "$src" "$dst" 2> /dev/null; then
        print_ok "已恢复: $pf"
      else
        print_warn "恢复失败: $pf"
      fi
    fi
  done

  return 0
}

stop_proxy_if_running() {
  if [ ! -d "$LIVE_DIR" ]; then
    return 0
  fi

  if pidof -s "$LIVE_DIR/bin/xray" > /dev/null 2>&1; then
    PROXY_WAS_RUNNING=true
    print_step "检测到代理服务正在运行，停止服务..."
    sh "$LIVE_DIR/scripts/core/service.sh" stop > /dev/null 2>&1
    print_ok "服务已停止"
  fi

  return 0
}

sync_to_live() {
  print_step "同步到运行时目录..."

  if [ ! -d "$LIVE_DIR" ]; then
    print_ok "首次安装，跳过同步"
    return 0
  fi

  if [ ! -f "$MANIFEST" ]; then
    print_warn "清单文件不存在，跳过同步"
    return 0
  fi

  # ── 阶段 1: 将清单内的文件同步到运行时目录 ──
  print_step "更新模块文件..."
  local updated=0
  while IFS= read -r rel; do
    is_runtime_path "$rel" && continue

    local src="$MODPATH/$rel"
    local dst="$LIVE_DIR/$rel"

    if is_preserved_file "$rel" && [ -f "$dst" ]; then
      continue
    fi

    mkdir -p "$(dirname "$dst")"
    if cp -f "$src" "$dst" 2> /dev/null; then
      updated=$((updated + 1))
    fi
  done < "$MANIFEST"
  print_ok "已更新 $updated 个文件"

  # ── 阶段 2: 将不在清单上的文件移至 trash ──
  print_step "清理旧版本文件..."
  local trash_dir="$LIVE_DIR/trash"
  local trashed=0

  find "$LIVE_DIR" -type f | while IFS= read -r f; do
    local rel="${f#$LIVE_DIR/}"
    is_runtime_path "$rel" && continue

    if ! grep -qxF "$rel" "$MANIFEST"; then
      local dst="$trash_dir/$rel"
      mkdir -p "$(dirname "$dst")"
      mv "$f" "$dst" 2> /dev/null
      print_ok "已移至回收站: $rel"
    fi
  done

  # 清理空目录（保留 logs 和 trash）
  find "$LIVE_DIR" -mindepth 1 -type d -empty \
    ! -path "$LIVE_DIR/logs" \
    ! -path "$LIVE_DIR/trash" ! -path "$LIVE_DIR/trash/*" \
    -delete 2> /dev/null

  print_ok "同步完成"
  return 0
}

restart_proxy_if_needed() {
  if [ "$PROXY_WAS_RUNNING" = true ]; then
    print_step "重新启动代理服务..."
    sh "$LIVE_DIR/scripts/core/service.sh" start > /dev/null 2>&1
    print_ok "服务已启动"
  fi

  return 0
}

set_permissions() {
  print_step "设置文件权限..."

  local file
  for file in $EXECUTABLE_FILES; do
    local path="$MODPATH/$file"
    if [ -e "$path" ]; then
      chmod 0755 "$path" 2> /dev/null
      [ -e "$LIVE_DIR/$file" ] && chmod 0755 "$LIVE_DIR/$file" 2> /dev/null
    fi
  done

  set_perm_recursive "$MODPATH" 0 0 0755 0755

  print_ok "权限设置完成"
  return 0
}

cleanup() {
  rm -rf "$BACKUP_DIR" 2> /dev/null
  rm -f "$MANIFEST" 2> /dev/null
}

################################################################################
# 主流程
################################################################################

print_title "NetProxy - Xray TUN 透明代理"

unzip -o "$ZIPFILE" "module.prop" -d "$TMPDIR" > /dev/null 2>&1
ui_print "  版本: $(grep_prop version "$TMPDIR/module.prop" 2> /dev/null || echo "未知")"

if backup_config \
  && extract_module \
  && restore_config \
  && stop_proxy_if_running \
  && sync_to_live \
  && set_permissions \
  && restart_proxy_if_needed; then

  cleanup

  print_title "安装完成，请重启设备"
else
  cleanup
  print_title "安装失败"
  ui_print ""
  ui_print "  请检查上述错误信息"
  ui_print "  并在 GitHub Issues 反馈"
  ui_print ""
  exit 1
fi
