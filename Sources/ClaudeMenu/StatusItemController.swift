import AppKit
import ClaudeMenuCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var eventMonitors: [Any] = []

    init(store: UsageStore) {
        self.store = store
        super.init()

        let hosting = NSHostingController(rootView: PopoverView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        // Not `.transient`: macOS does not activate this accessory app, so the popover only borrows
        // key focus and would close whenever any other app activates itself. Close on real clicks instead.
        popover.behavior = .applicationDefined
        popover.animates = false

        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        store.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = item.button else { return }
        store.popoverOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()

        // Global monitors see clicks aimed at other processes. The status item is hosted outside this
        // process on recent macOS, so its own click can arrive here too; the toggle action handles that one.
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in MainActor.assumeIsolated { self?.closeUnlessOnStatusItem() } }
        ) {
            eventMonitors.append(outside)
        }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePopover() }
            return nil
        }) {
            eventMonitors.append(escape)
        }
    }

    private func closeUnlessOnStatusItem() {
        if let frame = item.button?.window?.frame, frame.contains(NSEvent.mouseLocation) { return }
        closePopover()
    }

    private func closePopover() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        popover.performClose(nil)
    }

    private func updateTitle() {
        guard let button = item.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

        switch TitleFormatter.content(mode: store.titleMode, limits: store.limits) {
        case .placeholder:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "–", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        case .text(let segments):
            button.image = nil
            let title = NSMutableAttributedString()
            for segment in segments {
                title.append(NSAttributedString(string: segment.text, attributes: [
                    .font: font,
                    .foregroundColor: segment.severity.map(Self.textColor) ?? NSColor.labelColor,
                ]))
            }
            button.attributedTitle = title
        case .icon(let symbol, let severity):
            // Monochrome template glyph like other menubar icons, plus a traffic-light dot for the worst limit.
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude usage")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: "●", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .baselineOffset: 1,
                .foregroundColor: Self.dotColor(severity),
            ])
        }

        button.toolTip = store.limits.isEmpty
            ? (store.usageError?.message ?? "Claude usage: loading")
            : store.limits.map { "\($0.displayName): \(Formatting.percent($0.percent))" }.joined(separator: "\n")
    }

    private static func textColor(_ severity: Severity) -> NSColor {
        switch severity {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private static func dotColor(_ severity: Severity) -> NSColor {
        switch severity {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }
}
