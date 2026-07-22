# QuickRecorder 代码审查与开发跟踪

> 本文档用于跟踪 QuickRecorder 当前代码审查发现、兼容性边界和发布准备工作。修复完成后应更新对应条目的状态、验证结果和变更记录，不要仅删除问题描述。

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 首次审查日期 | 2026-07-22 |
| 最近复查日期 | 2026-07-22 |
| 当前代码基线 | `main` / 本地开发分支最新提交（具体提交见 `git log`） |
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

当前代码可以在 Apple Silicon Mac 上生成原生 `arm64` 应用，不依赖 Rosetta。最近一次复查中，Release 构建与 Xcode 静态分析均成功，本地化资源和 `git diff --check` 也通过；但“能够构建”仍不等于“适合公开分发”。当前主要风险是：

1. 真实录制帧率和新版 macOS 能力判断仍需收敛。
2. 项目仍缺少自动化测试、干净 Mac 分发验证和完整 Fork 发布资料。

`QR-001` 至 `QR-006`、`QR-014` 至 `QR-017` 均已完成对应验收，当前没有未完成的 P1。后续工作以 P2 稳定性和公开分发准备为主。

## 3. 问题总表

| ID | 优先级 | 状态 | 模块 | 摘要 |
| --- | --- | --- | --- | --- |
| QR-001 | P1 | 已完成 | 相机叠加 | 开始录制前会隐藏相机悬浮窗，Camera 状态仍显示开启 |
| QR-002 | P1 | 已完成 | 系统音频 | 麦克风 Writer 完成前就开始读取并导出 QMA |
| QR-003 | P1 | 已完成 | 录制停止 | SCStream 尚未完全停止，AVAssetWriter 已开始结束写入 |
| QR-004 | P1 | 已完成 | 相机 | 删除 Mobile Device 后，电脑相机独占 Capture Session |
| QR-005 | P1 | 已完成 | 错误处理 | 统一启动事务、失败回滚与外接麦克风断开降级已通过实机验证 |
| QR-006 | P2 | 已完成 | 系统兼容 | 工程、README 与构建产物已统一为 Apple Silicon / macOS 14.2+ |
| QR-007 | P2 | 进行中 | 视频配置 | 已修复无效 `CMTime`，等待 30/60 FPS 真实录制验证 |
| QR-008 | P2 | 已移除 | 手机录制 | Mobile Device 功能已整体删除，错误通知路径不再存在 |
| QR-009 | P2 | 已完成 | 麦克风 | 已改用稳定 `uniqueID`，指定输入录制与断连默认输入降级均通过实测 |
| QR-010 | P2 | 进行中 | 工程质量 | 普通构建项目警告已清零，仍需测试 Target、CI 和严格并发基线治理 |
| QR-011 | P2 | 进行中 | 构建分发 | Release 已限定 arm64 并使用开发签名，等待干净 Mac 手动放行验证 |
| QR-012 | P3 | 待处理 | 开源发布 | README、版本、AGPL 和第三方依赖声明尚未按 Fork 发布整理 |
| QR-013 | P3 | 已完成 | 系统兼容 | 已删除精确主版本判断和不可达分支，并迁移旧 SwiftUI/AVFoundation/截图 API |
| QR-014 | P1 | 已完成 | 暂停恢复 | 画面、系统音频和麦克风统一时间轴已通过实机验证 |
| QR-015 | P2 | 已完成 | QMA 导出 | 有界重试、较长轨时长和失败清理已通过实机验证 |
| QR-016 | P2 | 已完成 | 应用状态 | adaptor 实例与 `AppDelegate.shared` 已统一并通过实机回归 |
| QR-017 | P2 | 已完成 | 构建分发 | Release 已移除 `get-task-allow`，Debug 调试权限保持不变 |
| QR-018 | P3 | 待处理 | QMA 界面 | 导出指示器的重复 Timer 没有失效机制 |

## 4. 详细问题与验收标准

### QR-001：开始录制时相机悬浮窗被隐藏

