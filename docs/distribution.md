# QuickRecorder 非正式分发说明

## 分发模型

本 Fork 只面向 Apple Silicon 和 macOS 14.2 以上版本。当前选择免费的 Apple Development 签名，不购买 Developer ID，不做 Apple 公证，也不通过 Mac App Store 分发。

这意味着：

- 接收者只需下载 App，不需要 Xcode、源码或开发者账号。
- Gatekeeper 会拒绝直接打开，这是当前签名策略的预期行为；接收者必须手动选择“仍要打开”。
- 该方式适合熟人间、小范围开源测试，不等于普通用户可无提示安装的正式发行。
- 当前没有 Sparkle 或其他自动更新器，更新只能手动下载并覆盖旧版本。

## 版本规则

- App 使用 `MAJOR.MINOR.PATCH`，Git Tag 使用对应的 `vMAJOR.MINOR.PATCH`。
- `CURRENT_PROJECT_VERSION` 只递增，不复用旧构建号。
- 每个二进制必须由同名源码 Tag 构建；二进制、Tag、`Package.resolved`、根 `LICENSE` 和 `THIRD_PARTY_NOTICES.md` 必须同时发布。
- 首个 Fork 版本为 `1.7.0`，构建号为 `170`。后续不跟随上游版本号自动跳转。

## Release 构建

在仓库根目录运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project QuickRecorder.xcodeproj \
  -scheme QuickRecorder \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  clean build

./scripts/verify-release.sh
```

产物位于 `build/Build/Products/Release/QuickRecorder.app`。验证脚本会检查 arm64、最低系统版本、Bundle ID、Team、Apple Development 签名、Hardened Runtime、业务 entitlement、Release 不包含 `get-task-allow`，以及许可证文件已经进入 App Bundle。脚本还要求 `spctl` 拒绝当前产物；如果它意外通过，说明签名策略发生了变化，需要人工复核。

当前本机开发证书的已知到期日为 2027-07-21。每次发布前都应重新检查有效签名身份和证书有效期；证书变化后必须重新构建，不应继续分发旧包。

## 打包与源码对应

验证通过后，可用系统 `ditto` 保留扩展属性和资源分叉：

```bash
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  build/Build/Products/Release/QuickRecorder.app/Contents/Info.plist)

ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/QuickRecorder.app \
  "QuickRecorder-v${version}-arm64.zip"

shasum -a 256 "QuickRecorder-v${version}-arm64.zip"
```

在 GitHub Release 中同时提供：

- `QuickRecorder-vX.Y.Z-arm64.zip` 与 SHA-256。
- 对应 `vX.Y.Z` Tag 的源码归档。
- 明确写出“Apple Development 签名、未公证、需要手动放行”。
- 证书到期日、最低系统版本和需要授予的三类录制权限。

## 接收者首次打开

1. 解压后把 QuickRecorder 放到希望长期使用的位置；后续不要频繁移动路径。
2. 双击一次，允许 Gatekeeper 显示拦截。
3. 打开“系统设置 → 隐私与安全性”，在安全性提示中选择“仍要打开”。
4. 再次启动后，分别触发并授予“屏幕与系统音频录制”、麦克风和相机权限。
5. 授权后退出并重新打开 App，再做一段包含系统声音、麦克风和相机的短录制。

不要把关闭 Gatekeeper 或批量删除 quarantine 属性写成默认安装步骤。

## 干净 Mac 验收

每个准备公开分发的版本仍需在一台未安装维护者开发证书的 M 系列 Mac 上完成最终人工验收：

- 首次打开确实被拦截，且“仍要打开”后能够启动。
- 屏幕与系统音频、麦克风、相机三类权限均能授权。
- 整屏、区域、窗口、系统声音、指定麦克风和相机叠加能够生成可读文件。
- 覆盖升级同一 Bundle ID 后，设置和已授予权限没有异常漂移。

这一步无法由本机签名检查或 CI 代替；没有完成时，Release Notes 必须明确标为测试版。
