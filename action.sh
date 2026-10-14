#!/system/bin/sh
# action.sh — 「执行」按钮菜单。
#   音量键+ : 切换选择   音量键- : 确认
# 若系统没有 getevent(精简 ROM)，自动降级为键盘 read。
# 目标 busybox sh (ash)：不使用 bash 数组等 bashism。

MODDIR="$(dirname "$(readlink -f "$0")")"
export MODDIR

. "$MODDIR/script/init_env.sh"
export NG_PREFIX NG_CONF NG_BIN NG_PID NG_STOP_FLAG NG_LOG_DIR

# ---------------------------------------------------------------------------
# 菜单定义(共 4 项)
# ---------------------------------------------------------------------------
MENU_COUNT=4

item_name() {
    case "$1" in
        0) echo "启动 nginx" ;;
        1) echo "停止 nginx" ;;
        2) echo "重启 nginx" ;;
        3) echo "退出" ;;
    esac
}

run_item() {
    case "$1" in
        0) nginx_start ;;
        1) nginx_stop ;;
        2) nginx_restart ;;
        3) echo "已退出。" ;;
    esac
}

status_block() {
    if nginx_running; then
        echo "  状态: 运行中 (PID $(nginx_pid))，默认端口 :8080"
    elif [ -f "$NG_STOP_FLAG" ]; then
        echo "  状态: 已停止(手动)"
    else
        echo "  状态: 未运行"
    fi
}

draw_menu() {
    clear_screen
    echo "==============================="
    echo "        Nginx 控制"
    echo "==============================="
    status_block
    echo "-----------------------------"
    i=0
    while [ $i -lt $MENU_COUNT ]; do
        nm=$(item_name $i)
        if [ "$i" -eq "$SEL" ]; then
            echo "  > [$i] $nm"
        else
            echo "    [$i] $nm"
        fi
        i=$((i + 1))
    done
    echo "-----------------------------"
    if [ -n "$GETEVENT" ]; then
        echo "  音量+ 切换选择 / 音量- 确认"
    else
        echo "  getevent 不可用：键盘输入 0-3 + 回车"
    fi
}

# ---------------------------------------------------------------------------
# 取一个键事件(只认"按下"DOWN，忽略松开/其它键)，避免重复触发
#   输出: 0=音量+按下  1=音量-按下  2=超时(完全无输入)  3=其它事件(忽略)
# ---------------------------------------------------------------------------
read_key() {
    local ev
    if [ -n "$TIMEOUTCMD" ]; then
        ev=$($TIMEOUTCMD 60 $GETEVENT -qlc 1 2>/dev/null)
    else
        ev=$($GETEVENT -qlc 1 2>/dev/null)
    fi
    [ -z "$ev" ] && { echo 2; return; }
    if echo "$ev" | grep -q "KEY_VOLUMEUP"; then
        echo "$ev" | grep -q "DOWN" && { echo 0; return; }
    fi
    if echo "$ev" | grep -q "KEY_VOLUMEDOWN"; then
        echo "$ev" | grep -q "DOWN" && { echo 1; return; }
    fi
    echo 3
}

# 清空输入缓冲区里陈旧的事件(最多 1s)，避免上一次的按键直接确认了本次菜单
flush_keys() {
    [ -n "$TIMEOUTCMD" ] && $TIMEOUTCMD 1 $GETEVENT -qlc 1 >/dev/null 2>&1
    return 0
}

volume_loop() {
    flush_keys
    local r
    while true; do
        r=$(read_key)
        case "$r" in
            0)  # 音量+ 切换
                SEL=$((SEL + 1)); [ $SEL -ge $MENU_COUNT ] && SEL=0
                draw_menu ;;
            1)  # 音量- 确认
                run_item "$SEL"
                [ "$SEL" -eq 3 ] && exit 0
                draw_menu ;;
            2)  # 完全无输入超时
                echo ""
                echo "  等待超时，退出。"
                exit 0 ;;
            3)  # 其它键/松开，忽略，继续等待
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 键盘降级
# ---------------------------------------------------------------------------
keyboard_loop() {
    local ch
    while true; do
        draw_menu
        printf "  > "
        read ch || exit 0
        case "$ch" in
            0|1|2|3)
                SEL=$ch
                run_item "$SEL"
                [ "$SEL" -eq 3 ] && exit 0
                ;;
            *)
                echo "  无效输入 (0-3)"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
SEL=0
draw_menu

if [ -n "$GETEVENT" ]; then
    volume_loop
else
    keyboard_loop
fi