- 优先级：`P1`
- 状态：`已完成`
- 证据：
  - `QuickRecorder/ViewModel/ScreenSelector.swift:154`
  - `QuickRecorder/ViewModel/WinSelector.swift:249`
  - `QuickRecorder/ViewModel/AreaSelector.swift:222`
  - `QuickRecorder/QuickRecorderApp.swift:400`
- 问题：各录制选择器在开始录制前调用 `closeAllWindow()`。该函数会把 `camWindow` 关闭或移出屏幕，但不会清空 `SCContext.recordCam`，也不会停止相机 Session。界面可能继续显示 Camera 已开启，而屏幕录制无法稳定捕获相机悬浮窗。
- 修复方向：相机悬浮窗不应被通用关窗逻辑关闭；录制开始前应明确恢复相机窗口层级，并在生成 `SCContentFilter` 时确认窗口可捕获。
- 当前修复：`closeAllWindow()` 在 `SCContext.recordCam` 非空时保留同一个 `camWindow`，避免录制选择器、快捷键或 AppleScript 开始录制时把已开启的相机悬浮窗关闭。取消 Camera 或录制结束仍由原有 `closeCamera()` 显式停止并隐藏相机。
- 当前验证：`arm64 Debug` 构建与 Xcode 静态分析通过，`git diff --check` 通过；用户已完成真实摄像头录屏回归，确认相机悬浮窗保持可见并进入最终录屏。
- 验收标准：
  1. 开启 Camera 后分别启动整屏、区域和多窗口录制，相机圈从录制第一帧开始可见。
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

- 优先级：`P1`
- 状态：`已完成`
- 证据：
  - `QuickRecorder/RecordEngine.swift:285-300`
  - `QuickRecorder/RecordEngine.swift:329-337`
  - `QuickRecorder/RecordEngine.swift:342`
  - `QuickRecorder/RecordEngine.swift:380`
  - `QuickRecorder/RecordEngine.swift:464`
- 问题：录制路径存在 `try!`、隐式解包对象和 `try?` 后继续强制使用的情况。更严重的是，`initVideo()` 或麦克风会在 `SCStream.startCapture()` 之前启动；如果 Capture 因权限、目标窗口消失或设备错误而失败，`catch` 只执行 `assertionFailure` 后返回，不会取消 Writer、停止麦克风、清空 `streamType` 或恢复菜单 UI。Release 下可能表现为崩溃、空文件或无法再次开始录制。
- 优先级调整：复查后从 `P2` 提升为 `P1`。该路径直接影响首次授权和设备异常时的核心录制可恢复性。
- 修复方向：将录制准备阶段改为可失败流程，在开始 Capture 前完成目录、Writer、输入和设备验证；建立单一 `failRecordingStart(error:)` 入口，按逆序停止麦克风、取消 Writer、释放 Stream、恢复睡眠策略和 UI，并向用户显示具体错误。
- 当前实现：录制启动已改为单一可抛错事务；音频文件、视频 Writer、三类麦克风和 `SCStream.startCapture()` 共用回滚路径。回滚会停止并排空 Stream、停止已启动麦克风、取消 Writer、只删除本次独占创建的文件/QMA 目录、清空全局状态并在主线程提示错误；启动阶段的 `didStopWithError` 不再误入正常 Finalize。指定麦克风在启动前消失会自动改用 macOS 默认输入；录制中断开会关闭旧 Session 并尝试接续默认输入，默认输入也失败时只停止麦克风轨。运行时记录真实采集路径，停止逻辑不再依赖已经变化的设置值。
- 当前验证：最新 `arm64 Debug`、`arm64 Release` 与 Xcode Analyze 均通过，只有既存 Selector `Sendable` 警告；三份本地化资源通过 `plutil -lint`，启动路径不再包含 `try!`，源码未调用修改默认输出设备的 CoreAudio API。用户已完成外接麦克风断开、默认输入接续以及系统音频/视频不中断的真实录制验证，确认行为合理。
- 验收标准：
  1. 输出目录不可写、磁盘空间不足和麦克风不可用时不崩溃。
  2. Capture 权限缺失、目标窗口在启动前关闭或 `startCapture()` 抛错时不会遗留运行中的麦克风、Writer 或锁定文件。
  3. 失败后 `stream`、`streamType`、`isStopping`、状态栏和睡眠抑制均恢复到未录制状态，用户可以立即重试。
  4. 用户能看到具体失败原因和建议操作，不依赖 Debug assertion。
  5. 明确选择的麦克风在启动前消失时自动使用默认输入；录制中断开时优先接续默认输入，接续失败也不停止系统音频或视频。
  6. QuickRecorder 不修改 macOS 默认输出设备；耳机或扬声器切换继续由系统负责。

