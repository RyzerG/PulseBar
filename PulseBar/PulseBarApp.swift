import SwiftUI
import AppKit
import Combine

@main
struct PulseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hostingView: NSHostingView<MenuBarLabelView>!
    private let monitor = SystemMonitor()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create Liquid Glass Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverDashboardView(monitor: monitor)
        )

        // 2. Create Variable-Length Status Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self

            let labelView = MenuBarLabelView(monitor: monitor)
            hostingView = NSHostingView(rootView: labelView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }

        // Keep button width synced when user toggles the 3rd Network slot
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, let button = self.statusItem.button else { return }
                let size = self.hostingView.fittingSize
                self.statusItem.length = max(112, size.width)
                button.needsLayout = true
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.isOpaque = false
            popover.contentViewController?.view.window?.backgroundColor = .clear
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
