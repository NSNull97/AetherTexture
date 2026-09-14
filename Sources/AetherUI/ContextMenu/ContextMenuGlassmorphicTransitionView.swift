import UIKit
import CoreImage
import AsyncDisplayKit

enum ContextMenuBloomDirection: Equatable {
    case opening
    case closing
}

/// Independent clocks measured from the first changing dismissal frame.
/// The source becomes readable inside the still-collapsing surface; it must
/// not wait for the tiny source lobe to finish growing back into a button.
struct ContextMenuSourceMaterializationSample: Equatable {
    let opacity: CGFloat
    let blurRadius: CGFloat
}

func contextMenuSourceMaterializationSample(
    rawProgress: CGFloat,
    direction: ContextMenuBloomDirection,
    menuHeight: CGFloat,
    reduceMotion: Bool = false
) -> ContextMenuSourceMaterializationSample {
    let t = max(0.0, min(1.0, rawProgress))
    if direction == .opening {
        let fade = contextMenuBloomSmoothRange(t, start: 0.02, end: 0.18)
        return .init(opacity: 1.0 - fade, blurRadius: 0.0)
    }
    let elapsed = 1.0 - t
    let heightFactor = max(0.0, min(1.0, (menuHeight - 180.0) / 220.0))
    let revealStart = 0.30 + 0.08 * heightFactor
    let reveal = contextMenuBloomSmoothRange(elapsed, start: revealStart, end: 0.68)
    let focus = contextMenuBloomSmoothRange(elapsed, start: revealStart, end: 0.68)
    return .init(
        opacity: reveal,
        blurRadius: reduceMotion ? 0.0 : 8.0 * (1.0 - focus)
    )
}

/// A short menu loses its rows in ~81 ms; a tall platter needs ~129 ms.
/// Both finish before the source content returns. Heights are UIKit points,
/// not screen-recording pixels, so the clock is stable across device scales.
func contextMenuClosingContentProgress(rawProgress: CGFloat, menuHeight: CGFloat) -> CGFloat {
    let elapsed = 1.0 - max(0.0, min(1.0, rawProgress))
    let heightFactor = max(0.0, min(1.0, (menuHeight - 180.0) / 220.0))
    let dissolveFraction = 0.30 + 0.18 * heightFactor
    return max(0.0, 1.0 - elapsed / dissolveFraction)
}

private func contextMenuOpeningLiquidProgress(_ rawProgress: CGFloat) -> CGFloat {
    // The reference is emphatically non-linear in absolute time.  It spends
    // the first 80 ms pulling a compact egg from the button, accelerates
    // through the pear, reaches its overshoot at ~233 ms, and is settled by
    // ~267 ms.  A constant clock scale made the first broad platter arrive
    // roughly 50–60 ms early even though the endpoint timing was correct.
    contextMenuBloomSample(
        times: [
            0.0,       //   0 ms
            0.053125,  //  17 ms
            0.156250,  //  50 ms
            0.259375,  //  83 ms
            0.365625,  // 117 ms
            0.468750,  // 150 ms
            0.571875,  // 183 ms
            0.625000,  // 200 ms
            0.728125,  // 233 ms
            0.834375,  // 267 ms
            1.0
        ],
        values: [
            0.0,
            0.025,
            0.100,
            0.180,
            0.260,
            0.320,
            0.400,
            0.460,
            0.520,
            0.660,
            0.660
        ],
        at: max(0.0, min(1.0, rawProgress))
    )
}

/// The point of the source and destination surfaces that stays visually
/// attached while the platter changes size. Navbar menus normally use
/// `(1, 0)` (top-trailing); centred sources use `(0.5, 0)` instead of being
/// forced to one of the four corners.
struct ContextMenuBloomAnchor: Equatable {
    let unitPoint: CGPoint

    static let topTrailing = ContextMenuBloomAnchor(unitPoint: CGPoint(x: 1, y: 0))

    static func detect(
        source: CGRect,
        target: CGRect,
        tolerance: CGFloat = 1.0
    ) -> ContextMenuBloomAnchor {
        let x: CGFloat
        if abs(source.maxX - target.maxX) <= tolerance {
            x = 1.0
        } else if abs(source.minX - target.minX) <= tolerance {
            x = 0.0
        } else if abs(source.midX - target.midX) <= tolerance {
            x = 0.5
        } else {
            // A clamped menu can lose its exact edge relationship. Keeping
            // the closest semantic edge is less surprising than allowing the
            // glass to drift across the trigger during the morph.
            let leadingDistance = abs(source.minX - target.minX)
            let trailingDistance = abs(source.maxX - target.maxX)
            x = leadingDistance < trailingDistance ? 0.0 : 1.0
        }

        let y: CGFloat
        if abs(source.maxY - target.maxY) <= tolerance {
            y = 1.0
        } else if abs(source.minY - target.minY) <= tolerance {
            y = 0.0
        } else if abs(source.midY - target.midY) <= tolerance {
            y = 0.5
        } else {
            let topDistance = abs(source.minY - target.minY)
            let bottomDistance = abs(source.maxY - target.maxY)
            y = topDistance < bottomDistance ? 0.0 : 1.0
        }

        return ContextMenuBloomAnchor(unitPoint: CGPoint(x: x, y: y))
    }
}

struct ContextMenuBloomCornerRadii: Equatable {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    static func uniform(_ radius: CGFloat) -> ContextMenuBloomCornerRadii {
        ContextMenuBloomCornerRadii(
            topLeft: radius,
            topRight: radius,
            bottomLeft: radius,
            bottomRight: radius
        )
    }

    var average: CGFloat {
        (topLeft + topRight + bottomLeft + bottomRight) / 4.0
    }
}

struct ContextMenuBloomGeometrySample: Equatable {
    let frame: CGRect
    let cornerRadii: ContextMenuBloomCornerRadii
    let widthT: CGFloat
    let heightT: CGFloat
    let anchorTravelT: CGFloat
}

func contextMenuBloomAnchoredFrame(
    contentSize: CGSize,
    in containerBounds: CGRect,
    anchor: ContextMenuBloomAnchor
) -> CGRect {
    let unit = CGPoint(
        x: max(0.0, min(1.0, anchor.unitPoint.x)),
        y: max(0.0, min(1.0, anchor.unitPoint.y))
    )
    return CGRect(
        x: containerBounds.minX + (containerBounds.width - contentSize.width) * unit.x,
        y: containerBounds.minY + (containerBounds.height - contentSize.height) * unit.y,
        width: contentSize.width,
        height: contentSize.height
    )
}