### QR-006：最低系统版本与核心功能不一致

- 优先级：`P2`
- 状态：`已完成`
- 证据：
  - `README_zh.md:19`
  - `QuickRecorder/RecordEngine.swift:216`
  - `QuickRecorder/RecordEngine.swift:288`
- 问题：项目和 README 标称支持 macOS 12.3，但 ScreenCaptureKit 的系统音频输出从 macOS 13 开始可用。macOS 12 用户可能可以启动应用，却无法使用核心系统声音录制。
- 产品决策：首个 Fork 版本只支持 `arm64 + macOS 14.2 及以上`，降低 Presenter Overlay、菜单栏捕获和权限差异带来的维护成本。
- 当前实现：Project 与 App Target 的 Debug/Release `MACOSX_DEPLOYMENT_TARGET` 全部统一为 `14.2`；中英文 README 明确要求 M 系列 Mac 和 macOS 14.2，不再承诺 macOS 12/13 兼容模式。
- 当前验证：Debug、Release 与 Analyze 成功；两份产物的 `LSMinimumSystemVersion` 都是 `14.2`，架构均为 `arm64`。Bundle ID、Team ID 和 Debug/Release entitlement 保持不变，固定路径 Debug App 已重新启动。
- 验收标准：
  1. Xcode Deployment Target、README、Release 说明和运行时提示一致。
  2. 低于最低版本时系统阻止安装或给出明确说明，不展示不可用功能。

参考：[Apple `capturesAudio` 文档](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio)。

### QR-007：60 FPS 使用无效 CMTime

- 优先级：`P2`
- 状态：`已完成`
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
- 状态：`已完成`
- 原证据：`SCContext.getCurrentMic()`、各麦克风 Picker 与 `AudioRecorder.setupAudioCapture(deviceName:)` 曾使用 `localizedName` 保存、匹配输入设备。
- 问题：按可变且可能重名的显示名称保存设备时，应用无法保证恢复的是用户原先选择的物理输入。
- 当前修复：`micDevice` 现在保存 `default` 或 `AVCaptureDevice.uniqueID`；显示名称只用于界面。旧版唯一名称会自动迁移到对应 ID，缺失或重名的旧值安全回退到 `default`；同名设备会在菜单中附带 ID 以便区分。录制链路直接按 ID 打开设备，并保留 QR-005 的启动缺失和录制中断连默认输入降级。
- 当前验证：本机旧值 `XIBERIA DM01 MAX` 已在启动新版 Debug 后迁移为 `AppleUSBAudioEngine:Actions:XIBERIA DM01 MAX:0123456789AB:3`。`arm64 Debug`、`arm64 Release`、Xcode Analyze、签名校验、AppleScript 字典 XML 校验和 `git diff --check` 均通过；用户已完成指定 XIBERIA 录音和录制中断连实测，确认输入正常、录制不中断并切换到默认麦克风。
- 验收标准：
  1. 选择 XIBERIA 后，界面仍显示可读名称，实际录制能够收到该设备的声音。
  2. 录制前或录制中拔掉已选择设备时，自动改用 macOS 默认输入，不会静默录制无声文件。
  3. 同名输入设备在 Picker 中可区分，内部按 `uniqueID` 精确选择。

### QR-010：缺少测试和 Swift 6 并发准备

