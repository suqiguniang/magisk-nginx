# Nginx for Android — Magisk / KernelSU / APatch 模块

在 Root 手机上运行 **nginx 1.21.6（arm64-v8a 静态编译）**，提供**反向代理 / 静态站点 / 状态页**。
内置开机自启与崩溃自愈守护，通过「执行」按钮提供**音量键控制**（启动 / 停止 / 重启），
「打开」按钮进入 WebUI（当前为施工中占位页）。

- 二进制来源：[xiaoqidun/anmpp](https://github.com/xiaoqidun/anmpp) 内置的静态 arm64 nginx（OpenSSL 3.0.3，含 `http_ssl` / `http_v2` / `stream` / `gzip_static` / `auth_request` / `stub_status` 等模块）
- 仅支持 **arm64-v8a**；检测到其它架构会中止安装
- 运行目录 **`/data/nginx`**，nginx 以**非 root 身份**运行（默认 uid/gid 2000，原因见下）
- 安装全程离线，二进制随 zip 一起发布

---

## 目录

- [功能](#功能)
- [安装（刷入）](#安装刷入)
- [使用方法](#使用方法)
- [反向代理配置](#反向代理配置)
- [监听 80/443 低端口](#监听-80443-低端口)
- [为什么以非 root 运行](#为什么以非-root-运行)
- [已知限制](#已知限制)
- [从源码构建](#从源码构建)
- [目录结构](#目录结构)
- [常见问题排查](#常见问题排查)
- [卸载](#卸载)

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
| 日志 | `/data/nginx/logs/`，24h 自动轮转（>1MB 清空） | — |

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
> 安装后模块目录在 `/data/adb/modules/magisk-nginx`，运行时目录在 `/data/nginx`。

### 3. 验证

重启完成后（自动启动）：

```
http://127.0.0.1:8080                  # 默认状态页
http://<手机IP>:8080                   # 局域网访问
http://127.0.0.1:8080/nginx_status     # stub_status 运行状态
```

命令行检查（任意 Root Shell / Termux）：

```sh
su -c 'cat /data/nginx/logs/daemon.log'      # 守护循环日志
su -c 'cat /data/nginx/logs/error.log'       # nginx 错误日志
su -c 'ps -A | grep nginx'                   # 应看到 master + worker，用户为 shell
```

---

## 使用方法

### 「执行」音量键控制

在管理器的模块页点「执行 / Action」：

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

### 「打开」WebUI

KernelSU / APatch 的模块页点「打开」进入 `webroot/index.html`（当前是施工中占位页）。
官方 Magisk 不识别 `webroot/`，需装 [MMRL](https://github.com/MMRLApp/MMRL) 或 WebUI-X；
也可直接在浏览器访问 `:8080` 状态页。

---

## 反向代理配置

可写配置全部在 **`/data/nginx/`**（模块升级/重刷不会覆盖，卸载才会删除）：

```
/data/nginx/
├── nginx                     # 运行时二进制（属主 uid 2000）
├── conf/nginx.conf           # 主配置
├── conf/mime.types
├── conf/conf.d/
│   ├── 00-default.conf              # 默认站点 :8080（状态页 + 静态文件）
│   └── reverse-proxy.conf.example   # 反代示例（默认不启用）
├── html/                     # 静态文件
├── logs/                     # error.log / access.log / nginx.pid / daemon.log
├── .stopped                  # 手动停止标志（存在则守护不拉起）
└── allow-low-ports           # 存在则允许监听 80/443（见下节）
```

### 启用内置示例（example.com → 本机 8080）

```sh
su -c 'mv /data/nginx/conf/conf.d/reverse-proxy.conf.example \
          /data/nginx/conf/conf.d/reverse-proxy.conf'
# 在「执行」菜单选「重启 nginx」，或：
su -c 'setuidgid 2000:2000 /data/nginx/nginx -p /data/nginx \
        -c /data/nginx/conf/nginx.conf -s reload'
```

主配置里有 `include /data/nginx/conf/conf.d/*.conf;`，新增的 `*.conf` 自动载入
（`.example` 后缀不匹配，起「默认关闭」作用）。

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

---

## 监听 80/443 低端口

nginx 以**非 root 用户**运行，Linux 默认不允许绑定 <1024 的端口
（本机 `net.ipv4.ip_unprivileged_port_start = 1024`）。要监听 80/443，二选一：

**方式 A（推荐，模块内置开关）**

```sh
su -c 'touch /data/nginx/allow-low-ports'
# 重启 nginx 或重启手机；service.sh 开机时会把 ip_unprivileged_port_start 降到 80
```

模块只会在该标志存在时调整内核参数，且**只放宽、不还原**（该参数重启后恢复默认，
因此每次开机由 `service.sh` 重新设置）。

**方式 B（手动，立即生效）**

```sh
su -c 'echo 80 > /proc/sys/net/ipv4/ip_unprivileged_port_start'
```

之后 `listen 80;` 即可正常工作。

> 该内核参数是**设备级**的：放宽后任何 App 都能绑定 ≥80 的端口。不需要时删除
> `/data/nginx/allow-low-ports` 并重启手机即可恢复默认。

---

## 为什么以非 root 运行

不是偷懒，是这个二进制**以 root 跑不起来**（实测确认）：

1. nginx 以 root 启动时，会调用 `getpwnam()` 把 worker 进程降权（默认解析 `nobody`，
   或在配置里 `user xxx;`）。
2. 本模块内置的 anmpp nginx 是**静态链接 glibc** 构建（二进制里可见 `libnss_files.so.2`、
   `nsswitch.conf` 等符号）。静态 glibc 的 `getpwnam` 依赖运行时 `dlopen()` NSS 模块，
   静态二进制做不到，因此**必然失败**：`[emerg] getpwnam("nobody") failed (2: No such file or directory)`。
3. 这与 `/etc/passwd` 内容无关——实测该机型 `toybox id root` 能正常解析（系统工具是动态链接），
   同一时刻静态 nginx 仍然失败。所以「补 passwd 条目」「bind mount /etc/passwd」都无效。
4. **以非 root 运行时，nginx 会整个跳过用户解析**，于是稳定可用——anmpp 自己也正是以普通
   App 身份运行 nginx 的。

因此模块做的是：把 nginx 降权到 uid/gid 2000（`shell`，可在 `script/init_env.sh` 里用
`NG_UID`/`NG_GID` 改），运行目录放在 `/data/nginx`（**不能**放 `/data/adb` 下：那里是
0700 root，非 root 进程穿不过去）。

---

## 已知限制

以下都是在真机（Xiaomi 14T Pro / Android 17 / HyperOS）上**实测确认**的，不是推测：

- **不能直接监听 <1024 端口** —— 用上面的 `allow-low-ports` 开关解决（已验证 `listen 80` 可用）。
- **`proxy_pass` 必须写 IP，域名 upstream 用不了** —— 实测两种情况都失败：
  - 直接写域名：`[emerg] host not found in upstream "example.com"`（静态 glibc 缺 `libnss_dns`）
  - `resolver` + 变量写法：`[emerg] SSL_CTX_new() failed`（见下条）
  ```nginx
  proxy_pass http://127.0.0.1:8080;    # ✅ 用 IP
  # proxy_pass http://backend.example.com;   # ❌ 起不来
  ```
- **HTTPS / SSL 不可用** —— 该静态构建的 OpenSSL 有问题，实测任何需要创建 SSL 上下文的配置都会
  `[emerg] SSL_CTX_new() failed`（启动时固定打印的 `SSL_get_ex_new_index() failed` 是同一问题的表征）。
  设 `OPENSSL_CONF=/dev/null` 也无法绕过。所以本模块目前只能做 **HTTP** 反代；要 HTTPS 得换二进制。
- 二进制为 **1.21.6（2022 年）**，且上面两个限制都源自这个静态 glibc/OpenSSL 构建；
  想用 HTTPS 或域名 upstream，请换一个更好的构建（更新版本 / NDK-bionic 静态构建），方法见下一节。

**已实测可用的能力**：静态站点、`stub_status` 状态页、gzip、基于 IP 的反向代理、
`conf.d/` 多站点、开机自启 / 崩溃自愈 / 音量键启停、`listen 80`（配合 `allow-low-ports`）。

---

## 从源码构建

```
依赖：bash + python（Windows 用 Git Bash；Termux 需 pkg install bash curl file）
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
├── customize.sh              # 安装：校验 arm64、布署二进制、播种 /data/nginx
├── service.sh                # 开机 late_start：低端口策略 + 拉守护循环 + 日志轮转
├── action.sh                 # 「执行」音量键菜单（启动/停止/重启/退出）
├── uninstall.sh              # 卸载：停 nginx 并清理 /data/nginx
├── script/init_env.sh        # 路径 / busybox / 降权执行器 / 控制函数（各脚本 source）
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
| nginx 没起来 | 看 `/data/nginx/logs/error.log`；`bind: ...denied` 多为端口被占或低端口权限，换端口或开 `allow-low-ports` |
| 日志报 `getpwnam(...) failed` | 说明 nginx 被以 root 启动了（本静态构建不支持）。请用模块脚本启动，不要手动 `su -c nginx` |
| 反代域名解析失败 | 见[已知限制](#已知限制)：用 IP，或 `resolver` + 变量写法 |
| 重启后没自动启动 | 上次在「执行」里选过「停止」→ `.stopped` 还在，选「启动」即可；或 `rm /data/nginx/.stopped` |
| 「打开」按钮没有 | 官方 Magisk 需装 MMRL/WebUI-X；KernelSU/APatch 原生支持 |
| 安装时报「请从管理器安装」 | 别在 Recovery 刷，必须从管理器 App 安装 |
| 想换低端口策略 | 删掉 `/data/nginx/allow-low-ports` 并重启手机 |
| 日志太大 | 守护 24h 自动清空 >1MB 的日志；也可 `su -c ': > /data/nginx/logs/error.log'` |

---

## 升级到更新的 nginx

二进制是**静态单文件**，但替换时务必注意：**必须仍是「能在 Android 上以非 root 运行」的构建**。
静态 glibc 构建会带来上面的 passwd/DNS 限制；理想是 **NDK(bionic) 静态构建**（bionic 的
`getpwnam` 读 `/etc/passwd` 不依赖 dlopen，仍受限但行为不同）。

步骤：
1. 取一个 arm64 静态、16KB 页对齐的 nginx（Android 15+ 需要 16KB 对齐；
   `readelf -l` 看 `LOAD` 段 Align 是否为 `0x10000`）
2. 覆盖仓库里的 `nginx/nginx`，把 `build.sh` 里的版本串校验同步改掉，`sh build.sh` 重刷
3. 或只替换设备上的 `/data/nginx/nginx` 后在「执行」里选「重启 nginx」

---

## 卸载

管理器 → 模块 → 删除「Nginx for Android」。
`uninstall.sh` 会先停止 nginx 并删除 `/data/nginx`（含你改过的配置与日志）。
想保留配置就先备份 `/data/nginx/conf`。

---

## 说明

- 模块 id：`magisk-nginx`；运行时目录：`/data/nginx`；运行身份：uid/gid 2000
- 本模块不修改任何 `/system` 文件，无需 metamodule（KernelSU 3.x 也直接可用）
- 二进制由 anmpp 项目提供，本仓库仅重新打包分发
