import UIKit

private struct AetherBitmapGeometry {
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init?(size: CGSize, scale: CGFloat) {
        guard size.width.isFinite, size.height.isFinite,
              scale.isFinite,
              size.width > 0.0, size.height > 0.0, scale > 0.0 else {
            return nil
        }

        let scaledWidth = size.width * scale
        let scaledHeight = size.height * scale
        let maximumDimension: CGFloat = 16_384.0
        guard scaledWidth.isFinite, scaledHeight.isFinite,
              scaledWidth >= 1.0, scaledHeight >= 1.0,
              scaledWidth <= maximumDimension, scaledHeight <= maximumDimension else {
            return nil
        }

        let width = Int(ceil(scaledWidth))
        let height = Int(ceil(scaledHeight))
        let maximumPixelCount = 64 * 1_024 * 1_024
        guard width > 0, height > 0,
              width <= maximumPixelCount / height,
              width <= (Int.max - 31) / 4 else {
            return nil
        }

        self.scale = scale
        self.width = width
        self.height = height
        self.bytesPerRow = (4 * width + 31) & (~31)
    }
}

public func generateImage(_ size: CGSize, opaque: Bool = false, scale: CGFloat? = nil, rotatedContext: (CGSize, CGContext) -> Void) -> UIImage? {
    let selectedScale = scale ?? UIScreen.main.scale
    guard let geometry = AetherBitmapGeometry(size: size, scale: selectedScale) else {
        return nil
    }

    guard let context = CGContext(
        data: nil,
        width: geometry.width,
        height: geometry.height,
        bitsPerComponent: 8,
        bytesPerRow: geometry.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | (opaque ? CGImageAlphaInfo.noneSkipFirst.rawValue : CGImageAlphaInfo.premultipliedFirst.rawValue)).rawValue
    ) else {
        return nil
    }

    context.scaleBy(x: geometry.scale, y: geometry.scale)
    context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
    context.scaleBy(x: 1.0, y: -1.0)
    context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)

    rotatedContext(size, context)

    guard let cgImage = context.makeImage() else {
        return nil
    }

    return UIImage(cgImage: cgImage, scale: geometry.scale, orientation: .up)
}

public func generateImage(_ size: CGSize, contextGenerator: (CGSize, CGContext) -> Void, opaque: Bool = false, scale: CGFloat? = nil) -> UIImage? {
    let selectedScale = scale ?? UIScreen.main.scale
    guard let geometry = AetherBitmapGeometry(size: size, scale: selectedScale) else {
        return nil
    }

    guard let context = CGContext(
        data: nil,
        width: geometry.width,
        height: geometry.height,
        bitsPerComponent: 8,
        bytesPerRow: geometry.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | (opaque ? CGImageAlphaInfo.noneSkipFirst.rawValue : CGImageAlphaInfo.premultipliedFirst.rawValue)).rawValue
    ) else {
        return nil
    }

    context.scaleBy(x: geometry.scale, y: geometry.scale)
    contextGenerator(size, context)

    guard let cgImage = context.makeImage() else {
        return nil
    }

    return UIImage(cgImage: cgImage, scale: geometry.scale, orientation: .up)
}

public func generateFilledCircleImage(diameter: CGFloat, color: UIColor, strokeColor: UIColor? = nil, strokeWidth: CGFloat? = nil, backgroundColor: UIColor? = nil) -> UIImage? {
    return generateImage(CGSize(width: diameter, height: diameter), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        if let backgroundColor = backgroundColor {
            context.setFillColor(backgroundColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        context.setFillColor(color.cgColor)
        if let strokeColor = strokeColor, let strokeWidth = strokeWidth {
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(strokeWidth)
            let strokeInset = strokeWidth / 2.0
            context.fillEllipse(in: CGRect(origin: CGPoint(x: strokeInset, y: strokeInset), size: CGSize(width: size.width - strokeWidth, height: size.height - strokeWidth)))
            context.strokeEllipse(in: CGRect(origin: CGPoint(x: strokeInset, y: strokeInset), size: CGSize(width: size.width - strokeWidth, height: size.height - strokeWidth)))
        } else {
            context.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    })
}

public func generateStretchableFilledCircleImage(radius: CGFloat, color: UIColor?, backgroundColor: UIColor? = nil) -> UIImage? {
    return generateStretchableFilledCircleImage(diameter: radius * 2.0, color: color, strokeColor: nil, strokeWidth: nil, backgroundColor: backgroundColor)
}

public func generateStretchableFilledCircleImage(diameter: CGFloat, color: UIColor?, strokeColor: UIColor? = nil, strokeWidth: CGFloat? = nil, backgroundColor: UIColor? = nil) -> UIImage? {
    let fillColor = color ?? .clear
    let image = generateFilledCircleImage(
        diameter: diameter,
        color: fillColor,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        backgroundColor: backgroundColor
    )
    let inset = Int(max(1.0, floor(diameter / 2.0)))
    return image?.stretchableImage(withLeftCapWidth: inset, topCapHeight: inset)
}

@available(*, deprecated, message: "Resolve pixel size from the active window's screen instead.")
public let UIScreenPixel: CGFloat = 1.0 / UIScreen.main.scale
@available(*, deprecated, message: "Resolve width from the current view or window bounds instead.")
public let UIScreenWidth: CGFloat = UIScreen.main.bounds.size.width
@available(*, deprecated, message: "Resolve height from the current view or window bounds instead.")
public let UIScreenHeight: CGFloat = UIScreen.main.bounds.size.height

public func drawSvgPath(_ context: CGContext, path: String) throws {
    var index = path.startIndex
    let end = path.endIndex

    while index < end {
        let c = path[index]
        index = path.index(after: index)

        switch c {
        case " ", "\n", "\r", "\t", ",":
            continue
        case "M":
            let point = try parseSvgPoint(path, &index)
            context.move(to: point)
        case "L":
            let point = try parseSvgPoint(path, &index)
            context.addLine(to: point)
        case "C":
            let cp1 = try parseSvgPoint(path, &index)
            let cp2 = try parseSvgPoint(path, &index)
            let point = try parseSvgPoint(path, &index)
            context.addCurve(to: point, control1: cp1, control2: cp2)
        case "Q":
            let cp = try parseSvgPoint(path, &index)
            let point = try parseSvgPoint(path, &index)
            context.addQuadCurve(to: point, control: cp)
        case "Z":
            context.closePath()
            context.fillPath()
        default:
            continue
        }
    }
}

private func parseSvgFloat(_ string: String, _ index: inout String.Index) throws -> CGFloat {
    while index < string.endIndex && (string[index] == " " || string[index] == ",") {
        index = string.index(after: index)
    }
    let start = index
    if index < string.endIndex && (string[index] == "-" || string[index] == "+") {
        index = string.index(after: index)
    }
    var hasDot = false
    while index < string.endIndex {
        let c = string[index]
        if c == "." {
            if hasDot { break }
            hasDot = true
        } else if c < "0" || c > "9" {
            break
        }
        index = string.index(after: index)
    }
    guard let value = Double(String(string[start..<index])) else {
        throw NSError(domain: "SVGParseError", code: 0)
    }
    return CGFloat(value)
}

private func parseSvgPoint(_ string: String, _ index: inout String.Index) throws -> CGPoint {
    let x = try parseSvgFloat(string, &index)
    let y = try parseSvgFloat(string, &index)
    return CGPoint(x: x, y: y)
}
