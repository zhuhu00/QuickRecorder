# QuickRecorder

<p align="center">
  <img src="./QuickRecorder/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" alt="QuickRecorder icon" />
</p>

QuickRecorder is a macOS recorder built with SwiftUI, ScreenCaptureKit, and AVFoundation. It records displays, areas, windows, system audio, and microphones, and can burn a draggable circular camera overlay into the final screen recording.

[中文说明](./README_zh.md)

## Fork status

This community fork is maintained by [zhuhu00](https://github.com/zhuhu00). Its source is at [zhuhu00/QuickRecorder](https://github.com/zhuhu00/QuickRecorder), with reports tracked in the fork's [Issues](https://github.com/zhuhu00/QuickRecorder/issues). Modifications began in July 2026 from [lihaoyun6/QuickRecorder](https://github.com/lihaoyun6/QuickRecorder); upstream authorship and attribution are retained.

Major fork changes include:

- Menubar access and device-selectable camera and microphone controls.
- Independent system-audio and microphone switches, including microphone-only recording and an audio-source check before audio-only capture.
- Compact two-row controls and complete device lists, with aligned menubar controls.
- Local TXT/SRT transcription with an audio-presence check that skips silent recordings before queueing.
- A draggable, always-on-top circular camera overlay captured in the final recording.
- Removal of Application and Mobile Device recording, retaining display, area, and window capture.
- Recording lifecycle, pause/resume, microphone fallback, QMA export, and device identity fixes.
- A focused support target of Apple Silicon and macOS 14.2 or later.

## Installation

When binaries are published, download them from this fork's [Releases](https://github.com/zhuhu00/QuickRecorder/releases). This fork does not use the upstream Homebrew tap and has no automatic updater.

Published builds use a free Apple Development signature, not Developer ID, and are not notarized. Recipients do not need Xcode or a developer account, but the first launch requires these manual steps:

1. Try to open QuickRecorder once.
2. Open System Settings → Privacy & Security and choose Open Anyway.
3. Grant Screen & System Audio Recording, Microphone, and Camera access as needed.
4. Restart QuickRecorder after granting access.

See the [distribution guide](./docs/distribution.md) for reproducible build, signature, and delivery checks.

## Run from source

1. Install Xcode, clone this repository, and open `QuickRecorder.xcodeproj`.
2. Select your Personal Team under Signing & Capabilities for the QuickRecorder target. A free Apple Account is sufficient for local debugging.
3. Select `My Mac` and run. Grant recording permissions when macOS asks.

## Requirements

- Apple Silicon Mac.
- macOS 14.2 or later.

## Features

- Full-display, area, and single- or multi-window recording.
- Driver-free system audio capture through ScreenCaptureKit; BlackHole is not required.
- Simultaneous system audio and microphone recording, with optional separate tracks.
- Default or explicit microphone selection, with fallback to the system default if an external input disconnects.
- Built-in, external, and Continuity Camera selection with draggable, resizable, and mirrored circular preview.
- Cursor capture, mouse highlighting, screen magnifier, desktop-item hiding, and Presenter Overlay.
- MP4/MOV, H.264/H.265, HEVC with Alpha, and multiple audio formats.

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./img/preview_en_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="./img/preview_en.png">
    <img alt="QuickRecorder screenshots" src="./img/preview_en.png" width="840" />
  </picture>
</p>

## License and acknowledgements

QuickRecorder is distributed under the [GNU AGPL-3.0](./LICENSE), without warranty. A modified source or binary release must provide the exact corresponding source and retain upstream and third-party copyright and license notices. See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

Thanks to original author [lihaoyun6](https://github.com/lihaoyun6), [Azayaka](https://github.com/Mnpn/Azayaka), and the contributors to KeyboardShortcuts, AECAudioStream, MatrixColorSelector, SwiftLAME, and LAME.
