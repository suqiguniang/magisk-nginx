#!/system/bin/sh
# uninstall.sh — 模块卸载/删除前执行(由管理器调用)。
# 停止 nginx 并清理运行时目录 /data/adb/nginx。
# 注意：这会删除用户自行修改过的配置与日志。

MODDIR="$(dirname "$(readlink -f "$0")")"
export MODDIR
. "$MODDIR/script/init_env.sh" 2>/dev/null

# 优雅停止(若仍在运行)
if nginx_running 2>/dev/null; then
    "$NG_BIN" -c "$NG_CONF" -p "$NG_PREFIX" -s stop 2>/dev/null
    sleep 1
fi

# 清理运行时目录
rm -rf "$NG_PREFIX"

echo "Nginx 已停止，运行时目录 $NG_PREFIX 已清理。"
