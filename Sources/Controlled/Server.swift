import Foundation
import Network
import CoreMedia
import CoreGraphics

enum PacketType: UInt8 {
    case video = 1
    case control = 2
}

struct ControlEvent: Codable {
    let type: String
    let action: String
    let x: Double?
    let y: Double?
    let button: Int?
    let keyCode: Int?
    let deltaX: Double?
    let deltaY: Double?
}

final class RemoteServer {
    private let port: UInt16
    private var listener: NWListener?
    private var connection: NWConnection?

    private var incomingBuffer = Data()

    private var capturer: ScreenCapturer?
    private var encoder: H264Encoder?

    init(port: UInt16 = 5000) {
        self.port = port
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "RemoteServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid port"])
        }

        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: nwPort)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Listening on port \(self.port)")
            case .failed(let error):
                print("Listener failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            print("New connection from \(String(describing: conn.endpoint))")
            self?.accept(connection: conn)
        }

        listener?.start(queue: .main)
    }

    private func accept(connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Client connected: \(connection.endpoint)")
                self.startStreaming()
                self.receiveLoop()
            case .failed(let err):
                print("Connection failed: \(err)")
                self.stopStreaming()
            case .cancelled:
                print("Connection cancelled")
                self.stopStreaming()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func startStreaming() {
        // Setup encoder and capturer
        // We'll capture main display size
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let width = Int32(mainBounds.width)
        let height = Int32(mainBounds.height)

        encoder = H264Encoder(width: width, height: height, fps: 60)
        encoder?.onEncoded = { [weak self] data, isKeyframe in
            self?.sendVideo(data: data)
        }

        let capturer = AVScreenCapturer(fps: 60)
        capturer.onFrame = { [weak self] pixelBuffer, pts in
            self?.encoder?.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: pts)
        }
        self.capturer = capturer
        capturer.start()

        print("Started capture and encoder")
    }

    private func stopStreaming() {
        capturer?.stop()
        capturer = nil
        encoder = nil
    }

    private func sendVideo(data: Data) {
        guard let conn = connection else { return }
        var packet = Data()
        packet.append(PacketType.video.rawValue)
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { packet.append(contentsOf: $0) }
        packet.append(data)
        conn.send(content: packet, completion: .contentProcessed({ error in
            if let err = error {
                print("Send error: \(err)")
            }
        }))
    }

    private func receiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
            if let data = data, !data.isEmpty {
                self?.incomingBuffer.append(data)
                self?.processIncomingBuffer()
            }
            if let err = error {
                print("Receive error: \(err)")
                return
            }
            if isComplete {
                print("Connection complete")
                return
            }
            // Continue receiving
            self?.receiveLoop()
        }
    }

    private func processIncomingBuffer() {
        while incomingBuffer.count >= 5 {
            let typeByte = incomingBuffer[0]
            let lenData = incomingBuffer.subdata(in: 1..<5)
            let payloadLen = lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            if incomingBuffer.count < 5 + Int(payloadLen) { break }
            let payload = incomingBuffer.subdata(in: 5..<(5 + Int(payloadLen)))
            incomingBuffer.removeFirst(5 + Int(payloadLen))
            if typeByte == PacketType.control.rawValue {
                handleControl(payload)
            } else {
                // ignore unknown types
            }
        }
    }

    private func handleControl(_ data: Data) {
        guard let evt = try? JSONDecoder().decode(ControlEvent.self, from: data) else {
            print("Invalid control event")
            return
        }
        DispatchQueue.main.async {
            self.applyControl(evt)
        }
    }

    private func applyControl(_ evt: ControlEvent) {
        // Convert coordinates (assume client uses same coordinate space)
        if evt.type == "mouse" {
            guard let action = evt.action as String?, let x = evt.x, let y = evt.y else { return }
            let point = CGPoint(x: x, y: y)
            if action == "move" {
                if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                    event.post(tap: CGEventTapLocation.cghidEventTap)
                }
            } else if action == "down" {
                let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
                event?.post(tap: CGEventTapLocation.cghidEventTap)
            } else if action == "up" {
                let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
                event?.post(tap: CGEventTapLocation.cghidEventTap)
            } else if action == "scroll" {
                let dx = Int32(evt.deltaX ?? 0)
                let dy = Int32(evt.deltaY ?? 0)
                if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: dx, wheel3: 0) {
                    scrollEvent.post(tap: CGEventTapLocation.cghidEventTap)
                }
            }
        } else if evt.type == "keyboard" {
            guard let action = evt.action as String?, let key = evt.keyCode else { return }
            if action == "down" {
                if let ev = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true) {
                    ev.post(tap: .cghidEventTap)
                }
            } else if action == "up" {
                if let ev = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false) {
                    ev.post(tap: .cghidEventTap)
                }
            }
        }
    }
}

// Simple runner for command-line use
let server = RemoteServer(port: 5000)

do {
    try server.start()
    print("Remote server running. Grant Screen Recording / Accessibility for full functionality.")
    RunLoop.main.run()
} catch {
    print("Failed to start server: \(error)")
}
