import Foundation
import Network

protocol RemoteClientDelegate: AnyObject {
    func client(_ client: RemoteClient, didReceiveVideoData data: Data)
    func client(_ client: RemoteClient, didConnect: Bool)
}

final class RemoteClient {
    let host: String
    let port: UInt16
    private var connection: NWConnection?
    weak var delegate: RemoteClientDelegate?

    private var incoming = Data()

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func start() {
        guard let port = NWEndpoint.Port(rawValue: port) else { return }
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to server")
                if let strong = self {
                    strong.delegate?.client(strong, didConnect: true)
                    strong.receiveLoop()
                }
            case .failed(let err):
                print("Connection failed: \(err)")
                if let strong = self {
                    strong.delegate?.client(strong, didConnect: false)
                }
            default:
                break
            }
        }
        connection?.start(queue: .main)
    }

    func stop() {
        connection?.cancel()
    }

    func sendControl(data: Data) {
        guard let conn = connection else { return }
        var packet = Data()
        packet.append(UInt8(2)) // control
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { packet.append(contentsOf: $0) }
        packet.append(data)
        conn.send(content: packet, completion: .contentProcessed({ err in
            if let e = err { print("send error: \(e)") }
        }))
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536, completion: { [weak self] (data, ctx, isComplete, err) in
            if let d = data, !d.isEmpty {
                self?.incoming.append(d)
                self?.processBuffer()
            }
            if let e = err { print("Receive error: \(e)") }
            if isComplete { print("Connection closed by server") }
            // continue
            self?.receiveLoop()
        })
    }

    private func processBuffer() {
        while incoming.count >= 5 {
            let t = incoming[0]
            let lenData = incoming.subdata(in: 1..<5)
            let payloadLen = lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            if incoming.count < 5 + Int(payloadLen) { break }
            let payload = incoming.subdata(in: 5..<(5 + Int(payloadLen)))
            incoming.removeFirst(5 + Int(payloadLen))
            if t == 1 {
                delegate?.client(self, didReceiveVideoData: payload)
            } else {
                // ignore
            }
        }
    }
}
