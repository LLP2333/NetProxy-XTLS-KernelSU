#!/system/bin/sh
# NetProxy post-fs-data 阶段入口
# 由模块框架在文件系统挂载完成后、系统启动前执行
# 当前仅记录日志，预留后续扩展
set -e

readonly MODDIR="${0%/*}"
readonly LOG_FILE="$MODDIR/logs/service.log"

. "$MODDIR/scripts/utils/common.sh"

log "INFO" "post-fs-data 阶段"
