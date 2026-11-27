import AppKit
import OpenBetterDisplayCore
import SwiftUI

public enum PopoverLayoutMetrics {
    public static let popoverWidth: CGFloat = 320
    public static let minimumContentHeight: CGFloat = 260
    public static let screenEdgeMargin: CGFloat = 36

    public static func maxContentHeight(
        anchorRectInScreen: CGRect?,
        screenVisibleFrame: CGRect?
    ) -> CGFloat? {
        guard let screenVisibleFrame, screenVisibleFrame.height > 0 else {
            return nil
        }

        let availableHeight: CGFloat
        if let anchorRectInScreen, anchorRectInScreen.minY > screenVisibleFrame.minY {
            availableHeight = min(screenVisibleFrame.height, anchorRectInScreen.minY - screenVisibleFrame.minY)
        } else {
            availableHeight = screenVisibleFrame.height
        }

        return max(minimumContentHeight, floor(availableHeight - screenEdgeMargin))
    }
}

private final class FlippedPopoverClipView: NSClipView {
    override var isFlipped: Bool { true }
}

@MainActor
public final class VibrantPopoverViewController: NSViewController {
    private let hostingController: NSHostingController<DisplayPopoverView>
    private let visualEffectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let clipView = FlippedPopoverClipView()
    private var hostedHeightConstraint: NSLayoutConstraint?

    public var maxContentHeight: CGFloat? {
        didSet {
            if isViewLoaded {
                updatePreferredContentSize()
            }
        }
    }

    public init(coordinator: DisplayCoordinator, maxContentHeight: CGFloat? = nil) {
        self.maxContentHeight = maxContentHeight
        self.hostingController = NSHostingController(
            rootView: DisplayPopoverView(coordinator: coordinator)
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func loadView() {
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        visualEffectView.wantsLayer = true
        self.view = visualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        hostingController.sizingOptions = [.preferredContentSize]
        addChild(hostingController)

        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = hostedView
        visualEffectView.addSubview(scrollView)

        let heightConstraint = hostedView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.priority = .defaultHigh
        self.hostedHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: clipView.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            heightConstraint
        ])

        updatePreferredContentSize()
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        scrollToTop()
        updatePreferredContentSize()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        syncScrollerState()
    }

    override public func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        let size = viewController.preferredContentSize
        if size.width > 0, size.height > 0 {
            applyMeasuredContentSize(size)
        }
    }

    public func updateMaxContentHeight(forAnchorView anchorView: NSView?) {
        let screen = anchorView?.window?.screen ?? NSScreen.main
        let anchorRectInScreen: CGRect?
        if let anchorView, let anchorWindow = anchorView.window {
            let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            anchorRectInScreen = anchorWindow.convertToScreen(rectInWindow)
        } else {
            anchorRectInScreen = nil
        }
        maxContentHeight = PopoverLayoutMetrics.maxContentHeight(
            anchorRectInScreen: anchorRectInScreen,
            screenVisibleFrame: screen?.visibleFrame
        )
    }

    public func updatePreferredContentSize() {
        let fitted = hostingController.sizeThatFits(
            in: NSSize(width: PopoverLayoutMetrics.popoverWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        if fitted.width > 0, fitted.height > 0 {
            applyMeasuredContentSize(fitted)
        }
    }

    public func scrollToTop() {
        clipView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func applyMeasuredContentSize(_ fullSize: NSSize) {
        hostedHeightConstraint?.constant = fullSize.height
        let clampedHeight: CGFloat
        if let maxContentHeight {
            clampedHeight = min(fullSize.height, maxContentHeight)
        } else {
            clampedHeight = fullSize.height
        }

        let targetSize = NSSize(width: fullSize.width, height: clampedHeight)
        if preferredContentSize != targetSize {
            preferredContentSize = targetSize
        }

        hostingController.view.needsLayout = true
        visualEffectView.needsLayout = true
        syncScrollerState(documentHeight: fullSize.height, viewportHeight: clampedHeight)
    }

    private func syncScrollerState(documentHeight: CGFloat? = nil, viewportHeight: CGFloat? = nil) {
        let resolvedDocumentHeight = documentHeight ?? hostedHeightConstraint?.constant ?? hostingController.view.frame.height
        let resolvedViewportHeight =
            viewportHeight ?? (visualEffectView.bounds.height > 0 ? visualEffectView.bounds.height : preferredContentSize.height)
        guard resolvedViewportHeight > 0 else { return }

        let isOverflowing = resolvedDocumentHeight > resolvedViewportHeight + 0.5
        if scrollView.hasVerticalScroller != isOverflowing {
            scrollView.hasVerticalScroller = isOverflowing
        }

        let maxOffsetY = max(0, resolvedDocumentHeight - resolvedViewportHeight)
        if clipView.bounds.origin.y > maxOffsetY {
            clipView.scroll(to: NSPoint(x: 0, y: maxOffsetY))
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}
