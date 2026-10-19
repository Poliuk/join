import AppKit
import SwiftUI

/// The borderless, rounded window that hangs below the status item. A non-activating panel, like the alert:
/// it takes the keyboard (Esc, Return) without pulling the user's app out of the foreground.
final class MenuBarPanelWindow: NSPanel {
    static let width: CGFloat = 368
    static let cornerRadius: CGFloat = 14

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        // Not drawn on a borderless window; VoiceOver and the window chooser announce it.
        title = "Join! meetings"

        let hosting = PanelHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = Self.makeBackground(around: hosting)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Whether the panel is Liquid Glass; before macOS 26 it's the menu blur, which is already thick,
    /// so the frost over it is lighter.
    static var usesGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// The system menus' material: Liquid Glass on macOS 26 and later, the menu blur before that. The
    /// SwiftUI content lays a frost over it (`PanelFrost`) so text stays readable over any backdrop. Sized to
    /// `size` and rounded to the panel's corners: the panel's, and a notification card's behind its content
    /// (`NotificationCardWindow`).
    static func makeBackground(around content: NSView, size: NSSize = NSSize(width: width, height: 200)) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            // Regular is the default; set it anyway, since clear glass has no luminance adaptation at all.
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            glass.autoresizingMask = [.width, .height]
            // The window's shadow follows what the window draws, and the glass counts as its whole
            // rectangle: unclipped, the shadow was square, a dark outline with darkened corners around
            // the rounded glass. Clipping it to the rounded shape gives the shadow the same corners.
            let clip = NSView(frame: glass.frame)
            clip.wantsLayer = true
            clip.layer?.cornerRadius = cornerRadius
            clip.layer?.cornerCurve = .continuous
            clip.layer?.masksToBounds = true
            clip.addSubview(glass)
            return clip
        }
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        // The mask image shapes both the blur and the window shadow.
        blur.maskImage = roundedMask(radius: cornerRadius)
        content.frame = blur.bounds
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)
        return blur
    }

    /// Nonisolated: AppKit runs an image's drawing handler on whatever thread draws the image.
    nonisolated private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Buttons in the panel work on the first click, even when another window had focus.
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
