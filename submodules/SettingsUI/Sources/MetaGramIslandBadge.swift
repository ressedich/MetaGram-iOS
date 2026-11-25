import Foundation
import UIKit
import TelegramCore

/// MetaGram "Logo in Dynamic Island" (as Swiftgram): while the app is open, the Dynamic Island looks a little wider,
/// with the MetaGram glyph on its left and "METAGRAM" on its right. A black pill the island's height is drawn around
/// the island's place, in a window of its own above the app that takes no touches; it shows in portrait on iPhones
/// with the Dynamic Island only.
public enum MetaGramIslandBadge {
    private static var overlayWindow: UIWindow?
    private static weak var hostWindow: UIWindow?

    /// Shows or hides the badge after the app became active or the option changed. `window` is the app's window
    /// (nil reuses the last one).
    public static func update(window: UIWindow?) {
        if let window {
            self.hostWindow = window
        }
        guard MetaGramSettings.get(.islandBadge), let hostWindow = self.hostWindow, let scene = hostWindow.windowScene else {
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
            return
        }
        if self.overlayWindow == nil {
            let overlay = MetaGramIslandWindow(windowScene: scene)
            overlay.frame = scene.coordinateSpace.bounds
            overlay.windowLevel = UIWindow.Level.statusBar + 1.0
            overlay.isUserInteractionEnabled = false
            overlay.backgroundColor = .clear
            overlay.isHidden = false
            self.overlayWindow = overlay
        }
        self.overlayWindow?.setNeedsLayout()
    }
}

/// No root view controller, so the window never takes over the status bar's appearance; it lays the badge out
/// itself and takes no touches.
private final class MetaGramIslandWindow: UIWindow {
    private let badgeView = MetaGramIslandBadgeView()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        self.addSubview(self.badgeView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safeAreaTop = self.windowScene?.windows.first(where: { !($0 is MetaGramIslandWindow) })?.safeAreaInsets.top ?? self.safeAreaInsets.top
        self.badgeView.layout(in: self.bounds, safeAreaTop: safeAreaTop)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

private final class MetaGramIslandBadgeView: UIView {
    // the Dynamic Island in portrait (iPhone 14 Pro and later)
    private let islandWidth: CGFloat = 126.0
    private let islandHeight: CGFloat = 37.0
    private let islandTop: CGFloat = 11.0

    private let glyphLayer = CAShapeLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black
        self.isUserInteractionEnabled = false
        self.layer.masksToBounds = true

        self.glyphLayer.fillColor = UIColor.clear.cgColor
        self.glyphLayer.strokeColor = UIColor.white.cgColor
        self.glyphLayer.lineWidth = 2.2
        self.glyphLayer.lineCap = .round
        self.layer.addSublayer(self.glyphLayer)

        self.label.text = "METAGRAM"
        self.label.textColor = .white
        self.label.font = UIFont.systemFont(ofSize: 12.0, weight: .heavy)
        self.label.sizeToFit()
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layout(in bounds: CGRect, safeAreaTop: CGFloat) {
        // the island's status bar is 54-59 pt tall, a notch's 44-50 pt; landscape has no island at the top
        let hasIsland = UIDevice.current.userInterfaceIdiom == .phone && safeAreaTop >= 51.0 && bounds.width < bounds.height
        self.isHidden = !hasIsland
        if !hasIsland {
            return
        }

        let glyphSize: CGFloat = 15.0
        let leadingWidth: CGFloat = 12.0 + glyphSize + 8.0
        let trailingWidth: CGFloat = 8.0 + self.label.bounds.width + 14.0
        let islandMinX = floor((bounds.width - self.islandWidth) / 2.0)

        self.frame = CGRect(x: islandMinX - leadingWidth, y: self.islandTop, width: leadingWidth + self.islandWidth + trailingWidth, height: self.islandHeight)
        self.layer.cornerRadius = self.islandHeight / 2.0

        // the glyph: a circle crossed by a diagonal line, as the app icon
        let glyphRect = CGRect(x: 12.0, y: floor((self.islandHeight - glyphSize) / 2.0), width: glyphSize, height: glyphSize)
        let path = UIBezierPath(ovalIn: glyphRect.insetBy(dx: 1.1, dy: 1.1))
        let inset = glyphSize * 0.24
        path.move(to: CGPoint(x: glyphRect.minX + inset, y: glyphRect.maxY - inset))
        path.addLine(to: CGPoint(x: glyphRect.maxX - inset, y: glyphRect.minY + inset))
        self.glyphLayer.frame = self.bounds
        self.glyphLayer.path = path.cgPath

        self.label.frame = CGRect(x: leadingWidth + self.islandWidth + 8.0, y: floor((self.islandHeight - self.label.bounds.height) / 2.0), width: self.label.bounds.width, height: self.label.bounds.height)
    }
}