- 优先级：`P2`
- 状态：`待处理`
- 当前基线：
  - 工程只有一个应用 Target，没有应用单元测试或 UI 测试 Target。
  - 最低版本提升到 macOS 14.2 后，普通 `arm64 Debug/Release` 的 QuickRecorder 项目代码警告已清零；Xcode 26.5 仍输出 1 条“未链接 AppIntents”的工具级元数据提示，项目本身不使用 AppIntents。
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
- 状态：`已完成`
- 问题：代码使用 `majorVersion == 14`、`== 15` 等精确判断。macOS 15、26 及后续版本不会进入本应对“14 及以上”生效的分支，已经存在 Presenter Overlay 提示和状态栏偏移遗漏。
- 当前修复：删除精确主版本全局变量与 macOS 12/13、14.0 以下不可达分支；macOS 14.2 已提供的功能直接走现代路径，仅保留 macOS 15+ 的真实增量能力判断。同步迁移 SwiftUI `onChange`/Settings 导航、Locale、AVCaptureDevice、AVAsset 异步读取和 `SCScreenshotManager`，并收敛 Screen/Window selector 的主线程状态更新。
- 当前验证：干净 `arm64 Release`、Debug Analyze、`git diff --check` 和源码抑制搜索通过；QuickRecorder 项目代码 warning 为 0。固定路径 Debug App 已使用原 Bundle ID、Team 和 Apple Development 签名重新启动。Xcode 26.5 的 AppIntents 元数据工具仍有 1 条与项目代码无关的提示。
- 验收标准：支持范围内各系统使用正确功能路径，新增 macOS 主版本不会默认退回旧行为。

### QR-014：Pause/Resume 后音频时间轴没有同步压缩

- 优先级：`P1`
- 状态：`已完成`
- 证据：
  - `QuickRecorder/RecordEngine.swift:449-464`
  - `QuickRecorder/RecordEngine.swift:549-560`
  - `QuickRecorder/RecordEngine.swift:574`
  - `QuickRecorder/RecordEngine.swift:603-615`
  - `QuickRecorder/RecordEngine.swift:693-697`
- 问题：恢复录制时计算出的 `SCContext.timeOffset` 只通过 `adjustTime` 应用到 `.screen` SampleBuffer。视频内的系统音频仍直接 append 原始 SampleBuffer，默认麦克风、AEC 麦克风和指定外接麦克风也都保留原始采集时间戳。暂停期间 Sample 被丢弃，但恢复后的音频时间轴可能继续包含暂停间隔，导致视频被压短而音频不压短；纯系统音频＋麦克风生成的 QMA 双轨也可能长度不同或恢复后错位。
- 修复方向：定义一条统一录制时间轴，分别记录视频、系统音频和麦克风的最后 PTS，并把累计暂停偏移应用到所有写入 `AVAssetWriterInput` 的 SampleBuffer。纯音频写入 `AVAudioFile` 时仍需保证系统轨和麦克风 Writer 采用相同的暂停语义，不能只依赖连续文件写入。
- 当前实现：`SCContext` 用 host clock 保存当前与已完成暂停区间；每个 SampleBuffer 在写入前按自身原始 PTS 过滤暂停区间并减去此前累计暂停时长。ScreenCaptureKit 画面/系统音频、默认输入、AEC 与指定设备麦克风均走同一转换入口；时间信息复制按 SampleBuffer 实际 timing entry 数处理，避免把音频帧数误当成 timing entry 数。
- 当前验证：最新 `arm64 Debug`、`arm64 Release` 与 Xcode Analyze 均通过，`isResume` 旧分支和绕过统一麦克风写入入口的代码已经移除；固定路径签名 Debug App（Team `H7W4RZVP64`）已重启。用户已完成 Pause/Resume 真实录制，确认暂停段移除且画面、系统音频和麦克风同步合理。
- 验收标准：
  1. 屏幕＋系统音频＋麦克风录制中暂停 5 秒再恢复，最终文件不包含该 5 秒，恢复前后的音画误差不超过 100 ms。
  2. 纯系统音频＋麦克风录制中暂停 5 秒，导出的两轨起点、恢复点和总时长一致。
  3. 连续暂停/恢复三次后 PTS 单调递增，Writer 不报告非单调时间戳。
  4. 使用 `ffprobe` 对比视频、系统音频和麦克风时长，并人工检查恢复点口令与画面动作同步。

