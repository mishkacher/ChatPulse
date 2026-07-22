#if canImport(AppKit)
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
#else
import Foundation

print("ChatPulse — приложение строки меню для macOS. Соберите его на macOS 13 или новее.")
#endif
