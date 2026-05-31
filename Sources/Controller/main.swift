import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controllerView: ControllerView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
        let winRect = CGRect(x: 100, y: 100, width: 1024, height: 768)

        window = NSWindow(contentRect: winRect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Remote Controller"

        controllerView = ControllerView(frame: window.contentView!.bounds)
        controllerView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(controllerView)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
