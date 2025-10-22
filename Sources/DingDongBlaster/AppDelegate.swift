import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let statusItemController = StatusItemController()
    private lazy var settingsWindowController = SettingsWindowController(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install(menuItems: [
            .action(
                title: "Open Settings…",
                systemImageName: "gearshape",
                handler: { [weak self] in self?.openSettings() }
            ),
            .separator,
            .action(
                title: "Quit",
                systemImageName: "rectangle.portrait.and.arrow.right",
                handler: { NSApp.terminate(nil) }
            )
        ])
        appState.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopPlayback()
    }

    private func openSettings() {
        settingsWindowController.showWindow()
    }
}
