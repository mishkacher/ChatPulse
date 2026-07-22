#if canImport(AppKit)
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

Task { @MainActor in
    SkinCoordinator.shared.start()
    SkinStatusMenuInstaller.shared.start()
}

application.run()
#else
import Foundation

print("ChatPulse — приложение строки меню для macOS. Соберите его на macOS 13 или новее.")
#endif
