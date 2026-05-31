macOS Remote (Swift) — Core skeleton

这是一个示例 Swift Package，包含两个可执行目标：

- `controlled`：受控端（server）——采集屏幕、硬件编码 H.264、通过 TCP 发送，同时接收控制端发来的键盘/鼠标事件并注入到系统。
- `controller`：控制端（client）——连接受控端、接收 H.264 流并解码渲染到自定义 NSView，拦截键盘/鼠标事件并序列化发送给受控端。

目的

提供一套可编译的 macOS 15（纯 Swift）工程骨架，完成网络、编码/解码、输入注入与事件序列化的端到端流程。代码中使用 AVFoundation 的 `AVCaptureScreenInput` 作为屏幕采集实现（工作稳定且可编译）。按需可以把采集替换为 `ScreenCaptureKit`（README 中会指示替换点）。

注意

- 要在受控端运行屏幕录制/输入注入，需要在系统偏好设置中授予“屏幕录制”和“辅助功能”权限。
- 为了尽可能保证可编译性，示例使用 Swift Package Manager（Package.swift）。你可以在 Xcode 中直接打开 Package.swift 并运行两个可执行目标。
- 要生成通用二进制（Intel + Apple Silicon），请在 Xcode 中 Archive / 导出，或使用 `xcodebuild` 对两个架构分别构建再用 `lipo` 合并。仓库已包含一个自动化脚本 `scripts/build-universal.sh` 用于在本机上生成 universal 二进制。

构建和运行（在工程目录下）

1. 在 Xcode 中打开 `Package.swift`：Xcode 会识别 SPM 包并允许你运行 `controlled` 或 `controller`。直接选择 scheme 并运行。

2. 使用命令行构建：

   swift build -c release

   可执行文件位于 `.build/debug/controlled` 和 `.build/debug/controller`。

3. 通用二进制（示例）

   - 在 Xcode 中用 Archive 打包并导出通用二进制。
   - 或者使用仓库中的自动化脚本生成：

     chmod +x scripts/build-universal.sh
     ./scripts/build-universal.sh both

   脚本会尝试使用 `swift package generate-xcodeproj` 生成 Xcode 工程，然后分别为 `arm64` 与 `x86_64` 构建 Release 二进制并用 `lipo` 合并。合并后的二进制位于 `build/universal/`。

   注意：在 Apple Silicon 上构建 x86_64 需要 Rosetta / SDK 支持；如果 x86_64 构建失败，脚本仍会保留 arm64-only 二进制。

替换为 ScreenCaptureKit

- `Sources/Controlled/Capturer.swift` 中实现了 `ScreenCapturer` 协议并提供了一个基于 `AVCaptureScreenInput` 的实现 `AVScreenCapturer`。
- 如果你需要使用 `ScreenCaptureKit`，请在该文件中实现 `ScreenCapturer`：创建 `SCStream`/`SCStreamConfiguration` 并把每帧转为 `CVPixelBuffer`，然后调用 `onFrame(pixelBuffer:timestamp:)`。

协议和网络格式

- 网络采用 TCP（Network.framework）。消息包格式：
  - 1 字节 type（1 = video, 2 = control）
  - 4 字节 big-endian payload length
  - payload bytes

- 视频 payload 为 H.264 Annex-B（start-code 0x00000001 分隔的 NAL units）。
- 控制 payload 为 UTF-8 编码的 JSON，对应 ControlEvent。示例：
  { "type":"mouse", "action":"move", "x":123.4, "y":456.7 }

接下来

我已把工程骨架写入仓库（Sources/Controlled、Sources/Controller）。你可以：

- 在 Xcode 中打开 `Package.swift` 并先运行 `controlled`（受控端），随后运行 `controller`（控制端）并在界面中输入受控端 IP:5000 进行直连测试。
- 如果你希望我把采集替换为 ScreenCaptureKit 的实现，我可以继续实现替代类（需要小心 macOS 权限与 API 的细节）。

脚本：

- `scripts/build-universal.sh` — 在本机生成 Xcode 工程并构建 arm64/x86_64，然后用 `lipo` 合并为 universal 二进制。运行之前请确保安装 Xcode 与命令行工具，并为脚本添加可执行权限（chmod +x scripts/build-universal.sh）。

