#if DEBUG
import AppKit

final class WindowInventoryCheck: NSObject, NSApplicationDelegate {
    private let service = DockService()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let index = CommandLine.arguments.firstIndex(of: "--check-window-count"),
              CommandLine.arguments.count > index + 2,
              let expected = Int(CommandLine.arguments[index + 2]), AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == CommandLine.arguments[index + 1]
              }) else {
            print("CHECK unavailable: running target, expected count, and Accessibility permission are required")
            exit(2)
        }
        let select = CommandLine.arguments.contains("--select")
        if !CommandLine.arguments.contains("--hover") && !select {
            let actual = WindowController().windows(of: app).count
            print("Window inventory check: expected \(expected), found \(actual)")
            exit(actual == expected ? 0 : 1)
        }
        Task { @MainActor in
            guard self.service.start(), self.service.locator.item(for: app) != nil else {
                self.service.stop()
                print("CHECK unavailable: active event tap and target Dock icon are required")
                exit(2)
            }
            let previousPointer = quartzPoint(NSEvent.mouseLocation)
            let previousApp = NSWorkspace.shared.frontmostApplication
            let initialWindows = self.service.controller.windows(of: app)
            if select, CommandLine.arguments.contains("--minimized"),
               let target = initialWindows.last {
                _ = self.service.controller.perform(.minimize(target.key.id), app: app, windows: [target])
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            var decoy: NSWindow?
            if select, let sourceIndex = CommandLine.arguments.firstIndex(of: "--from-app"),
               CommandLine.arguments.count > sourceIndex + 1,
               let source = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == CommandLine.arguments[sourceIndex + 1] }) {
                _ = AX.set(AXUIElementCreateApplication(source.processIdentifier), kAXFrontmostAttribute, true)
                source.activate(options: [])
                try? await Task.sleep(nanoseconds: 500_000_000)
            } else if select {
                let window = NSWindow(contentRect: CGRect(x: 100, y: 180, width: 360, height: 180),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.title = "Dock Enhanced · 临时切换验证"
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                decoy = window
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            var maximum = 0
            var previewMaximum = 0
            for _ in 0..<12 {
                if let current = self.service.locator.item(for: app) {
                    let point = CGPoint(x: current.frame.midX, y: current.frame.midY)
                    CGWarpMouseCursorPosition(point)
                    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                let inventory = self.service.controller.windows(of: app)
                maximum = max(maximum, inventory.count)
                if self.service.preview.app?.processIdentifier == app.processIdentifier {
                    previewMaximum = max(previewMaximum, self.service.preview.windowKeys.count)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if self.service.preview.isVisible && self.service.preview.app?.processIdentifier == app.processIdentifier {
                    previewMaximum = max(previewMaximum, self.service.preview.windowKeys.count)
                    break
                }
            }
            var stayedFrontmost = true
            var becameFrontmost = false
            var revealed = true
            var didSelect = false
            var selectedKey: WindowKey?
            if select, self.service.preview.isVisible, self.service.preview.app?.processIdentifier == app.processIdentifier {
                let original = self.service.preview.onSelect
                self.service.preview.onSelect = { window, selectedApp in
                    didSelect = selectedApp.processIdentifier == app.processIdentifier
                    selectedKey = window.key
                    original?(window, selectedApp)
                }
                let frame = self.service.preview.panel.frame
                let index = max(0, self.service.preview.windowKeys.count - 1)
                let click = quartzPoint(CGPoint(x: frame.minX + 12 + CGFloat(index) * 244 + 117, y: frame.minY + 100))
                CGWarpMouseCursorPosition(click)
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 100_000_000)
                for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                for _ in 0..<25 {
                    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                    if frontmost { becameFrontmost = true }
                    else if becameFrontmost { stayedFrontmost = false }
                    let inventory = self.service.controller.windows(of: app)
                    maximum = max(maximum, inventory.count)
                    revealed = inventory.first(where: { $0.key == selectedKey })?.state.minimized == false
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                stayedFrontmost = stayedFrontmost && becameFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            }
            self.service.stop()
            decoy?.close()
            for window in initialWindows { _ = AX.set(window.element, kAXMinimizedAttribute, window.state.minimized) }
            CGWarpMouseCursorPosition(previousPointer)
            if let previousApp { previousApp.activate(options: []) }
            print("Window inventory hover check: expected \(expected), inventory maximum \(maximum), preview maximum \(previewMaximum)")
            if select { print("Window selection foreground check: \(stayedFrontmost ? "PASS" : "FAIL"), restored: \(revealed), selection invoked: \(didSelect)") }
            if select && !didSelect { print("CHECK unavailable: target preview selection was not invoked"); exit(2) }
            exit(maximum == expected && previewMaximum == expected && stayedFrontmost && revealed ? 0 : 1)
        }
    }

}
#endif
