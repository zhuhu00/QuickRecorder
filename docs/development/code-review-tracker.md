# QuickRecorder 代码审查与开发跟踪

> 本文档用于跟踪 QuickRecorder 当前代码审查发现、兼容性边界和发布准备工作。修复完成后应更新对应条目的状态、验证结果和变更记录，不要仅删除问题描述。

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 首次审查日期 | 2026-07-22 |
| 审查基线 | `main` / `ca87910 feat: customize QuickRecorder recording workflow` |
| 当前总体状态 | 适合本机开发测试；暂不建议直接分发二进制 |
| 建议首发范围 | Apple Silicon (`arm64`) / macOS 14.2 及以上 |
| 主要技术 | SwiftUI、AppKit、ScreenCaptureKit、AVFoundation |
| 不在本文范围 | BlackHole 驱动的修改、构建、安装和卸载 |

状态约定：

- `待处理`：问题已经确认，尚未开始修改。
- `进行中`：已经开始修改，但尚未通过全部验收标准。
- `已阻塞`：存在明确的外部依赖或决策阻塞。
- `已完成`：代码、构建和对应验证均已通过。
- `已移除`：对应功能已经从产品和源码中删除，原问题不再适用。
- `不处理`：明确接受风险，并记录原因。

优先级约定：

- `P1`：可能破坏核心录制功能、导致文件不完整或产生明显错误行为，分发前必须处理。
- `P2`：稳定性、兼容性或可维护性问题，应在首个可分发版本前处理。
- `P3`：发布卫生、长期维护或体验问题，可在核心问题之后处理。

## 2. 审查结论

当前代码可以在 Apple Silicon Mac 上生成原生 `arm64` 应用，不依赖 Rosetta。主要分发风险不是 M 系列芯片兼容性，而是以下三类问题：

1. 相机悬浮窗的显示状态、录制状态和 Capture Session 生命周期没有完全对齐。
2. ScreenCaptureKit、麦克风 Writer、文件合成之间缺少严格的异步停止顺序。
3. 缺少自动化测试、可重复的设备回归矩阵和正式 Release 签名流程。

`QR-001` 至 `QR-004` 已完成，当前没有未解决的 P1；正式分发前仍需处理下表中的 P2 兼容性、错误处理和发布问题。

## 3. 问题总表

| ID | 优先级 | 状态 | 模块 | 摘要 |
| --- | --- | --- | --- | --- |
| QR-001 | P1 | 已完成 | 相机叠加 | 开始录制前会隐藏相机悬浮窗，Camera 状态仍显示开启 |
| QR-002 | P1 | 已完成 | 系统音频 | 麦克风 Writer 完成前就开始读取并导出 QMA |
| QR-003 | P1 | 已完成 | 录制停止 | SCStream 尚未完全停止，AVAssetWriter 已开始结束写入 |
| QR-004 | P1 | 已完成 | 相机 | 删除 Mobile Device 后，电脑相机独占 Capture Session |
| QR-005 | P2 | 待处理 | 错误处理 | 常规磁盘或设备错误可能触发崩溃，而不是可恢复失败 |
| QR-006 | P2 | 待处理 | 系统兼容 | 标称支持 macOS 12.3，但系统音频实际需要 macOS 13 |
| QR-007 | P2 | 进行中 | 视频配置 | 已修复无效 `CMTime`，等待 30/60 FPS 真实录制验证 |
| QR-008 | P2 | 已移除 | 手机录制 | Mobile Device 功能已整体删除，错误通知路径不再存在 |
| QR-009 | P2 | 待处理 | 麦克风 | 外接麦克风按名称保存，断连或重名时可能静默录制无声文件 |
| QR-010 | P2 | 待处理 | 工程质量 | 没有应用测试 Target 或 CI，Swift 6 并发迁移债务较高 |
| QR-011 | P2 | 进行中 | 构建分发 | Release 已限定 arm64 并使用开发签名，等待干净 Mac 手动放行验证 |
| QR-012 | P3 | 待处理 | 开源发布 | README、版本、AGPL 和第三方依赖声明尚未按 Fork 发布整理 |
| QR-013 | P3 | 待处理 | 系统兼容 | 使用精确主版本判断，较新 macOS 会遗漏部分分支逻辑 |