/// Pure geometry resolver shared by production and tests. `rawProgress` is
/// always the visible surface state (`0 = source`, `1 = menu`); closing feeds
/// it from 1 back to 0 but uses its own measured profile instead of reversing
/// the opening curve.
func contextMenuBloomGeometrySample(
    source: CGRect,
    target: CGRect,
    sourceRadius: CGFloat,
    targetRadius: CGFloat,
    anchor: ContextMenuBloomAnchor,
    direction: ContextMenuBloomDirection,
    rawProgress: CGFloat,
    reduceMotion: Bool
) -> ContextMenuBloomGeometrySample {
    let raw = max(0.0, min(1.0, rawProgress))

    if raw <= 0.0 {
        return ContextMenuBloomGeometrySample(
            frame: source,
            cornerRadii: .uniform(sourceRadius),
            widthT: 0.0,
            heightT: 0.0,
            anchorTravelT: 0.0
        )
    }
    if raw >= 1.0 {
        return ContextMenuBloomGeometrySample(
            frame: target,
            cornerRadii: .uniform(targetRadius),
            widthT: 1.0,
            heightT: 1.0,
            anchorTravelT: 1.0
        )
    }

    let widthT: CGFloat
    let heightT: CGFloat
    switch direction {
    case .opening:
        // The reference does not reach a near-final footprint in its first
        // pear frame. It pulls a small body out at ~50 ms, then keeps growing
        // that same asymmetric mass for another ~170 ms before the final
        // rebound. Sampling on the absolute opening clock avoids compressing
        // that whole transfer into one large capsule frame.
        if reduceMotion {
            let localT = contextMenuBloomNormalize(raw, start: 0.04, end: 0.58)
            let eased = contextMenuBloomSmootherstep(localT)
            widthT = eased
            heightT = eased
        } else {
            let liquidT = contextMenuOpeningLiquidProgress(raw)
            widthT = contextMenuBloomSample(
                times: [
                    0.04, 0.08, 0.12, 0.16, 0.20, 0.24, 0.28,
                    0.32, 0.36, 0.40, 0.44, 0.48, 0.52, 0.58, 0.66
                ],
                values: [
                    0.0, 0.025, 0.17, 0.35, 0.49, 0.61, 0.72,
                    0.80, 0.87, 0.93, 0.97, 1.0, 1.025, 1.010, 1.0
                ],
                at: liquidT
            )
            heightT = contextMenuBloomSample(
                times: [
                    0.04, 0.08, 0.12, 0.16, 0.20, 0.24, 0.28,
                    0.32, 0.36, 0.40, 0.44, 0.48, 0.50, 0.54, 0.60, 0.66
                ],
                values: [
                    0.0, 0.04, 0.17, 0.30, 0.42, 0.54, 0.66,
                    0.75, 0.83, 0.89, 0.94, 0.98, 1.035, 1.018, 1.010, 1.0
                ],
                at: liquidT
            )
        }

    case .closing:
        let elapsed = 1.0 - raw
        if reduceMotion {
            let localT = contextMenuBloomNormalize(elapsed, start: 0.0, end: 0.78)
            let remaining = 1.0 - contextMenuBloomSmootherstep(localT)
            widthT = remaining
            heightT = remaining
        } else {
            // Recording 4.183...4.483: contraction begins on the next
            // 17 ms frame, reaches a compact egg at about 110 ms, then the
            // narrow body rebounds to the source. These are elapsed-time
            // samples, without the old ~98 ms normalization/plateau delay.
            let times: [CGFloat] = [
                0.0, 0.053125, 0.131250, 0.234375, 0.340625,
                0.443750, 0.546875, 0.653125, 0.756250, 0.875, 1.0
            ]
            let contraction = contextMenuBloomSample(
                times: times,
                values: [1.0, 0.72, 0.59, 0.37, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                at: elapsed
            )
            let sourceCompression = contextMenuBloomSample(
                times: times,
                values: [0.0, 0.0, 0.0, 0.0, 0.06, 0.25, 0.28, 0.14, 0.06, 0.0, 0.0],
                at: elapsed
            )
            let widthDifference = target.width - source.width
            // Scale the undershoot to the trigger, not the menu: the same
            // motion remains valid for a 44 pt icon and a wide text button.
            let shortWidthT = widthDifference > 1.0
                ? contraction - source.width / widthDifference * sourceCompression
                : contraction
            let shortHeightT = contextMenuBloomSample(
                times: times,
                values: [1.0, 0.90, 0.765, 0.72, 0.585, 0.36, 0.215, 0.08, 0.02, 0.0, 0.0],
                at: elapsed
            )
            let tallness = contextMenuClosingTallness(target: target)
            let tall = contextMenuTallClosingSample(elapsed: elapsed)
            let tallBodyHeight = source.height + (target.height - source.height) * tall.bodyHeightT
            let tallEnvelopeHeight = max(source.height, tallBodyHeight + target.height * tall.topOffset)
            let tallHeightT = (tallEnvelopeHeight - source.height) / max(1.0, target.height - source.height)
            widthT = shortWidthT + (tall.widthT - shortWidthT) * tallness
            heightT = shortHeightT + (tallHeightT - shortHeightT) * tallness
        }
    }

    let width = max(0.001, source.width + (target.width - source.width) * widthT)
    let height = max(0.001, source.height + (target.height - source.height) * heightT)
    let anchorTravelT = max(0.0, min(1.0, (widthT + heightT) * 0.5))
    let unit = CGPoint(
        x: max(0.0, min(1.0, anchor.unitPoint.x)),
        y: max(0.0, min(1.0, anchor.unitPoint.y))
    )
    let sourceAnchor = CGPoint(
        x: source.minX + source.width * unit.x,
        y: source.minY + source.height * unit.y
    )
    let targetAnchor = CGPoint(
        x: target.minX + target.width * unit.x,
        y: target.minY + target.height * unit.y
    )
    let currentAnchor = CGPoint(
        x: sourceAnchor.x + (targetAnchor.x - sourceAnchor.x) * anchorTravelT,
        y: sourceAnchor.y + (targetAnchor.y - sourceAnchor.y) * anchorTravelT
    )
    let frame = CGRect(
        x: currentAnchor.x - width * unit.x,
        y: currentAnchor.y - height * unit.y,
        width: width,
        height: height
    )

    let openAmount = max(0.0, min(1.0, (widthT + heightT) * 0.5))
    let circleRadius = min(width, height) * 0.5
    let circleT = contextMenuBloomSmoothRange(openAmount, start: 0.0, end: 0.18)
    let menuT = contextMenuBloomSmoothRange(openAmount, start: 0.52, end: 0.94)
    let bubbleRadius = sourceRadius + (circleRadius - sourceRadius) * circleT
    let freeRadius = min(
        circleRadius,
        bubbleRadius + (targetRadius - bubbleRadius) * menuT
    )
    // The attached corner remains button-like while the other three corners
    // inflate into the teardrop. It joins the final 27 pt menu radius only in
    // the latter half of the morph.
    let attachedT = contextMenuBloomSmoothRange(openAmount, start: 0.54, end: 0.94)
    let attachedRadius = min(
        circleRadius,
        sourceRadius + (targetRadius - sourceRadius) * attachedT
    )
    var radii = ContextMenuBloomCornerRadii.uniform(freeRadius)
    if unit.x >= 0.75, unit.y <= 0.25 {
        radii = ContextMenuBloomCornerRadii(
            topLeft: freeRadius,
            topRight: attachedRadius,
            bottomLeft: freeRadius,
            bottomRight: freeRadius
        )
    } else if unit.x <= 0.25, unit.y <= 0.25 {
        radii = ContextMenuBloomCornerRadii(
            topLeft: attachedRadius,
            topRight: freeRadius,
            bottomLeft: freeRadius,
            bottomRight: freeRadius
        )
    } else if unit.x >= 0.75, unit.y >= 0.75 {
        radii = ContextMenuBloomCornerRadii(
            topLeft: freeRadius,
            topRight: freeRadius,
            bottomLeft: freeRadius,
            bottomRight: attachedRadius
        )
    } else if unit.x <= 0.25, unit.y >= 0.75 {
        radii = ContextMenuBloomCornerRadii(
            topLeft: freeRadius,
            topRight: freeRadius,
            bottomLeft: attachedRadius,
            bottomRight: freeRadius
        )
    }

    return ContextMenuBloomGeometrySample(
        frame: frame,
        cornerRadii: radii,
        widthT: widthT,
        heightT: heightT,
        anchorTravelT: anchorTravelT
    )
}

private func contextMenuClosingTallness(target: CGRect) -> CGFloat {
    contextMenuBloomSmoothRange(target.height / max(1.0, target.width), start: 0.90, end: 1.40)
}

private func contextMenuTallClosingSample(elapsed: CGFloat) -> (
    widthT: CGFloat, bodyWidthT: CGFloat, bodyHeightT: CGFloat, topOffset: CGFloat
) {
    // Tall filter-menu reference 20.437...20.757. Unlike the short Edit
    // platter, this body travels down while contracting and keeps enough
    // width for a rounded lower lobe until the source/neck takes over.
    let times: [CGFloat] = [0, 0.05, 0.156, 0.26, 0.363, 0.469, 0.572, 0.675, 0.781, 0.875, 1]
    return (
        contextMenuBloomSample(times: times, values: [1, 0.974, 0.787, 0.584, 0.377, 0.206, 0.077, 0.013, 0, 0, 0], at: elapsed),
        contextMenuBloomSample(times: times, values: [1, 0.974, 0.787, 0.584, 0.377, 0.206, 0.068, -0.032, 0, 0, 0], at: elapsed),
        contextMenuBloomSample(times: times, values: [1, 0.976, 0.758, 0.533, 0.338, 0.19, 0.079, -0.018, 0, 0, 0], at: elapsed),
        contextMenuBloomSample(times: times, values: [0, 0.036, 0.153, 0.166, 0.140, 0.101, 0.078, 0.074, 0.03, 0, 0], at: elapsed)
    )
}

private func contextMenuBloomNormalize(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
    guard start != end else { return value >= end ? 1.0 : 0.0 }
    return max(0.0, min(1.0, (value - start) / (end - start)))
}

private func contextMenuBloomSmootherstep(_ value: CGFloat) -> CGFloat {
    let t = max(0.0, min(1.0, value))
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

private func contextMenuBloomSmoothRange(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
    contextMenuBloomSmootherstep(contextMenuBloomNormalize(value, start: start, end: end))
}

private func contextMenuBloomSample(
    times: [CGFloat],
    values: [CGFloat],
    at progress: CGFloat
) -> CGFloat {
    precondition(times.count == values.count && !times.isEmpty)
    let t = max(times[0], min(times[times.count - 1], progress))
    if t <= times[0] { return values[0] }
    for index in 1..<times.count where t <= times[index] {
        let lowerIndex = index - 1
        let duration = times[index] - times[lowerIndex]
        let segment = contextMenuBloomNormalize(t, start: times[lowerIndex], end: times[index])
        let segmentSquared = segment * segment
        let segmentCubed = segmentSquared * segment
        let lowerTangent = contextMenuBloomTangent(times: times, values: values, index: lowerIndex)
        let upperTangent = contextMenuBloomTangent(times: times, values: values, index: index)

        // A shape-preserving cubic Hermite spline keeps a shared velocity at
        // every measured checkpoint. The old per-segment smootherstep made
        // the shell stop for a few milliseconds at every point, which read
        // as tiny hitches at 120 Hz. Tangents become zero only at genuine
        // extrema and at the delayed/settled endpoints.
        let lowerWeight = 2.0 * segmentCubed - 3.0 * segmentSquared + 1.0
        let lowerTangentWeight = segmentCubed - 2.0 * segmentSquared + segment
        let upperWeight = -2.0 * segmentCubed + 3.0 * segmentSquared
        let upperTangentWeight = segmentCubed - segmentSquared
        return lowerWeight * values[lowerIndex]
            + lowerTangentWeight * duration * lowerTangent
            + upperWeight * values[index]
            + upperTangentWeight * duration * upperTangent
    }
    return values[values.count - 1]
}

private func contextMenuBloomTangent(
    times: [CGFloat],
    values: [CGFloat],
    index: Int
) -> CGFloat {
    guard index > 0, index < values.count - 1 else { return 0.0 }

    let previousDuration = times[index] - times[index - 1]
    let nextDuration = times[index + 1] - times[index]
    guard previousDuration > 0.0, nextDuration > 0.0 else { return 0.0 }

    let previousSlope = (values[index] - values[index - 1]) / previousDuration
    let nextSlope = (values[index + 1] - values[index]) / nextDuration
    guard previousSlope * nextSlope > 0.0 else {
        // A measured peak/trough must stay exactly where it was observed and
        // must not gain an extra spline overshoot.
        return 0.0
    }

    // Fritsch-Carlson weighted harmonic mean: C1-continuous at checkpoints
    // and monotone inside each monotone run, even with uneven sample times.
    let previousWeight = 2.0 * nextDuration + previousDuration
    let nextWeight = nextDuration + 2.0 * previousDuration
    return (previousWeight + nextWeight)
        / (previousWeight / previousSlope + nextWeight / nextSlope)
}

private func contextMenuBloomRoundedPath(
    in rect: CGRect,
    radii: ContextMenuBloomCornerRadii
) -> CGPath {
    let maximumRadius = max(0.0, min(rect.width, rect.height) * 0.5)
    let topLeft = min(maximumRadius, max(0.0, radii.topLeft))
    let topRight = min(maximumRadius, max(0.0, radii.topRight))
    let bottomLeft = min(maximumRadius, max(0.0, radii.bottomLeft))
    let bottomRight = min(maximumRadius, max(0.0, radii.bottomRight))
    let path = UIBezierPath()

    path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
    if topRight > 0 {
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: -.pi / 2.0,
            endAngle: 0.0,
            clockwise: true
        )
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
    if bottomRight > 0 {
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight,
            startAngle: 0.0,
            endAngle: .pi / 2.0,
            clockwise: true
        )
    }
    path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
    if bottomLeft > 0 {
        path.addArc(
            withCenter: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
            startAngle: .pi / 2.0,
            endAngle: .pi,
            clockwise: true
        )
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
    if topLeft > 0 {
        path.addArc(
            withCenter: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            clockwise: true
        )
    }
    path.close()
    return path.cgPath
}

/// Direction-specific glass topology sampled independently from rendering.
/// Opening keeps a compact seed embedded in one connected carrier; closing
/// keeps the source/body/neck breakup needed for its longer return flow.
/// Keeping both profiles in one value lets tests inspect the exact visible
/// silhouette while production drives every surface from one display-link.
struct ContextMenuGlassmorphicGeometrySample: Equatable {
    let headFrame: CGRect
    let bodyFrame: CGRect
    let headRotation: CGFloat
    let bodyRotation: CGFloat
    let headRadius: CGFloat
    let bodyCornerRadii: ContextMenuBloomCornerRadii
    let bridgeStart: CGPoint
    let bridgeEnd: CGPoint
    let bridgeRadius: CGFloat
    let neckBulbCenter: CGPoint
    let neckBulbRadius: CGFloat
    let headAlpha: CGFloat
    let bodyAlpha: CGFloat

    static func interpolated(
        from: ContextMenuGlassmorphicGeometrySample,
        to: ContextMenuGlassmorphicGeometrySample,
        progress: CGFloat
    ) -> ContextMenuGlassmorphicGeometrySample {
        let t = max(0.0, min(1.0, progress))
        if t == 0.0 { return from }
        if t == 1.0 { return to }
        func scalar(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
            lhs + (rhs - lhs) * t
        }
        func point(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
            CGPoint(x: scalar(lhs.x, rhs.x), y: scalar(lhs.y, rhs.y))
        }
        func rect(_ lhs: CGRect, _ rhs: CGRect) -> CGRect {
            CGRect(
                x: scalar(lhs.minX, rhs.minX),
                y: scalar(lhs.minY, rhs.minY),
                width: scalar(lhs.width, rhs.width),
                height: scalar(lhs.height, rhs.height)
            )
        }
        func radii(
            _ lhs: ContextMenuBloomCornerRadii,
            _ rhs: ContextMenuBloomCornerRadii
        ) -> ContextMenuBloomCornerRadii {
            ContextMenuBloomCornerRadii(
                topLeft: scalar(lhs.topLeft, rhs.topLeft),
                topRight: scalar(lhs.topRight, rhs.topRight),
                bottomLeft: scalar(lhs.bottomLeft, rhs.bottomLeft),
                bottomRight: scalar(lhs.bottomRight, rhs.bottomRight)
            )
        }

        return ContextMenuGlassmorphicGeometrySample(
            headFrame: rect(from.headFrame, to.headFrame),
            bodyFrame: rect(from.bodyFrame, to.bodyFrame),
            headRotation: scalar(from.headRotation, to.headRotation),
            bodyRotation: scalar(from.bodyRotation, to.bodyRotation),
            headRadius: scalar(from.headRadius, to.headRadius),
            bodyCornerRadii: radii(from.bodyCornerRadii, to.bodyCornerRadii),
            bridgeStart: point(from.bridgeStart, to.bridgeStart),
            bridgeEnd: point(from.bridgeEnd, to.bridgeEnd),
            bridgeRadius: scalar(from.bridgeRadius, to.bridgeRadius),
            neckBulbCenter: point(from.neckBulbCenter, to.neckBulbCenter),
            neckBulbRadius: scalar(from.neckBulbRadius, to.neckBulbRadius),
            headAlpha: scalar(from.headAlpha, to.headAlpha),
            bodyAlpha: scalar(from.bodyAlpha, to.bodyAlpha)
        )
    }
}

/// Opening uses one connected mass after the initial egg impulse. The seed
/// remains embedded in the carrier as its compact attachment shoulder while
/// the belly grows, then retires only after the body has swallowed it. The two
/// native surfaces always overlap; there is no detached cap or explicit tail.
private func contextMenuOpeningSingleMassMorphSample(
    source: CGRect,
    target: CGRect,
    outerFrame: CGRect,
    outerCornerRadii: ContextMenuBloomCornerRadii,
    sourceRadius: CGFloat,
    anchor: ContextMenuBloomAnchor,
    rawProgress: CGFloat
) -> ContextMenuGlassmorphicGeometrySample {
    let raw = max(0.0, min(1.0, rawProgress))
    let liquidT = contextMenuOpeningLiquidProgress(raw)
    let unit = CGPoint(
        x: max(0.0, min(1.0, anchor.unitPoint.x)),
        y: max(0.0, min(1.0, anchor.unitPoint.y))
    )
    let sourceCenter = CGPoint(x: source.midX, y: source.midY)
    let sourceMinSide = max(1.0, min(source.width, source.height))

    let horizontalExitSign: CGFloat = unit.x >= 0.75 ? -1.0 : (unit.x <= 0.25 ? 1.0 : 0.0)
    let verticalExitSign: CGFloat = unit.y <= 0.25 ? 1.0 : (unit.y >= 0.75 ? -1.0 : 0.0)
    var semanticExit = CGPoint(
        x: horizontalExitSign * (verticalExitSign == 0.0 ? 1.0 : 0.22),
        y: verticalExitSign
    )
    let semanticLength = hypot(semanticExit.x, semanticExit.y)
    if semanticLength > 0.001 {
        semanticExit.x /= semanticLength
        semanticExit.y /= semanticLength
    }

    let targetCenter = CGPoint(x: target.midX, y: target.midY)
    var destinationFlow = CGPoint(
        x: targetCenter.x - sourceCenter.x,
        y: targetCenter.y - sourceCenter.y
    )
    let destinationLength = hypot(destinationFlow.x, destinationFlow.y)
    if destinationLength > 0.001 {
        destinationFlow.x /= destinationLength
        destinationFlow.y /= destinationLength
    } else {
        destinationFlow = semanticExit
    }

    func point(from origin: CGPoint, direction: CGPoint, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + direction.x * distance,
            y: origin.y + direction.y * distance
        )
    }

    func quadratic(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        let t = max(0.0, min(1.0, progress))
        let inverse = 1.0 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2.0 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2.0 * inverse * t * control.y + t * t * end.y
        )
    }

    func shiftedInside(_ frame: CGRect, bounds: CGRect) -> CGRect {
        var result = frame
        if result.width <= bounds.width {
            result.origin.x = max(bounds.minX, min(bounds.maxX - result.width, result.minX))
        }
        if result.height <= bounds.height {
            result.origin.y = max(bounds.minY, min(bounds.maxY - result.height, result.minY))
        }
        return result
    }

    func scalar(_ lhs: CGFloat, _ rhs: CGFloat, progress: CGFloat) -> CGFloat {
        lhs + (rhs - lhs) * progress
    }

    // 17 ms impulse -> 33 ms egg.  The seed keeps its area while deforming;
    // the following growth belongs to this same silhouette, not a second cap.
    let eggIn = contextMenuBloomSmoothRange(liquidT, start: 0.025, end: 0.075)
    let eggOut = 1.0 - contextMenuBloomSmoothRange(liquidT, start: 0.13, end: 0.23)
    let egg = eggIn * eggOut
    let seedTravelT = contextMenuBloomSample(
        times: [0.025, 0.065, 0.11, 0.17],
        values: [0.0, 0.30, 0.76, 1.0],
        at: liquidT
    )
    let seedPathControl = point(
        from: sourceCenter,
        direction: semanticExit,
        distance: sourceMinSide * 0.28
    )
    let seedPathEnd = point(
        from: sourceCenter,
        direction: destinationFlow,
        distance: sourceMinSide * 0.38
    )
    var seedCenter = quadratic(
        from: sourceCenter,
        control: seedPathControl,
        to: seedPathEnd,
        progress: seedTravelT
    )
    var seedFlow = CGPoint(
        x: semanticExit.x + (destinationFlow.x - semanticExit.x) * seedTravelT,
        y: semanticExit.y + (destinationFlow.y - semanticExit.y) * seedTravelT
    )
    let seedFlowLength = hypot(seedFlow.x, seedFlow.y)
    if seedFlowLength > 0.001 {
        seedFlow.x /= seedFlowLength
        seedFlow.y /= seedFlowLength
    } else {
        seedFlow = semanticExit
    }

    // The reference seed is an egg, not a long capsule. A real rotation now
    // supplies the diagonal pull, so it no longer needs exaggerated axial
    // stretch to imply direction.
    let majorScale = 1.0 + 0.40 * egg
    let minorScale = 1.0 / majorScale
    // Keep the seed's real principal axes and rotate the surface itself.
    // Converting an oriented ellipse into an axis-aligned bounding box made
    // the centre follow a curve while the glass still read as a flat vertical
    // scale. The area remains constant because major * minor == 1.
    let seedWidth = max(1.0, source.width * minorScale)
    let seedHeight = max(1.0, source.height * majorScale)
    let seedFlowAngle = atan2(seedFlow.y, seedFlow.x)
    let seedAxisRotation = seedFlowAngle - .pi * 0.5
    let headRotation = seedAxisRotation * egg
    var seedFrame = CGRect(
        x: seedCenter.x - seedWidth * 0.5,
        y: seedCenter.y - seedHeight * 0.5,
        width: seedWidth,
        height: seedHeight
    )
    let motionBounds = source.union(target).union(outerFrame)
    seedFrame = shiftedInside(seedFrame, bounds: motionBounds)
    seedCenter = CGPoint(x: seedFrame.midX, y: seedFrame.midY)
    let seedRadius = min(sourceRadius, min(seedFrame.width, seedFrame.height) * 0.5)

    // The carrier first follows the moving egg, then accelerates into the
    // measured top-trailing-pinned outer frame.  Because the seed itself is
    // already down-leading, this interpolation is a curved pull rather than
    // a stationary scale from the button corner.
    // The body is still practically coincident with the egg when it becomes
    // visible. Its wider velocity window lets the belly grow over several
    // 120 Hz frames while the seed remains embedded as the attachment shoulder.
    let carrierT = contextMenuBloomSmoothRange(liquidT, start: 0.09, end: 0.22)
    var bodyFrame = CGRect(
        x: scalar(seedFrame.minX, outerFrame.minX, progress: carrierT),
        y: scalar(seedFrame.minY, outerFrame.minY, progress: carrierT),
        width: scalar(seedFrame.width, outerFrame.width, progress: carrierT),
        height: scalar(seedFrame.height, outerFrame.height, progress: carrierT)
    )

    // Menus with only a few rows can have an almost square destination.  If
    // their target aspect is inherited immediately, the drop skips the
    // reference's height-first pear and reads as a rounded-square scale. Keep
    // the same area/energy during the liquid phase but redistribute it along
    // the flow axis; release that constraint as the platter starts settling.
    let pearIn = contextMenuBloomSmoothRange(liquidT, start: 0.105, end: 0.19)
    let pearOut = 1.0 - contextMenuBloomSmoothRange(liquidT, start: 0.22, end: 0.44)
    let pearShape = pearIn * pearOut
    let currentAspect = bodyFrame.width / max(1.0, bodyFrame.height)
    let liquidAspect = min(currentAspect, 0.78)
    let bodyArea = max(1.0, bodyFrame.width * bodyFrame.height)
    let pearWidth = sqrt(bodyArea * liquidAspect)
    let pearHeight = bodyArea / pearWidth
    let bodyCenterBeforePear = CGPoint(x: bodyFrame.midX, y: bodyFrame.midY)
    let resolvedBodyWidth = scalar(bodyFrame.width, pearWidth, progress: pearShape)
    let resolvedBodyHeight = scalar(bodyFrame.height, pearHeight, progress: pearShape)
    bodyFrame = CGRect(
        x: bodyCenterBeforePear.x - resolvedBodyWidth * 0.5,
        y: bodyCenterBeforePear.y - resolvedBodyHeight * 0.5,
        width: resolvedBodyWidth,
        height: resolvedBodyHeight
    )

    // The reference drop does not grow in place at the source corner.  Its
    // whole mass first falls down-leading, then the destination pulls it back
    // into the final platter.  This transient translation is deliberately a
    // bell rather than an offset baked into the endpoint, so the measured
    // menu frame remains exact after the liquid phase.
    // Let the carrier gain volume before its lower edge starts falling.  Keeping
    // this slightly behind the size handoff removes the single-frame vertical
    // snap while preserving the compact, bottom-pulled seed.
    let fallIn = contextMenuBloomSmoothRange(liquidT, start: 0.105, end: 0.235)
    let fallOut = 1.0 - contextMenuBloomSmoothRange(liquidT, start: 0.32, end: 0.60)
    let fall = fallIn * fallOut
    let turnT = contextMenuBloomSmoothRange(liquidT, start: 0.105, end: 0.22)
    var carrierFlow = CGPoint(
        x: semanticExit.x + (destinationFlow.x - semanticExit.x) * turnT,
        y: semanticExit.y + (destinationFlow.y - semanticExit.y) * turnT
    )
    let carrierFlowLength = hypot(carrierFlow.x, carrierFlow.y)
    if carrierFlowLength > 0.001 {
        carrierFlow.x /= carrierFlowLength
        carrierFlow.y /= carrierFlowLength
    } else {
        carrierFlow = semanticExit
    }
    let fallDistance = sourceMinSide * 0.76 * fall
    bodyFrame = bodyFrame.offsetBy(
        dx: carrierFlow.x * fallDistance,
        dy: carrierFlow.y * fallDistance
    )
    bodyFrame = shiftedInside(bodyFrame, bounds: motionBounds)
    let bodyCenter = CGPoint(x: bodyFrame.midX, y: bodyFrame.midY)
    // The destination surface inherits the seed's angle during ownership,
    // then straightens only after its belly has begun to gain volume. This
    // makes the handoff one continuous curved mass instead of a rotated tail
    // being replaced by an axis-aligned rounded rectangle.
    // Only the compact shoulder carries the physical tilt. Once the belly
    // becomes broad, rotating its whole rectangular backing would enlarge
    // the visual bbox and read as a card swinging in. Straighten during the
    // seed-to-pear handoff; the asymmetric radii keep the curved pull alive.
    let bodyStraightenT = contextMenuBloomSmoothRange(liquidT, start: 0.105, end: 0.18)
    let bodyRotation = seedAxisRotation * (1.0 - bodyStraightenT)

    // Three free corners remain fully inflated during the pear phase.  Only
    // the top-trailing attachment tightens toward the destination radius,
    // preserving a compact shoulder while the belly grows down-leading.
    let birthRadius = min(bodyFrame.width, bodyFrame.height) * 0.5
    let shoulderT = contextMenuBloomSmoothRange(liquidT, start: 0.105, end: 0.20)
    let cornerSettleT = contextMenuBloomSmoothRange(liquidT, start: 0.24, end: 0.58)
    func freeRadius(_ targetRadius: CGFloat) -> CGFloat {
        birthRadius + (targetRadius - birthRadius) * cornerSettleT
    }
    func attachedRadius(_ targetRadius: CGFloat) -> CGFloat {
        // The attachment is compact, but it remains a rounded shoulder of
        // the same drop. Letting it collapse straight to the final 27 pt
        // corner while the belly is still circular creates a square notch.
        let compactRadius = min(
            birthRadius,
            max(targetRadius * 0.58, birthRadius * 0.28)
        )
        let pearRadius = birthRadius + (compactRadius - birthRadius) * shoulderT
        return pearRadius + (targetRadius - pearRadius) * cornerSettleT
    }
    var bodyCornerRadii = ContextMenuBloomCornerRadii(
        topLeft: freeRadius(outerCornerRadii.topLeft),
        topRight: freeRadius(outerCornerRadii.topRight),
        bottomLeft: freeRadius(outerCornerRadii.bottomLeft),
        bottomRight: freeRadius(outerCornerRadii.bottomRight)
    )
    if unit.x >= 0.75, unit.y <= 0.25 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: attachedRadius(outerCornerRadii.topRight),
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: bodyCornerRadii.bottomRight
        )
    } else if unit.x <= 0.25, unit.y <= 0.25 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: attachedRadius(outerCornerRadii.topLeft),
            topRight: bodyCornerRadii.topRight,
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: bodyCornerRadii.bottomRight
        )
    } else if unit.x >= 0.75, unit.y >= 0.75 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: bodyCornerRadii.topRight,
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: attachedRadius(outerCornerRadii.bottomRight)
        )
    } else if unit.x <= 0.25, unit.y >= 0.75 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: bodyCornerRadii.topRight,
            bottomLeft: attachedRadius(outerCornerRadii.bottomLeft),
            bottomRight: bodyCornerRadii.bottomRight
        )
    }

    // Native glass lobes are opaque whenever registered. The body becomes
    // available while coincident with the seed, but the seed stays registered
    // as an embedded shoulder until the growing belly fully contains it. This
    // gives the container effect overlapping fields to flow together without
    // ever manufacturing a detached bridge.
    let bodyOwnershipT = contextMenuBloomSmoothRange(liquidT, start: 0.062, end: 0.105)
    let headRetirementT = contextMenuBloomSmoothRange(liquidT, start: 0.16, end: 0.245)
    let transportCenter = CGPoint(
        x: (seedCenter.x + bodyCenter.x) * 0.5,
        y: (seedCenter.y + bodyCenter.y) * 0.5
    )
    return ContextMenuGlassmorphicGeometrySample(
        headFrame: seedFrame,
        bodyFrame: bodyFrame,
        headRotation: headRotation,
        bodyRotation: bodyRotation,
        headRadius: seedRadius,
        bodyCornerRadii: bodyCornerRadii,
        bridgeStart: transportCenter,
        bridgeEnd: transportCenter,
        bridgeRadius: 0.0,
        neckBulbCenter: transportCenter,
        neckBulbRadius: 0.0,
        headAlpha: 1.0 - headRetirementT,
        bodyAlpha: bodyOwnershipT
    )
}

