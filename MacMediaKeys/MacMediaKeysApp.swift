import Cocoa

// The main entry point - using traditional AppKit approach
// which is more reliable than SwiftUI's MenuBarExtra on macOS 26

@main
class AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
