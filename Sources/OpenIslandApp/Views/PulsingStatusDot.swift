import AppKit
import SwiftUI

/// A status pulse rendered entirely by Core Animation.
///
/// Keeping the pulse below SwiftUI prevents a running session from invalidating
/// its full row many times per second while the session list is being scrolled.
struct PulsingStatusDot: NSViewRepresentable {
    let tint: Color

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView()
        view.update(tint: NSColor(tint))
        return view
    }

    func updateNSView(_ nsView: LayerView, context: Context) {
        nsView.update(tint: NSColor(tint))
    }

    /// Hosts the animating layers without invalidating the enclosing SwiftUI row.
    final class LayerView: NSView {
        private let dotLayer = CAShapeLayer()
        private var tintColor = NSColor.white

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.masksToBounds = false

            dotLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            dotLayer.masksToBounds = false
            layer?.addSublayer(dotLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Updates the visible tint while preserving an existing pulse animation.
        func update(tint: NSColor) {
            tintColor = tint
            updateColors()
            needsLayout = true
            startAnimationIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                dotLayer.removeAllAnimations()
            } else {
                dotLayer.contentsScale = window?.backingScaleFactor ?? 2
                startAnimationIfNeeded()
            }
        }

        override func layout() {
            super.layout()
            let diameter: CGFloat = 9
            let dotBounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dotLayer.bounds = dotBounds
            dotLayer.position = CGPoint(x: bounds.midX, y: bounds.maxY - 6 - diameter / 2)
            dotLayer.path = CGPath(ellipseIn: dotBounds, transform: nil)
            dotLayer.shadowPath = dotLayer.path
            CATransaction.commit()

            startAnimationIfNeeded()
        }

        private func updateColors() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dotLayer.fillColor = tintColor.cgColor
            dotLayer.shadowColor = tintColor.cgColor
            dotLayer.shadowOpacity = 0.36
            dotLayer.shadowRadius = 4
            dotLayer.shadowOffset = .zero
            CATransaction.commit()
        }

        private func startAnimationIfNeeded() {
            guard window != nil, dotLayer.animation(forKey: "statusPulse") == nil else { return }

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 1.18

            let shadowOpacity = CABasicAnimation(keyPath: "shadowOpacity")
            shadowOpacity.fromValue = 0.36
            shadowOpacity.toValue = 0.62

            let shadowRadius = CABasicAnimation(keyPath: "shadowRadius")
            shadowRadius.fromValue = 4
            shadowRadius.toValue = 7

            let group = CAAnimationGroup()
            group.animations = [scale, shadowOpacity, shadowRadius]
            group.duration = 0.98
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            dotLayer.add(group, forKey: "statusPulse")
        }
    }
}