### QR-015：QMA 离线渲染可能无限循环

- 优先级：`P2`
- 状态：`已完成`
- 证据：`QuickRecorder/ViewModel/QmaPlayer.swift:626-638`
- 问题：`renderOffline` 返回 `.insufficientDataFromInputNode` 或 `.cannotDoInCurrentContext` 时，当前 `break` 只退出 `switch`，不会退出外层 `while`。若 `manualRenderingSampleTime` 没有增长，线程会持续空转；自动 QMA 导出不会调用 completion，录制生命周期会一直停在 `Processing...`，退出 App 也可能永久等待。
- 修复方向：检测每轮渲染是否有时间进度，对可重试状态设置有限重试次数或短暂退避；超过阈值后抛出可恢复错误。用 `defer` 统一退出手动渲染模式、停止 Engine、恢复播放 Engine 并确保 completion 只执行一次。
- 当前实现：离线渲染按两轨真实时长的较大值计算总 frame；`.success` 和有有效数据的 `.insufficientDataFromInputNode` 会写入 buffer。每轮比较 `manualRenderingSampleTime`，连续 200 次无进度时按 10 ms 间隔有界失败。manual mode 切换前已经建立清理 `defer`，成功或失败都恢复实时 Engine；失败删除不完整输出、保留 QMA并执行 completion。
- 当前验证：`arm64 Debug`、`arm64 Release` 与 Xcode Analyze 均通过，三份本地化资源和 `git diff --check` 通过；固定路径签名 Debug App（Team `H7W4RZVP64`）已重启。用户已完成正常系统音频＋麦克风自动混音实测，确认 `Processing...` 正常退出且最终文件合理。
- 验收标准：
  1. 正常 QMA、两轨长度不同和损坏 QMA 都能在有限时间内成功或失败，不出现无限循环。
  2. 导出失败时发送失败通知、保留 QMA，并最终将 `isStopping` 恢复为 `false`。
  3. 录制后处理中退出 App 时，无论导出成功或失败都会收到终止 completion。

### QR-016：存在两个 `AppDelegate` 实例

- 优先级：`P2`
- 状态：`进行中`
- 原证据：
  - `QuickRecorder/QuickRecorderApp.swift:37`
  - `QuickRecorder/QuickRecorderApp.swift:91-99`
  - `QuickRecorder/ViewModel/StatusBar.swift:40-44`
- 问题：`@NSApplicationDelegateAdaptor(AppDelegate.self)` 会创建系统使用的 App Delegate，`static let shared = AppDelegate()` 又创建第二个实例。键盘快捷键闭包使用系统 Delegate 的 `self`，大多数 SwiftUI、相机和 AppleScript 入口使用 `AppDelegate.shared`。`isPresenterON`、`presenterType`、`frameQueue`、`isCameraReady` 和终止等待等实例状态可能被写在不同对象上，造成不同入口行为不一致。
- 修复方向：只保留一个权威 App Delegate 实例。所有 UI、快捷键、AppleScript、SCStream 回调和相机恢复逻辑都应访问同一个对象；长期可把录制状态进一步迁移到明确的 Observable 状态拥有者。
- 当前实现：删除 `static let shared = AppDelegate()`。`@NSApplicationDelegateAdaptor` 创建的实例在 `init` 时登记到私有弱引用，`shared` 只返回该实例；第二次主动构造会触发前置条件。`applicationDidFinishLaunching` 断言回调接收者与 `shared` 相同。
- 生命周期说明：SwiftUI App 的 `NSApp.delegate` 可能是框架内部代理，不能通过 `NSApp.delegate as? AppDelegate` 取回 adaptor 实例；实机构建已验证该错误写法会在启动时失败，开发规范已记录这一边界。
- 当前验证：源码搜索只剩 `@NSApplicationDelegateAdaptor` 一个构造入口；Debug、Release、Analyze、严格签名校验和 `git diff --check` 通过。固定路径签名 Debug App 已稳定启动，用户确认菜单栏、相机和录制入口均正常。
- 验收标准：
  1. `applicationDidFinishLaunching` 的接收者与业务代码访问的 `AppDelegate.shared` 是同一个实例。
  2. 菜单、键盘快捷键和 AppleScript 启动录制时使用同一 `frameQueue` 与 Presenter Overlay 状态。
  3. Presenter Overlay 开启时打开菜单栏 Popover，不会因读取另一实例的 `isPresenterON` 而错误恢复普通相机窗口。

