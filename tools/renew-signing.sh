#!/bin/bash
# 众妙：免费 Apple 账号的签名续期 + 真机重装
#
# 免费个人团队（Personal Team）签出的描述文件固定 7 天过期，且无法"提前续期"——
# Xcode 只在描述文件缺失或已过期时才重新签发，构建一次并不会把到期时间往后推。
# 所以续期的实质是：重建描述文件 → 重新构建 → 重新安装到设备。
# 设备上的 App 内嵌的是旧的 embedded.mobileprovision，光在 Mac 上刷新没用。
#
# 用法：
#   tools/renew-signing.sh           # 剩余不足 2 天才动作（日常由 launchd 调用）
#   tools/renew-signing.sh --force   # 无论如何都重建一次（排障 / 首次验证）
#
# 环境变量可覆盖：ZM_DEVICE（设备 UDID）、ZM_TEAM（Team ID）、
#                 ZM_PROJECT_DIR、ZM_RENEW_THRESHOLD（提前几天续，默认 2）

set -uo pipefail

PROJECT_DIR="${ZM_PROJECT_DIR:-$HOME/Git/zhongmiao}"
TEAM="${ZM_TEAM:-2C6YRKGU49}"
DEVICE="${ZM_DEVICE:-00008150-001E15E42E87801C}"
BUNDLE_ID="im.yufei.zhongmiao"
THRESHOLD_DAYS="${ZM_RENEW_THRESHOLD:-2}"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
LOG="$HOME/Library/Logs/zhongmiao-renew.log"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# launchd 环境下 PATH 很干净，xcodebuild / xcrun 都在 /usr/bin
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

log() {
    mkdir -p "$(dirname "$LOG")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

# 找出本 App 的描述文件，输出剩余天数（小数）
remaining_days() {
    local f="$1"
    local exp
    exp=$(security cms -D -i "$f" 2>/dev/null \
          | plutil -extract ExpirationDate xml1 -o - - 2>/dev/null \
          | sed -n 's/.*<date>\(.*\)<\/date>.*/\1/p')
    [ -z "$exp" ] && { echo "-1"; return; }
    local exp_epoch now_epoch
    exp_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$exp" "+%s" 2>/dev/null)
    now_epoch=$(date -u "+%s")
    [ -z "$exp_epoch" ] && { echo "-1"; return; }
    echo $(( (exp_epoch - now_epoch) / 86400 ))
}

# 本 App 相关的描述文件（主 App 与 Widget 是两份，都要处理）
collect_profiles() {
    profiles=()
    for f in "$PROFILE_DIR"/*.mobileprovision; do
        [ -e "$f" ] || continue
        name=$(security cms -D -i "$f" 2>/dev/null \
               | plutil -extract AppIDName xml1 -o - - 2>/dev/null \
               | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
        case "$name" in
            *zhongmiao*|*Zhongmiao*) profiles+=("$f") ;;
        esac
    done
}

collect_profiles

if [ ${#profiles[@]} -eq 0 ]; then
    log "未找到描述文件，视为需要重建（首次或已被清理）"
    min_days=-1
else
    min_days=99999
    for f in "${profiles[@]}"; do
        d=$(remaining_days "$f")
        [ "$d" -lt "$min_days" ] && min_days=$d
    done
    log "描述文件剩余 ${min_days} 天（阈值 ${THRESHOLD_DAYS} 天）"
fi

if [ "$FORCE" -eq 0 ] && [ "$min_days" -ge "$THRESHOLD_DAYS" ]; then
    exit 0   # 还早，什么都不做——每天被调用也不该打扰用户
fi

# 设备必须可见（USB 或同一 Wi-Fi 下已配对）
if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE"; then
    log "设备 $DEVICE 不可见，跳过（下次再试）"
    exit 0
fi

log "开始续期：重建描述文件 → 构建 → 重装"

# 1. 清掉旧描述文件，逼 Xcode 重新签发
for f in "${profiles[@]}"; do
    rm -f "$f"
done

# 2. 重新构建
# 必须清掉整个 DerivedData，不能只删 Products：增量构建系统把上一轮用过的
# 描述文件路径记成了 input file，那份文件刚被我们删掉，只清产物会直接报
# "Build input file cannot be found"。
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
rm -rf "$DERIVED"/Zhongmiao-* 2>/dev/null

cd "$PROJECT_DIR" || { log "项目目录不存在：$PROJECT_DIR"; exit 1; }

if ! xcodebuild -project Zhongmiao.xcodeproj -scheme Zhongmiao \
        -destination "platform=iOS,id=$DEVICE" \
        DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates build >/tmp/zm-renew-build.log 2>&1; then
    log "构建失败：$(grep -m1 'error:' /tmp/zm-renew-build.log)"
    exit 1
fi

# iOS 产物的目录名已改成 ASCII（Configurator 的 AFC 传输对非 ASCII 目录名有坑），
# 旧的「众妙.app」保留兼容。
APP=$(ls -d "$DERIVED"/Zhongmiao-*/Build/Products/Debug-iphoneos/Zhongmiao.app 2>/dev/null | head -1)
[ -z "$APP" ] && APP=$(ls -d "$DERIVED"/Zhongmiao-*/Build/Products/Debug-iphoneos/众妙.app 2>/dev/null | head -1)
[ -z "$APP" ] && { log "未找到构建产物"; exit 1; }

# 3. 装到设备（覆盖安装，App 容器内的数据保留）
if ! xcrun devicectl device install app --device "$DEVICE" "$APP" >/tmp/zm-renew-install.log 2>&1; then
    log "安装失败：$(tail -2 /tmp/zm-renew-install.log | tr '\n' ' ')"
    exit 1
fi

collect_profiles
new_days=99999
for f in "${profiles[@]}"; do
    d=$(remaining_days "$f")
    [ "$d" -lt "$new_days" ] && new_days=$d
done
log "续期完成，新描述文件剩余 ${new_days} 天（共 ${#profiles[@]} 份），已重装到设备"