/// Resolves the direction-specific topology inside the gross bloom bounds.
/// Opening becomes one connected seed/shoulder/carrier mass with guaranteed
/// overlap; closing retains the source/body/neck composition used by its
/// return flow.
func contextMenuGlassmorphicGeometrySample(
    source: CGRect,
    target: CGRect,
    outerFrame: CGRect,
    outerCornerRadii: ContextMenuBloomCornerRadii,
    sourceRadius: CGFloat,
    targetRadius: CGFloat,
    anchor: ContextMenuBloomAnchor,
    direction: ContextMenuBloomDirection,
    rawProgress: CGFloat,
    reduceMotion: Bool
) -> ContextMenuGlassmorphicGeometrySample {
    let raw = max(0.0, min(1.0, rawProgress))
    let unit = CGPoint(
        x: max(0.0, min(1.0, anchor.unitPoint.x)),
        y: max(0.0, min(1.0, anchor.unitPoint.y))
    )
    let sourceCenter = CGPoint(x: source.midX, y: source.midY)

    if raw <= 0.0 {
        return ContextMenuGlassmorphicGeometrySample(
            headFrame: source,
            bodyFrame: source,
            headRotation: 0.0,
            bodyRotation: 0.0,
            headRadius: sourceRadius,
            bodyCornerRadii: .uniform(sourceRadius),
            bridgeStart: sourceCenter,
            bridgeEnd: sourceCenter,
            bridgeRadius: 0.0,
            neckBulbCenter: sourceCenter,
            neckBulbRadius: 0.0,
            headAlpha: 1.0,
            bodyAlpha: 0.0
        )
    }
    if raw >= 1.0 {
        return ContextMenuGlassmorphicGeometrySample(
            headFrame: CGRect(
                x: sourceCenter.x - 0.5,
                y: sourceCenter.y - 0.5,
                width: 1.0,
                height: 1.0
            ),
            bodyFrame: target,
            headRotation: 0.0,
            bodyRotation: 0.0,
            headRadius: 0.5,
            bodyCornerRadii: .uniform(targetRadius),
            bridgeStart: sourceCenter,
            bridgeEnd: sourceCenter,
            bridgeRadius: 0.0,
            neckBulbCenter: sourceCenter,
            neckBulbRadius: 0.0,
            headAlpha: 0.0,
            bodyAlpha: 1.0
        )
    }

    if reduceMotion {
        let headFade = 1.0 - contextMenuBloomSmootherstep(raw)
        return ContextMenuGlassmorphicGeometrySample(
            headFrame: source,
            bodyFrame: outerFrame,
            headRotation: 0.0,
            bodyRotation: 0.0,
            headRadius: sourceRadius,
            bodyCornerRadii: outerCornerRadii,
            bridgeStart: sourceCenter,
            bridgeEnd: sourceCenter,
            bridgeRadius: 0.0,
            neckBulbCenter: sourceCenter,
            neckBulbRadius: 0.0,
            headAlpha: headFade,
            bodyAlpha: 1.0 - headFade
        )
    }

    if direction == .opening {
        return contextMenuOpeningSingleMassMorphSample(
            source: source,
            target: target,
            outerFrame: outerFrame,
            outerCornerRadii: outerCornerRadii,
            sourceRadius: sourceRadius,
            anchor: anchor,
            rawProgress: raw
        )
    }

    let phase: CGFloat
    let surfaceTensionStrength: CGFloat
    let headDeformationStrength: CGFloat
    let horizontalTension: CGFloat
    let verticalTension: CGFloat
    let headScale: CGFloat
    let headAlpha: CGFloat
    let bodyAlpha: CGFloat
    let bridgeVisibility: CGFloat
    let menuAmount: CGFloat

    switch direction {
    case .opening:
        // Open has only one or two strongly separated frames in Messages:
        // egg -> teardrop -> platter. The source head is swallowed quickly.
        phase = contextMenuBloomNormalize(raw, start: 0.32, end: 0.91)
        horizontalTension = contextMenuBloomSmoothRange(phase, start: 0.10, end: 0.30)
            * (1.0 - contextMenuBloomSmoothRange(phase, start: 0.36, end: 0.70))
        verticalTension = contextMenuBloomSmoothRange(phase, start: 0.00, end: 0.20)
            * (1.0 - contextMenuBloomSmoothRange(phase, start: 0.48, end: 0.82))
        surfaceTensionStrength = max(horizontalTension, verticalTension)
        // The button yields before the platter begins its gross size change.
        // This produces the reference's circle -> vertical egg -> descending
        // drop sequence instead of holding a static circle for 130 ms and
        // then scaling a menu out of it.
        let earlySeedYield = contextMenuBloomSmoothRange(raw, start: 0.08, end: 0.22)
            * (1.0 - contextMenuBloomSmoothRange(raw, start: 0.42, end: 0.60))
        headDeformationStrength = max(surfaceTensionStrength, earlySeedYield)
        // Preserve a substantial source lobe while the waist is thick, then
        // swallow both together. Letting the head become tiny while a long
        // bridge remained produced the non-native antenna frame.
        headScale = 1.0 - 0.985 * contextMenuBloomSmoothRange(phase, start: 0.24, end: 0.40)
        headAlpha = 1.0 - contextMenuBloomSmoothRange(phase, start: 0.30, end: 0.40)
        bodyAlpha = contextMenuBloomSmoothRange(phase, start: 0.01, end: 0.20)
        bridgeVisibility = contextMenuBloomSmoothRange(phase, start: 0.06, end: 0.20)
            * (1.0 - contextMenuBloomSmoothRange(phase, start: 0.24, end: 0.38))
        menuAmount = phase

    case .closing:
        // Close exposes the construction much longer: the 45 pt source head
        // separates while the lower lobe is still roughly 120 x 186 pt, then
        // remains connected through a 24-30 pt waist almost to the endpoint.
        phase = contextMenuBloomNormalize(1.0 - raw, start: 0.20, end: 0.96)
        let collapsed = contextMenuBloomSmoothRange(phase, start: 0.86, end: 1.0)
        horizontalTension = contextMenuBloomSmoothRange(phase, start: 0.46, end: 0.66)
            * (1.0 - collapsed)
        verticalTension = contextMenuBloomSmoothRange(phase, start: 0.36, end: 0.56)
            * (1.0 - collapsed)
        surfaceTensionStrength = max(horizontalTension, verticalTension)
        headDeformationStrength = surfaceTensionStrength
        headScale = 0.015 + 0.985 * contextMenuBloomSmoothRange(phase, start: 0.40, end: 0.74)
        headAlpha = contextMenuBloomSmoothRange(phase, start: 0.40, end: 0.64)
        bodyAlpha = 1.0 - contextMenuBloomSmoothRange(phase, start: 0.86, end: 1.0)
        bridgeVisibility = contextMenuBloomSmoothRange(phase, start: 0.38, end: 0.60)
            * (1.0 - contextMenuBloomSmoothRange(phase, start: 0.86, end: 1.0))
        menuAmount = 1.0 - phase
    }

    // Keep the destination lobe close enough to the source that the native
    // compositor reads the intermediate state as one pear-shaped drop, not
    // a ball hanging from a long straight antenna.
    let maximumInsetX: CGFloat
    let maximumInsetY: CGFloat
    switch direction {
    case .opening:
        maximumInsetX = min(7.0, max(0.0, outerFrame.width * 0.09))
        maximumInsetY = min(16.0, max(0.0, outerFrame.height * 0.15))
    case .closing:
        maximumInsetX = min(10.0, max(0.0, outerFrame.width * 0.12))
        maximumInsetY = min(22.0, max(0.0, outerFrame.height * 0.22))
    }
    let insetX = maximumInsetX * horizontalTension
    let insetY = maximumInsetY * verticalTension

    var bodyFrame = outerFrame
    if unit.x >= 0.75 {
        bodyFrame.size.width = max(1.0, bodyFrame.width - insetX)
    } else if unit.x <= 0.25 {
        bodyFrame.origin.x += insetX
        bodyFrame.size.width = max(1.0, bodyFrame.width - insetX)
    } else {
        bodyFrame.origin.x += insetX * 0.5
        bodyFrame.size.width = max(1.0, bodyFrame.width - insetX)
    }
    if unit.y <= 0.25 {
        bodyFrame.origin.y += insetY
        bodyFrame.size.height = max(1.0, bodyFrame.height - insetY)
    } else if unit.y >= 0.75 {
        bodyFrame.size.height = max(1.0, bodyFrame.height - insetY)
    } else {
        bodyFrame.origin.y += insetY * 0.5
        bodyFrame.size.height = max(1.0, bodyFrame.height - insetY)
    }

    // Register/unregistering an alpha-animated UIGlassEffect in the middle of
    // a merge can flash. Grow/collapse the destination material geometrically
    // instead, keeping every active effect fully opaque to the compositor.
    let bodyAnchor = CGPoint(
        x: bodyFrame.minX + bodyFrame.width * unit.x,
        y: bodyFrame.minY + bodyFrame.height * unit.y
    )
    let bodyWidth = max(1.0, bodyFrame.width * bodyAlpha)
    let bodyHeight = max(1.0, bodyFrame.height * bodyAlpha)
    bodyFrame = CGRect(
        x: bodyAnchor.x - bodyWidth * unit.x,
        y: bodyAnchor.y - bodyHeight * unit.y,
        width: bodyWidth,
        height: bodyHeight
    )
    if direction == .closing {
        let tallness = contextMenuClosingTallness(target: target)
        if tallness > 0 {
            let tall = contextMenuTallClosingSample(elapsed: 1.0 - raw)
            let width = max(1.0, (source.width + (target.width - source.width) * tall.bodyWidthT) * bodyAlpha)
            let height = max(1.0, (source.height + (target.height - source.height) * tall.bodyHeightT) * bodyAlpha)
            let topOffset = target.height * tall.topOffset
            let tallFrame = CGRect(
                x: outerFrame.minX + outerFrame.width * unit.x - width * unit.x,
                y: unit.y <= 0.25 ? outerFrame.minY + topOffset
                    : (unit.y >= 0.75 ? outerFrame.maxY - topOffset - height : outerFrame.midY - height * 0.5),
                width: width, height: height
            )
            bodyFrame = CGRect(
                x: bodyFrame.minX + (tallFrame.minX - bodyFrame.minX) * tallness,
                y: bodyFrame.minY + (tallFrame.minY - bodyFrame.minY) * tallness,
                width: bodyFrame.width + (tallFrame.width - bodyFrame.width) * tallness,
                height: bodyFrame.height + (tallFrame.height - bodyFrame.height) * tallness
            )
        }
    }

    var headWidth = max(1.0, source.width * headScale)
    var headHeight = max(1.0, source.height * headScale)
    let sourceAnchor = CGPoint(
        x: source.minX + source.width * unit.x,
        y: source.minY + source.height * unit.y
    )
    var headFrame = CGRect(
        x: sourceAnchor.x - headWidth * unit.x,
        y: sourceAnchor.y - headHeight * unit.y,
        width: headWidth,
        height: headHeight
    )
    var headCenter = CGPoint(x: headFrame.midX, y: headFrame.midY)

    let capsuleRadius = min(bodyFrame.width, bodyFrame.height) * 0.5
    let radiusSettle = contextMenuBloomSmoothRange(menuAmount, start: 0.60, end: 0.94)
    let liquidRadius = capsuleRadius + (targetRadius - capsuleRadius) * radiusSettle
    let liquidRadii = ContextMenuBloomCornerRadii.uniform(max(targetRadius, liquidRadius))
    var bodyCornerRadii = ContextMenuBloomCornerRadii(
        topLeft: liquidRadii.topLeft + (outerCornerRadii.topLeft - liquidRadii.topLeft) * radiusSettle,
        topRight: liquidRadii.topRight + (outerCornerRadii.topRight - liquidRadii.topRight) * radiusSettle,
        bottomLeft: liquidRadii.bottomLeft + (outerCornerRadii.bottomLeft - liquidRadii.bottomLeft) * radiusSettle,
        bottomRight: liquidRadii.bottomRight + (outerCornerRadii.bottomRight - liquidRadii.bottomRight) * radiusSettle
    )
    // The corner attached to the source never becomes a free capsule corner.
    // Keeping it button-sized lets the growing body physically overlap the
    // descending seed. A uniform early radius retracts the body boundary and
    // leaves a long, antenna-like connector between two otherwise separate
    // blobs.
    if unit.x >= 0.75, unit.y <= 0.25 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: outerCornerRadii.topRight,
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: bodyCornerRadii.bottomRight
        )
    } else if unit.x <= 0.25, unit.y <= 0.25 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: outerCornerRadii.topLeft,
            topRight: bodyCornerRadii.topRight,
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: bodyCornerRadii.bottomRight
        )
    } else if unit.x >= 0.75, unit.y >= 0.75 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: bodyCornerRadii.topRight,
            bottomLeft: bodyCornerRadii.bottomLeft,
            bottomRight: outerCornerRadii.bottomRight
        )
    } else if unit.x <= 0.25, unit.y >= 0.75 {
        bodyCornerRadii = ContextMenuBloomCornerRadii(
            topLeft: bodyCornerRadii.topLeft,
            topRight: bodyCornerRadii.topRight,
            bottomLeft: outerCornerRadii.bottomLeft,
            bottomRight: bodyCornerRadii.bottomRight
        )
    }

    let attachedCorner = CGPoint(
        x: unit.x >= 0.75 ? bodyFrame.maxX : (unit.x <= 0.25 ? bodyFrame.minX : bodyFrame.midX),
        y: unit.y <= 0.25 ? bodyFrame.minY : (unit.y >= 0.75 ? bodyFrame.maxY : bodyFrame.midY)
    )
    let bodyCenter = CGPoint(x: bodyFrame.midX, y: bodyFrame.midY)
    let contactDepth: CGFloat
    switch direction {
    case .opening:
        // At birth the body pulls from well inside the future platter, then
        // the attachment rolls back toward its corner. That moving target is
        // the broad arc of the drop; a fixed 30% contact reads as a straight
        // scale from the source into the menu.
        contactDepth = 0.78
            + (0.30 - 0.78) * contextMenuBloomSmoothRange(
                phase,
                start: 0.10,
                end: 0.34
            )
    case .closing:
        let compactBody = 1.0 - contextMenuBloomSmoothRange(
            bodyFrame.width / max(1.0, source.width), start: 0.9, end: 2.2
        )
        contactDepth = 0.30
            + (0.78 - 0.30) * max(
                compactBody,
                contextMenuBloomSmoothRange(phase, start: 0.66, end: 0.90)
            )
    }
    var bodyContact = CGPoint(
        x: attachedCorner.x + (bodyCenter.x - attachedCorner.x) * contactDepth,
        y: attachedCorner.y + (bodyCenter.y - attachedCorner.y) * contactDepth
    )

    let flowDX = bodyContact.x - headCenter.x
    let flowDY = bodyContact.y - headCenter.y
    let flowDistance = hypot(flowDX, flowDY)
    let resolvedFlowX = flowDistance > 0.001 ? flowDX / flowDistance : 0.0
    let resolvedFlowY = flowDistance > 0.001 ? flowDY / flowDistance : 1.0

    // A corner-attached menu has a semantic exit independent of the tiny,
    // rapidly changing destination frame. For a top-trailing source this is
    // deliberately down and slightly leading: (-0.22, +1). Using the raw
    // source->body vector here was the reason the first visible tail could
    // sprout from the top of the button.
    let horizontalExitSign: CGFloat = unit.x >= 0.75 ? -1.0 : (unit.x <= 0.25 ? 1.0 : 0.0)
    let verticalExitSign: CGFloat = unit.y <= 0.25 ? 1.0 : (unit.y >= 0.75 ? -1.0 : 0.0)
    var semanticExit = CGPoint(
        x: horizontalExitSign * (verticalExitSign == 0.0 ? 1.0 : 0.22),
        y: verticalExitSign
    )
    let semanticLength = hypot(semanticExit.x, semanticExit.y)
    if semanticLength > 0.001 {
        semanticExit.x /= semanticLength
        semanticExit.y /= semanticLength
    } else {
        semanticExit = CGPoint(x: resolvedFlowX, y: resolvedFlowY)
    }

    // The source first yields in the semantic exit direction, then turns
    // toward the body. Closing performs the same turn in reverse.
    let headTurn: CGFloat
    switch direction {
    case .opening:
        headTurn = contextMenuBloomSmoothRange(phase, start: 0.12, end: 0.36)
    case .closing:
        headTurn = 1.0 - contextMenuBloomSmoothRange(phase, start: 0.64, end: 0.88)
    }
    var headFlowX = semanticExit.x + (resolvedFlowX - semanticExit.x) * headTurn
    var headFlowY = semanticExit.y + (resolvedFlowY - semanticExit.y) * headTurn
    let headFlowLength = hypot(headFlowX, headFlowY)
    if headFlowLength > 0.001 {
        headFlowX /= headFlowLength
        headFlowY /= headFlowLength
    } else {
        headFlowX = semanticExit.x
        headFlowY = semanticExit.y
    }
    // The seed stretches along the flow before it is absorbed. This brief
    // anisotropy is the small elastic impulse that makes the glass feel like
    // one moving mass rather than two cross-fading rounded rectangles.
    let majorScale: CGFloat = 1.36
    let minorScale: CGFloat = 0.76
    let projectedScaleX = hypot(majorScale * headFlowX, minorScale * headFlowY)
    let projectedScaleY = hypot(majorScale * headFlowY, minorScale * headFlowX)
    headWidth *= 1.0 + (projectedScaleX - 1.0) * headDeformationStrength
    headHeight *= 1.0 + (projectedScaleY - 1.0) * headDeformationStrength
    let headTravel = (direction == .opening ? 12.0 : 8.0) * headDeformationStrength
    headCenter = CGPoint(
        x: headCenter.x + headFlowX * headTravel,
        y: headCenter.y + headFlowY * headTravel
    )
    let headMotionBounds = source.union(target)
    headWidth = min(headWidth, max(1.0, headMotionBounds.width))
    headHeight = min(headHeight, max(1.0, headMotionBounds.height))
    headFrame = CGRect(
        x: headCenter.x - headWidth * 0.5,
        y: headCenter.y - headHeight * 0.5,
        width: headWidth,
        height: headHeight
    )
    headFrame.origin.x = max(
        headMotionBounds.minX,
        min(headMotionBounds.maxX - headFrame.width, headFrame.minX)
    )
    headFrame.origin.y = max(
        headMotionBounds.minY,
        min(headMotionBounds.maxY - headFrame.height, headFrame.minY)
    )
    headCenter = CGPoint(x: headFrame.midX, y: headFrame.midY)

    // Keep the body-side endpoint genuinely below/inside the source before
    // bending it inward. The clamps matter while the destination lobe is
    // still only a few points tall.
    if unit.y <= 0.25 {
        bodyContact.y = min(
            bodyFrame.maxY,
            max(bodyFrame.minY, max(bodyContact.y, headFrame.maxY + 6.0))
        )
    } else if unit.y >= 0.75 {
        bodyContact.y = max(
            bodyFrame.minY,
            min(bodyFrame.maxY, min(bodyContact.y, headFrame.minY - 6.0))
        )
    }
    if unit.x >= 0.75 {
        bodyContact.x = max(
            bodyFrame.minX,
            min(bodyFrame.maxX, min(bodyContact.x, headCenter.x - 4.0))
        )
    } else if unit.x <= 0.25 {
        bodyContact.x = min(
            bodyFrame.maxX,
            max(bodyFrame.minX, max(bodyContact.x, headCenter.x + 4.0))
        )
    }

    let sourceMinSide = min(source.width, source.height)
    let fullNeckRadius: CGFloat
    switch direction {
    case .opening:
        fullNeckRadius = min(15.5, max(10.0, sourceMinSide * 0.34))
    case .closing:
        fullNeckRadius = min(14.0, max(9.0, sourceMinSide * 0.31))
    }
    let rawNeckRadius = fullNeckRadius * bridgeVisibility
    // The bridge and its body-side bulb enter as one continuous topology.
    // A bulb-only threshold frame reads as a bead popping into existence.
    let neckRadius = rawNeckRadius > 1.25 ? rawNeckRadius : 0.0
    let neckBulbRadius = neckRadius * (direction == .opening ? 1.16 : 1.24)
    let bridgeSafeRadius = max(neckRadius, neckBulbRadius)
    let bridgeSafeBounds = outerFrame.insetBy(dx: bridgeSafeRadius, dy: bridgeSafeRadius)
    func clampBridgePoint(_ point: CGPoint) -> CGPoint {
        guard bridgeSafeBounds.width >= 0.0, bridgeSafeBounds.height >= 0.0 else {
            return CGPoint(x: outerFrame.midX, y: outerFrame.midY)
        }
        return CGPoint(
            x: max(bridgeSafeBounds.minX, min(bridgeSafeBounds.maxX, point.x)),
            y: max(bridgeSafeBounds.minY, min(bridgeSafeBounds.maxY, point.y))
        )
    }

    // Start inside the source ellipse in the direction of travel. For the
    // common top-trailing button this is its lower-leading quadrant, so the
    // material is visibly pulled from the bottom instead of sprouting from
    // the top edge.
    let headRadiusX = max(0.5, headFrame.width * 0.5)
    let headRadiusY = max(0.5, headFrame.height * 0.5)
    let ellipseDenominator = hypot(semanticExit.x / headRadiusX, semanticExit.y / headRadiusY)
    let headEdgeDistance = ellipseDenominator > 0.001 ? 1.0 / ellipseDenominator : 0.0
    let overlapDistance = min(headEdgeDistance * 0.28, max(2.0, neckRadius * 0.36))
    let bridgeOriginDistance = max(0.0, headEdgeDistance - overlapDistance)
    let bridgeOrigin = clampBridgePoint(CGPoint(
        x: headCenter.x + semanticExit.x * bridgeOriginDistance,
        y: headCenter.y + semanticExit.y * bridgeOriginDistance
    ))
    bodyContact = clampBridgePoint(bodyContact)

    let bridgeDX = bodyContact.x - bridgeOrigin.x
    let bridgeDY = bodyContact.y - bridgeOrigin.y
    let bridgeDistance = hypot(bridgeDX, bridgeDY)
    let fallbackHorizontalSign: CGFloat = bridgeDX >= 0.0 ? 1.0 : -1.0
    let fallbackVerticalSign: CGFloat = bridgeDY >= 0.0 ? 1.0 : -1.0
    let controlHorizontalSign = horizontalExitSign == 0.0
        ? fallbackHorizontalSign
        : horizontalExitSign
    let controlVerticalSign = verticalExitSign == 0.0
        ? fallbackVerticalSign
        : verticalExitSign
    let bridgeControl: CGPoint
    if verticalExitSign != 0.0 {
        // First tangent: almost vertical and away from the source. The body
        // endpoint then pulls the second half inward, producing a readable
        // spatial curve instead of two collinear capsules.
        bridgeControl = clampBridgePoint(CGPoint(
            x: bridgeOrigin.x + controlHorizontalSign * min(bridgeDistance * 0.08, abs(bridgeDX) * 0.12),
            y: bridgeOrigin.y + controlVerticalSign * bridgeDistance * 0.62
        ))
    } else {
        bridgeControl = clampBridgePoint(CGPoint(
            x: bridgeOrigin.x + controlHorizontalSign * bridgeDistance * 0.62,
            y: bridgeOrigin.y + controlVerticalSign * min(bridgeDistance * 0.08, abs(bridgeDY) * 0.12)
        ))
    }

    func pointAlongCurvedBridge(_ amount: CGFloat) -> CGPoint {
        let t = max(0.0, min(1.0, amount))
        let inverse = 1.0 - t
        return CGPoint(
            x: inverse * inverse * bridgeOrigin.x
                + 2.0 * inverse * t * bridgeControl.x
                + t * t * bodyContact.x,
            y: inverse * inverse * bridgeOrigin.y
                + 2.0 * inverse * t * bridgeControl.y
                + t * t * bodyContact.y
        )
    }
    let bridgeKneeAmount: CGFloat = 0.46
    let neckBulbAmount: CGFloat = 0.96

    return ContextMenuGlassmorphicGeometrySample(
        headFrame: headFrame,
        bodyFrame: bodyFrame,
        headRotation: 0.0,
        bodyRotation: 0.0,
        headRadius: min(sourceRadius * headScale, min(headWidth, headHeight) * 0.5),
        bodyCornerRadii: bodyCornerRadii,
        bridgeStart: clampBridgePoint(bridgeOrigin),
        bridgeEnd: clampBridgePoint(pointAlongCurvedBridge(bridgeKneeAmount)),
        bridgeRadius: neckRadius,
        neckBulbCenter: clampBridgePoint(pointAlongCurvedBridge(neckBulbAmount)),
        neckBulbRadius: neckBulbRadius,
        headAlpha: headAlpha,
        bodyAlpha: bodyAlpha
    )
}

