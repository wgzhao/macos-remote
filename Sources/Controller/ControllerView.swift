import Foundation
import AppKit
import AVFoundation
import CoreMedia
import VideoToolbox
import Network

class ControllerView: NSView {
    private let ipField = NSTextField(string: "127.0.0.1")
    private let portField = NSTextField(string: "5000")
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let videoContainer = VideoView(frame: .zero)

    private var client: RemoteClient?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        ipField.frame = CGRect(x: 10, y: bounds.height - 36, width: 200, height: 24)
        ipField.autoresizingMask = [.minYMargin]
        addSubview(ipField)

        portField.frame = CGRect(x: 220, y: bounds.height - 36, width: 80, height: 24)
        portField.autoresizingMask = [.minYMargin]
        addSubview(portField)

        connectButton.frame = CGRect(x: 310, y: bounds.height - 38, width: 80, height: 28)
        connectButton.autoresizingMask = [.minYMargin]
        connectButton.target = self
        connectButton.action = #selector(connectTapped)
        addSubview(connectButton)

        videoContainer.frame = CGRect(x: 10, y: 10, width: bounds.width - 20, height: bounds.height - 60)
        videoContainer.autoresizingMask = [.width, .height]
        addSubview(videoContainer)
    }

    @objc private func connectTapped() {
        guard let port = UInt16(portField.stringValue) else { return }
        let host = ipField.stringValue
        client = RemoteClient(host: host, port: port)
        client?.delegate = videoContainer
        client?.start()
    }

    // Forward events to videoContainer so it can send control packets
    override var acceptsFirstResponder: Bool { return true }
    override func keyDown(with event: NSEvent) { videoContainer.keyDown(with: event) }
    override func keyUp(with event: NSEvent) { videoContainer.keyUp(with: event) }
    override func mouseDown(with event: NSEvent) { videoContainer.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { videoContainer.mouseUp(with: event) }
    override func mouseMoved(with event: NSEvent) { videoContainer.mouseMoved(with: event) }
    override func mouseDragged(with event: NSEvent) { videoContainer.mouseDragged(with: event) }
    override func scrollWheel(with event: NSEvent) { videoContainer.scrollWheel(with: event) }
}


// MARK: - VideoView (render + event capture)

class VideoView: NSView, RemoteClientDelegate {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var decoder: H264Decoder?
    private var client: RemoteClient?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    private func setupLayer() {
        wantsLayer = true
        layer = CALayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        layer?.addSublayer(displayLayer)
    }

    // RemoteClientDelegate
    func client(_ client: RemoteClient, didReceiveVideoData data: Data) {
        // Pass Annex-B H264 data to decoder
        if decoder == nil {
            decoder = H264Decoder(displayLayer: displayLayer)
        }
        decoder?.parseAndDecode(nalData: data)
    }

    func client(_ client: RemoteClient, didConnect: Bool) {
        self.client = client
    }

    // Input event serialization and sending
    private func sendControl(json: [String: Any]) {
        guard let client = client else { return }
        if let data = try? JSONSerialization.data(withJSONObject: json, options: []) {
            client.sendControl(data: data)
        }
    }

    // Mouse/keyboard events
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let json: [String: Any] = ["type":"mouse", "action":"move", "x": Double(loc.x), "y": Double(loc.y)]
        sendControl(json: json)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let json: [String: Any] = ["type":"mouse", "action":"down", "x": Double(loc.x), "y": Double(loc.y)]
        sendControl(json: json)
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let json: [String: Any] = ["type":"mouse", "action":"up", "x": Double(loc.x), "y": Double(loc.y)]
        sendControl(json: json)
    }

    override func scrollWheel(with event: NSEvent) {
        let json: [String: Any] = ["type":"mouse", "action":"scroll", "deltaX": Double(event.scrollingDeltaX), "deltaY": Double(event.scrollingDeltaY)]
        sendControl(json: json)
    }

    override func keyDown(with event: NSEvent) {
        let json: [String: Any] = ["type":"keyboard", "action":"down", "keyCode": Int(event.keyCode)]
        sendControl(json: json)
    }

    override func keyUp(with event: NSEvent) {
        let json: [String: Any] = ["type":"keyboard", "action":"up", "keyCode": Int(event.keyCode)]
        sendControl(json: json)
    }
}
