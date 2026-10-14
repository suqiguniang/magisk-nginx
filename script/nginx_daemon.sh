#!/system/bin/sh
# nginx_daemon.sh — 守护循环：nginx 崩溃则自愈，但尊重用户在「执行」里的停止选择。
# 由 service.sh 在后台拉起；本身保持常驻。
MODDIR="$(dirname "$(readlink -f "$0")")"
MODDIR="$(dirname "$MODDIR")"
export MODDIR

# 加载路径 / busybox / 控制函数
. "$MODDIR/script/init_env.sh"
export NG_PREFIX NG_CONF NG_BIN NG_PID NG_STOP_FLAG NG_LOG_DIR

LOG="$NG_LOG_DIR/daemon.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
}

seed_runtime
log "daemon 启动，运行目录 $NG_PREFIX"

while true; do
    # 尊重手动停止标志：存在 .stopped 就跳过，直到用户在「执行」里选择「启动/重启」
    if [ ! -f "$NG_STOP_FLAG" ] && ! nginx_running; then
        log "nginx 未运行且未被手动停止，拉起..."
        "$NG_BIN" -c "$NG_CONF" -p "$NG_PREFIX" >> "$NG_LOG_DIR/startup.log" 2>&1
        sleep 1
        if nginx_running; then
            log "nginx 已拉起 (PID $(nginx_pid))"
        else
            log "nginx 拉起失败，详见 $NG_LOG_DIR/error.log"
        fi
    fi
    sleep 3
done
