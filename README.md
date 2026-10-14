# Nginx for Android — Magisk / KernelSU / APatch 模块

在 Root 手机上运行 **nginx 1.21.6（arm64-v8a 静态编译）**，提供**反向代理 / 静态站点 / 状态页**。
内置开机自启与崩溃自愈守护，通过「执行」按钮提供**音量键控制**（启动 / 停止 / 重启），
「打开」按钮进入 WebUI（当前为施工中占位页）。

- 二进制来源：[xiaoqidun/anmpp](https://github.com/xiaoqidun/anmpp) 内置的静态 arm64 nginx（OpenSSL 3.0.3，含 `http_ssl` / `http_v2` / `stream` / `gzip_static` / `auth_request` / `stub_status` 等模块）
- 仅支持 **arm64-v8a**；检测到其它架构会中止安装
- 安装全程离线，二进制随 zip 一起发布
- 仓库已内置二进制，`sh build.sh` 即可出包；缺失时可用 `sh build.sh --fetch` 在线拉取

---

## 目录

- [功能](#功能)
- [安装（刷入）](#安装刷入)
- [使用方法](#使用方法)
- [反向代理配置](#反向代理配置)
- [从源码构建](#从源码构建)
- [目录结构](#目录结构)
- [常见问题排查](#常见问题排查)
- [升级到更新的 nginx](#升级到更新的-nginx)

---

## 功能

| 能力 | 说明 | 支持 |
|---|---|---|
| 开机自启 | `service.sh` 在 late_start 阶段等开机完成后拉起 nginx | Magisk / KernelSU / APatch |
| 崩溃自愈 | 守护循环检测到 nginx 退出即自动拉起（除非手动「停止」过） | 同上 |
| 「执行」菜单 | `action.sh`：音量+ 切换选择、音量- 确认 —— 启动 / 停止 / 重启 / 退出 | Magisk v28+ / KernelSU / APatch |
| 「打开」WebUI | `webroot/index.html` 施工中占位页（内联 SVG，离线） | KernelSU / APatch（官方 Magisk 需 MMRL / WebUI-X） |
| 反向代理 | `conf.d/` 下新增 `*.conf` 即生效，内置 example.com → 127.0.0.1:8080 示例 | — |
| 状态页 | `http://127.0.0.1:8080/nginx_status`（`stub_status`，仅本机） | — |
| 日志 | `/data/adb/nginx/logs/`，24h 自动轮转（>1MB 清空） | — |

---

## 安装（刷入）

### 1. 获取模块包

本仓库已内置 nginx 二进制，构建一次即可（Windows Git Bash / Linux / Termux）：

```sh
git clone https://github.com/suqiguniang/magisk-nginx.git
cd magisk-nginx
sh build.sh            # 产物在 dist/magisk-nginx.zip
```

> 若 `nginx/nginx` 缺失：`sh build.sh --fetch` 会从 anmpp 仓库自动下载。

把 `magisk-nginx.zip` 传到手机上（任意目录，如 `/sdcard/Download`）。

### 2. 刷入

前置条件：设备为 **arm64-v8a**，已安装 **Magisk / KernelSU / APatch** 并获得 Root。

| 管理器 | 步骤 |
|---|---|
| Magisk | 打开 Magisk App → 底部「模块」→ 右上角「…」→「从存储安装」→ 选 `magisk-nginx.zip` → 安装 → **重启** |
| KernelSU | KernelSU App → 底部「模块」→ 右上角「＋」→ 选 zip → 安装 → **重启** |
| APatch | APatch App → 「模块管理」→ 「安装」→ 选 zip → 安装 → **重启** |

> 本模块**不支持 Recovery 刷入**，必须从管理器安装（`customize.sh` 会检查 `BOOTMODE`）。
> 安装后模块目录在 `/data/adb/modules/magisk-nginx`。

### 3. 验证

重启完成后（自动启动）：

```sh
# 任意 Root Shell / Termux：
su -c "/data/adb/nginx/nginx -p /data/adb/nginx -c /data/adb/nginx/conf/nginx.conf -s stop >/dev/null 2>&1; echo check"
# 更直观：浏览器直接打开
#   http://127.0.0.1:8080           # 默认状态页
#   http://<手机IP>:8080            # 局域网访问
#   http://127.0.0.1:8080/nginx_status   # stub_status
```

或看日志：`cat /data/adb/nginx/logs/daemon.log`（守护循环会记录每次拉起/失败原因）。

---

## 使用方法

### 「执行」音量键控制

在管理器的模块页点「执行 / Action / 执行动作」：

```
===============================
        Nginx 控制
===============================
  状态: 运行中 (PID 1234)，默认端口 :8080
-----------------------------
  > [0] 启动 nginx
    [1] 停止 nginx
    [2] 重启 nginx
    [3] 退出
-----------------------------
  音量+ 切换选择 / 音量- 确认
```

- **音量+** 切换高亮（循环），**音量-** 确认执行；选「退出」离开菜单
- 完全无输入 60 秒自动退出
- ROM 没有 `getevent` 时自动降级为键盘输入 `0-3`
- 「停止」会写 `.stopped` 标志，守护进程**不再自动拉起**；「启动/重启」清除该标志
- 改了配置后选「重启 nginx」即可重载（`nginx -s reload` 语义：进程不在则全新启动）

### 「打开」WebUI

KernelSU / APatch 的模块页点「打开 / WebUI」进入 `webroot/index.html`。
当前是**施工中占位**（内联 SVG 动画 + 模块信息），管理功能尚未实现。
官方 Magisk 不识别 `webroot/`，需装 [MMRL](https://github.com/MMRLApp/MMRL) 或 WebUI-X；
不想装宿主也可直接在浏览器访问 `:8080` 状态页。

---

## 反向代理配置

可写配置全部在 `/data/adb/nginx/`（**模块升级/重刷不会覆盖**，卸载才会删除）：

```
/data/adb/nginx/
├── nginx                     # 运行时二进制
├── conf/nginx.conf           # 主配置
├── conf/mime.types
├── conf/conf.d/
│   ├── 00-default.conf              # 默认站点 :8080（状态页 + 静态文件）
│   └── reverse-proxy.conf.example   # 反代示例（默认不启用）
├── html/                   # 静态文件
├── logs/                   # error.log / access.log / nginx.pid / daemon.log
└── tmp/
```

### 启用内置示例（example.com → 本机 8080）

```sh
su -c 'mv /data/adb/nginx/conf/conf.d/reverse-proxy.conf.example \
          /data/adb/nginx/conf/conf.d/reverse-proxy.conf'
# 在「执行」菜单选「重启 nginx」，或：
su -c "/data/adb/nginx/nginx -p /data/adb/nginx -c /data/adb/nginx/conf/nginx.conf -s reload"
```

主配置里有 `include conf/conf.d/*.conf;`，所以任何新增的 `*.conf` 自动被载入
（`.example` 后缀不会匹配，起到「默认关闭」的作用）。

示例内容（含 WebSocket 升级、透传头、超时；完整见
`nginx/conf/conf.d/reverse-proxy.conf.example`）：

```nginx
server {
    listen 80;
    server_name example.com;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # WebSocket
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

> 端口 80 是特权端口，root 可绑；被占用时把 `listen` 改掉即可。
> 注意：nginx 里的相对路径都相对**前缀** `/data/adb/nginx` 解析（启动带 `-p`）。

---

## 从源码构建

```
依赖：bash + python（Windows 用 Git Bash；Termux 需要 pkg install bash curl file）
      dos2unix 可选（没有则自动用 python 兜底）

sh build.sh           # 校验二进制 -> 行尾规范化为 LF -> 打 deflate zip
sh build.sh --fetch   # 二进制缺失时先下载
产物：dist/magisk-nginx.zip
```

`build.sh` 会做：
1. ELF 校验（python 解析：aarch64 / 静态 / 含 `nginx/1.21.6` 串），不合格不出包
2. 所有文本脚本/配置 `dos2unix` 为 LF（Android 上 CRLF 会直接报错）
3. 用 Python `zipfile` 按清单打 Deflate zip，并写入正确 Unix 权限位
   （`*.sh`/`update-binary`/二进制 = 755，配置 = 644）

---

## 目录结构

```
magisk-nginx/
├── module.prop               # id=magisk-nginx, name=Nginx for Android
├── customize.sh              # 安装：校验 arm64、布署二进制、播种 /data/adb/nginx
├── service.sh                # 开机 late_start：拉守护循环 + 日志轮转
├── action.sh                 # 「执行」音量键菜单（启动/停止/重启/退出）
├── uninstall.sh              # 卸载：停 nginx 并清理 /data/adb/nginx
├── script/init_env.sh        # 路径 / busybox / 控制函数（各脚本 source）
├── script/nginx_daemon.sh    # 崩溃自愈守护，尊重 .stopped 标志
├── nginx/
│   ├── nginx                 # 二进制（anmpp 1.21.6 arm64 静态）
│   ├── conf/{nginx.conf,mime.types,conf.d/*.conf}
│   └── html/index.html
├── webroot/index.html        # 「打开」WebUI：施工中 SVG 占位
├── META-INF/com/google/android/{update-binary,updater-script}
├── build.sh                  # 校验 + LF 规范化 + 打 zip（python）
└── README.md
```

---

## 常见问题排查

| 现象 | 排查 |
|---|---|
| nginx 没起来 | 看 `/data/adb/nginx/logs/error.log`；`bind: ...denied` 多为端口被占，把 `listen` 换端口后「重启」 |
| 反代域名解析失败 | 静态二进制的 DNS 走系统 `/system/etc/resolv.conf`（Android 上常不存在）。用 IP 直连，或在 `nginx.conf` 里 `resolver 223.5.5.5;` + 变量式 `proxy_pass` |
| 重启后没自动启动 | 上次在「执行」里选过「停止」→ `.stopped` 标志还在，选「启动」即可；或 `rm /data/adb/nginx/.stopped` |
| 「打开」按钮没有 | 官方 Magisk 需装 MMRL/WebUI-X；KernelSU/APatch 原生支持 |
| 安装时报「请从管理器安装」 | 别在 Recovery 刷，必须从管理器 App 安装 |
| 日志太大 | 守护 24h 自动清空 >1MB 的日志；也可 `: > /data/adb/nginx/logs/error.log` |
| SELinux 个别 ROM 拦低端口 | 用 1024 以上端口 |

---

## 升级到更新的 nginx

二进制是**静态单文件**，替换后重打包即可（想上 1.29 / 1.31+ 时）：

1. 找一个 **arm64 静态 + 16KB 页对齐** 的 nginx（Android 15+ 需要 16KB 对齐，
   用 `readelf -l` 看 `LOAD` 段 Align 是否为 `0x10000`）
2. 覆盖仓库里的 `nginx/nginx`，把 `build.sh` 里的版本串校验同步改掉，`sh build.sh` 重刷
3. 或只替换设备上的 `/data/adb/nginx/nginx` 后在「执行」里选「重启 nginx」

当前内置的 1.21.6 已校验：`ELF aarch64`、完全静态、两个 `LOAD` 段 `p_align=0x10000`
（16KB 对齐，新机型无兼容问题）。

---

## 卸载

管理器 → 模块 → 删除「Nginx for Android」。
`uninstall.sh` 会先停止 nginx 并删除 `/data/adb/nginx`（含你改过的配置与日志）。
想保留配置就先备份 `/data/adb/nginx/conf`。

---

## 说明

- 模块 id：`magisk-nginx`；运行时目录：`/data/adb/nginx`
- 本模块不修改任何 `/system` 文件，无需 metamodule（KernelSU 3.x 也直接可用）
- 二进制由 anmpp 项目提供，本仓库仅重新打包分发；如需最新 nginx 见上一节
