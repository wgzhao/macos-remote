请基于 macOS 15 纯 Swift 编写一个通用二进制（支持 Intel 和 Apple Silicon）的局域网远程桌面核心逻辑。
受控端： 使用 ScreenCaptureKit 采集主屏幕，配置为 60FPS、NV12 格式。使用 VideoToolbox 将其硬件编码为 H.264 Annex B 流（关闭 B 帧，配置为低延迟实时模式）。通过 Network.framework 的 TCP 发送给客户端。同时接收客户端发来的键盘鼠标自定义包，使用 CoreGraphics 的 CGEvent 进行输入模拟。
控制端： 手动输入 IP 直连受控端，接收 TCP 流，使用 VideoToolbox 硬件解码，并用 AVSampleBufferDisplayLayer 渲染在一个自定义 NSView 上。拦截该 NSView 的键盘、鼠标、滚轮事件，序列化为自定义包发送给服务端。
请按照上述需求，创建完整的项目工程以及完整可编译通过的代码
