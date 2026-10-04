import CoreGraphics

/// Geometry and ownership decisions shared by gesture tracking and its tests.
/// Every drag starts from the displayed frame, including an interrupted settle.
struct AetherModalDragGeometry {
    typealias Detent = AetherModalController.Detent

    let compactFrame: CGRect
    let expandedFrame: CGRect
    let allowedDetents: Set<Detent>

    func progress(for frame: CGRect) -> CGFloat {
        let distance = compactFrame.minY - expandedFrame.minY
        guard distance > 0 else { return allowedDetents.contains(.stage2) ? 1 : 0 }
        return max(0, min(1, (compactFrame.minY - frame.minY) / distance))
    }

    func shouldDrive(
        translationY: CGFloat,
        currentFrame: CGRect,
        startsInScrollContent: Bool,
        scrollIsAtTop: Bool
    ) -> Bool {
        guard translationY != 0 else { return false }
        guard startsInScrollContent else { return true }
        if translationY > 0 { return scrollIsAtTop }
        // Upward content scrolling expands a compact two-detent sheet. A
        // compact-only sheet must yield to its scroll view instead of trapping
        // its content in a rubber-band gesture that cannot expand anything.
        return allowedDetents.contains(.stage2)
            && currentFrame.minY > expandedFrame.minY + 0.5
    }

    func frame(from start: CGRect, translationY: CGFloat) -> CGRect {
        guard translationY != 0 else { return start }
        if translationY > 0 {
            let lower = allowedDetents.contains(.stage1) ? compactFrame : expandedFrame
            let distance = max(0, lower.minY - start.minY)
            if distance > 0, translationY < distance {
                return Self.interpolate(from: start, to: lower, progress: translationY / distance)
            }
            if distance > 0 {
                return lower.offsetBy(dx: 0, dy: translationY - distance)
            }
            return start.offsetBy(dx: 0, dy: translationY)
        }

        let upper = allowedDetents.contains(.stage2) ? expandedFrame : compactFrame
        let distance = max(0, start.minY - upper.minY)
        let travel = -translationY
        if distance > 0, travel < distance {
            return Self.interpolate(from: start, to: upper, progress: travel / distance)
        }
        // Header dragging above a compact-only detent has a little resistance;
        // expanded sheets stop at their top boundary. Neither path changes the
        // frame at zero translation, even when interrupting a correction.
        if !allowedDetents.contains(.stage2) {
            let excess = max(0, travel - distance)
            let baseline = distance > 0 ? upper : start
            return baseline.offsetBy(dx: 0, dy: -Self.rubberband(excess))
        }
        return distance > 0 ? upper : start
    }

    static func interpolate(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let t = max(0, min(1, progress))
        return CGRect(
            x: start.minX + (end.minX - start.minX) * t,
            y: start.minY + (end.minY - start.minY) * t,
            width: start.width + (end.width - start.width) * t,
            height: start.height + (end.height - start.height) * t
        )
    }

    private static func rubberband(_ distance: CGFloat) -> CGFloat {
        let dimension: CGFloat = 100
        return dimension * (1 - 1 / (1 + max(0, distance) * 0.55 / dimension))
    }
}
