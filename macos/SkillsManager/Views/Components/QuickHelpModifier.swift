import SwiftUI

/// A custom tooltip modifier that shows instantly on hover (no delay).
/// Uses NSWindow overlay to avoid clipping by parent views.
struct QuickHelpModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    showTooltip(text, near: content)
                } else {
                    hideTooltip()
                }
            }
    }

    // MARK: - Tooltip Window Management

    private func showTooltip(_ text: String, near content: Content) {
        guard let keyWindow = NSApp.keyWindow else { return }

        // Get the frame of the hovered view in screen coordinates
        guard let contentView = keyWindow.contentView else { return }

        // Find the NSView for this SwiftUI view by traversing
        let mouseLocation = NSEvent.mouseLocation
        let windowOrigin = keyWindow.frame.origin
        let localPoint = NSPoint(
            x: mouseLocation.x - windowOrigin.x,
            y: mouseLocation.y - windowOrigin.y
        )

        // Remove existing tooltip
        hideTooltip()

        // Create tooltip window
        let tooltipWindow = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.isOpaque = false
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.hasShadow = true
        tooltipWindow.level = .popUpMenu
        tooltipWindow.collectionBehavior = [.canJoinAllSpaces, .transient]
        tooltipWindow.ignoresMouseEvents = true

        // Build the tooltip view
        let hostingView = NSHostingView(
            rootView: TooltipLabel(text: text)
        )
        hostingView.layout()
        let size = hostingView.fittingSize

        // Position above the mouse cursor
        let origin = NSPoint(
            x: mouseLocation.x - size.width / 2,
            y: mouseLocation.y + 12
        )
        tooltipWindow.setFrame(NSRect(origin: origin, size: size), display: false)
        tooltipWindow.contentView = hostingView
        tooltipWindow.orderFront(nil)

        // Store reference
        objc_setAssociatedObject(
            NSApp,
            &QuickHelpModifier.tooltipKey,
            tooltipWindow,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func hideTooltip() {
        if let existing = objc_getAssociatedObject(NSApp, &QuickHelpModifier.tooltipKey) as? NSPanel {
            existing.close()
            objc_setAssociatedObject(NSApp, &QuickHelpModifier.tooltipKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private static var tooltipKey: UInt8 = 0
}

/// The tooltip content view.
private struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            )
            .fixedSize()
    }
}

extension View {
    /// Shows a tooltip instantly on hover with no delay. Not clipped by parent views.
    func quickHelp(_ text: String) -> some View {
        modifier(QuickHelpModifier(text: text))
    }
}