## 4. 详细问题与验收标准

### QR-001：开始录制时相机悬浮窗被隐藏

- 优先级：`P1`
- 状态：`已完成`
- 证据：
  - `QuickRecorder/ViewModel/ScreenSelector.swift:154`
  - `QuickRecorder/ViewModel/AppSelector.swift:164`
  - `QuickRecorder/ViewModel/WinSelector.swift:249`
  - `QuickRecorder/ViewModel/AreaSelector.swift:222`
  - `QuickRecorder/QuickRecorderApp.swift:400`
- 问题：各录制选择器在开始录制前调用 `closeAllWindow()`。该函数会把 `camWindow` 关闭或移出屏幕，但不会清空 `SCContext.recordCam`，也不会停止相机 Session。界面可能继续显示 Camera 已开启，而屏幕录制无法稳定捕获相机悬浮窗。
- 修复方向：相机悬浮窗不应被通用关窗逻辑关闭；录制开始前应明确恢复相机窗口层级，并在生成 `SCContentFilter` 时确认窗口可捕获。
- 当前修复：`closeAllWindow()` 在 `SCContext.recordCam` 非空时保留同一个 `camWindow`，避免录制选择器、快捷键或 AppleScript 开始录制时把已开启的相机悬浮窗关闭。取消 Camera 或录制结束仍由原有 `closeCamera()` 显式停止并隐藏相机。
- 当前验证：`arm64 Debug` 构建与 Xcode 静态分析通过，`git diff --check` 通过；用户已完成真实摄像头录屏回归，确认相机悬浮窗保持可见并进入最终录屏。
- 验收标准：
  1. 开启 Camera 后分别启动整屏、区域、应用和多窗口录制，相机圈从录制第一帧开始可见。
  2. 打开或关闭菜单栏 Popover 不影响相机圈可见性。
  3. Camera 开关状态、`recordCam`、Session 运行状态和窗口可见状态一致。
  4. 单窗口录制若继续不支持相机叠加，界面必须在开始前明确禁用或提示，不能录完后才发现缺失。

### QR-002：QMA 导出早于麦克风 Writer 完成

- 优先级：`P1`
- 状态：`已完成`
- 证据：`QuickRecorder/SCContext.swift:388`、`QuickRecorder/SCContext.swift:420`
- 问题：系统音频和麦克风同时录制时，`finishWriting` 异步执行，但代码立即加载 `.qma` 并启动混音导出，可能读取到尚未完成或被截断的麦克风文件。
- 修复方向：只有在麦克风 Writer 明确完成且状态为 `.completed` 后，才能加载 QMA、导出最终音频和删除 QMA。
- 当前修复：停止系统音频录制时捕获本次录制的路径和导出设置；只有麦克风 `AVAssetWriter.finishWriting` 回调确认状态为 `.completed` 后才加载并导出 QMA。Writer 或 QMA 加载失败会发送失败通知并保留原始 QMA；MP3 成功通知移动到转码完成之后。
- 当前验证：`arm64 Debug` 构建与 Xcode 静态分析通过，且没有新增编译警告；`git diff --check` 通过。用户已完成“系统音频＋麦克风”真实录制，确认最终声音和 QMA 清理结果正常。
- 验收标准：
  1. 连续执行至少 20 次“系统音频＋麦克风”短录制，最终文件均包含两条声音。
  2. 录制结束后不会遗留半成品 `.qma`，导出失败时则保留 QMA 供恢复。
  3. MP3 转换完成前不发送最终成功通知。
  4. Writer 失败时显示可理解的错误，不删除原始轨道。

### QR-003：停止 Capture 与结束 Writer 的顺序存在竞态

