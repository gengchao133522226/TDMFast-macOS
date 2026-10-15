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

## 🚀 编译与运行 (macOS)

### 1. 环境准备

推荐在 macOS 13+ (Ventura / Sonoma / Sequoia) 上运行：
```bash
# 安装 Xcode Command Line Tools
xcode-select --install

# 推荐通过 Homebrew 安装流媒体解析依赖（yt-dlp 和 ffmpeg）
brew install yt-dlp ffmpeg
```

### 2. 使用命令行直接编译与运行

在项目根目录下执行：
```bash
# 编译 Release 版本
swift build -c release

# 直接启动应用
swift run -c release TDMFast
```

### 3. 生成 Xcode 工程（可选）

如果你喜欢使用 Xcode 进行界面调试或打包：
```bash
# 使用 Xcode 直接打开 Package.swift 即可
open Package.swift
```

---

## 🧩 浏览器嗅探插件支持

本程序完全兼容原版 TDM Fast 的官方浏览器插件（Chrome / Edge）：
1. 程序启动后，`SnifferServer` 会自动在 `127.0.0.1:37651` 监听浏览器扩展发送的 HTTP POST 请求。
2. 当浏览器扩展检测到下载或视频时，将请求转发给本地程序，自动唤起“新建下载”或“清晰度选择”窗口。
3. 即使程序未预先开启，浏览器通过网页点击 `tdmfast://` 协议链接时，macOS 会自动唤起本应用并将任务参数传递给下载引擎。

### 🔗 官方浏览器嗅探扩展下载地址

- **Microsoft Edge 加载项商店**：[TDM Fast 资源嗅探 - Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/fbhfbpinjmjhleidkgfjokfkcjgkjjkh)
- **Google Chrome / 其他 Chromium 浏览器**：可直接通过 Edge 加载项商店安装，或访问官方网站 [tdmfast.com](https://tdmfast.com) 获取扩展程序。
