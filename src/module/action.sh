#!/system/bin/sh
# NetProxy 模块操作按钮入口
# 由模块管理器的操作按钮触发，自动切换服务状态（运行中→停止，未运行→启动）

readonly MODDIR="${0%/*}"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly XRAY_BIN="$MODDIR/bin/xray"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# 检查 Xray 是否运行
#######################################
is_xray_running() {
  pidof -s "$XRAY_BIN" > /dev/null 2>&1
}

# 将输出交给模块管理器显示
exec 2>&1

echo "==================================="
echo "        NetProxy 模块操作         "
echo "==================================="

# 根据当前状态执行启动或停止
if is_xray_running; then
  log "INFO" "检测到 Xray 正在运行，准备执行停止操作..."
  sh "$SERVICE_SCRIPT" stop
  echo "==================================="
  echo " 操作结果: NetProxy 服务已停止"
  echo "==================================="
else
  log "INFO" "检测到 Xray 未运行，准备执行启动操作..."
  sh "$SERVICE_SCRIPT" start
  echo "==================================="
  echo " 操作结果: NetProxy 服务已启动"
  echo "==================================="
fi

# 短暂休眠以确保日志显示完整再退出
sleep 1
