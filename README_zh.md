# QuickRecorder

<p align="center">
  <img src="./QuickRecorder/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" alt="QuickRecorder 图标" />
</p>

QuickRecorder 是一款基于 SwiftUI、ScreenCaptureKit 与 AVFoundation 的 macOS 录屏工具，可录制整屏、区域、窗口、系统声音、麦克风，并把可拖动的圆形摄像头画面叠进最终视频。

[English](./README.md)

## Fork 说明

这是由 [zhuhu00](https://github.com/zhuhu00) 维护的社区 Fork，源码位于 [zhuhu00/QuickRecorder](https://github.com/zhuhu00/QuickRecorder)，问题请提交到本 Fork 的 [Issues](https://github.com/zhuhu00/QuickRecorder/issues)。本 Fork 从 2026 年 7 月开始修改，基于 [lihaoyun6/QuickRecorder](https://github.com/lihaoyun6/QuickRecorder)；原作者与上游项目归属保持不变。

当前 Fork 的主要变化包括：

- 增加菜单栏入口和可选择设备的相机、麦克风控制。
- 增加可拖动、置顶并进入最终录屏的圆形相机悬浮层。
- 删除 Application 与 Mobile Device 录制入口，保留整屏、区域和窗口录制。
- 修复录制停止、暂停恢复、麦克风断连降级、QMA 导出和设备身份保存问题。
- 仅面向 Apple Silicon 与 macOS 14.2 及以上版本。

## 安装

预编译版本发布后可从本 Fork 的 [Releases](https://github.com/zhuhu00/QuickRecorder/releases) 下载。当前 Fork 不使用上游 Homebrew Tap，也没有自动更新器。

发布包使用免费的 Apple Development 签名，不是 Developer ID 签名，也未经过 Apple 公证。接收者不需要安装 Xcode 或注册开发者账号，但首次打开时需要：

1. 尝试打开一次 QuickRecorder。
2. 前往“系统设置 → 隐私与安全性”，选择“仍要打开”。
3. 按功能授予“屏幕与系统音频录制”、麦克风和相机权限。
4. 授权后重新启动 QuickRecorder。

详细的构建、验签和交付步骤见 [分发说明](./docs/distribution.md)。

## 从源码运行

1. 安装 Xcode，克隆本仓库并打开 `QuickRecorder.xcodeproj`。
2. 在 QuickRecorder Target 的 Signing & Capabilities 中选择自己的 Personal Team；免费的 Apple Account 足以进行本机调试。
3. 选择 `My Mac` 后运行。首次录制时按系统提示授予权限。

## 系统要求

- Apple Silicon（M 系列）Mac。
- macOS 14.2 或更高版本。

## 功能

- 整屏、区域和单个或多个窗口录制。
- 直接通过 ScreenCaptureKit 录制系统声音，不依赖 BlackHole 等虚拟声卡。
- 系统声音与麦克风同时录制，并支持保留独立音轨。
- 可选择默认或指定麦克风，外接麦克风断开后降级到系统默认输入。
- 可选择内建、外接或 Continuity Camera，圆形预览可拖动、缩放和镜像。
- 鼠标指针、鼠标高亮、屏幕放大镜、隐藏桌面文件和 Presenter Overlay。
- MP4/MOV、H.264/H.265、HEVC with Alpha 和多种音频格式。

## 截图

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./img/preview_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="./img/preview.png">
    <img alt="QuickRecorder 截图" src="./img/preview.png" width="840" />
  </picture>
</p>

## 许可证与致谢

本项目依据 [GNU AGPL-3.0](./LICENSE) 发布，不提供任何担保。发布修改版或二进制时，应同时提供与该版本完全对应的源码，并保留原项目与第三方组件的许可证和版权声明；详见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

感谢原作者 [lihaoyun6](https://github.com/lihaoyun6)、[Azayaka](https://github.com/Mnpn/Azayaka) 以及 KeyboardShortcuts、AECAudioStream、MatrixColorSelector、SwiftLAME 和 LAME 的贡献者。
