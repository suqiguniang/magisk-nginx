#!/system/bin/sh
# uninstall.sh — 模块卸载/删除前执行(由管理器调用)。
# 停止 nginx 并清理运行时目录 /data/nginx (以及 v1 遗留的 /data/adb/nginx)。
# 注意：这会删除用户自行修改过的配置与日志。

MODDIR="$(dirname "$(readlink -f "$0")")"
export MODDIR
. "$MODDIR/script/init_env.sh" 2>/dev/null

# 优雅停止(若仍在运行)。nginx 以普通用户运行，用同样的身份发信号。
if nginx_running 2>/dev/null; then
    ng_exec -c "$NG_CONF" -p "$NG_PREFIX" -s stop 2>/dev/null
    sleep 1
fi

# 清理运行时目录
rm -rf "$NG_PREFIX"
# 清理旧版运行目录
[ "$LEGACY_PREFIX" != "$NG_PREFIX" ] && rm -rf "$LEGACY_PREFIX"

echo "Nginx 已停止，运行时目录 $NG_PREFIX 已清理。"
