#!/system/bin/sh
# init_env.sh — 统一的环境与控制函数
# 该文件被其他模块脚本 source(不是执行)，所以不能在这里 exit。
# 兼容 Magisk / KernelSU / APatch；目标 busybox sh (ash)。
#
# 重要设计：nginx 以「非 root 用户」运行(默认 uid/gid 2000 = shell)。
# 原因：以 root 启动时 nginx 会调用 getpwnam() 解析 worker 降权用户(默认 nobody)。
# Android(尤其 15+)的 /system/etc/passwd 被系统裁剪，没有 root/nobody 条目；
# 且静态二进制的 passwd 查找本来就不可靠(旧版 anmpp glibc 构建实测 getpwnam
# 恒失败，补条目/挂载 passwd 均无效)。因此 root 启动必然 [emerg]。
# 非 root 运行时 nginx 整个跳过用户解析，稳定可用(anmpp 等同类项目亦然)。
# 代价：非 root 无法绑定 <1024 的端口，需要监听 80/443 时见 apply_low_port_policy。

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

# 运行时数据目录(持久化、可写)。注意不能放在 /data/adb 下：/data/adb 是 0700 root，
# 非 root 的运行用户无法穿过它，nginx 将读不到配置/写不了日志。
NG_PREFIX="${NG_PREFIX:-/data/nginx}"
NG_CONF="$NG_PREFIX/conf/nginx.conf"
NG_BIN="$NG_PREFIX/nginx"
NG_PID="$NG_PREFIX/logs/nginx.pid"
NG_STOP_FLAG="$NG_PREFIX/.stopped"
NG_LOG_DIR="$NG_PREFIX/logs"
NG_LOW_PORT_FLAG="$NG_PREFIX/allow-low-ports"
LEGACY_PREFIX="/data/adb/nginx"     # v1 版本的运行目录(用于迁移)

# nginx 运行身份
NG_UID="${NG_UID:-2000}"
NG_GID="${NG_GID:-2000}"

export MODDIR NG_PREFIX NG_CONF NG_BIN NG_PID NG_STOP_FLAG NG_LOG_DIR NG_LOW_PORT_FLAG
export NG_UID NG_GID LEGACY_PREFIX

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

# 降权执行器：优先 setuidgid，其次 setpriv。用它以普通用户身份跑 nginx。
NG_RUN=""
if [ -n "$BUSYBOX_PATH" ]; then
    if "$BUSYBOX_PATH" setuidgid "$NG_UID:$NG_GID" true >/dev/null 2>&1; then
        NG_RUN="$BUSYBOX_PATH setuidgid $NG_UID:$NG_GID"
    elif "$BUSYBOX_PATH" setpriv --reuid="$NG_UID" --regid="$NG_GID" --clear-groups true >/dev/null 2>&1; then
        NG_RUN="$BUSYBOX_PATH setpriv --reuid=$NG_UID --regid=$NG_GID --clear-groups"
    fi
fi
export NG_RUN

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

# 以运行身份执行 nginx(所有对 nginx 的调用都必须走这里，包括 -s 控制命令)
ng_exec() {
    if [ -n "$NG_RUN" ]; then
        $NG_RUN "$NG_BIN" "$@"
    else
        "$NG_BIN" "$@"
    fi
}

# 确保运行时目录存在、二进制就位、配置/页面播种(缺失才复制，不覆盖用户改动)，
# 并把整个运行目录 chown 给运行用户。
seed_runtime() {
    mkdir -p "$NG_PREFIX/conf/conf.d" "$NG_PREFIX/html" "$NG_PREFIX/logs" "$NG_PREFIX/tmp" 2>/dev/null

    # 二进制：缺失才复制(保留用户自行替换的版本)
    if [ ! -x "$NG_BIN" ]; then
        cp -f "$MODDIR/nginx/nginx" "$NG_BIN" 2>/dev/null
        chmod 755 "$NG_BIN" 2>/dev/null
    fi

    # 配置：新目录没有配置时，优先从旧版运行目录(/data/adb/nginx)迁移，其次用模块内置默认
    if [ ! -f "$NG_CONF" ]; then
        if [ -f "$LEGACY_PREFIX/conf/nginx.conf" ]; then
            cp -rf "$LEGACY_PREFIX/conf/." "$NG_PREFIX/conf/" 2>/dev/null
            # 旧配置：改写前缀路径 + 删掉 user 指令(本静态构建下 user 要么被忽略要么致命)
            for f in "$NG_PREFIX/conf/nginx.conf" "$NG_PREFIX"/conf/conf.d/*.conf; do
                [ -f "$f" ] && sed -i -e "s#$LEGACY_PREFIX#$NG_PREFIX#g" -e "/^[[:space:]]*user[[:space:]]/d" "$f" 2>/dev/null
            done
        fi
        [ -f "$NG_CONF" ] || cp -rf "$MODDIR/nginx/conf/." "$NG_PREFIX/conf/" 2>/dev/null
    fi

    if [ ! -f "$NG_PREFIX/html/index.html" ]; then
        cp -rf "$MODDIR/nginx/html/." "$NG_PREFIX/html/" 2>/dev/null
    fi

    # 以运行用户持有整个运行目录(否则非 root 的 nginx 写不了日志/临时文件)
    chown -R "$NG_UID:$NG_GID" "$NG_PREFIX" 2>/dev/null
    chmod 755 "$NG_PREFIX" "$NG_BIN" 2>/dev/null

    # 清理旧版运行目录(v1 曾把运行目录放在 /data/adb/nginx)
    if [ -d "$LEGACY_PREFIX" ] && [ "$LEGACY_PREFIX" != "$NG_PREFIX" ]; then
        rm -rf "$LEGACY_PREFIX" 2>/dev/null
    fi
    return 0
}

# 可选：允许 nginx 监听 80/443 等低端口。
# 开关：$NG_PREFIX/allow-low-ports 存在时，把内核 ip_unprivileged_port_start 降到 80。
# (只抬高权限、不还原；该 sysctl 设备级生效，重启后恢复默认，需每次开机重新设置)
apply_low_port_policy() {
    local cur
    cur=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null)
    [ -n "$cur" ] || return 0
    if [ -f "$NG_LOW_PORT_FLAG" ]; then
        if [ "$cur" -gt 80 ] 2>/dev/null; then
            if echo 80 > /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null; then
                echo "已允许 nginx 监听低端口 (ip_unprivileged_port_start=80)"
            else
                echo "无法修改 ip_unprivileged_port_start，80/443 端口仍不可用"
            fi
        fi
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
    chown -R "$NG_UID:$NG_GID" "$NG_LOG_DIR" "$NG_PREFIX/tmp" 2>/dev/null
    ng_exec -c "$NG_CONF" -p "$NG_PREFIX" >> "$NG_LOG_DIR/startup.log" 2>&1
    sleep 1
    if nginx_running; then
        echo "nginx 已启动 (PID $(nginx_pid), 运行身份 uid=$NG_UID)，默认监听 :8080"
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
    ng_exec -c "$NG_CONF" -p "$NG_PREFIX" -s quit 2>/dev/null
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        nginx_running || break
        sleep 1
    done
    if nginx_running; then
        ng_exec -c "$NG_CONF" -p "$NG_PREFIX" -s stop 2>/dev/null
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
