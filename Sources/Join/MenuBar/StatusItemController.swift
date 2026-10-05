import AppKit
import SwiftUI
import JoinCore

/// The menu bar icon and its drop-down panel.
/// SwiftUI's MenuBarExtra window grows with its content but never shrinks, so the panel is an
/// NSPopover whose hosting controller reports its SwiftUI content size in both directions.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        configureButton()
        configurePopover()
        observeChanges(of: { [model] in _ = model.menuBarTitle }) { [weak self] in
            self?.updateButton()
        }
        updateButton()
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    func toggle() {
        togglePanel(nil)
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        model.refreshNow()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Join!")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(togglePanel(_:))
    }

    private func configurePopover() {
        let controller = NSHostingController(rootView: MenuBarPanelView().environment(model))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if let title = model.menuBarTitle {
            button.title = title
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }
}
