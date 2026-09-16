import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore()
        statusItem = StatusItemController(store: store)
        self.store = store
        store.start()
    }
}
