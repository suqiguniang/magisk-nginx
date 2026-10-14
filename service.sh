#!/system/bin/sh
# service.sh — late_start 阶段执行(非阻塞，推荐用于守护进程)。
# 等待开机完成 -> 播种运行时目录 -> 应用低端口策略 -> 后台拉起守护循环。

MODDIR="$(dirname "$(readlink -f "$0")")"
export MODDIR

# 加载路径 / busybox / 控制函数
. "$MODDIR/script/init_env.sh"
export NG_PREFIX NG_CONF NG_BIN NG_PID NG_STOP_FLAG NG_LOG_DIR NG_UID NG_GID NG_RUN

# KernelSU 要求脚本可执行
chmod 755 "$MODDIR/script/"*.sh 2>/dev/null

# 等待系统完全启动，避免抢端口/抢资源
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done

# 播种运行时目录(缺失才复制 + 迁移旧版目录 + chown 给运行用户)
seed_runtime

# 若存在 /data/nginx/allow-low-ports，则允许 nginx 监听 80/443 等低端口
apply_low_port_policy

# 后台守护循环(崩溃自愈，尊重手动停止标志)
sh "$MODDIR/script/nginx_daemon.sh" &

# 每 24h 轮转一次超过 1MB 的日志(保持系统整洁)
while true; do
    sleep 24h
    for the_log in "$NG_LOG_DIR"/*.log; do
        [ -f "$the_log" ] || continue
        the_size=$(wc -c < "$the_log" 2>/dev/null)
        if [ "$the_size" -gt 1048576 ]; then
            : > "$the_log"
        fi
    done
done
