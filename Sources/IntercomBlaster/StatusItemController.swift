import AppKit

@MainActor
final class StatusItemController {
    enum MenuItem {
        case action(title: String, systemImageName: String, handler: () -> Void)
        case separator
    }

    private var statusItem: NSStatusItem?
    private var handlers: [NSMenuItem: () -> Void] = [:]

    func install(menuItems: [MenuItem]) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "video.doorbell", accessibilityDescription: "Intercom Blaster")
        }

        let menu = NSMenu()
        for menuItem in menuItems {
            switch menuItem {
            case let .action(title, systemImageName, handler):
                let item = NSMenuItem(title: title, action: #selector(triggerAction(_:)), keyEquivalent: "")
                if !systemImageName.isEmpty {
                    item.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title)
                }
                item.target = self
                menu.addItem(item)
                handlers[item] = handler
            case .separator:
                menu.addItem(.separator())
            }
        }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func triggerAction(_ sender: NSMenuItem) {
        handlers[sender]?()
    }
}