private func contextMenuGlassmorphicSilhouetteParts(
    sample: ContextMenuGlassmorphicGeometrySample
) -> [CGPath] {
    func rotationTransform(for frame: CGRect, angle: CGFloat) -> CGAffineTransform {
        guard abs(angle) > 0.0001 else { return .identity }
        return CGAffineTransform(translationX: frame.midX, y: frame.midY)
            .rotated(by: angle)
            .translatedBy(x: -frame.midX, y: -frame.midY)
    }

    var paths: [CGPath] = []
    func append(_ path: CGPath, transform: CGAffineTransform = .identity) {
        var transform = transform
        paths.append(path.copy(using: &transform) ?? path)
    }
    if sample.headAlpha > 0.001, sample.headFrame.width > 0.5, sample.headFrame.height > 0.5 {
        append(contextMenuBloomRoundedPath(
            in: sample.headFrame,
            radii: .uniform(sample.headRadius)
        ), transform: rotationTransform(for: sample.headFrame, angle: sample.headRotation))
    }
    if sample.bridgeRadius > 0.5 {
        let sourceSegment = CGMutablePath()
        sourceSegment.move(to: sample.bridgeStart)
        sourceSegment.addLine(to: sample.bridgeEnd)
        append(sourceSegment.copy(
            strokingWithWidth: sample.bridgeRadius * 2.0,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0.0
        ))
        if sample.neckBulbRadius > 0.5 {
            let continuation = CGMutablePath()
            continuation.move(to: sample.bridgeEnd)
            continuation.addLine(to: sample.neckBulbCenter)
            append(continuation.copy(
                strokingWithWidth: sample.neckBulbRadius * 2.0,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 0.0
            ))
        }
    }
    if sample.bodyAlpha > 0.001, sample.bodyFrame.width > 0.5, sample.bodyFrame.height > 0.5 {
        append(contextMenuBloomRoundedPath(
            in: sample.bodyFrame,
            radii: sample.bodyCornerRadii
        ), transform: rotationTransform(for: sample.bodyFrame, angle: sample.bodyRotation))
    }
    return paths
}

private func contextMenuGlassmorphicSilhouettePath(
    sample: ContextMenuGlassmorphicGeometrySample
) -> CGPath {
    let path = CGMutablePath()
    for part in contextMenuGlassmorphicSilhouetteParts(sample: sample) {
        path.addPath(part)
    }
    return path
}

struct ContextMenuBloomContentWeights: Equatable {
    let blurred: CGFloat
    let sharp: CGFloat
    let live: CGFloat
    let snapshotContainer: CGFloat
}

private func contextMenuBloomContentWeights(
    at progress: CGFloat,
    revealRange: ClosedRange<CGFloat>,
    sharpRange: ClosedRange<CGFloat>,
    liveRange: ClosedRange<CGFloat>
) -> ContextMenuBloomContentWeights {
    func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return value >= edge1 ? 1.0 : 0.0 }
        let t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    let reveal = smootherstep(revealRange.lowerBound, revealRange.upperBound, progress)
    let sharpMix = smootherstep(sharpRange.lowerBound, sharpRange.upperBound, progress)
    let liveMix = smootherstep(liveRange.lowerBound, liveRange.upperBound, progress)
    let snapshotGain = reveal * sqrt(max(0.0, 1.0 - liveMix))
    let liveGain = reveal * sqrt(max(0.0, liveMix))
    let blurred = snapshotGain * sqrt(max(0.0, 1.0 - sharpMix))
    let sharp = snapshotGain * sqrt(max(0.0, sharpMix))
    return ContextMenuBloomContentWeights(
        blurred: blurred,
        sharp: sharp,
        live: liveGain,
        snapshotContainer: snapshotGain
    )
}

