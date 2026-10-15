# TDM Fast for macOS (SwiftUI 原生轻量版)

本项目是基于对 **TDM Fast (freedm)** 逆向分析后，为 **macOS** 平台全新编写的 100% 原生高效下载器。

使用 **Swift 5.9+ / SwiftUI** 架构重写，替代了原版体积庞大且资源占用高的 Electron 运行时，具备极致的轻量性（内存占用从 300MB+ 骤降至 ~25MB，零冗余开销），并去除了原版商业授权限制。

---

## 🌟 核心特性与逆向还原对比

| 功能模块 | 原版 (Electron / Windows) | 本版 (SwiftUI / macOS) |
| :--- | :--- | :--- |
| **GUI 架构** | Electron + Node.js (150MB+ 体积) | **SwiftUI 纯原生** (极致启动速度与低内存) |
| **HTTP 分块加速** | Node.js stream + HTTP Range | **Swift Concurrency + FileHandle 分片并发** (支持 1~64 线程) |
| **流媒体音视频解析** | `yt-dlp.exe` + `ffmpeg.exe` | **原生适配 macOS Homebrew / 内部嵌入的 `yt-dlp` 与 `ffmpeg`** |
| **视频清晰度选择** | 弹出 Electron Web 窗口 | **原生 SwiftUI 视频信息与分辨率选择面板** |
| **浏览器嗅探插件联动** | 127.0.0.1:37651 HTTP 本地服务 | **Apple Network Framework (`NWListener`) 本地原生监听服务** |
| **深度链接唤起** | `tdmfast://` Windows 注册表协议 | **macOS `tdmfast://` URL Scheme 原生协议关联** |
| **系统交互** | Windows 任务栏托盘 | **macOS MenuBarExtra 菜单栏状态与 Dock 原生交互** |
| **商业授权锁定** | 依赖远程 `activate.tdmfast.com` | **完全移除授权锁，永久免费开箱即用** |

---

## 🛠️ 项目结构

```text
TDMFast-macOS/
├── Package.swift                    # Swift Package Manager 工程配置文件
├── README.md                        # 本文档
├── Resources/
│   ├── Info.plist                   # 包含 tdmfast:// 协议与网络权限配置
│   └── TDMFast.entitlements         # macOS 沙盒与网络权限描述
└── Sources/
    └── TDMFast/
        ├── App/
        │   ├── TDMFastApp.swift     # SwiftUI 应用入口与 URL 协议监听
        │   └── AppDelegate.swift    # 原生生命周期与窗口响应
        ├── Models/
        │   ├── DownloadTask.swift   # 下载任务数据模型
        │   ├── TaskStatus.swift     # 状态与分类定义
        │   ├── AppSettings.swift    # 本地偏好设置持久化
        │   └── VideoQuality.swift   # 音视频清晰度解析模型
        ├── Engine/
        │   ├── DownloadManager.swift# 核心任务调度与并发管理
        │   ├── ChunkDownloader.swift# HTTP 多线程 Range 切片与断点续传
        │   ├── FileSegment.swift    # 分段文件结构
        │   ├── YtDlpService.swift   # yt-dlp 视频解析与下载通道
        │   └── SnifferServer.swift  # 127.0.0.1:37651 浏览器扩展嗅探监听服务
        └── Views/
            ├── MainWindowView.swift # 主窗口与统一工具栏
            ├── SidebarView.swift    # 左侧分类导航
            ├── TaskListView.swift   # 任务列表与实时进度展示
            ├── TaskRowView.swift    # 单个任务行（包含速度、剩余时间、操作）
            ├── NewDownloadSheet.swift # 新建下载与剪贴板自动识别面板
            ├── VideoQualitySheet.swift# 视频清晰度自选面板
            ├── SettingsView.swift   # 偏好设置面板（线程、代理、路径等）
            └── MenuBarView.swift    # macOS 顶部菜单栏快捷面板
```

---

## 🚀 下载与安装 (macOS)

### 1. 免编译直接安装（推荐，无需 12GB Xcode）

普通用户**无需**在电脑上安装庞大的完整版 Xcode（约 12GB），直接下载官方预编译好的 DMG 镜像即可：