### QR-017：Release 包含 `get-task-allow`

- 优先级：`P2`
- 状态：`已完成`
- 原证据：
  - Release 构建设置曾为：`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`
  - Release 签名权限曾包含：`com.apple.security.get-task-allow = true`
  - `QuickRecorder.xcodeproj/project.pbxproj:507-539`
- 问题：当前 Apple Development Release 可以按既定方案让熟人手动放行，但仍携带允许调试器附加的开发权限。它不妨碍免费分发，却会削弱发布包的运行时保护，也不应出现在公开下载的 Release 中。
- 修复方向：仅在 Release 设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`，保留 Debug 的调试能力以及既定的 Apple Development、Team ID、Bundle ID 和 arm64 配置。该修改不要求购买 99 美元会员，也不改变接收者首次通过“隐私与安全性 → 仍要打开”的流程。
- 当前实现：QuickRecorder App Target 的 Release 设置为 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`；Debug 仍解析为 `YES`。显式 entitlement 文件未改动，麦克风和相机权限继续保留。
- 当前验证：签名 Release 只包含 audio-input 与 camera，不含 `get-task-allow`；签名 Debug 额外包含 `get-task-allow = true`。Release 严格签名校验通过、架构为 arm64、Identifier 为 `io.github.zhuhu00.QuickRecorder`、Authority 为 Apple Development、Team 为 `H7W4RZVP64`；Debug、Release 和 Analyze 均通过。
- 验收标准：
  1. `codesign -d --entitlements :- QuickRecorder.app` 的 Release 输出不再包含 `com.apple.security.get-task-allow`。
  2. Debug 仍可由 Xcode 附加调试，Release 仍为 `arm64`、Apple Development 和 Team `H7W4RZVP64`。
  3. 在干净 M 系列 Mac 上手动放行后，屏幕与系统音频、麦克风和相机权限均可正常授权。

参考：[Apple：Avoid the get-task-allow entitlement](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)。

### QR-018：QMA 导出指示器 Timer 不会失效

- 优先级：`P3`
- 状态：`待处理`
- 证据：`QuickRecorder/ViewModel/QmaPlayer.swift:12-40`
- 问题：`ActivityIndicator.onAppear` 每次创建一个 50 ms 重复 Timer，但没有保存引用或在 `onDisappear` 时 invalidate。反复导出或重建视图后可能累积 Timer 和动画更新，带来无意义的 CPU 占用和对象生命周期延长。
- 修复方向：优先改用 SwiftUI `repeatForever` 动画或 `TimelineView`；若保留 Timer，则由对象持有并在视图消失时明确停止。
- 验收标准：连续打开、导出和关闭 QMA 窗口后不累积活动 Timer，导出动画仍能正常开始和停止。

## 5. 建议兼容性矩阵

| 平台 | 支持策略 | 需要验证的重点 |
| --- | --- | --- |
| Apple Silicon / macOS 14.2 | 最低支持版本 | 屏幕、区域、窗口、系统音频、麦克风、相机叠加 |
| Apple Silicon / macOS 15 | 支持 | 权限、Continuity Camera、外接麦克风、Presenter Overlay |
| Apple Silicon / macOS 26 | 支持 | 当前开发环境；回归 ScreenCaptureKit、状态栏、系统音频权限 |
| Apple Silicon / macOS 13 | 不支持 | 产物最低版本为 14.2 |
| Apple Silicon / macOS 12.3 | 不支持 | 产物最低版本为 14.2，且 ScreenCaptureKit 系统音频不可用 |
| Intel Mac | 不支持 | Release 不再构建 x86_64 |

