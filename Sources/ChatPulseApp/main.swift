#if canImport(AppKit)
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
#else
import Foundation

print("ChatPulse is a macOS menu bar application. Build it on macOS 13 or newer.")
#endif