👉 **[下载最新版 TDM-Fast-macOS.dmg](https://github.com/gengchao133522226/TDMFast-macOS/releases/latest/download/TDM-Fast-macOS.dmg)**

**安装方法**：
1. 双击下载好的 `TDM-Fast-macOS.dmg` 打开；
2. 将 **TDM Fast** 图标直接拖拽到旁边的 **Applications（应用程序）** 文件夹即可！

> 🛡️ **首次打开提示「无法打开，因为 Apple 无法检查恶意软件」解决办法**：
> 这是 macOS 对未购买苹果 99 美元年费商业证书的开源软件的默认拦截保护（Gatekeeper 机制）。**只需操作一次即可解除**：
> - **方法 A（最快捷）**：在访达「应用程序」中找到 **TDM Fast**，**按住键盘 `Control` 键点击图标（或右键）**，在弹出菜单中点击 **「打开」**，再点击弹窗中的 **「仍要打开」** 即可！
> - **方法 B**：进入 Mac **「系统设置」->「隐私与安全性」**，在底部找到 *已阻止“TDM Fast”*，点击旁边的 **「仍要打开」**。
> - **方法 C（终端一条命令）**：在终端执行 `xattr -cr "/Applications/TDM Fast.app"` 彻底移除隔离标识。

> 💡 **关于流媒体视频解析**：
> 如果需要下载 YouTube、B 站等流媒体高清视频，请在终端执行一次以下命令（无需 Xcode，只需通过 Homebrew 安装流媒体合流工具）：
> ```bash
> brew install yt-dlp ffmpeg
> ```

---

### 2. 源码本地编译与全自动构建脚本（开发者可选）

> ⚠️ **编译提示**：如果选择自行从源码编译，因苹果官方 SDK 机制限制，macOS 纯 Command Line Tools 会报 `unable to lookup item 'PlatformPath'` 错误，**本地源码编译需要机器安装了完整的 Xcode**。若没有安装 Xcode，请直接使用上方的 **[DMG 直接安装]**。

如果您本机安装了完整 Xcode 并希望从源码构建：
```bash
# 一键自动构建并安装至 /Applications
chmod +x install.sh
./install.sh
```

本项目流媒体解析基于 `yt-dlp` 与 `ffmpeg`：
- **为什么需要 FFmpeg？**
  - **音视频分离合并**：主流平台（如 YouTube、B 站、X/Twitter 等）的 1080P、2K、4K 等高分辨率视频，其服务器上视频轨与音频轨是**完全分离存放**的。`yt-dlp` 下载完成后必须依赖 `ffmpeg` 进行多轨无损合流。
  - **默认自动封装为 `.mp4` 格式**：现代平台的高清视频多采用 VP9/AV1 编码（默认容器为 `.webm`，macOS 自带 QuickTime 默认无法直接播放）。本项目内部已配置自动调用 `ffmpeg` 执行 `--merge-output-format mp4`，**下载合并后会自动输出为通用的 `.mp4` 格式**，无需额外手动转码即可在 Mac 访达、QuickTime、手机相册中流畅播放！

若希望手动安装流媒体依赖：
```bash
# 推荐通过 Homebrew 一键安装
brew install yt-dlp ffmpeg
```

---

### 3. 手动编译与运行（可选）

如果你喜欢手动编译或调试：
```bash
# 1. 编译 Release 原生版本
swift build -c release

# 2. 命令行直接启动
swift run -c release TDMFast

# 3. 或使用 Xcode 打开项目
open Package.swift
```

---

## 🧩 浏览器嗅探插件支持

本程序完全兼容原版 TDM Fast 的官方浏览器插件（Chrome / Edge）：
1. 程序启动后，`SnifferServer` 会自动在 `127.0.0.1:37651` 监听浏览器扩展发送的 HTTP POST 请求。
2. 当浏览器扩展检测到下载或视频时，将请求转发给本地程序，自动唤起“新建下载”或“清晰度选择”窗口。
3. 即使程序未预先开启，浏览器通过网页点击 `tdmfast://` 协议链接时，macOS 会自动唤起本应用并将任务参数传递给下载引擎。

### 🔗 官方浏览器嗅探扩展下载与安装

本插件为 Chromium 通用扩展（Manifest V3），同时完美支持 **Google Chrome** 与 **Microsoft Edge**：

#### 方案一：在 Chrome / Edge 中直接一键安装（推荐）
1. 在浏览器（Chrome 或 Edge 均可）中直接打开：[TDM Fast 资源嗅探 - Edge Add-ons 商店](https://microsoftedge.microsoft.com/addons/detail/fbhfbpinjmjhleidkgfjokfkcjgkjjkh)；
2. 如果是在 **Google Chrome** 中打开，页面顶部会提示 *“允许来自其他应用商店的扩展程序”*，点击允许；
3. 点击右侧蓝色的 **“获取”**（或“添加至 Chrome”）按钮即可一键完成安装。

#### 方案二：通过本地离线包导入（Chrome / Brave / Vivaldi 等）
本项目已在代码仓库中直接内置了开箱即用的插件包：
- **离线 Zip 安装包下载**：[browser-extension.zip](Resources/browser-extension.zip)（或解压目录 [`Resources/browser-extension`](Resources/browser-extension)）

**安装步骤**：
1. 下载并解压 `browser-extension.zip`（若直接拉取了仓库代码则直接使用 `Resources/browser-extension` 目录）；
2. 打开 Chrome 并在地址栏输入：`chrome://extensions/`
3. 打开右上角的 **“开发者模式”**（Developer mode）开关；
4. 点击左上角 **“加载已解压的扩展程序”**（Load unpacked），选择该文件夹即可直接导入使用（亦可直接将文件夹拖入 Chrome 扩展管理窗口）。