/// Opening content is already present inside the growing drop. Equal-power
/// handoffs keep the blurred, sharp and live representations at constant
/// optical energy while the glass is still changing shape. The live view owns
/// the result by ~256 ms, before the animator completion can remove snapshots,
/// so there is no separate final-frame flash.
func contextMenuBloomContentWeights(at progress: CGFloat) -> ContextMenuBloomContentWeights {
    contextMenuBloomContentWeights(
        at: progress,
        revealRange: 0.22...0.58,
        sharpRange: 0.46...0.82,
        liveRange: 0.50...0.80
    )
}

/// Dismissal uses its own reveal curve and a size-aware clock; it is not a
/// mathematical reversal of opening.
func contextMenuBloomClosingContentWeights(at progress: CGFloat) -> ContextMenuBloomContentWeights {
    contextMenuBloomContentWeights(
        at: progress,
        revealRange: 0.16...0.48,
        sharpRange: 0.34...0.70,
        liveRange: 0.68...0.92
    )
}

private func contextMenuBloomRevealProgress(
    for weights: ContextMenuBloomContentWeights
) -> CGFloat {
    min(
        1.0,
        sqrt(
            weights.blurred * weights.blurred
                + weights.sharp * weights.sharp
                + weights.live * weights.live
        )
    )
}

func contextMenuBloomRevealProgress(at progress: CGFloat) -> CGFloat {
    contextMenuBloomRevealProgress(
        for: contextMenuBloomContentWeights(at: progress)
    )
}

final class ContextMenuGlassmorphicTransitionView: UIView {
    static var debugFrozenProgress: CGFloat? = {
        #if DEBUG
        guard
            let rawValue = ProcessInfo.processInfo.environment["AETHER_CONTEXT_MENU_FROZEN_PROGRESS"],
            let value = Double(rawValue)
        else {
            return nil
        }
        return CGFloat(max(0.0, min(1.0, value)))
        #else
        return nil
        #endif
    }()

    let finalMenuGlassSurfaceView: MenuGlassSurfaceView
    let sourceProxyContainer = UIView()
    let liveMenuContentView = UIView()

    var contentRevealProgressChanged: ((CGFloat) -> Void)?

    private let sourceFrameInOverlay: CGRect
    private let targetMenuFrameInOverlay: CGRect
    private let finalCornerRadius: CGFloat
    private let sourceCornerRadius: CGFloat
    private let sourceMode: ContextMenuSourceVisualMode
    private let isDark: Bool
    private let usesOpticalDistortion: Bool
    private let sourceContentCarrier = UIView()
    private let sourceContentMask = CALayer()
    private var sourceContentMaskParts: [CAShapeLayer] = []
    private var sourceMaterializationView: AetherMaterializationImageView?

    private let shadowView = UIView()
    private let ambientShadowLayer = CAShapeLayer()
    private let contactShadowLayer = CAShapeLayer()
    private let glassMorphContainer: GlassBackgroundContainerView
    private let sourceSeedGlassSurfaceView: MenuGlassSurfaceView
    private let bridgeGlassSurfaceView: MenuGlassSurfaceView
    private let bridgeContinuationGlassSurfaceView: MenuGlassSurfaceView
    private let snapshotContainer = UIView()
    private let blurredMenuSnapshotView = UIImageView()
    private let sharpMenuSnapshotView = UIImageView()
    private let highlightView = UIView()
    private let highlightLayer = CAGradientLayer()
    private let progressDriverView = UIView(frame: .zero)
    private var surfaceSDFFilter: AnyObject?
    private var contentSDFFilter: AnyObject?

    private var progress: CGFloat = 0
    private var progressAnimator: UIViewPropertyAnimator?
    private var progressDisplayLink: CADisplayLink?
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    private var animationDirection: CGFloat = 1
    private var animationCompletion: (() -> Void)?
    private var interruptedCollapse: InterruptedCollapse?
    private var lastAppliedProgress: CGFloat = 0
    private var displayedGlassmorphicSample: ContextMenuGlassmorphicGeometrySample?
    private var displayedContentReveal: CGFloat = 0
    private var displayedContentDistortion = OpticalDistortion.zero
    private var displayedSurfaceDistortion = OpticalDistortion.zero
    private var displayedGlassSpacing: CGFloat = 0