- 优先级：`P1`
- 状态：`已完成`
- 证据：`QuickRecorder/SCContext.swift:342`、`QuickRecorder/SCContext.swift:353`、`QuickRecorder/SCContext.swift:386`
- 问题：代码发起 `stopCapture()` 后立即释放 Stream、停止麦克风、标记 Writer Input 完成并调用 `finishWriting()`。尾部 SampleBuffer 可能在 Input 结束后继续到达；`dispatchGroup.wait()` 还可能阻塞主线程。
- 修复方向：建立单一录制状态机，按“停止接收 Sample → 等待 Stream 停止 → 停止麦克风 → 标记 Input 完成 → Writer Finalize → 后处理”的顺序异步执行。
- 当前修复：屏幕和系统音频 Sample 改用同一个串行输出队列；停止时保持 `streamType` 并进入 `isStopping`，等待 `SCStream.stopCapture` 完成后排空输出队列，再停止并排空麦克风、标记 Writer Input、异步 Finalize 和执行后处理。重复停止只复用同一次流程，退出 App 时使用 `terminateLater` 等待录制收尾。
- 当前验证：`arm64 Debug` 构建和 Xcode 静态分析通过且没有新增编译警告；主线程上的 `dispatchGroup.wait()` 已移除。用户已完成真实录屏，确认 Processing 状态、尾部音画、文件可读性和快速重复停止均正常。
- 验收标准：
  1. 停止录制时界面不冻结，状态栏能立即进入“处理中”状态。
  2. 最后几帧、最后一句麦克风声音和系统声音不被截断。
  3. 重复点击停止按钮不会触发二次 Finalize 或崩溃。
  4. Stream 错误、用户停止和应用退出共用同一个幂等停止入口。

### QR-004：相机与手机功能共享 Capture Session

- 优先级：`P1`
- 状态：`已完成`
- 原证据：`QuickRecorder/AVContext.swift` 中的 `AVOutputClass`、`SCContext.captureSession` 和 `SCContext.previewSession`
- 问题：电脑相机、手机录制和手机预览都写入 `SCContext.captureSession` 或紧邻的全局 Session，后启动的功能会覆盖前一个 Session 的引用，导致停止错误对象、摄像头灯常亮或预览黑屏。
- 当前修复：根据产品决策整体删除 Mobile Device。移除了 USB 屏幕设备发现、`AVOutputClass`、`previewSession`、手机预览窗口、手机录制状态栏分支和对应菜单入口；`SCContext.captureSession` 现在只归普通 Camera 悬浮层所有。
- 保留边界：`SCContext.getCameras()` 仍可发现外接摄像头和 iPhone Continuity Camera；它们都作为普通 Camera 输入，不是手机屏幕录制。
- 当前验证：源码与工程中不存在 `idevice`、`AVOutputClass`、`previewSession`、`.muxed` 和 `iDeviceSelector` 残留引用；`arm64 Debug` 构建通过。
- 验收标准：
  1. 主界面和菜单栏不再显示 Mobile Device。
  2. 工程不再启用或发现 `.muxed` 手机屏幕采集设备。
  3. 普通 Camera 和 Continuity Camera 继续使用同一套相机悬浮层。

### QR-005：可恢复错误会转为崩溃

- 优先级：`P2`
- 状态：`待处理`
- 证据：
  - `QuickRecorder/RecordEngine.swift:327`
  - `QuickRecorder/RecordEngine.swift:331`
  - `QuickRecorder/RecordEngine.swift:340`
  - `QuickRecorder/RecordEngine.swift:378`
  - `QuickRecorder/RecordEngine.swift:462`
- 问题：录制路径存在 `try!`、隐式解包对象和 `try?` 后继续强制使用的情况。磁盘已满、目录失效、Writer 创建失败或麦克风启动失败都可能导致崩溃。
- 修复方向：将录制准备阶段改为可失败流程，在开始 Capture 前完成目录、Writer、输入和设备验证。
- 验收标准：
  1. 输出目录不可写、磁盘空间不足和麦克风不可用时不崩溃。
  2. 失败后所有 Session、Writer 和 UI 状态均恢复到未录制状态。
  3. 用户能看到具体失败原因和建议操作。

