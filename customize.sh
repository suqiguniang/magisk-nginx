#!/system/bin/sh
# customize.sh — 安装脚本(被安装器 source)。结束时不要 exit。
# 仅支持 arm64-v8a。

if [ "$BOOTMODE" != true ]; then
    ui_print "! 请从管理器(Bootloader)安装，本模块不支持在 Recovery 中刷入"
    abort "请从管理器安装"
fi

MODDIR=$MODPATH
export MODDIR

# 校验架构
if [ "$ARCH" != "arm64" ]; then
    ui_print "! 仅支持 arm64-v8a，当前检测到架构: $ARCH"
    abort "不支持的 CPU 架构"
fi

# 给模块脚本执行位(KernelSU 要求脚本可执行才会开机运行)
chmod 755 $MODPATH/nginx/nginx 2>/dev/null
chmod 755 $MODPATH/*.sh $MODPATH/META-INF/com/google/android/* 2>/dev/null

# 加载路径 / busybox / 控制函数
. "$MODDIR/script/init_env.sh"
export NG_PREFIX NG_CONF NG_BIN NG_LOG_DIR NG_UID NG_GID NG_RUN

# 在 /data/nginx 播种运行时目录(缺失才复制，保留用户改动；会迁移 v1 的 /data/adb/nginx)
seed_runtime

# 清空旧日志
: > "$NG_LOG_DIR/install.log"
echo "installed $(date '+%Y-%m-%d %H:%M:%S')" >> "$NG_LOG_DIR/install.log"

ui_print "---------------- Nginx for Android ----------------"
ui_print "- 架构: $ARCH (arm64)"
ui_print "- 运行目录: $NG_PREFIX"
ui_print "- 运行身份: uid=$NG_UID (非 root，静态 glibc 二进制无法以 root 运行)"
ui_print "- 默认监听端口: 8080"
ui_print "- 开机自动启动；「执行」中可用音量键控制"
ui_print "- 需监听 80/443？见 README「监听低端口」"
ui_print "----------------------------------------------------"

# 说明：不对 webroot/ 做任何权限处理 —— KernelSU/APatch 会自行设置其权限与
# SELinux 上下文，乱设反而会导致「打开」页面打不开。
