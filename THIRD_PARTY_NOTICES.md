# Third-party notices

QuickRecorder depends on the components below. The exact revisions are locked in `QuickRecorder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. This notice and the root `LICENSE` are copied into the application bundle so binary recipients can inspect the applicable terms.

| Component | Locked version or revision | License | Source and license text |
| --- | --- | --- | --- |
| KeyboardShortcuts | 2.2.4 (`7ecc38bb6edf7d087d30e737057b8d8a9b7f51eb`) | MIT | [source](https://github.com/sindresorhus/KeyboardShortcuts/tree/7ecc38bb6edf7d087d30e737057b8d8a9b7f51eb), [license](https://github.com/sindresorhus/KeyboardShortcuts/blob/7ecc38bb6edf7d087d30e737057b8d8a9b7f51eb/license) |
| AECAudioStream | `0eab971c1dd0420ee84646c71172dd66fa59117c` | MIT | [source](https://github.com/lihaoyun6/AECAudioStream/tree/0eab971c1dd0420ee84646c71172dd66fa59117c), [license](https://github.com/lihaoyun6/AECAudioStream/blob/0eab971c1dd0420ee84646c71172dd66fa59117c/LICENSE/LICENSE.txt) |
| MatrixColorSelector | `0853e68c0c9b205ffe6a963f2a56b26e6ceca51a` | Apache-2.0 | [source](https://github.com/lihaoyun6/MatrixColorSelector/tree/0853e68c0c9b205ffe6a963f2a56b26e6ceca51a), [license](https://github.com/lihaoyun6/MatrixColorSelector/blob/0853e68c0c9b205ffe6a963f2a56b26e6ceca51a/LICENSE) |
| SwiftLAME | `e8256a8151594f47f103c742f684253c6c44871d` | LGPL-2.1 | [source](https://github.com/hidden-spectrum/SwiftLAME/tree/e8256a8151594f47f103c742f684253c6c44871d), [license](https://github.com/hidden-spectrum/SwiftLAME/blob/e8256a8151594f47f103c742f684253c6c44871d/LICENSE) |
| LAME, bundled by SwiftLAME | revision bundled by the SwiftLAME lock above | LGPL-2.0 | [project](https://lame.sourceforge.io), [license notice](https://github.com/hidden-spectrum/SwiftLAME/blob/e8256a8151594f47f103c742f684253c6c44871d/Sources/LAME/LICENSE), [copying terms](https://github.com/hidden-spectrum/SwiftLAME/blob/e8256a8151594f47f103c742f684253c6c44871d/Sources/LAME/COPYING) |
| Argmax OSS Swift / WhisperKit / SpeakerKit | 1.0.0 (`25c62997041c134b03ca82731ce2f6fd2cae1eb9`) | MIT | [source](https://github.com/argmaxinc/argmax-oss-swift/tree/25c62997041c134b03ca82731ce2f6fd2cae1eb9), [license](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/LICENSE) |
| OpenAI Whisper model architecture and weights | `openai_whisper-large-v3-v20240930_626MB`, downloaded on demand from Argmax | MIT | [OpenAI source and license](https://github.com/openai/whisper/blob/main/LICENSE), [Argmax model source](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB) |
| SpeakerKit Core ML diarization models | `pyannote-v3` segmenter/embedder and `pyannote-v4` clusterer, downloaded on demand from Argmax | See upstream model terms | [Argmax model source](https://huggingface.co/argmaxinc/speakerkit-coreml) |

## MIT notices

- KeyboardShortcuts: Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com).
- AECAudioStream: Copyright (c) [2023] [0x67].
- Argmax OSS Swift / WhisperKit / SpeakerKit: Copyright (c) 2024 argmax, inc.
- OpenAI Whisper: Copyright (c) 2022 OpenAI.

Permission is hereby granted, free of charge, to any person obtaining a copy of these components and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The applicable copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Relinkable and corresponding source

SwiftLAME and LAME are resolved and built from the revisions above. The public QuickRecorder source, its Xcode project, and `Package.resolved` provide the information required to fetch those exact sources and rebuild or relink the application. If a release modifies a dependency, the modified dependency source and its applicable license must also be published.

This notice is a practical inventory, not a replacement for the complete license texts linked above and included in each resolved package source.
