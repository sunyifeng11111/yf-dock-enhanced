#if DEBUG
import AppKit

/// Exercises the real AX/CG inventory using only windows owned by this process.
/// No application activation, posted input, or changes to another app's windows.
final class TransparentWindowInventoryCheck: NSObject, NSApplicationDelegate {
    private var fixtures: [NSWindow] = []
    private let controller = WindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard AXIsProcessTrusted() else { print("UNAVAILABLE: Accessibility permission required"); exit(2) }
        let standard = NSWindow(contentRect: CGRect(x: 60, y: 100, width: 360, height: 240),
                                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        standard.setAccessibilityIdentifier("inventory-standard")
        fixtures.append(standard)
        for index in 0..<2 {
            let panel = NSPanel(contentRect: CGRect(x: 440 + index * 200, y: 100, width: 187, height: 51),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setAccessibilitySubrole(.dialog)
            panel.setAccessibilityIdentifier("inventory-dialog-\(index)")
            panel.level = .floating
            fixtures.append(panel)
        }
        for window in fixtures {
            window.title = ""
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
        }
        Task { @MainActor in
            var passed = await self.expect(["inventory-standard", "inventory-dialog-0", "inventory-dialog-1"],
                                          "untitled standard and small visible dialogs remain eligible")
            self.fixtures[1].alphaValue = 0
            passed = await self.expect(["inventory-standard", "inventory-dialog-1"],
                                      "transparent floating dialog is removed even after being cached") && passed
            let originalFrame = self.fixtures[2].frame
            self.fixtures[2].setFrame(self.fixtures[1].frame, display: false)
            passed = await self.expect(["inventory-standard", "inventory-dialog-0", "inventory-dialog-1"],
                                      "ambiguous geometry with a visible dialog preserves both windows") && passed
            self.fixtures[2].setFrame(originalFrame, display: false)
            self.fixtures[1].level = .normal
            passed = await self.expect(["inventory-standard", "inventory-dialog-0", "inventory-dialog-1"],
                                      "transparent normal-level dialog is not classified as a floating helper") && passed
            self.fixtures[1].level = .floating
            self.fixtures[1].alphaValue = 1
            passed = await self.expect(["inventory-standard", "inventory-dialog-0", "inventory-dialog-1"],
                                      "dialog returns when visible again") && passed
            for window in self.fixtures { window.close() }
            exit(passed ? 0 : 1)
        }
    }

    @MainActor private func expect(_ expected: Set<String>, _ description: String) async -> Bool {
        try? await Task.sleep(nanoseconds: 150_000_000)
        let actual: Set<String> = await withCheckedContinuation { continuation in
            let scan = DispatchWorkItem {
                let windows = self.controller.windows(of: .current)
                continuation.resume(returning: Set(windows.compactMap {
                    AX.value($0.element, kAXIdentifierAttribute) as String?
                }))
            }
            DispatchQueue.global().async(execute: scan)
        }
        let passed = actual == expected
        print("\(passed ? "PASS" : "FAIL"): \(description); expected \(expected.sorted()), found \(actual.sorted())")
        return passed
    }
}
#endif