    init(
        sourceFrameInOverlay: CGRect,
        targetMenuFrameInOverlay: CGRect,
        finalCornerRadius: CGFloat,
        sourceCornerRadius: CGFloat,
        sourceMode: ContextMenuSourceVisualMode,
        isDark: Bool,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.sourceFrameInOverlay = sourceFrameInOverlay
        self.targetMenuFrameInOverlay = targetMenuFrameInOverlay
        self.finalCornerRadius = finalCornerRadius
        self.sourceCornerRadius = sourceCornerRadius
        self.sourceMode = sourceMode
        self.isDark = isDark
        self.usesOpticalDistortion = (appearanceStyle ?? AetherAppearance.runtimeCurrent.style).usesLiquidGlass
        self.glassMorphContainer = GlassBackgroundContainerView(
            spacing: 18.0,
            appearanceStyle: appearanceStyle
        )
        self.sourceSeedGlassSurfaceView = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: appearanceStyle
        )
        self.bridgeGlassSurfaceView = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: appearanceStyle
        )
        self.bridgeContinuationGlassSurfaceView = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: appearanceStyle
        )
        self.finalMenuGlassSurfaceView = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: appearanceStyle
        )

        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        progressDriverView.frame = CGRect(x: -4, y: -4, width: 1, height: 1)
        progressDriverView.backgroundColor = .clear
        progressDriverView.isUserInteractionEnabled = false
        addSubview(progressDriverView)

        shadowView.backgroundColor = .clear
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.masksToBounds = false
        addSubview(shadowView)
        configureShadowLayer(ambientShadowLayer)
        configureShadowLayer(contactShadowLayer)
        shadowView.layer.addSublayer(ambientShadowLayer)
        shadowView.layer.addSublayer(contactShadowLayer)

        glassMorphContainer.clipsToBounds = false
        glassMorphContainer.layer.masksToBounds = false
        addSubview(glassMorphContainer)

        sourceSeedGlassSurfaceView.isUserInteractionEnabled = false
        sourceSeedGlassSurfaceView.clipsToBounds = false
        sourceSeedGlassSurfaceView.layer.masksToBounds = false
        sourceSeedGlassSurfaceView.setSupplementalScatteringEnabled(false)
        glassMorphContainer.contentView.addSubview(sourceSeedGlassSurfaceView)

        bridgeGlassSurfaceView.isUserInteractionEnabled = false
        bridgeGlassSurfaceView.clipsToBounds = false
        bridgeGlassSurfaceView.layer.masksToBounds = false
        bridgeGlassSurfaceView.setSupplementalScatteringEnabled(false)
        glassMorphContainer.contentView.addSubview(bridgeGlassSurfaceView)

        bridgeContinuationGlassSurfaceView.isUserInteractionEnabled = false
        bridgeContinuationGlassSurfaceView.clipsToBounds = false
        bridgeContinuationGlassSurfaceView.layer.masksToBounds = false
        bridgeContinuationGlassSurfaceView.setSupplementalScatteringEnabled(false)
        glassMorphContainer.contentView.addSubview(bridgeContinuationGlassSurfaceView)

        finalMenuGlassSurfaceView.clipsToBounds = false
        finalMenuGlassSurfaceView.layer.masksToBounds = false
        glassMorphContainer.contentView.addSubview(finalMenuGlassSurfaceView)

        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = .clear
        highlightLayer.type = .radial
        highlightLayer.colors = [
            UIColor.white.withAlphaComponent(isDark ? 0.24 : 0.34).cgColor,
            UIColor.white.withAlphaComponent(isDark ? 0.08 : 0.14).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        highlightLayer.locations = [0.0, 0.38, 1.0]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        highlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        highlightView.layer.addSublayer(highlightLayer)
        finalMenuGlassSurfaceView.contentView.addSubview(highlightView)

        snapshotContainer.isUserInteractionEnabled = false
        snapshotContainer.clipsToBounds = false
        finalMenuGlassSurfaceView.contentView.addSubview(snapshotContainer)

        blurredMenuSnapshotView.contentMode = .scaleAspectFit
        blurredMenuSnapshotView.clipsToBounds = false
        blurredMenuSnapshotView.isUserInteractionEnabled = false
        snapshotContainer.addSubview(blurredMenuSnapshotView)

        sharpMenuSnapshotView.contentMode = .scaleAspectFit
        sharpMenuSnapshotView.clipsToBounds = false
        sharpMenuSnapshotView.isUserInteractionEnabled = false
        snapshotContainer.addSubview(sharpMenuSnapshotView)

        installContentDistortionFilterIfAvailable()
        installSurfaceDistortionFilterIfAvailable()

        // Selection is driven by the recognizer on MenuGlassSurfaceView.
        // Keep this wrapper passive so touches reach the glass material and
        // native UIGlassEffect.isInteractive can stretch the menu container.
        liveMenuContentView.isUserInteractionEnabled = false
        finalMenuGlassSurfaceView.contentView.addSubview(liveMenuContentView)

        sourceProxyContainer.isUserInteractionEnabled = false
        sourceProxyContainer.clipsToBounds = false
        // The source label returns on the upper rim of the collapsing body
        // before the source lobe grows back. Mask it by the complete surface,
        // not the tiny (initially 1pt) lobe that used to hide it until the end.
        sourceContentCarrier.isUserInteractionEnabled = false
        sourceContentCarrier.layer.mask = sourceContentMask
        addSubview(sourceContentCarrier)
        sourceContentCarrier.addSubview(sourceProxyContainer)

        setProgress(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
        sourceSeedGlassSurfaceView.tearDownGlassEffect()
        bridgeGlassSurfaceView.tearDownGlassEffect()
        bridgeContinuationGlassSurfaceView.tearDownGlassEffect()
        finalMenuGlassSurfaceView.tearDownGlassEffect()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassMorphContainer.frame = bounds
        glassMorphContainer.update(size: bounds.size, isDark: isDark, transition: .immediate)
        shadowView.frame = bounds
        updateGeometry(progress: progress)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if finalMenuGlassSurfaceView.isUserInteractionEnabled {
            return finalMenuGlassSurfaceView.frame.contains(point)
        }
        guard let displayedGlassmorphicSample else { return false }
        let path = contextMenuGlassmorphicSilhouettePath(sample: displayedGlassmorphicSample)
        if path.contains(point) { return true }
        // Native container spacing optically extends the merged neck beyond
        // the mathematical union. Swallow that transition-only halo so a
        // second tap cannot leak through to the dim view and dismiss the menu
        // while the platter is still opening.
        let halo = path.copy(
            strokingWithWidth: 28.0,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0.0
        )
        return halo.contains(point)
    }

    func tearDownGlassEffects() {
        cancelAnimation()
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
        surfaceSDFFilter = nil
        contentSDFFilter = nil
        sourceSeedGlassSurfaceView.tearDownGlassEffect()
        bridgeGlassSurfaceView.tearDownGlassEffect()
        bridgeContinuationGlassSurfaceView.tearDownGlassEffect()
        finalMenuGlassSurfaceView.tearDownGlassEffect()
    }

    func setProgress(_ progress: CGFloat, direction: ContextMenuBloomDirection = .opening) {
        cancelAnimation()
        interruptedCollapse = nil
        animationDirection = direction == .opening ? 1 : -1
        self.progress = max(0, min(1, progress))
        updateGeometry(progress: self.progress)
    }

    func animateExpand(duration: TimeInterval, damping: CGFloat, completion: (() -> Void)? = nil) {
        if let frozenProgress = Self.debugFrozenProgress {
            setProgress(frozenProgress)
            completion?()
            return
        }
        animateProgress(to: 1, duration: duration, dampingRatio: damping) { [weak self] in
            self?.finishToFinalMenu()
            completion?()
        }
    }

    func animateCollapse(duration: TimeInterval, damping: CGFloat, completion: (() -> Void)? = nil) {
        animateProgress(to: 0, duration: duration, dampingRatio: damping) { [weak self] in
            self?.cancelOrDismiss()
            completion?()
        }
    }

    func prepareMenuContentSnapshots(from view: UIView) {
        view.layoutIfNeeded()
        Self.ensureTextureContentIsDisplayed(in: view)
        let image = Self.renderImage(from: view)
        sharpMenuSnapshotView.image = image
        blurredMenuSnapshotView.image = Self.blurredImage(from: image, radius: 18.0) ?? image
        updateContentFrames(for: finalMenuGlassSurfaceView.bounds)
    }

    func prepareSourceContentSnapshots() {
        guard sourceMaterializationView == nil,
              !sourceProxyContainer.subviews.isEmpty,
              sourceProxyContainer.bounds.width > 0,
              sourceProxyContainer.bounds.height > 0 else { return }
        sourceProxyContainer.layoutIfNeeded()
        Self.ensureTextureContentIsDisplayed(in: sourceProxyContainer)
        let image = Self.renderImage(from: sourceProxyContainer)
        sourceProxyContainer.subviews.forEach { $0.isHidden = true }
        let content = AetherMaterializationImageView(image: image, maximumBlurRadius: 8.0)
        content.frame = sourceProxyContainer.bounds
        sourceProxyContainer.addSubview(content)
        sourceMaterializationView = content
        updateSourceProxy(rawT: progress)
    }

    func finishToFinalMenu() {
        cancelAnimation()
        interruptedCollapse = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress = 1
        let metrics = currentMetrics(rawT: 1)
        apply(metrics: metrics, rawT: 1)
        sourceProxyContainer.alpha = 0
        sourceProxyContainer.isHidden = true
        snapshotContainer.alpha = 0
        blurredMenuSnapshotView.alpha = 0
        sharpMenuSnapshotView.alpha = 0
        liveMenuContentView.alpha = 1
        updateSurfaceSDFDistortion(rawT: 1)
        updateContentSDFDistortion(rawT: 1, liveMix: 1)
        contentRevealProgressChanged?(1)
        CATransaction.commit()
    }

    func cancelOrDismiss() {
        cancelAnimation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress = 0
        let metrics = currentMetrics(rawT: 0)
        apply(metrics: metrics, rawT: 0)
        updateSurfaceSDFDistortion(rawT: 0)
        updateContentSDFDistortion(rawT: 0, liveMix: 0)
        contentRevealProgressChanged?(0)
        CATransaction.commit()
        interruptedCollapse = nil
    }

    private func updateGeometry(progress rawT: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(metrics: currentMetrics(rawT: rawT), rawT: rawT)
        CATransaction.commit()
    }

    private func applySurfaceGeometry(
        frame: CGRect,
        rotation: CGFloat,
        to view: UIView
    ) {
        // Assigning frame while a transform is active is undefined in UIKit.
        // Resolve the untransformed geometry through bounds/center, then apply
        // the measured flow angle around the surface's own centre.
        view.transform = .identity
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        view.transform = abs(rotation) > 0.0001
            ? CGAffineTransform(rotationAngle: rotation)
            : .identity
    }

    private func apply(metrics: Metrics, rawT: CGFloat) {
        lastAppliedProgress = rawT
        let glassSample = currentGlassmorphicSample(metrics: metrics, rawT: rawT)
        displayedGlassmorphicSample = glassSample

        let surfaceTension = max(0.0, min(1.0, glassSample.bridgeRadius / 15.0))
        var glassSpacing: CGFloat
        if animationDirection >= 0.0, interruptedCollapse == nil {
            // Opening uses overlapping seed/shoulder/carrier fields. A wide
            // compositor reach would manufacture a detached halo outside that
            // intentionally connected mass.
            glassSpacing = 0.0
        } else {
            // Closing intentionally keeps the longer measured neck.
            glassSpacing = 18.0 + 4.0 * surfaceTension
        }
        let interruptionBlend = interruptedCollapse.map {
            Self.smootherstep(0.0, 0.35, interruptedCollapseRunProgress(rawT: rawT, startProgress: $0.rawProgress))
        }
        if let state = interruptedCollapse, let interruptionBlend {
            glassSpacing = Self.lerp(state.glassSpacing, glassSpacing, interruptionBlend)
        }
        displayedGlassSpacing = glassSpacing
        glassMorphContainer.setSpacing(glassSpacing)

        if glassMorphContainer.isUsingNativeContainerEffect {
            applySurfaceGeometry(
                frame: glassSample.bodyFrame,
                rotation: glassSample.bodyRotation,
                to: finalMenuGlassSurfaceView
            )
            finalMenuGlassSurfaceView.setSurfaceCornerRadii(glassSample.bodyCornerRadii)
        } else {
            // Older systems do not have a compositor capable of merging
            // sibling glass fields. Preserve the established single-platter
            // fallback there while still staging the source head cleanly.
            applySurfaceGeometry(
                frame: metrics.frame,
                rotation: 0.0,
                to: finalMenuGlassSurfaceView
            )
            finalMenuGlassSurfaceView.setSurfaceCornerRadii(metrics.cornerRadii)
        }
        let usesOpaqueNativeLobes = glassMorphContainer.isUsingNativeContainerEffect
            && !UIAccessibility.isReduceMotionEnabled
        if usesOpaqueNativeLobes {
            finalMenuGlassSurfaceView.alpha = glassSample.bodyAlpha <= 0.001 ? 0.0 : 1.0
        } else {
            finalMenuGlassSurfaceView.alpha = glassSample.bodyAlpha
        }
        finalMenuGlassSurfaceView.isHidden = glassSample.bodyAlpha <= 0.001
        finalMenuGlassSurfaceView.isUserInteractionEnabled = rawT >= 0.999
            && animationDirection >= 0.0
            && interruptedCollapse == nil
        finalMenuGlassSurfaceView.updateMaterialThickness(materialProgress(rawT))

        applySurfaceGeometry(
            frame: glassSample.headFrame,
            rotation: glassSample.headRotation,
            to: sourceSeedGlassSurfaceView
        )
        sourceSeedGlassSurfaceView.setSurfaceCornerRadius(glassSample.headRadius)
        var renderedHeadAlpha: CGFloat
        if usesOpaqueNativeLobes {
            renderedHeadAlpha = glassSample.headAlpha <= 0.001 ? 0.0 : 1.0
        } else if animationDirection >= 0.0, !UIAccessibility.isReduceMotionEnabled {
            // Legacy glass cannot merge overlapping fields. Let its existing
            // single-platter fallback own the overlap instead of drawing two
            // translucent shells; native iOS 26 keeps the embedded shoulder.
            renderedHeadAlpha = glassSample.headAlpha * (1.0 - glassSample.bodyAlpha)
        } else {
            renderedHeadAlpha = glassSample.headAlpha
        }
        if let state = interruptedCollapse, let interruptionBlend {
            renderedHeadAlpha = Self.lerp(state.renderedHeadAlpha, renderedHeadAlpha, interruptionBlend)
        }
        sourceSeedGlassSurfaceView.alpha = renderedHeadAlpha
        sourceSeedGlassSurfaceView.isHidden = renderedHeadAlpha <= 0.001
        sourceSeedGlassSurfaceView.updateMaterialThickness(materialProgress(rawT))
        updateBridge(using: glassSample, rawT: rawT)

        ambientShadowLayer.frame = shadowView.bounds
        contactShadowLayer.frame = shadowView.bounds
        let shadowPath = glassMorphContainer.isUsingNativeContainerEffect
            ? contextMenuGlassmorphicSilhouettePath(sample: glassSample)
            : contextMenuBloomRoundedPath(in: metrics.frame, radii: metrics.cornerRadii)
        ambientShadowLayer.shadowPath = shadowPath
        contactShadowLayer.shadowPath = shadowPath
        updateShadow(rawT: rawT)

        sourceContentCarrier.frame = bounds
        sourceContentMask.frame = sourceContentCarrier.bounds
        let sourceMaskPaths = glassMorphContainer.isUsingNativeContainerEffect
            ? contextMenuGlassmorphicSilhouetteParts(sample: glassSample)
            : [shadowPath]
        updateSourceContentMask(paths: sourceMaskPaths)
        sourceProxyContainer.transform = .identity
        if animationDirection < 0 {
            if let state = interruptedCollapse {
                let t = contextMenuBloomSmootherstep(interruptedCollapseRunProgress(
                    rawT: rawT, startProgress: state.rawProgress
                ))
                sourceProxyContainer.frame = CGRect(
                    x: Self.lerp(state.sourceContentFrame.minX, startFrame.minX, t),
                    y: Self.lerp(state.sourceContentFrame.minY, startFrame.minY, t),
                    width: startFrame.width, height: startFrame.height
                )
            } else {
                let attached = contextMenuBloomAnchoredFrame(
                    contentSize: startFrame.size,
                    in: glassMorphContainer.isUsingNativeContainerEffect ? glassSample.bodyFrame : metrics.frame,
                    anchor: bloomAnchor
                )
                let t = Self.smootherstep(0.40, 0.78, 1.0 - rawT)
                sourceProxyContainer.frame = CGRect(
                    x: Self.lerp(attached.minX, startFrame.minX, t),
                    y: Self.lerp(attached.minY, startFrame.minY, t),
                    width: startFrame.width, height: startFrame.height
                )
            }
        } else {
            sourceProxyContainer.frame = contextMenuBloomAnchoredFrame(
                contentSize: startFrame.size, in: glassSample.headFrame, anchor: bloomAnchor
            )
        }
        for proxySubview in sourceProxyContainer.subviews {
            // The proxy is the source glyph/content, not another glass shell.
            // Keep it at its native source size and pinned to the same anchor
            // as the changing surface. Stretching it to the platter bounds
            // made the final close frames slide/scale before the real button
            // was restored.
            proxySubview.frame = sourceProxyContainer.bounds
            proxySubview.autoresizingMask = []
        }
        updateSourceProxy(rawT: rawT)
        let surfaceBounds = finalMenuGlassSurfaceView.bounds
        updateSurfaceSDFLayout(
            size: surfaceBounds.size,
            cornerRadius: glassSample.bodyCornerRadii.average
        )
        updateHighlight(rawT: rawT, surfaceFrame: finalMenuGlassSurfaceView.frame)
        updateContentFrames(for: surfaceBounds)
        updateContentVisibility(rawT: rawT)
        updateSurfaceSDFDistortion(rawT: rawT)
    }

    private func updateBridge(
        using sample: ContextMenuGlassmorphicGeometrySample,
        rawT: CGFloat
    ) {
        guard glassMorphContainer.isUsingNativeContainerEffect else {
            bridgeGlassSurfaceView.isHidden = true
            bridgeGlassSurfaceView.alpha = 0.0
            bridgeGlassSurfaceView.transform = .identity
            bridgeContinuationGlassSurfaceView.isHidden = true
            bridgeContinuationGlassSurfaceView.alpha = 0.0
            bridgeContinuationGlassSurfaceView.transform = .identity
            return
        }

        func configureSegment(
            _ view: MenuGlassSurfaceView,
            from start: CGPoint,
            to end: CGPoint,
            radius: CGFloat
        ) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let distance = hypot(dx, dy)
            let diameter = radius * 2.0
            view.isHidden = false
            view.alpha = 1.0
            view.bounds = CGRect(
                x: 0.0,
                y: 0.0,
                width: max(diameter, distance + diameter),
                height: diameter
            )
            view.center = CGPoint(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5
            )
            view.transform = CGAffineTransform(rotationAngle: atan2(dy, dx))
            view.setSurfaceCornerRadius(radius)
            view.updateMaterialThickness(materialProgress(rawT))
        }

        if sample.bridgeRadius > 0.5 {
            configureSegment(
                bridgeGlassSurfaceView,
                from: sample.bridgeStart,
                to: sample.bridgeEnd,
                radius: sample.bridgeRadius
            )
            configureSegment(
                bridgeContinuationGlassSurfaceView,
                from: sample.bridgeEnd,
                to: sample.neckBulbCenter,
                radius: sample.neckBulbRadius
            )
        } else {
            bridgeGlassSurfaceView.isHidden = true
            bridgeGlassSurfaceView.alpha = 0.0
            bridgeGlassSurfaceView.transform = .identity
            bridgeContinuationGlassSurfaceView.isHidden = true
            bridgeContinuationGlassSurfaceView.alpha = 0.0
            bridgeContinuationGlassSurfaceView.transform = .identity
        }
    }

    private func updateSourceProxy(rawT: CGFloat) {
        switch sourceMode {
        case .persistentSource:
            sourceProxyContainer.alpha = 0
            sourceProxyContainer.isHidden = true
            sourceProxyContainer.transform = .identity
        case .leasedGlassSource:
            let sample = sourceMaterializationSample(rawT: rawT)
            sourceProxyContainer.alpha = sample.opacity
            sourceProxyContainer.isHidden = sample.opacity <= 0.001
            sourceProxyContainer.transform = sourceContentTransform(rawT: rawT)
            sourceMaterializationView?.setBlurRadius(sample.blurRadius)
        }
    }

    private func sourceContentTransform(rawT: CGFloat) -> CGAffineTransform {
        guard animationDirection < 0, !UIAccessibility.isReduceMotionEnabled else { return .identity }
        if let state = interruptedCollapse {
            let t = Self.smootherstep(0.0, 0.68, interruptedCollapseRunProgress(
                rawT: rawT, startProgress: state.rawProgress
            ))
            return Self.interpolate(state.sourceContentTransform, .identity, t)
        }
        let body = finalMenuGlassSurfaceView.convert(finalMenuGlassSurfaceView.bounds, to: self)
        let scale = min(1.0, max(0.0, body.width / max(1.0, startFrame.width)))
        let headReturn = Self.smootherstep(0.64, 0.90, 1.0 - rawT)
        let scaleX = Self.lerp(scale, 1.0, headReturn)
        // A compact drop is narrower than the complete button. Fit its label
        // inside the upper body, then let it expand/recenter with the source
        // capsule instead of clipping the last letters against the mask.
        let offsetX = scale < 1.0
            ? (body.midX - sourceProxyContainer.center.x) * (1.0 - headReturn)
            : 0.0
        return CGAffineTransform(a: scaleX, b: 0, c: 0, d: 1, tx: offsetX, ty: 0)
    }

    private func updateSourceContentMask(paths: [CGPath]) {
        // A single nonzero-fill path can subtract overlapping clockwise and
        // counterclockwise contours (notably the stroked bridge), splitting
        // returning text in two. Separate opaque layers form an alpha union.
        while sourceContentMaskParts.count < paths.count {
            let part = CAShapeLayer()
            part.fillColor = UIColor.black.cgColor
            sourceContentMask.addSublayer(part)
            sourceContentMaskParts.append(part)
        }
        for (index, part) in sourceContentMaskParts.enumerated() {
            part.frame = sourceContentMask.bounds
            part.isHidden = index >= paths.count
            part.path = index < paths.count ? paths[index] : nil
        }
    }

    private func sourceMaterializationSample(rawT: CGFloat) -> ContextMenuSourceMaterializationSample {
        if animationDirection < 0, let state = interruptedCollapse {
            let t = Self.smootherstep(0.0, 0.68, interruptedCollapseRunProgress(
                rawT: rawT, startProgress: state.rawProgress
            ))
            return .init(
                opacity: Self.lerp(state.sourceContentSample.opacity, 1.0, t),
                blurRadius: Self.lerp(state.sourceContentSample.blurRadius, 0.0, t)
            )
        }
        return contextMenuSourceMaterializationSample(
            rawProgress: rawT,
            direction: animationDirection < 0 ? .closing : .opening,
            menuHeight: targetMenuFrameInOverlay.height,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
    }

    private func updateContentFrames(for surfaceBounds: CGRect) {
        let targetFrame = contextMenuBloomAnchoredFrame(
            contentSize: targetMenuFrameInOverlay.size,
            in: surfaceBounds,
            anchor: bloomAnchor
        )
        let targetBounds = CGRect(origin: .zero, size: targetFrame.size)
        snapshotContainer.bounds = targetBounds
        snapshotContainer.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        // Both images can retain a directional transform from the last frame.
        // Assigning frame under that transform changes their underlying bounds.
        for imageView in [blurredMenuSnapshotView, sharpMenuSnapshotView] {
            imageView.bounds = targetBounds
            imageView.center = CGPoint(x: targetBounds.midX, y: targetBounds.midY)
        }
        updateContentSDFLayout()

        liveMenuContentView.bounds = targetBounds
        liveMenuContentView.center = snapshotContainer.center
    }

    private func updateContentVisibility(rawT: CGFloat) {
        // Keep destination layout immutable and stage only its rendering:
        // blurred snapshot -> sharp snapshot -> live content. Every weight
        // reaches an exact endpoint, so completion does not cause a one-frame
        // brightness snap when the snapshots are removed.
        let contentT = contentTimelineProgress(rawT: rawT)
        let isOpening = animationDirection >= 0.0 && interruptedCollapse == nil
        var weights = isOpening
            ? contextMenuBloomContentWeights(at: contentT)
            : contextMenuBloomClosingContentWeights(at: contentT)
        var interruptedBlend: CGFloat = 0
        var interruptedReveal: CGFloat?
        if let state = interruptedCollapse {
            let runT = interruptedCollapseRunProgress(rawT: rawT, startProgress: state.rawProgress)
            let dissolveT = 1.0 - contextMenuClosingContentProgress(
                rawProgress: 1.0 - runT, menuHeight: targetMenuFrameInOverlay.height
            )
            interruptedBlend = Self.smootherstep(0.0, 0.72, dissolveT)
            let revealGain = contextMenuBloomRevealProgress(
                for: contextMenuBloomClosingContentWeights(at: 1.0 - dissolveT)
            )
            let captured = state.contentRendering.weights
            if runT <= 0 {
                weights = captured
            } else {
                // Dissolve only the content that was actually visible when
                // opening was interrupted. Transfer its sharp/live energy to
                // the existing blurred snapshot without revealing extra rows.
                let blurred = sqrt(
                    captured.blurred * captured.blurred
                        + (captured.sharp * captured.sharp + captured.live * captured.live) * interruptedBlend
                ) * revealGain
                let sharp = captured.sharp * sqrt(1.0 - interruptedBlend) * revealGain
                let live = captured.live * sqrt(1.0 - interruptedBlend) * revealGain
                weights = ContextMenuBloomContentWeights(
                    blurred: blurred, sharp: sharp, live: live,
                    snapshotContainer: sqrt(blurred * blurred + sharp * sharp)
                )
            }
            interruptedReveal = state.contentRendering.reveal * revealGain
        }
        let liveT = weights.live
        let reveal = interruptedReveal ?? contextMenuBloomRevealProgress(for: weights)
        let liveMix = reveal > 0.0001
            ? min(1.0, (liveT / reveal) * (liveT / reveal))
            : 0.0
        let flow = Self.normalize(flowVector)
        let normal = CGPoint(x: -flow.y, y: flow.x)
        let pull = contextMenuBloomSample(
            times: [0.16, 0.34, 0.52, 0.68, 0.84, 0.92],
            values: [9.0, 10.0, 5.0, -1.5, 0.0, 0.0],
            at: contentT
        )
        let arc = contextMenuBloomSample(
            times: [0.16, 0.36, 0.54, 0.72, 0.88, 0.92],
            values: [0.0, 2.5, 4.0, 1.5, 0.0, 0.0],
            at: contentT
        )
        let blurredCrossScale = contextMenuBloomSample(
            times: [0.16, 0.36, 0.54, 0.74, 0.92],
            values: [0.960, 0.965, 0.985, 1.006, 1.0],
            at: contentT
        )
        let blurredAlongScale = contextMenuBloomSample(
            times: [0.16, 0.36, 0.54, 0.74, 0.92],
            values: [1.075, 1.065, 1.035, 0.996, 1.0],
            at: contentT
        )
        let sharpCrossScale = contextMenuBloomSample(
            times: [0.34, 0.52, 0.70, 0.86, 0.92],
            values: [0.985, 0.988, 0.997, 1.003, 1.0],
            at: contentT
        )
        let sharpAlongScale = contextMenuBloomSample(
            times: [0.34, 0.52, 0.70, 0.86, 0.92],
            values: [1.035, 1.025, 1.010, 0.998, 1.0],
            at: contentT
        )

        func directionalTransform(
            pull: CGFloat,
            arc: CGFloat,
            alongScale: CGFloat,
            crossScale: CGFloat
        ) -> CGAffineTransform {
            guard !UIAccessibility.isReduceMotionEnabled else { return .identity }
            let offset = CGPoint(
                x: -flow.x * pull + normal.x * arc,
                y: -flow.y * pull + normal.y * arc
            )
            let xx = flow.x * flow.x
            let yy = flow.y * flow.y
            let xy = flow.x * flow.y
            return CGAffineTransform(
                a: alongScale * xx + crossScale * yy,
                b: (alongScale - crossScale) * xy,
                c: (alongScale - crossScale) * xy,
                d: alongScale * yy + crossScale * xx,
                tx: offset.x,
                ty: offset.y
            )
        }

        let snapshotAlpha = weights.snapshotContainer
        snapshotContainer.alpha = snapshotAlpha
        if isOpening, !UIAccessibility.isReduceMotionEnabled, snapshotAlpha > 0.0001 {
            // The reference does not reveal a fixed final canvas through a
            // growing crop. Its rows are optically compressed into the drop
            // and expand with it. Scale around the bloom attachment so the
            // content and glass keep one shared top-trailing origin.
            let targetSize = snapshotContainer.bounds.size
            let carrierSize = finalMenuGlassSurfaceView.bounds.size
            let scaleX = min(
                1.0,
                max(0.12, carrierSize.width / max(1.0, targetSize.width))
            )
            let scaleY = min(
                1.0,
                max(0.12, carrierSize.height / max(1.0, targetSize.height))
            )
            let localAnchor = CGPoint(
                x: targetSize.width * bloomAnchor.unitPoint.x,
                y: targetSize.height * bloomAnchor.unitPoint.y
            )
            let center = CGPoint(x: targetSize.width * 0.5, y: targetSize.height * 0.5)
            let anchorVector = CGPoint(
                x: localAnchor.x - center.x,
                y: localAnchor.y - center.y
            )
            snapshotContainer.transform = CGAffineTransform(
                a: scaleX,
                b: 0.0,
                c: 0.0,
                d: scaleY,
                tx: anchorVector.x * (1.0 - scaleX),
                ty: anchorVector.y * (1.0 - scaleY)
            )
        } else {
            snapshotContainer.transform = .identity
        }
        if snapshotAlpha > 0.0001 {
        // Child alphas are normalized because the container supplies the
        // common opacity. Equal-power gains soften the source-over midpoint
        // dip, while the filtered container still reaches an exact zero
        // before the endpoint handoff.
            blurredMenuSnapshotView.alpha = weights.blurred / snapshotAlpha
            sharpMenuSnapshotView.alpha = weights.sharp / snapshotAlpha
        } else {
            blurredMenuSnapshotView.alpha = 0.0
            sharpMenuSnapshotView.alpha = 0.0
        }
        blurredMenuSnapshotView.transform = directionalTransform(
            pull: pull,
            arc: arc,
            alongScale: blurredAlongScale,
            crossScale: blurredCrossScale
        )
        sharpMenuSnapshotView.transform = directionalTransform(
            pull: pull,
            arc: arc,
            alongScale: sharpAlongScale,
            crossScale: sharpCrossScale
        )
        liveMenuContentView.alpha = liveT
        let liveDistortion = 0.25 * (1.0 - liveMix)
        liveMenuContentView.transform = directionalTransform(
            pull: pull * liveDistortion,
            arc: arc * liveDistortion,
            alongScale: 1.0 + (sharpAlongScale - 1.0) * liveDistortion,
            crossScale: 1.0 + (sharpCrossScale - 1.0) * liveDistortion
        )
        if let state = interruptedCollapse {
            let captured = state.contentRendering
            snapshotContainer.transform = Self.interpolate(
                captured.snapshotTransform, snapshotContainer.transform, interruptedBlend
            )
            blurredMenuSnapshotView.transform = Self.interpolate(
                captured.blurredTransform, blurredMenuSnapshotView.transform, interruptedBlend
            )
            sharpMenuSnapshotView.transform = Self.interpolate(
                captured.sharpTransform, sharpMenuSnapshotView.transform, interruptedBlend
            )
            liveMenuContentView.transform = Self.interpolate(
                captured.liveTransform, liveMenuContentView.transform, interruptedBlend
            )
        }
        updateContentSDFDistortion(
            rawT: contentT, liveMix: liveMix,
            interruptionBlend: interruptedCollapse == nil ? nil : interruptedBlend
        )
        displayedContentReveal = reveal
        contentRevealProgressChanged?(reveal)
    }

    private func contentTimelineProgress(rawT: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, rawT))
        guard animationDirection < 0 else { return t }
        if let interruptedCollapse {
            let runT = interruptedCollapseRunProgress(
                rawT: t,
                startProgress: interruptedCollapse.rawProgress
            )
            return max(
                0.0,
                interruptedCollapse.contentProgress * contextMenuClosingContentProgress(
                    rawProgress: 1.0 - runT, menuHeight: targetMenuFrameInOverlay.height
                )
            )
        }
        return contextMenuClosingContentProgress(rawProgress: t, menuHeight: targetMenuFrameInOverlay.height)
    }

    private func installContentDistortionFilterIfAvailable() {
        guard usesOpticalDistortion, contentSDFFilter == nil else { return }
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            let size = targetMenuFrameInOverlay.size
            filter.install(
                on: snapshotContainer.layer,
                size: size,
                cornerRadius: min(finalCornerRadius, min(size.width, size.height) * 0.5),
                preserveExistingFilters: false
            )
            filter.setDisplacementHeight(0)
            filter.setBlurRadius(0)
            contentSDFFilter = filter
        }
    }

    private func installSurfaceDistortionFilterIfAvailable() {
        guard usesOpticalDistortion, surfaceSDFFilter == nil, glassMorphContainer.isUsingNativeContainerEffect else { return }
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(
                on: finalMenuGlassSurfaceView.layer,
                size: sourceFrameInOverlay.size,
                cornerRadius: startCornerRadius,
                preserveExistingFilters: false
            )
            filter.setDisplacementHeight(0)
            filter.setBlurRadius(0)
            surfaceSDFFilter = filter
        }
    }

    private func updateSurfaceSDFLayout(size: CGSize, cornerRadius: CGFloat) {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            filter.updateLayout(
                size: size,
                cornerRadius: min(cornerRadius, min(size.width, size.height) * 0.5)
            )
        }
    }

    private func updateSurfaceSDFDistortion(rawT: CGFloat) {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            guard !UIAccessibility.isReduceMotionEnabled else {
                filter.setDisplacementHeight(0)
                filter.setBlurRadius(0)
                displayedSurfaceDistortion = .zero
                return
            }

            func apply(displacement: CGFloat, blur: CGFloat) {
                var value = OpticalDistortion(displacement: displacement, blur: blur)
                if let state = interruptedCollapse {
                    let runT = interruptedCollapseRunProgress(rawT: rawT, startProgress: state.rawProgress)
                    value = .interpolated(
                        from: state.surfaceDistortion, to: value,
                        progress: Self.smootherstep(0.0, 0.35, runT)
                    )
                }
                displayedSurfaceDistortion = value
                filter.setDisplacementHeight(value.displacement)
                filter.setBlurRadius(value.blur)
            }

            let t = max(0, min(1, rawT))
            let phase = Self.smootherstep(0.02, 0.82, t)
            let lensBell = sin(.pi * phase)
            let visibleIn = Self.smootherstep(0.015, 0.12, t)
            let finalDecay = 1.0 - Self.smootherstep(0.58, 0.96, t)
            let sourceFade = Self.smootherstep(0.04, 0.20, t)
            let intensity = max(0, lensBell * visibleIn * max(finalDecay, 0.0) * sourceFade)
            if animationDirection >= 0.0, interruptedCollapse == nil {
                // The transport lobe begins smaller than the old fixed 30 pt
                // displacement. Cap refraction to its current diameter so
                // the filter cannot manufacture a spike that reads as the
                // removed explicit tail.
                let minimumSide = min(
                    finalMenuGlassSurfaceView.bounds.width,
                    finalMenuGlassSurfaceView.bounds.height
                )
                let bodyReady = Self.smootherstep(0.08, 0.22, t)
                let peakDisplacement = min(30.0, max(0.0, minimumSide * 0.14))
                let peakBlur = min(1.8, max(0.0, minimumSide * 0.018))
                apply(displacement: peakDisplacement * intensity * bodyReady, blur: peakBlur * intensity * bodyReady)
            } else {
                apply(displacement: 30.0 * intensity, blur: 1.8 * intensity)
            }
        }
    }

    private func updateContentSDFLayout() {
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            let size = snapshotContainer.bounds.size
            filter.updateLayout(
                size: size,
                cornerRadius: min(finalCornerRadius, min(size.width, size.height) * 0.5)
            )
        }
    }

    private func updateContentSDFDistortion(rawT: CGFloat, liveMix: CGFloat, interruptionBlend: CGFloat? = nil) {
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            guard !UIAccessibility.isReduceMotionEnabled else {
                filter.setDisplacementHeight(0)
                filter.setBlurRadius(0)
                displayedContentDistortion = .zero
                return
            }

            func apply(displacement: CGFloat, blur: CGFloat) {
                var value = OpticalDistortion(displacement: displacement, blur: blur)
                if let state = interruptedCollapse, let interruptionBlend {
                    value = .interpolated(
                        from: state.contentDistortion, to: value, progress: interruptionBlend
                    )
                }
                displayedContentDistortion = value
                filter.setDisplacementHeight(value.displacement)
                filter.setBlurRadius(value.blur)
            }

            let t = max(0, min(1, rawT))
            let isOpening = animationDirection >= 0.0 && interruptedCollapse == nil
            if isOpening {
                // Strong enough to bend the early rows, but short and compact
                // enough that they remain visible inside the growing drop.
                // Closing keeps its established longer 48 pt dissolve below.
                let distortionIn = Self.smootherstep(0.10, 0.24, t)
                let distortionOut = 1.0 - Self.smootherstep(0.62, 0.90, t)
                let snapshotVisibility = max(0.0, min(1.0, snapshotContainer.alpha))
                let intensity = max(
                    0.0,
                    distortionIn * distortionOut * sqrt(snapshotVisibility)
                )
                apply(displacement: 42.0 * intensity, blur: 1.5 * intensity)
                return
            }

            let phase = Self.smootherstep(0.20, 0.90, t)
            let lensBell = sin(.pi * phase)
            let snapshotVisibility = max(0.0, min(1.0, snapshotContainer.alpha))
            let liveDecay = 1.0 - Self.smootherstep(0.82, 0.98, liveMix)
            let intensity = max(
                0.0,
                lensBell * sqrt(snapshotVisibility) * liveDecay
            )
            let minimumSide = min(snapshotContainer.bounds.width, snapshotContainer.bounds.height)
            let peakDisplacement = min(48.0, max(36.0, minimumSide * 0.18))

            apply(displacement: peakDisplacement * intensity, blur: 2.7 * intensity)
        }
    }

    private func updateHighlight(rawT: CGFloat, surfaceFrame: CGRect) {
        let highlightT = Self.smootherstep(0.05, 0.78, rawT)
        let motionFactor: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0.35 : 1.0
        let start = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let target = CGPoint(
            x: targetMenuFrameInOverlay.midX + flowVector.x * targetMenuFrameInOverlay.width * 0.18 * motionFactor,
            y: targetMenuFrameInOverlay.midY + flowVector.y * targetMenuFrameInOverlay.height * 0.18 * motionFactor
        )
        let overlayCenter = Self.lerpPoint(start, target, highlightT)
        let localCenter = CGPoint(
            x: overlayCenter.x - surfaceFrame.minX,
            y: overlayCenter.y - surfaceFrame.minY
        )
        let radius = Self.lerp(22.0, max(targetMenuFrameInOverlay.width, targetMenuFrameInOverlay.height) * 0.70, highlightT)
        let alphaPeak = UIAccessibility.isReduceMotionEnabled ? 0.08 : 0.18
        let alpha = alphaPeak * sin(.pi * Self.smootherstep(0.05, 0.88, rawT))
        highlightView.alpha = alpha
        highlightView.bounds = CGRect(x: 0, y: 0, width: radius * 2.0, height: radius * 2.0)
        highlightView.center = localCenter
        highlightLayer.frame = highlightView.bounds
    }

    private func updateShadow(rawT: CGFloat) {
        let energy = sin(.pi * Self.smootherstep(0.08, 0.86, rawT))
        let finalT = Self.smootherstep(0.78, 1.0, rawT)
        let visibleT = Self.smootherstep(0.02, 0.18, rawT)

        let ambientOpacity = Self.lerp(Self.lerp(0.035, 0.09, energy), 0.08, finalT) * visibleT
        let contactOpacity = Self.lerp(Self.lerp(0.02, 0.055, energy), 0.045, finalT) * visibleT
        ambientShadowLayer.shadowOpacity = Float(ambientOpacity)
        ambientShadowLayer.shadowRadius = Self.lerp(Self.lerp(10.0, 26.0, energy), 22.0, finalT)
        ambientShadowLayer.shadowOffset = .zero
        contactShadowLayer.shadowOpacity = Float(contactOpacity)
        contactShadowLayer.shadowRadius = Self.lerp(Self.lerp(6.0, 14.0, energy), 12.0, finalT)
        contactShadowLayer.shadowOffset = CGSize(width: 0, height: Self.lerp(Self.lerp(2.0, 5.0, energy), 4.0, finalT))
    }

    private func currentMetrics(rawT: CGFloat) -> Metrics {
        if animationDirection < 0, let interruptedCollapse {
            return interruptedCollapseMetrics(rawT: rawT, state: interruptedCollapse)
        }
        let sample = contextMenuBloomGeometrySample(
            source: startFrame,
            target: targetMenuFrameInOverlay,
            sourceRadius: startCornerRadius,
            targetRadius: finalCornerRadius,
            anchor: bloomAnchor,
            direction: animationDirection < 0 ? .closing : .opening,
            rawProgress: rawT,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        return Metrics(frame: sample.frame, cornerRadii: sample.cornerRadii)
    }

    private func currentGlassmorphicSample(
        metrics: Metrics,
        rawT: CGFloat
    ) -> ContextMenuGlassmorphicGeometrySample {
        if animationDirection < 0, let interruptedCollapse {
            let runT = interruptedCollapseRunProgress(
                rawT: rawT,
                startProgress: interruptedCollapse.rawProgress
            )
            let collapseT = contextMenuBloomSmootherstep(runT)
            let sourceSample = contextMenuGlassmorphicGeometrySample(
                source: startFrame,
                target: targetMenuFrameInOverlay,
                outerFrame: startFrame,
                outerCornerRadii: .uniform(startCornerRadius),
                sourceRadius: startCornerRadius,
                targetRadius: finalCornerRadius,
                anchor: bloomAnchor,
                direction: .closing,
                rawProgress: 0.0,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
            return ContextMenuGlassmorphicGeometrySample.interpolated(
                from: interruptedCollapse.glassSample,
                to: sourceSample,
                progress: collapseT
            )
        }

        return contextMenuGlassmorphicGeometrySample(
            source: startFrame,
            target: targetMenuFrameInOverlay,
            outerFrame: metrics.frame,
            outerCornerRadii: metrics.cornerRadii,
            sourceRadius: startCornerRadius,
            targetRadius: finalCornerRadius,
            anchor: bloomAnchor,
            direction: animationDirection < 0 ? .closing : .opening,
            rawProgress: rawT,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
    }

    private func interruptedCollapseMetrics(
        rawT: CGFloat,
        state: InterruptedCollapse
    ) -> Metrics {
        let runT = interruptedCollapseRunProgress(
            rawT: rawT,
            startProgress: state.rawProgress
        )
        let profile = contextMenuBloomGeometrySample(
            source: CGRect(x: 0, y: 0, width: 1, height: 1),
            target: CGRect(x: 0, y: 0, width: 2, height: 2),
            sourceRadius: 0.5,
            targetRadius: 1.0,
            anchor: ContextMenuBloomAnchor(unitPoint: .zero),
            direction: .closing,
            rawProgress: 1.0 - runT,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        let unit = bloomAnchor.unitPoint
        let width = startFrame.width + (state.metrics.frame.width - startFrame.width) * profile.widthT
        let height = startFrame.height + (state.metrics.frame.height - startFrame.height) * profile.heightT
        let sourceAnchor = CGPoint(
            x: startFrame.minX + startFrame.width * unit.x,
            y: startFrame.minY + startFrame.height * unit.y
        )
        let capturedAnchor = CGPoint(
            x: state.metrics.frame.minX + state.metrics.frame.width * unit.x,
            y: state.metrics.frame.minY + state.metrics.frame.height * unit.y
        )
        let anchorT = max(0.0, min(1.0, (profile.widthT + profile.heightT) * 0.5))
        let currentAnchor = CGPoint(
            x: sourceAnchor.x + (capturedAnchor.x - sourceAnchor.x) * anchorT,
            y: sourceAnchor.y + (capturedAnchor.y - sourceAnchor.y) * anchorT
        )
        let frame = CGRect(
            x: currentAnchor.x - width * unit.x,
            y: currentAnchor.y - height * unit.y,
            width: width,
            height: height
        )
        let sourceRadii = ContextMenuBloomCornerRadii.uniform(startCornerRadius)
        let radii = ContextMenuBloomCornerRadii(
            topLeft: Self.lerp(sourceRadii.topLeft, state.metrics.cornerRadii.topLeft, anchorT),
            topRight: Self.lerp(sourceRadii.topRight, state.metrics.cornerRadii.topRight, anchorT),
            bottomLeft: Self.lerp(sourceRadii.bottomLeft, state.metrics.cornerRadii.bottomLeft, anchorT),
            bottomRight: Self.lerp(sourceRadii.bottomRight, state.metrics.cornerRadii.bottomRight, anchorT)
        )
        return Metrics(frame: frame, cornerRadii: radii)
    }

    private func interruptedCollapseRunProgress(
        rawT: CGFloat,
        startProgress: CGFloat
    ) -> CGFloat {
        guard startProgress > 0.0001 else { return 1.0 }
        return max(0.0, min(1.0, (startProgress - rawT) / startProgress))
    }

    private var bloomAnchor: ContextMenuBloomAnchor {
        ContextMenuBloomAnchor.detect(source: startFrame, target: targetMenuFrameInOverlay)
    }

    private var flowVector: CGPoint {
        let sourceCenter = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let targetCenter = CGPoint(x: targetMenuFrameInOverlay.midX, y: targetMenuFrameInOverlay.midY)
        let vector = CGPoint(x: targetCenter.x - sourceCenter.x, y: targetCenter.y - sourceCenter.y)
        let length = hypot(vector.x, vector.y)
        if length > 0.001 {
            return CGPoint(x: vector.x / length, y: vector.y / length)
        }
        return Self.normalize(CGPoint(x: -0.6, y: 0.8))
    }

    private var startFrame: CGRect {
        switch sourceMode {
        case .leasedGlassSource:
            return sourceFrameInOverlay
        case .persistentSource:
            let seed = persistentSeedPoint
            return CGRect(x: seed.x - 18.0, y: seed.y - 18.0, width: 36.0, height: 36.0)
        }
    }

    private var startCornerRadius: CGFloat {
        switch sourceMode {
        case .leasedGlassSource:
            let maxRadius = min(sourceFrameInOverlay.width, sourceFrameInOverlay.height) * 0.5
            let radius = sourceCornerRadius > 0 ? sourceCornerRadius : maxRadius
            return min(max(0, radius), maxRadius)
        case .persistentSource:
            return 18.0
        }
    }

    private var persistentSeedPoint: CGPoint {
        let sourceCenter = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let insetTarget = targetMenuFrameInOverlay.insetBy(dx: 12.0, dy: 12.0)
        return Self.nearestPoint(on: insetTarget, to: sourceCenter)
    }

    private func materialProgress(_ rawT: CGFloat) -> CGFloat {
        let t = max(0, min(1, rawT))
        return Self.smootherstep(0.08, 0.70, t)
    }

    private func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        dampingRatio: CGFloat,
        completion: (() -> Void)?
    ) {
        // The CA presentation transform can be up to one display-link tick
        // ahead of the geometry currently on screen. When direction changes,
        // reverse from the last geometry we actually drew; sampling the newer
        // driver value here would create one forward frame before collapse.
        let wasAnimating = progressAnimator != nil || progressDisplayLink != nil
        let visibleProgress = wasAnimating ? lastAppliedProgress : progress
        cancelAnimation()
        // An explicitly sampled/frozen frame can also differ from the idle
        // driver's transform. Preserve that rendered state on either path.
        progress = visibleProgress
        let sampledMetrics = currentMetrics(rawT: progress)
        let sampledContentProgress = contentTimelineProgress(rawT: progress)
        let sampledContentRendering = RenderedContent(
            weights: ContextMenuBloomContentWeights(
                blurred: snapshotContainer.alpha * blurredMenuSnapshotView.alpha,
                sharp: snapshotContainer.alpha * sharpMenuSnapshotView.alpha,
                live: liveMenuContentView.alpha,
                snapshotContainer: snapshotContainer.alpha
            ),
            snapshotTransform: snapshotContainer.transform,
            blurredTransform: blurredMenuSnapshotView.transform,
            sharpTransform: sharpMenuSnapshotView.transform,
            liveTransform: liveMenuContentView.transform,
            reveal: displayedContentReveal
        )
        let sampledSourceContent = sourceMaterializationSample(rawT: progress)
        let sampledSourceFrame = CGRect(
            x: sourceProxyContainer.center.x - sourceProxyContainer.bounds.width * 0.5,
            y: sourceProxyContainer.center.y - sourceProxyContainer.bounds.height * 0.5,
            width: sourceProxyContainer.bounds.width,
            height: sourceProxyContainer.bounds.height
        )
        let sampledGlassSample = currentGlassmorphicSample(metrics: sampledMetrics, rawT: progress)
        animationFrom = progress
        animationTo = target
        let isInterruptedCollapse = target < progress && progress < 0.999
        animationDirection = target >= animationFrom ? 1 : -1
        interruptedCollapse = isInterruptedCollapse
            ? InterruptedCollapse(
                rawProgress: progress,
                metrics: sampledMetrics,
                contentProgress: sampledContentProgress,
                contentRendering: sampledContentRendering,
                contentDistortion: displayedContentDistortion,
                surfaceDistortion: displayedSurfaceDistortion,
                glassSpacing: displayedGlassSpacing,
                renderedHeadAlpha: sourceSeedGlassSurfaceView.alpha,
                sourceContentSample: sampledSourceContent,
                sourceContentFrame: sampledSourceFrame,
                sourceContentTransform: sourceProxyContainer.transform,
                glassSample: sampledGlassSample
            )
            : nil
        _ = dampingRatio
        animationCompletion = completion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressDriverView.layer.removeAllAnimations()
        progressDriverView.transform = CGAffineTransform(translationX: progress, y: 0)
        CATransaction.commit()

        // Geometry already applies its measured, direction-specific sampled
        // profile in `currentMetrics`; the driver itself stays linear.
        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.0, y: 0.0),
            controlPoint2: CGPoint(x: 1.0, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(duration: max(0.001, duration), timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.progressDriverView.transform = CGAffineTransform(translationX: target, y: 0)
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self,
                  let animator,
                  self.progressAnimator === animator else {
                return
            }

            self.stopProgressDisplayLink()
            self.progressAnimator = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.progressDriverView.layer.removeAllAnimations()
            self.progressDriverView.transform = CGAffineTransform(translationX: target, y: 0)
            self.progress = max(0, min(1, target))
            self.updateGeometry(progress: self.progress)
            CATransaction.commit()
            self.interruptedCollapse = nil

            let completion = self.animationCompletion
            self.animationCompletion = nil
            completion?()
        }
        progressAnimator = animator
        startProgressDisplayLink()
        animator.startAnimation()
    }

    private func startProgressDisplayLink() {
        stopProgressDisplayLink()
        let target = AetherDisplayLinkTarget { [weak self] link in
            self?.handleDisplayLink(link)
        }
        let link = CADisplayLink(
            target: target,
            selector: #selector(AetherDisplayLinkTarget.tick(_:))
        )
        let maximumFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let preferredFrameRate = Float(min(120, maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, preferredFrameRate),
                maximum: preferredFrameRate,
                preferred: preferredFrameRate
            )
        } else {
            link.preferredFramesPerSecond = maximumFramesPerSecond
        }
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
    }

    private func stopProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    private func cancelAnimation() {
        sampleProgressDriver()
        progressAnimator?.stopAnimation(true)
        progressAnimator = nil
        progressDriverView.layer.removeAllAnimations()
        stopProgressDisplayLink()
        animationCompletion = nil
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        sampleProgressDriver()
        updateGeometry(progress: progress)
    }

    private func sampleProgressDriver() {
        let sampled = progressDriverView.layer.presentation()?.affineTransform().tx
            ?? progressDriverView.transform.tx
        let lowerBound = min(animationFrom, animationTo) - 0.12
        let upperBound = max(animationFrom, animationTo) + 0.14
        progress = max(lowerBound, min(upperBound, sampled))
    }

    private func configureShadowLayer(_ layer: CALayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.backgroundColor = UIColor.clear.cgColor
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 10
        layer.shadowOffset = .zero
    }

    private struct Metrics {
        let frame: CGRect
        let cornerRadii: ContextMenuBloomCornerRadii
    }

    private struct InterruptedCollapse {
        let rawProgress: CGFloat
        let metrics: Metrics
        let contentProgress: CGFloat
        let contentRendering: RenderedContent
        let contentDistortion: OpticalDistortion
        let surfaceDistortion: OpticalDistortion
        let glassSpacing: CGFloat
        let renderedHeadAlpha: CGFloat
        let sourceContentSample: ContextMenuSourceMaterializationSample
        let sourceContentFrame: CGRect
        let sourceContentTransform: CGAffineTransform
        let glassSample: ContextMenuGlassmorphicGeometrySample
    }

    private struct RenderedContent {
        let weights: ContextMenuBloomContentWeights
        let snapshotTransform: CGAffineTransform
        let blurredTransform: CGAffineTransform
        let sharpTransform: CGAffineTransform
        let liveTransform: CGAffineTransform
        let reveal: CGFloat
    }

    private struct OpticalDistortion {
        let displacement: CGFloat
        let blur: CGFloat
        static let zero = OpticalDistortion(displacement: 0, blur: 0)

        static func interpolated(from: Self, to: Self, progress: CGFloat) -> Self {
            if progress <= 0 { return from }
            if progress >= 1 { return to }
            return Self(
                displacement: from.displacement + (to.displacement - from.displacement) * progress,
                blur: from.blur + (to.blur - from.blur) * progress
            )
        }
    }

    private static func interpolate(_ from: CGAffineTransform, _ to: CGAffineTransform, _ progress: CGFloat) -> CGAffineTransform {
        if progress <= 0 { return from }
        if progress >= 1 { return to }
        return CGAffineTransform(
            a: lerp(from.a, to.a, progress), b: lerp(from.b, to.b, progress),
            c: lerp(from.c, to.c, progress), d: lerp(from.d, to.d, progress),
            tx: lerp(from.tx, to.tx, progress), ty: lerp(from.ty, to.ty, progress)
        )
    }

    private static func renderImage(from view: UIView) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private static func ensureTextureContentIsDisplayed(in view: UIView) {
        if let node = ASViewToDisplayNode(view) {
            node.recursivelyEnsureDisplaySynchronously(true)
        }
        for subview in view.subviews {
            ensureTextureContentIsDisplayed(in: subview)
        }
    }

    private static func blurredImage(from image: UIImage, radius: CGFloat) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let clamped = input.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return x >= edge1 ? 1 : 0 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func easeOutCubic(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        let inverse = 1.0 - t
        return 1.0 - inverse * inverse * inverse
    }

    private static func easeOutQuart(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        let inverse = 1.0 - t
        return 1.0 - inverse * inverse * inverse * inverse
    }

    private static func easeOutPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return 1.0 - pow(1.0 - t, power)
    }

    private static func easeInPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return pow(t, power)
    }

    private static func fluidMotionProgress(_ t: CGFloat, closing: Bool) -> CGFloat {
        let x = max(0, min(1, t))
        if x == 0 || x == 1 {
            return x
        }
        if closing {
            return pow(x, 2.55)
        }
        return 1.0 - pow(1.0 - x, 2.55)
    }

    private static func dampedSpring01(
        _ t: CGFloat,
        response: CGFloat,
        dampingRatio: CGFloat,
        overshootLimit: CGFloat = 1.08
    ) -> CGFloat {
        let x = max(0, min(1, t))
        if x == 0 { return 0 }
        if x == 1 { return 1 }

        let response = max(0.001, response)
        let zeta = max(0.05, min(1.2, dampingRatio))
        let omega0 = 2.0 * CGFloat.pi / response

        if zeta < 1.0 {
            let omegaD = omega0 * sqrt(1.0 - zeta * zeta)
            let envelope = exp(-zeta * omega0 * x)
            let value = 1.0 - envelope * (
                cos(omegaD * x) +
                (zeta * omega0 / omegaD) * sin(omegaD * x)
            )
            return min(max(value, 0), overshootLimit)
        } else {
            let value = 1.0 - exp(-omega0 * x) * (1.0 + omega0 * x)
            return min(max(value, 0), 1.0)
        }
    }

    private static func interpolateRectByCenterAndSize(
        from: CGRect,
        to: CGRect,
        t: CGFloat
    ) -> CGRect {
        interpolateRectByCenterAndSizeUnclamped(from: from, to: to, t: max(0, min(1, t)))
    }

    private static func interpolateRectByCenterAndSize(
        from: CGRect,
        to: CGRect,
        centerT: CGFloat,
        sizeT: CGFloat
    ) -> CGRect {
        let clampedCenterT = max(0, min(1, centerT))
        let clampedSizeT = max(0, min(1, sizeT))
        let center = CGPoint(
            x: lerpUnclamped(from.midX, to.midX, clampedCenterT),
            y: lerpUnclamped(from.midY, to.midY, clampedCenterT)
        )
        let size = CGSize(
            width: lerpUnclamped(from.width, to.width, clampedSizeT),
            height: lerpUnclamped(from.height, to.height, clampedSizeT)
        )
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func interpolateRectByCenterAndSizeUnclamped(
        from: CGRect,
        to: CGRect,
        t: CGFloat
    ) -> CGRect {
        let center = CGPoint(
            x: lerpUnclamped(from.midX, to.midX, t),
            y: lerpUnclamped(from.midY, to.midY, t)
        )
        let size = CGSize(
            width: lerpUnclamped(from.width, to.width, t),
            height: lerpUnclamped(from.height, to.height, t)
        )
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func scale(rect: CGRect, sx: CGFloat, sy: CGFloat, around anchor: CGPoint) -> CGRect {
        let minX = anchor.x + (rect.minX - anchor.x) * sx
        let maxX = anchor.x + (rect.maxX - anchor.x) * sx
        let minY = anchor.y + (rect.minY - anchor.y) * sy
        let maxY = anchor.y + (rect.maxY - anchor.y) * sy
        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func stretch(rect: CGRect, along flow: CGPoint, bell: CGFloat) -> CGRect {
        guard bell > 0.001 else { return rect }
        let alongStretch = 1.0 + 0.035 * bell
        let crossStretch = 1.0 - 0.012 * bell
        let sx: CGFloat
        let sy: CGFloat
        if abs(flow.x) > abs(flow.y) {
            sx = alongStretch
            sy = crossStretch
        } else {
            sx = crossStretch
            sy = alongStretch
        }
        return scale(
            rect: rect,
            sx: sx,
            sy: sy,
            around: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private static func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(rect.maxX, point.x)),
            y: max(rect.minY, min(rect.maxY, point.y))
        )
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        lerpUnclamped(a, b, max(0, min(1, t)))
    }

    private static func lerpUnclamped(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func lerpPoint(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(
            x: lerp(a.x, b.x, t),
            y: lerp(a.y, b.y, t)
        )
    }

    private static func fluidCurvePoint(
        from source: CGPoint,
        to target: CGPoint,
        flow: CGPoint,
        travelT: CGFloat,
        distance: CGFloat,
        lowerBias: CGFloat,
        reduceMotion: Bool
    ) -> CGPoint {
        let t = max(0, min(1, travelT))
        guard !reduceMotion, distance > 1.0 else {
            return lerpPoint(source, target, t)
        }

        let perpendicular = CGPoint(x: -flow.y, y: flow.x)
        let curveAmount = min(distance * 0.24, 58.0)
        let lowerPull = min(distance * 0.12, 32.0)
        let sideSign: CGFloat = flow.x >= 0 ? 1.0 : -1.0

        let control1 = add(
            add(source, multiply(flow, by: distance * 0.23)),
            add(
                multiply(perpendicular, by: curveAmount * sideSign),
                CGPoint(x: 0, y: lowerPull * lowerBias)
            )
        )
        let control2 = add(
            add(target, multiply(flow, by: -distance * 0.36)),
            add(
                multiply(perpendicular, by: curveAmount * 0.46 * sideSign),
                CGPoint(x: 0, y: lowerPull * 0.68 * lowerBias)
            )
        )

        return cubicBezierPoint(source, control1, control2, target, t)
    }

    private static func cubicBezierPoint(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint,
        _ t: CGFloat
    ) -> CGPoint {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        return CGPoint(
            x: uuu * p0.x + 3.0 * uu * t * p1.x + 3.0 * u * tt * p2.x + ttt * p3.x,
            y: uuu * p0.y + 3.0 * uu * t * p1.y + 3.0 * u * tt * p2.y + ttt * p3.y
        )
    }

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }

    private static func multiply(_ point: CGPoint, by value: CGFloat) -> CGPoint {
        CGPoint(x: point.x * value, y: point.y * value)
    }

    private static func normalize(_ point: CGPoint) -> CGPoint {
        let length = hypot(point.x, point.y)
        guard length > 0.001 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: point.x / length, y: point.y / length)
    }
}