### QR-006：最低系统版本与核心功能不一致

- 优先级：`P2`
- 状态：`待处理`
- 证据：
  - `README_zh.md:19`
  - `QuickRecorder/RecordEngine.swift:216`
  - `QuickRecorder/RecordEngine.swift:288`
- 问题：项目和 README 标称支持 macOS 12.3，但 ScreenCaptureKit 的系统音频输出从 macOS 13 开始可用。macOS 12 用户可能可以启动应用，却无法使用核心系统声音录制。
- 决策建议：首个 Fork 版本直接支持 `arm64 + macOS 14.2 及以上`，降低 Presenter Overlay、菜单栏捕获和权限差异带来的维护成本。
- 验收标准：
  1. Xcode Deployment Target、README、Release 说明和运行时提示一致。
  2. 低于最低版本时系统阻止安装或给出明确说明，不展示不可用功能。

参考：[Apple `capturesAudio` 文档](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio)。

### QR-007：60 FPS 使用无效 CMTime

- 优先级：`P2`
- 状态：`进行中`
- 证据：`QuickRecorder/QuickRecorderApp.swift:127`、`QuickRecorder/RecordEngine.swift:224`
- 问题：默认帧率为 60，但 `frameRate >= 60` 时构造 `CMTime(value: 1, timescale: 0)`。该值无效，不等价于“使用最大帧率”。
- 当前修复：所有界面中明确选择的 FPS 都使用合法的 `CMTime(value: 1, timescale: max(frameRate, 1))`；30、60、120 FPS 分别对应 `1/30`、`1/60`、`1/120`。纯音频继续使用 `CMTimeScale.max`。
- 当前验证：Debug 与 Release 构建通过；还需实际录制 30 FPS 与 60 FPS 样本并检查输出帧率后才能标记完成。
- 验收标准：30 FPS、60 FPS 和高刷新率屏幕录制均产生合法配置，实际输出帧率符合预期且无相关日志错误。

### QR-008：手机录制忽略完成错误

- 优先级：`P2`
- 状态：`已移除`
- 原证据：已删除的 `AVOutputClass.fileOutput(_:didFinishRecordingTo:from:error:)`
- 问题：`didFinishRecordingTo` 忽略 `error` 参数，始终发送“Recording Completed”。设备断开或文件写入失败时会误报成功。
- 处理结果：Mobile Device 的独立文件录制器已整体删除，该回调和错误通知路径不再存在。

### QR-009：麦克风选择和故障反馈不可靠

- 优先级：`P2`
- 状态：`待处理`
- 证据：`QuickRecorder/SCContext.swift:533`、`QuickRecorder/RecordEngine.swift:640`
- 问题：外接麦克风设置保存 `localizedName`，设备重名、改名或断连时可能无法找到输入。设置失败目前主要打印日志，录制仍可能继续并得到无声轨道。
- 修复方向：保存稳定 `uniqueID`，启动前验证设备，监听连接变化，并在设备失效时明确降级到默认麦克风或停止录制。
- 验收标准：
  1. 内建麦克风、USB 耳机、蓝牙耳机分别录制成功。
  2. 录制前拔掉已选择设备时，应用不会静默录制无声文件。
  3. 同名输入设备可以被正确区分。

### QR-010：缺少测试和 Swift 6 并发准备

- 优先级：`P2`
- 状态：`待处理`
- 当前基线：
  - 工程只有一个应用 Target，没有应用单元测试或 UI 测试 Target。
  - 普通 `arm64 Release` 构建成功，共 9 条警告。
  - 启用完整并发检查后共有 454 条警告，其中 175 处会在 Swift 6 模式下成为错误。
- 修复方向：先为录制状态机、输出路径和设备选择抽出可测试逻辑；逐步隔离全局可变状态和 AppKit 主线程状态。
- 验收标准：
  1. 建立最小测试 Target 和 CI 构建任务。
  2. 核心状态机覆盖开始、暂停、恢复、停止、失败和重复停止。
  3. 普通 Release 无项目代码警告。
  4. 在计划升级 Swift 6 前，将严格并发检查纳入 CI。

