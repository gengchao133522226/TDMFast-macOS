#!/bin/bash
set -e

echo "=========================================="
echo "  🚀 TDM Fast for macOS 一键自动安装脚本"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="/Applications/TDM Fast.app"

# 1. 检查并安装多媒体流解析依赖 (ffmpeg & yt-dlp)
echo ""
echo "🔍 检查流媒体解析依赖 (ffmpeg & yt-dlp)..."
if command -v brew >/dev/null 2>&1; then
    MISSING_PKGS=()
    if ! command -v ffmpeg >/dev/null 2>&1; then
        MISSING_PKGS+=("ffmpeg")
    fi
    if ! command -v yt-dlp >/dev/null 2>&1; then
        MISSING_PKGS+=("yt-dlp")
    fi

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo "📦 正在自动通过 Homebrew 安装依赖: ${MISSING_PKGS[*]}..."
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "${MISSING_PKGS[@]}"
    else
        echo "✅ ffmpeg 与 yt-dlp 均已就绪！"
    fi
else
    echo "⚠️ 未检测到 Homebrew，请确保手动安装了 ffmpeg 和 yt-dlp 以支持流媒体音视频合轨。"
fi

# 2. 编译 Release 原生应用
echo ""
echo "🔨 正在使用 Swift 编译器编译 Release 原生版本..."
cd "$SCRIPT_DIR"
swift build -c release

# 3. 组装 .app 安装包
echo ""
echo "📦 正在打包应用至 /Applications/TDM Fast.app..."
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$SCRIPT_DIR/.build/release/TDMFast" "$APP_PATH/Contents/MacOS/TDMFast"
chmod +x "$APP_PATH/Contents/MacOS/TDMFast"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# 4. 清理隔离属性并完成签名
echo "🔐 正在注册本地安全签名并移除隔离属性..."
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "=========================================="
echo "🎉 安装完成！TDM Fast 已安装至 /Applications"
echo "支持原生自动合流为 .mp4 格式，可在启动台直接运行！"
echo "=========================================="