## 6. 首发前人工回归清单

### 视频

- [ ] 整屏录制：内建屏幕、外接屏幕。
- [ ] 区域录制：普通分辨率、Retina、高刷新率。
- [ ] 窗口录制：单窗口、多窗口，并确认相机支持边界。
- [ ] H.264、H.265；MP4、MOV；30 FPS、60 FPS。
- [x] 视频＋系统音频＋麦克风录制中暂停 5 秒再恢复，确认暂停段被移除且三路时间轴同步。
- [ ] 连续暂停/恢复三次、连续快速开始和停止，确认 PTS 单调且没有 Writer 错误。

### 音频

- [ ] 仅系统音频。
- [ ] 仅麦克风。
- [ ] 系统音频＋麦克风，验证最终混音。
- [ ] 内建麦克风、USB 耳机、蓝牙耳机。
- [x] 录制过程中切换默认输出、断开麦克风或耳机。
- [ ] M4A、MP3，以及导出失败后的 QMA 恢复能力。
- [ ] 纯系统音频＋麦克风暂停/恢复后，QMA 两轨恢复点和总时长一致。
- [ ] 两轨长度不同或 QMA 损坏时，导出在有限时间内失败并保留恢复源。

### 相机

- [ ] 打开相机后进入和退出菜单栏 Popover，相机圈保持可见。
- [ ] 相机叠加从第一帧进入最终录屏。
- [ ] 拖动、缩放、翻转相机圈。
- [ ] 内建摄像头、外接摄像头、Continuity Camera。
- [ ] 相机断连时正确提示并释放设备。

### 文件与异常

- [ ] 输出目录无权限、目录被删除、磁盘空间不足。
- [ ] `SCStream.startCapture()` 失败时，Writer、麦克风、睡眠抑制和 UI 全部回滚并允许立即重试。
- [ ] 应用被强制退出后不会误报完成。
- [ ] 最终文件可以被 QuickTime 正常打开，音视频时长匹配。
- [ ] 失败时保留可恢复原始文件，成功时不遗留临时文件。

### 分发

- [ ] 在未安装开发证书的干净用户账户上首次启动。
- [ ] 屏幕录制、系统音频、麦克风和摄像头权限提示完整。
- [ ] 覆盖升级后 Bundle ID、签名和权限保持稳定。
- [ ] Release 签名权限不包含 `com.apple.security.get-task-allow`。
- [ ] GitHub Release 的二进制、源码 Tag、版本号和许可证一致。

## 7. 推荐开发顺序

以下顺序按风险优先；`QR-001` 至 `QR-004` 已完成，不再重复安排：

1. `QR-007`、`QR-013`：验证实际帧率并收敛新版 macOS 能力判断。
2. `QR-010`：建立测试 Target 和 CI，覆盖开始、暂停、恢复、停止及失败状态机。
3. `QR-011`、`QR-012`、`QR-018`：完成干净 Mac 验证、Fork 发布资料和低优先级 UI 生命周期清理。

## 8. 变更记录