### QR-011：Release 架构和签名尚未面向分发

- 优先级：`P2`
- 状态：`进行中`
- 当前基线：
  - Debug：`arm64`、Apple Development、固定 Team 和 Bundle ID，适合本机调试。
  - Release：项目与 App Target 均限定 `arm64`，使用用户的 Apple Development、固定 Team 和 Bundle ID。
  - Hardened Runtime 已启用；摄像头、麦克风和屏幕录制用途说明已配置。
- 分发决策：不购买 Developer ID，采用熟人之间的非正式分发。接收者第一次运行时先在“隐私与安全性”中选择“仍要打开”，再授予屏幕与系统音频录制、麦克风和相机权限。
- 当前验证：Release 构建成功；`lipo` 只返回 `arm64`；签名为 `Apple Development`，Team ID 为 `H7W4RZVP64`。`spctl` 拒绝该 App 是非 Developer ID 签名的预期结果。当前证书有效至 2027-07-21，产物没有嵌入 provisioning profile。
- 验收标准：
  1. Release 产物为原生 arm64，不依赖 Rosetta。
  2. Bundle ID、Team ID 和签名身份稳定，升级后权限行为可预测。
  3. 在未安装开发证书的 M 系列 Mac 上完成 Gatekeeper 手动放行和三项录制权限验证。
  4. 交付说明明确开发证书有效期与重新构建要求，不宣称 App 已公证。

