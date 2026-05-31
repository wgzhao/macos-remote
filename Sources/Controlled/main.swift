import Foundation

// Simple runner for command-line use
let server = RemoteServer(port: 5000)

do {
    try server.start()
    print("Remote server running. Grant Screen Recording / Accessibility for full functionality.")
    RunLoop.main.run()
} catch {
    print("Failed to start server: \(error)")
}