| 日期 | 变更 | 关联项 |
| --- | --- | --- |
| 2026-07-22 | 删除精确系统版本与不可达兼容分支，迁移 SwiftUI、AVFoundation 和截图 API；普通 Debug/Release 项目警告由 44 条降至 0 | QR-013、QR-010 |
| 2026-07-22 | Project、App Target、中英文 README 与构建产物统一为 Apple Silicon / macOS 14.2+；Debug、Release、Analyze、签名和固定调试版启动验证通过 | QR-006 |
| 2026-07-22 | 用户确认指定 XIBERIA 录音和录制中断连默认输入降级均正常，QR-009 标记完成 | QR-009 |
| 2026-07-22 | 麦克风选择、持久化与采集查找改用 `AVCaptureDevice.uniqueID`；加入旧名称迁移和同名显示区分，本机 XIBERIA 设置迁移及全套构建检查通过，等待真实录制与断连回归 | QR-009 |
| 2026-07-22 | 用户确认 AppDelegate 单实例版本的菜单栏、相机和录制入口均正常，QR-016 标记完成 | QR-016 |
| 2026-07-22 | 删除第二个 AppDelegate 构造；由 SwiftUI adaptor 实例登记唯一共享入口，并记录 NSApp.delegate 可能是框架代理的生命周期边界 | QR-016 |
| 2026-07-22 | Release 禁止注入 base debug entitlement，最终签名不再包含 get-task-allow；Debug 仍保留调试权限，签名身份与 arm64 分发策略不变 | QR-017 |
| 2026-07-22 | 用户完成正常 QMA 自动混音实测，确认 Processing 正常退出且最终文件合理；QR-015 标记完成 | QR-015 |
| 2026-07-22 | QMA 离线混音按较长轨时长渲染，写入可用的 insufficient-data frame，并以连续无进度上限保证失败路径恢复 Engine、保留 QMA和结束 Processing | QR-015 |
| 2026-07-22 | 用户完成外接麦克风断开与 Pause/Resume 真实录制验证，确认默认输入接续、录制不中断且三路时间轴同步合理；两项标记完成 | QR-005、QR-014 |
| 2026-07-22 | 指定麦克风缺失或录制中断开时自动降级到 macOS 默认输入；默认输入不可用时保持系统音频/视频继续，且不修改系统输出设备 | QR-005、QR-009 |
| 2026-07-22 | 用共享 host-clock 暂停区间统一画面、系统音频和三类麦克风时间轴；修正 SampleBuffer timing entry 复制方式 | QR-014 |
| 2026-07-22 | 清理 Mobile Device 删除后遗留的固定宽度，五项主面板从 801 pt 收紧为 674 pt | 产品范围调整 |
| 2026-07-22 | 根据产品决策删除 Application 录制入口、选择器、过滤分支与 AppleScript 命令；共享录制选项迁移到独立视图，保留 Screen、Area 和 Window | 产品范围调整 |
| 2026-07-22 | 将录制准备、Writer、麦克风和 Capture 启动合并为可回滚事务；Debug、Release 与 Analyze 通过，等待真实异常场景验证 | QR-005 |
| 2026-07-22 | 基于 `e7f1629` 再次审查：QR-005 提升为 P1；新增 Pause/Resume 时间轴、QMA 无限循环、双 AppDelegate、Release 调试权限和 Timer 生命周期问题 | QR-005、QR-014 ～ QR-018 |
| 2026-07-22 | 修复 60 FPS 及以上的无效 `CMTime`；Release 限定 arm64 并改用固定 Apple Development 签名，等待真实录制与干净 Mac 验证 | QR-007、QR-011 |
| 2026-07-22 | 根据产品决策整体删除 Mobile Device、USB 屏幕采集与手机预览链路，QR-004 完成，QR-008 不再适用 | QR-004、QR-008 |
| 2026-07-22 | 用户确认异步停止、尾部音画和重复停止均正常，QR-003 完成 | QR-003 |
| 2026-07-22 | 用户确认系统音频与麦克风导出、QMA 清理正常，QR-002 完成 | QR-002 |
| 2026-07-22 | 重构异步幂等停止顺序，串行排空 Sample 后再 Finalize Writer，等待真实录屏回归 | QR-003 |
| 2026-07-22 | 用户确认真实录屏包含相机悬浮窗，QR-001 完成 | QR-001 |
| 2026-07-22 | 等待麦克风 Writer 完成后再导出 QMA；MP3 转码成功后才通知并删除 QMA，等待真实音频回归 | QR-002 |
| 2026-07-22 | 修复通用关窗逻辑误关相机悬浮窗；通过 arm64 Debug 构建和静态分析，等待真实录屏回归 | QR-001 |
| 2026-07-22 | 创建代码审查与开发跟踪文档，记录 Apple Silicon 兼容性、录制生命周期和发布风险 | QR-001 ～ QR-013 |