参考：[Apple Developer ID](https://developer.apple.com/help/glossary/developer-id-certificate/)、[Apple 公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

### QR-012：Fork 发布资料和许可证声明待整理

- 优先级：`P3`
- 状态：`待处理`
- 问题：README 仍包含上游主页、下载和 Homebrew 信息；当前 Fork 没有独立版本策略、更新渠道和完整第三方声明。Sparkle 已移除，因此后续更新需要手动分发。
- 发布要求：
  1. 保留原项目版权、AGPL-3.0 和无担保声明。
  2. 明确说明 Fork 修改内容和日期。
  3. 二进制 Release 旁提供完全对应的源码 Tag。
  4. 增加 KeyboardShortcuts、AECAudioStream、MatrixColorSelector、SwiftLAME/LAME 的第三方许可证声明。
  5. 更新 README 中的仓库、下载、安装、支持系统和问题反馈地址。

参考：[GNU AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html)。

### QR-013：精确系统主版本判断不利于未来兼容

- 优先级：`P3`
- 状态：`待处理`
- 证据：`QuickRecorder/QuickRecorderApp.swift:18`
- 问题：代码使用 `majorVersion == 14`、`== 15` 等精确判断。macOS 15、26 及后续版本不会进入本应对“14 及以上”生效的分支，已经存在 Presenter Overlay 提示和状态栏偏移遗漏。
- 修复方向：功能能力使用 `#available` 或能力检测；只在确实需要单个系统版本规避 Bug 时使用精确版本判断。
- 验收标准：支持范围内各系统使用正确功能路径，新增 macOS 主版本不会默认退回旧行为。

## 5. 建议兼容性矩阵

| 平台 | 支持策略 | 需要验证的重点 |
| --- | --- | --- |
| Apple Silicon / macOS 14.2 | 建议最低支持版本 | 屏幕、区域、应用、窗口、系统音频、麦克风、相机叠加 |
| Apple Silicon / macOS 15 | 支持 | 权限、Continuity Camera、外接麦克风、Presenter Overlay |
| Apple Silicon / macOS 26 | 支持 | 当前开发环境；回归 ScreenCaptureKit、状态栏、系统音频权限 |
| Apple Silicon / macOS 13 | 暂不承诺，按需评估 | 核心系统音频可用，但缺少部分 14.2 功能 |
| Apple Silicon / macOS 12.3 | 不建议支持 | ScreenCaptureKit 系统音频不可用 |
| Intel Mac | 不支持 | Release 不再构建 x86_64 |

## 6. 首发前人工回归清单

### 视频

- [ ] 整屏录制：内建屏幕、外接屏幕。
- [ ] 区域录制：普通分辨率、Retina、高刷新率。
- [ ] 应用录制：单应用、多窗口。
- [ ] 窗口录制：单窗口、多窗口，并确认相机支持边界。
- [ ] H.264、H.265；MP4、MOV；30 FPS、60 FPS。
- [ ] 暂停、恢复、停止、连续快速开始和停止。

### 音频

- [ ] 仅系统音频。
- [ ] 仅麦克风。
- [ ] 系统音频＋麦克风，验证最终混音。
- [ ] 内建麦克风、USB 耳机、蓝牙耳机。
- [ ] 录制过程中切换默认输出、断开麦克风或耳机。
- [ ] M4A、MP3，以及导出失败后的 QMA 恢复能力。

### 相机

- [ ] 打开相机后进入和退出菜单栏 Popover，相机圈保持可见。
- [ ] 相机叠加从第一帧进入最终录屏。
- [ ] 拖动、缩放、翻转相机圈。
- [ ] 内建摄像头、外接摄像头、Continuity Camera。
- [ ] 相机断连时正确提示并释放设备。

### 文件与异常

- [ ] 输出目录无权限、目录被删除、磁盘空间不足。
- [ ] 应用被强制退出后不会误报完成。
- [ ] 最终文件可以被 QuickTime 正常打开，音视频时长匹配。
- [ ] 失败时保留可恢复原始文件，成功时不遗留临时文件。

### 分发

- [ ] 在未安装开发证书的干净用户账户上首次启动。
- [ ] 屏幕录制、系统音频、麦克风和摄像头权限提示完整。
- [ ] 覆盖升级后 Bundle ID、签名和权限保持稳定。
- [ ] GitHub Release 的二进制、源码 Tag、版本号和许可证一致。

## 7. 推荐开发顺序

1. `QR-001`：先保证相机真正进入最终录屏。
2. `QR-002`、`QR-003`：统一录制停止和文件 Finalize 状态机。
3. `QR-005`、`QR-009`：补齐设备、磁盘和导出错误路径。
4. `QR-006`、`QR-007`、`QR-013`：收敛系统版本和视频配置。
5. `QR-010`：建立测试和 CI，防止后续功能反复回归。
6. `QR-011`、`QR-012`：完成 arm64 Release、版本、文档、许可证和分发方案。

## 8. 变更记录

| 日期 | 变更 | 关联项 |
| --- | --- | --- |
| 2026-07-22 | 修复 60 FPS 及以上的无效 `CMTime`；Release 限定 arm64 并改用固定 Apple Development 签名，等待真实录制与干净 Mac 验证 | QR-007、QR-011 |
| 2026-07-22 | 根据产品决策整体删除 Mobile Device、USB 屏幕采集与手机预览链路，QR-004 完成，QR-008 不再适用 | QR-004、QR-008 |
| 2026-07-22 | 用户确认异步停止、尾部音画和重复停止均正常，QR-003 完成 | QR-003 |
| 2026-07-22 | 用户确认系统音频与麦克风导出、QMA 清理正常，QR-002 完成 | QR-002 |
| 2026-07-22 | 重构异步幂等停止顺序，串行排空 Sample 后再 Finalize Writer，等待真实录屏回归 | QR-003 |
| 2026-07-22 | 用户确认真实录屏包含相机悬浮窗，QR-001 完成 | QR-001 |
| 2026-07-22 | 等待麦克风 Writer 完成后再导出 QMA；MP3 转码成功后才通知并删除 QMA，等待真实音频回归 | QR-002 |
| 2026-07-22 | 修复通用关窗逻辑误关相机悬浮窗；通过 arm64 Debug 构建和静态分析，等待真实录屏回归 | QR-001 |
| 2026-07-22 | 创建代码审查与开发跟踪文档，记录 Apple Silicon 兼容性、录制生命周期和发布风险 | QR-001 ～ QR-013 |
