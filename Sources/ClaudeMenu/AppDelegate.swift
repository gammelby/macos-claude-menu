import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A window-less accessory app is eligible for macOS automatic termination; stay resident.
        ProcessInfo.processInfo.disableAutomaticTermination("menubar item")
        ProcessInfo.processInfo.disableSuddenTermination()
        let store = UsageStore()
        statusItem = StatusItemController(store: store)
        self.store = store
        store.start()
    }
}
