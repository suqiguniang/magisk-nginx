#!/system/bin/sh
# init_env.sh — 统一的环境与控制函数
# 该文件被其他模块脚本 source(不是执行)，所以不能在这里 exit。
# 兼容 Magisk / KernelSU / APatch；目标 busybox sh (ash)。

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
# 模块根目录：优先使用外部传入的 MODDIR，其次 MAGISK 的 MODPATH，最后按脚本位置推断
if [ -z "$MODDIR" ]; then
    if [ -n "$MODPATH" ]; then
        MODDIR="$MODPATH"
    else
        MODDIR="$(dirname "$(readlink -f "$0")")"
    fi
fi

# 运行时数据目录(持久化、可写)。模块目录 $MODDIR 在升级/重刷时会被整个替换，
# 因此二进制、用户可改的配置、日志都放在这里，避免被抹掉。
NG_PREFIX="${NG_PREFIX:-/data/adb/nginx}"
NG_CONF="$NG_PREFIX/conf/nginx.conf"
NG_BIN="$NG_PREFIX/nginx"
NG_PID="$NG_PREFIX/logs/nginx.pid"
NG_STOP_FLAG="$NG_PREFIX/.stopped"
NG_LOG_DIR="$NG_PREFIX/logs"

# 对外暴露(供脚本 export / 日志查看)
export MODDIR NG_PREFIX NG_CONF NG_BIN NG_PID NG_STOP_FLAG NG_LOG_DIR

# ---------------------------------------------------------------------------
# busybox 探测(同时兼容 Magisk 与 KernelSU/APatch)
# ---------------------------------------------------------------------------
BUSYBOX_SEARCH_PATH="/data/adb/ksu/bin/busybox:/data/adb/magisk/busybox:/data/adb/ap/busybox"
if command -v magisk >/dev/null 2>&1; then
    MAGISK_BUSYBOX="$(magisk --path 2>/dev/null)/.magisk/busybox/busybox"
    BUSYBOX_SEARCH_PATH="${MAGISK_BUSYBOX}:${BUSYBOX_SEARCH_PATH}"
fi
BUSYBOX_PARENT_PATH=""
BUSYBOX_PATH=""
for the_path in $(echo "$BUSYBOX_SEARCH_PATH" | tr ":" "\n"); do
    if [ -f "$the_path" ]; then
        BUSYBOX_PATH="$the_path"
        BUSYBOX_PARENT_PATH=$(echo "$the_path" | sed 's#/busybox$##g')
        break
    fi
done
export BUSYBOX_PATH BUSYBOX_PARENT_PATH

# getevent / timeout：系统工具，可能不在精简 ROM 的 PATH 里，探测一下
GETEVENT=""
if [ -x /system/bin/getevent ]; then
    GETEVENT=/system/bin/getevent
elif command -v getevent >/dev/null 2>&1; then
    GETEVENT=getevent
fi
TIMEOUTCMD=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUTCMD=timeout
elif [ -n "$BUSYBOX_PATH" ] && "$BUSYBOX_PATH" timeout --help >/dev/null 2>&1; then
    TIMEOUTCMD="$BUSYBOX_PATH timeout"
fi
export GETEVENT TIMEOUTCMD

# ---------------------------------------------------------------------------
# 运行时控制函数
# ---------------------------------------------------------------------------

# 确保运行时目录存在、二进制就位(缺失才复制，保留用户自定义二进制)，
# 配置/页面缺失才播种(不覆盖用户已改动的文件)。
seed_runtime() {
    mkdir -p "$NG_PREFIX/conf/conf.d" "$NG_PREFIX/html" "$NG_PREFIX/logs" "$NG_PREFIX/tmp" 2>/dev/null
    if [ ! -x "$NG_BIN" ]; then
        cp -f "$MODDIR/nginx/nginx" "$NG_BIN" 2>/dev/null
        chmod 755 "$NG_BIN" 2>/dev/null
    fi
    if [ ! -f "$NG_PREFIX/conf/nginx.conf" ]; then
        cp -rf "$MODDIR/nginx/conf/." "$NG_PREFIX/conf/" 2>/dev/null
    fi
    if [ ! -f "$NG_PREFIX/html/index.html" ]; then
        cp -rf "$MODDIR/nginx/html/." "$NG_PREFIX/html/" 2>/dev/null
    fi
    return 0
}

# 判断 nginx 主进程是否在运行
nginx_running() {
    if [ -f "$NG_PID" ]; then
        local pid
        pid=$(cat "$NG_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    if [ -n "$BUSYBOX_PATH" ]; then
        "$BUSYBOX_PATH" pgrep -f "$NG_PREFIX/nginx" >/dev/null 2>&1 && return 0
    else
        pgrep -f "$NG_PREFIX/nginx" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# 当前 nginx 的 PID(运行中才返回)
nginx_pid() {
    if [ -f "$NG_PID" ]; then
        local pid
        pid=$(cat "$NG_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"; return 0
        fi
    fi
    return 1
}

nginx_start() {
    if nginx_running; then
        echo "nginx 已在运行 (PID $(nginx_pid))"
        return 0
    fi
    rm -f "$NG_STOP_FLAG"
    seed_runtime
    mkdir -p "$NG_LOG_DIR" "$NG_PREFIX/tmp" 2>/dev/null
    chmod 755 "$NG_BIN" 2>/dev/null
    "$NG_BIN" -c "$NG_CONF" -p "$NG_PREFIX" >> "$NG_LOG_DIR/startup.log" 2>&1
    sleep 1
    if nginx_running; then
        echo "nginx 已启动 (PID $(nginx_pid))，默认监听 :8080"
        return 0
    fi
    echo "nginx 启动失败，请查看 $NG_LOG_DIR/error.log"
    return 1
}

nginx_stop() {
    if ! nginx_running; then
        echo "nginx 未运行"
        return 0
    fi
    echo "正在停止 nginx ..."
    "$NG_BIN" -c "$NG_CONF" -p "$NG_PREFIX" -s quit 2>/dev/null
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        nginx_running || break
        sleep 1
    done
    if nginx_running; then
        "$NG_BIN" -c "$NG_CONF" -p "$NG_PREFIX" -s stop 2>/dev/null
    fi
    echo "stopped" > "$NG_STOP_FLAG"
    echo "nginx 已停止 (已写入 .stopped 标志，守护进程不会自动拉起)"
    return 0
}

nginx_restart() {
    echo "正在重启 nginx ..."
    nginx_stop >/dev/null 2>&1
    nginx_start
}

nginx_status() {
    if nginx_running; then
        echo "nginx 运行中 (PID $(nginx_pid))"
        return 0
    fi
    if [ -f "$NG_STOP_FLAG" ]; then
        echo "nginx 已停止(手动)，守护进程不会自动拉起"
    else
        echo "nginx 未运行"
    fi
    return 1
}

# 清屏：仅在真正的 TTY 下用 ANSI(避免某些管理器把转义码当普通文本显示)
clear_screen() {
    if [ -t 1 ]; then
        printf '\033c'
    fi
}
