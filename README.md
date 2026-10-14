# Nginx for Android — Magisk / KernelSU / APatch 模块

在 Root 手机上运行 **nginx 1.29.1（arm64-v8a 静态 bionic 构建，OpenSSL 1.1.1w）**，
提供**反向代理 / 静态站点 / 状态页 / HTTPS**。
内置开机自启与崩溃自愈守护，通过「执行」按钮提供**音量键控制**（启动 / 停止 / 重启），
「打开」按钮进入 WebUI（当前为施工中占位页）。

- 二进制来源：[Dirinkbottle/nginx-for-andorid-aarch64](https://github.com/Dirinkbottle/nginx-for-andorid-aarch64) release v1.0.0（NDK r29 静态编译，4.9 MB，16KB 页对齐）
- 仅支持 **arm64-v8a**；检测到其它架构会中止安装
- 运行目录 **`/data/nginx`**，nginx 以**非 root 身份**运行（默认 uid/gid 2000，原因见下）
- 安装全程离线，二进制随 zip 一起发布
- **版本升级说明**：v1.21.6.1 用的是 anmpp 的静态 glibc 构建，实测其 OpenSSL 无法创建
  SSL 上下文（`SSL_CTX_new() failed`），HTTPS 不可用；本版换用 1.29.1（静态 bionic +
  OpenSSL 1.1.1w）后支持 HTTPS

---

## 目录

- [功能](#功能)
- [安装（刷入）](#安装刷入)
- [使用方法](#使用方法)
- [反向代理配置](#反向代理配置)
- [HTTPS](#https)
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
| HTTPS | `conf.d/01-https.conf.example`：443 + 自带自签测试证书（见下节） | — |
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

> 若 `nginx/nginx` 缺失：`sh build.sh --fetch` 会自动从 release 下载。

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
├── conf/ssl/                 # 证书目录(自带自签测试证书)
├── conf/conf.d/
│   ├── 00-default.conf              # 默认站点 :8080（状态页 + 静态文件）
│   ├── 01-https.conf.example        # HTTPS 示例(默认不启用)
│   └── reverse-proxy.conf.example   # 反代示例(默认不启用)
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

## HTTPS

v1.29.1 构建（OpenSSL 1.1.1w）支持 HTTPS。模块自带一张**测试用自签证书**
（`conf/ssl/selfsigned.crt` / `selfsigned.key`，CN=nginx-for-android，有效期 10 年）。

启用（同时开 443 低端口）：

```sh
su -c 'touch /data/nginx/allow-low-ports'        # 允许 443(开机时应用)
su -c 'mv /data/nginx/conf/conf.d/01-https.conf.example \
          /data/nginx/conf/conf.d/01-https.conf'
# 「执行」菜单选「重启 nginx」
# 然后: https://<手机IP>/ (浏览器会提示「不安全」—— 自签证书属正常现象)
```

- 需要 443 低端口时别忘了 `allow-low-ports`（见下节）。
- **生产环境请换正式证书**：把 `conf/ssl/` 下换成你的 `.crt`/`.key`，并修改
  `01-https.conf` 里的 `ssl_certificate` / `ssl_certificate_key` 路径，再「重启」。
- 验证握手（电脑侧，设备连好 USB 时）：
  ```sh
  adb forward tcp:8443 tcp:8443        # 如示例改成对应端口
  echo | openssl s_client -connect 127.0.0.1:8443
  ```

---

## 监听 80/443 低端口

nginx 以**非 root 用户**运行，Linux 默认不允许绑定 <1024 的端口
（`net.ipv4.ip_unprivileged_port_start = 1024`）。要监听 80/443，二选一：

**方式 A（推荐，模块内置开关）**

```sh
su -c 'touch /data/nginx/allow-low-ports'
# 重启手机(或等 service.sh 开机执行)；开机时模块会把 ip_unprivileged_port_start 降到 80
```

模块只会在该标志存在时调整内核参数，且**只放宽、不还原**（该参数重启后恢复默认，
因此每次开机由 `service.sh` 重新设置）。

**方式 B（手动，立即生效）**

```sh
su -c 'echo 80 > /proc/sys/net/ipv4/ip_unprivileged_port_start'
```

之后 `listen 80;` / `listen 443 ssl;` 即可正常工作。

> 该内核参数是**设备级**的：放宽后任何 App 都能绑定 ≥80 的端口。不需要时删除
> `/data/nginx/allow-low-ports` 并重启手机即可恢复默认。

---

## 为什么以非 root 运行

1. nginx 以 root 启动时，会调用 `getpwnam()` 解析 worker 降权用户（默认 `nobody`，
   或配置里的 `user xxx;`）。
2. Android（尤其 15+）的 `/system/etc/passwd` 被系统裁剪，**没有 `root`/`nobody` 条目**；
   而静态二进制（glibc 版甚至读不到 passwd 数据库）解析用户名必然失败：
   `[emerg] getpwnam("nobody") failed (2: No such file or directory)`。
   补 passwd 条目 / bind mount 都救不了（已在真机实测确认）。
3. **以非 root 运行时，nginx 会整个跳过用户解析**，于是稳定可用——anmpp 等同类项目
   也都是以普通 uid 运行 nginx。

因此模块把 nginx 降权到 uid/gid 2000（`shell`，可在 `script/init_env.sh` 里用
`NG_UID`/`NG_GID` 改），运行目录放在 `/data/nginx`（**不能**放 `/data/adb` 下：
那里是 0700 root，非 root 进程穿不过去）。

---

## 已知限制

- **不能直接监听 <1024 端口** —— 用上面的 `allow-low-ports` 开关解决（已验证 `listen 80` 可用）。
- **`proxy_pass` 建议写 IP** —— 静态二进制的 `getaddrinfo` 依赖系统 DNS
  （`/system/etc/resolv.conf`，Android 上通常不存在）：直接写域名可能
  `host not found in upstream`。可用 `resolver 223.5.5.5;` + 变量写法替代：
  ```nginx
  resolver 223.5.5.5 valid=30s;
  set $backend "backend.example.com";
  proxy_pass http://$backend:8080;
  ```
  （1.29.1 构建的 SSL 正常，旧版 1.21.6 上此写法会踩 `SSL_CTX_new` 问题，新版无此坑）
- **自签证书**只适合内网测试；公网/正式域名请换 CA 签发的证书。
- 该 1.29.1 构建**未含 FastCGI**（不能直接反代 PHP-FPM）；需要的话见下节换二进制。
- HTTP/2：该构建未编译 `--with-http_v2_module`，默认只有 HTTP/1.1。

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
1. ELF 校验（python 解析：aarch64 / 静态 / 含 `nginx/1.29.1` 串），不合格不出包
2. 所有文本脚本/配置 `dos2unix` 为 LF（Android 上 CRLF 会直接报错）
3. 用 Python `zipfile` 按清单打 Deflate zip，并写入正确 Unix 权限位
   （`*.sh`/`update-binary`/二进制 = 755，配置 = 644，ssl 密钥 = 600）

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
│   ├── nginx                 # 二进制（1.29.1 arm64 静态 bionic, OpenSSL 1.1.1w）
│   ├── conf/{nginx.conf,mime.types,ssl/,conf.d/*.conf}
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
| nginx 没起来 | 看 `/data/nginx/logs/error.log`；`bind: ...denied` 多为端口被占或低端口未开 `allow-low-ports` |
| 日志报 `getpwnam(...) failed` | 说明 nginx 被以 root 启动了。请用模块脚本启动，不要手动 `su -c nginx` |
| HTTPS 握手失败 | 看 `error.log`；确认 `01-https.conf` 里证书路径对、`allow-low-ports` 已开、443 没被占 |
| 反代域名解析失败 | 见[已知限制](#已知限制)：用 IP，或 `resolver` + 变量写法 |
| 重启后没自动启动 | 上次在「执行」里选过「停止」→ `.stopped` 还在，选「启动」即可；或 `rm /data/nginx/.stopped` |
| 「打开」按钮没有 | 官方 Magisk 需装 MMRL/WebUI-X；KernelSU/APatch 原生支持 |
| 安装时报「请从管理器安装」 | 别在 Recovery 刷，必须从管理器 App 安装 |
| 浏览器提示证书不安全 | 正常：默认是自签测试证书，换 CA 证书即消失 |
| 日志太大 | 守护 24h 自动清空 >1MB 的日志；也可 `su -c ': > /data/nginx/logs/error.log'` |

---

## 升级到更新的 nginx

二进制是**静态单文件**，替换时务必注意：**必须仍能在 Android 上以非 root 运行**，且
**16KB 页对齐**（Android 15+ 需要；`readelf -l` 看 `LOAD` 段 Align 是否为 `0x10000`）。
想要 HTTPS 优先选 **NDK(bionic) 静态构建**；想要 FastCGI/HTTP2 则需自己用 NDK 交叉编译
（`--with-http_v2_module`、`--with-http_fastcgi_module` 等），配方可参考
[ryanlee486/nginx-android](https://github.com/ryanlee486/nginx-android)。

步骤：
1. 取一个 arm64 静态、16KB 页对齐的 nginx
2. 覆盖仓库里的 `nginx/nginx`，把 `build.sh` 里的版本串/URL 同步改掉，`sh build.sh` 重刷
3. 或只替换设备上的 `/data/nginx/nginx` 后在「执行」里选「重启 nginx」

---

## 卸载

管理器 → 模块 → 删除「Nginx for Android」。
`uninstall.sh` 会先停止 nginx 并删除 `/data/nginx`（含你改过的配置、证书与日志）。
想保留配置/证书就先备份 `/data/nginx/conf`。

---

## 说明

- 模块 id：`magisk-nginx`；运行时目录：`/data/nginx`；运行身份：uid/gid 2000
- 本模块不修改任何 `/system` 文件，无需 metamodule（KernelSU 3.x 也直接可用）
- 二进制来自社区预编译构建，本仓库仅重新打包分发；使用前请自行评估信任边界
