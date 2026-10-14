#!/usr/bin/env bash
# ===========================================================================
# build.sh — 校验二进制 + 规范化行尾(LF) + 打包成 Magisk 可安装 zip
# 在 Windows(Git Bash) / Linux / Termux 上运行：需要 bash + python
# （--fetch 需要 curl，行尾规范化需要 dos2unix 或 python）
# 用法：  sh build.sh            # 使用已就位的 nginx/nginx(本仓库已内置)
#         sh build.sh --fetch    # 缺失时先从 Dirinkbottle release 下载二进制
# 产物：  dist/magisk-nginx.zip
# ===========================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BIN="nginx/nginx"
OUT="$ROOT/dist/magisk-nginx.zip"

# nginx 1.29.1 arm64 静态 bionic 构建(NDK r29, OpenSSL 1.1.1w)
# 来源: https://github.com/Dirinkbottle/nginx-for-andorid-aarch64 (release v1.0.0)
NG_URL="https://github.com/Dirinkbottle/nginx-for-andorid-aarch64/releases/download/v1.0.0/nginx-android-aarch64"
NG_VERSION="nginx/1.29.1"

# --- 可选：拉取二进制 -------------------------------------------------------
if [ "${1:-}" = "--fetch" ] && [ ! -f "$BIN" ]; then
    echo "[*] 下载 nginx $NG_VERSION (arm64 静态 bionic) ..."
    curl -L --fail --retry 3 -o "$BIN" "$NG_URL"
    chmod 755 "$BIN"
fi

# --- 1) 校验二进制 ---------------------------------------------------------
# 用 python 直接解析 ELF(无 file/strings 依赖，Termux 也能跑)：
#   - 必须是 64 位 aarch64
#   - 必须静态(无 PT_INTERP / PT_DYNAMIC)
#   - 必须带 nginx/1.29.1 版本串
[ -f "$BIN" ] || { echo "[x] 缺少 $BIN，请先运行: sh build.sh --fetch"; exit 1; }
echo "[*] 校验二进制 ..."
python - "$BIN" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
assert d[:4] == b"\x7fELF", "不是 ELF 文件"
assert d[4] == 2, "不是 64 位 ELF"
machine, = struct.unpack_from("<H", d, 0x12)
assert machine == 183, "不是 aarch64 (e_machine=%d)" % machine
phoff, = struct.unpack_from("<Q", d, 0x20)
phentsz, = struct.unpack_from("<H", d, 0x36)
phnum, = struct.unpack_from("<H", d, 0x38)
for i in range(phnum):
    t, = struct.unpack_from("<I", d, phoff + i * phentsz)
    assert t not in (2, 3), "含动态段(PT_DYNAMIC/PT_INTERP)，非静态链接"
assert b"nginx/1.29.1" in d, "找不到 nginx/1.29.1 版本串"
print("  ELF 校验通过: aarch64 64-bit, 静态, nginx/1.29.1")
PY
if command -v file >/dev/null 2>&1; then
    file "$BIN"
fi
chmod 755 "$BIN"
echo "[ok] 二进制 OK (nginx 1.29.1, arm64 静态, OpenSSL 1.1.1w)"

# --- 2) 行尾规范化：所有文本文件 -> LF (绝不动二进制) -----------------------
echo "[*] 规范化行尾为 LF ..."
TEXT_FILES="
module.prop
customize.sh
service.sh
action.sh
uninstall.sh
script/init_env.sh
script/nginx_daemon.sh
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
nginx/conf/nginx.conf
nginx/conf/mime.types
nginx/conf/conf.d/00-default.conf
nginx/conf/conf.d/reverse-proxy.conf.example
nginx/html/index.html
webroot/index.html
"
if command -v dos2unix >/dev/null 2>&1; then
    for f in $TEXT_FILES; do
        [ -f "$f" ] || { echo "[x] 缺少 $f"; exit 1; }
        dos2unix -q "$f"
    done
else
    # 无 dos2unix 时用 python 兜底(仅 CRLF->LF)
    python - "$ROOT" <<'PY'
import io, sys, os
root = sys.argv[1]
files = """module.prop customize.sh service.sh action.sh uninstall.sh
script/init_env.sh script/nginx_daemon.sh
META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script
nginx/conf/nginx.conf nginx/conf/mime.types
nginx/conf/conf.d/00-default.conf nginx/conf/conf.d/reverse-proxy.conf.example
nginx/html/index.html webroot/index.html""".split()
for f in files:
    p = os.path.join(root, f)
    data = open(p, "rb").read()
    open(p, "wb").write(data.replace(b"\r\n", b"\n"))
print("  (python 行尾规范化完成)")
PY
fi
echo "[ok] 行尾已统一为 LF"

# --- 3) 打包 zip (python zipfile, deflate + 正确 Unix 权限位) -------------
echo "[*] 生成 $OUT ..."
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
python - "$ROOT" "$OUT" <<'PY'
import os, sys, zipfile, time

root, out = sys.argv[1], sys.argv[2]

# (arcname, unix_mode) ; arcname 相对模块根目录
MANIFEST = [
    ("module.prop",                          0o644),
    ("customize.sh",                         0o755),
    ("service.sh",                           0o755),
    ("action.sh",                            0o755),
    ("uninstall.sh",                         0o755),
    ("script/init_env.sh",                   0o755),
    ("script/nginx_daemon.sh",               0o755),
    ("nginx/nginx",                          0o755),
    ("nginx/conf/nginx.conf",                0o644),
    ("nginx/conf/mime.types",                0o644),
    ("nginx/conf/conf.d/00-default.conf",    0o644),
    ("nginx/conf/conf.d/01-https.conf.example", 0o644),
    ("nginx/conf/conf.d/reverse-proxy.conf.example", 0o644),
    ("nginx/conf/ssl/selfsigned.crt",       0o644),
    ("nginx/conf/ssl/selfsigned.key",       0o600),
    ("nginx/html/index.html",               0o644),
    ("webroot/index.html",                   0o644),
    ("META-INF/com/google/android/update-binary", 0o755),
    ("META-INF/com/google/android/updater-script",  0o644),
]
ORDER = [m for m, _ in MANIFEST]

st = os.stat(root)
tm = time.localtime(st.st_mtime)
dt = (tm.tm_year, tm.tm_mon, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for arc, mode in MANIFEST:
        p = os.path.join(root, *arc.split("/"))
        if not os.path.isfile(p):
            raise SystemExit(f"[x] manifest 中缺少文件: {arc}")
        zi = zipfile.ZipInfo(arc, dt)
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.create_system = 3            # Unix
        zi.external_attr = (mode | 0o100000) << 16   # 高位=unix 权限(含 regular file)
        z.writestr(zi, open(p, "rb").read())

# 复述清单
with zipfile.ZipFile(out) as z:
    for i in z.infolist():
        print("    %o  %6d  %s" % ((i.external_attr >> 16) & 0o777, i.file_size, i.filename))

print(f"[ok] 已生成 {out}")
print("     共 %d 个条目" % len(MANIFEST))
PY

# --- 4) 收尾 --------------------------------------------------------------
echo "[*] 校验产物 ..."
ls -lh "$OUT"
echo "[ok] 构建完成：$OUT"
