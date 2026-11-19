import AppKit

enum CharacterPose: String, CaseIterable {
    case idle, walk, run, stretch, play, closeup, carry, blanket

    var frameCount: Int {
        switch self {
        case .walk, .run, .carry: return 8
        case .idle, .stretch, .play, .blanket: return 6
        case .closeup: return 3
        }
    }

    var canvas: CGSize {
        switch self {
        case .carry, .blanket: return CGSize(width: 256, height: 240)
        default: return CGSize(width: 192, height: 208)
        }
    }
}

struct CharacterFrame {
    let image: NSImage
    let pixels: NSBitmapImageRep
}

/// Fits one set of outfit parts to the anatomy of the original animation frames.
final class SeasonDressing {
    private struct Fitting: Decodable {
        enum View: String, Decodable { case side, front, prone }
        let back: [CGFloat]
        let throat: [CGFloat]
        let shoulder: [CGFloat]
        let flank: [CGFloat]
        let view: View
        let occluders: [[CGFloat]]

        func isValid(in canvas: CGSize) -> Bool {
            func valid(_ xy: [CGFloat]) -> Bool {
                xy.count == 2 && (0..<canvas.width).contains(xy[0]) && (0..<canvas.height).contains(xy[1])
            }
            return [back, throat, shoulder, flank].allSatisfy(valid)
                && hypot(throat[0] - back[0], throat[1] - back[1]) >= 6
                && occluders.allSatisfy { polygon in
                    polygon.count >= 6 && polygon.count.isMultiple(of: 2)
                        && stride(from: 0, to: polygon.count, by: 2).allSatisfy { valid(Array(polygon[$0...$0 + 1])) }
                }
        }
    }

    private let fittings: [CharacterPose: [Fitting]]
    private let flower: CGImage
    private let toggle: CGImage
    private let satchel: CGImage
    private let scarfEnd: CGImage
    private let knit: CGImage

    private struct Key: Hashable {
        let season: PetSeason
        let pose: CharacterPose
        let frame: Int
    }
    private var cache: [Key: CharacterFrame] = [:]
    private var cacheOrder: [Key] = []
    private let cacheLimit = 96

    init(root: URL) throws {
        func part(_ name: String) throws -> CGImage {
            let url = root.appendingPathComponent("parts/\(name).png")
            guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
                  bitmap.hasAlpha, let image = bitmap.cgImage else {
                throw Self.artError("配饰素材无效：\(name)")
            }
            return image
        }
        flower = try part("flower")
        toggle = try part("toggle")
        satchel = try part("satchel")
        let end = try part("scarf-end")
        scarfEnd = end
        guard let patch = end.cropping(to: CGRect(x: end.width / 4, y: end.height / 5,
                                                  width: end.width / 2, height: end.height / 3)) else {
            throw Self.artError("围巾针织纹理无效")
        }
        knit = patch

        var loaded: [CharacterPose: [Fitting]] = [:]
        for file in ["desktop-pose-anchors.json", "home-pose-anchors.json"] {
            let raw = try Data(contentsOf: root.appendingPathComponent(file))
            for (name, frames) in try JSONDecoder().decode([String: [Fitting]].self, from: raw) {
                guard let pose = CharacterPose(rawValue: name), loaded[pose] == nil,
                      frames.count == pose.frameCount, frames.allSatisfy({ $0.isValid(in: pose.canvas) }) else {
                    throw Self.artError("动作穿戴坐标无效：\(name)")
                }
                loaded[pose] = frames
            }
        }
        let required = Set(CharacterPose.allCases.filter { $0 != .idle && $0 != .walk })
        guard Set(loaded.keys) == required else { throw Self.artError("动作穿戴坐标不完整") }
        fittings = loaded
    }

    func frame(for season: PetSeason, pose: CharacterPose, index: Int, base: CharacterFrame) -> CharacterFrame {
        let key = Key(season: season, pose: pose, frame: index)
        if let frame = cache[key] { return frame }
        let size = pose.canvas
        guard let fitting = fittings[pose]?[index], let original = base.pixels.cgImage,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        let canvas = CGRect(origin: .zero, size: size)
        context.draw(original, in: canvas)
        context.clip(to: canvas, mask: original)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        for polygon in fitting.occluders {
            let clip = CGMutablePath()
            clip.addRect(canvas)
            clip.move(to: CGPoint(x: polygon[0], y: polygon[1]))
            for i in stride(from: 2, to: polygon.count, by: 2) {
                clip.addLine(to: CGPoint(x: polygon[i], y: polygon[i + 1]))
            }
            clip.closeSubpath()
            context.addPath(clip)
            context.clip(using: .evenOdd)
        }
        context.interpolationQuality = .high
        draw(season, fitting: fitting, pose: pose, index: index, in: context)
        guard let rendered = context.makeImage() else { return base }
        let frame = CharacterFrame(image: NSImage(cgImage: rendered, size: size), pixels: NSBitmapImageRep(cgImage: rendered))
        if cacheOrder.count >= cacheLimit { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        cacheOrder.append(key)
        cache[key] = frame
        return frame
    }

    private func draw(_ season: PetSeason, fitting: Fitting, pose: CharacterPose, index: Int, in c: CGContext) {
        let back = point(fitting.back), throat = point(fitting.throat)
        let width = hypot(throat.x - back.x, throat.y - back.y)
        let angle = atan2(throat.y - back.y, throat.x - back.x)
        let compression: CGFloat = fitting.view == .prone ? 0.64 : 1
        // A small lag behind the paw cycle, fixed for held reactions and sleeping.
        let sway = [.run, .carry, .play].contains(pose) ? sin(CGFloat(index) * 2 * .pi / CGFloat(pose.frameCount) - 0.8) : 0
        if season == .autumn {
            let shoulder = point(fitting.shoulder), flank = point(fitting.flank)
            let bag = CGPoint(x: flank.x + width * 0.045 * sway, y: flank.y)
            let strap = CGMutablePath()
            strap.move(to: CGPoint(x: min(throat.x, shoulder.x + width * 0.5), y: shoulder.y - width * 0.12))
            strap.addQuadCurve(to: CGPoint(x: bag.x, y: bag.y - width * 0.16), control: shoulder)
            stroke(strap, width: width * 0.14, color: rgb(0x50382b, alpha: 0.6), in: c)
            stroke(strap, width: width * 0.105, color: rgb(0xd9ba92), in: c)
            stroke(strap, width: width * 0.025, color: rgb(0xf3d9b5), in: c)
            drawPart(satchel, at: bag, width: width * 0.53, height: width * 0.50 * compression, angle: angle * 0.18 + sway * 0.09, in: c)
            return
        }

        // Local coordinates follow the neck axis. Curved hems follow the near side of the chest.
        c.translateBy(x: back.x, y: back.y)
        c.rotate(by: angle)
        c.scaleBy(x: width, y: width * compression)
        let curve = CGMutablePath()
        curve.move(to: CGPoint(x: 0, y: 0.025))
        curve.addQuadCurve(to: CGPoint(x: 0.96, y: 0.05), control: CGPoint(x: 0.51, y: 0.29))
        let front = fitting.view == .front
        let ornamentX: CGFloat = front ? 0.49 : 0.77
        switch season {
        case .spring:
            stroke(curve, width: 0.11, color: rgb(0x655745, alpha: 0.64), in: c)
            stroke(curve, width: 0.075, color: rgb(0xdcc5a1), in: c)
            drawPart(flower, at: CGPoint(x: ornamentX, y: 0.22), width: 0.32, height: 0.30, angle: -angle * 0.4, in: c)
        case .summer:
            let collar = CGMutablePath()
            collar.addPath(curve)
            collar.addQuadCurve(to: CGPoint(x: ornamentX, y: 0.49), control: CGPoint(x: 1.02, y: 0.35))
            collar.addQuadCurve(to: CGPoint(x: 0, y: 0.025), control: CGPoint(x: 0.14, y: 0.36))
            collar.closeSubpath()
            cloth(collar, colors: [0x628ba9, 0x244762], depth: 0.54, in: c)
            for (start, end, bend) in [(0.12, 0.38, 0.34), (0.18, 0.43, 0.40)] {
                let hem = CGMutablePath()
                hem.move(to: CGPoint(x: start, y: 0.17))
                hem.addQuadCurve(to: CGPoint(x: ornamentX, y: end), control: CGPoint(x: 0.42, y: bend))
                hem.addQuadCurve(to: CGPoint(x: 0.96, y: 0.14), control: CGPoint(x: 0.94, y: 0.33))
                stroke(hem, width: 0.023, color: rgb(0xf8e8bd), in: c)
            }
            drawPart(toggle, at: CGPoint(x: ornamentX, y: 0.41), width: 0.21, height: 0.09, angle: -angle * 0.5, in: c)
        case .winter:
            let endAngle = -angle * 0.65 + sway * 0.12
            drawPart(scarfEnd, at: CGPoint(x: ornamentX + 0.025 * sway, y: 0.39),
                     width: 0.28, height: 0.45, angle: endAngle, in: c)
            let wrap = CGMutablePath()
            wrap.addPath(curve)
            wrap.addQuadCurve(to: CGPoint(x: 0.93, y: 0.30), control: CGPoint(x: 1.02, y: 0.16))
            wrap.addQuadCurve(to: CGPoint(x: 0.045, y: 0.27), control: CGPoint(x: 0.52, y: 0.51))
            wrap.addQuadCurve(to: CGPoint(x: 0, y: 0.025), control: CGPoint(x: -0.045, y: 0.19))
            wrap.closeSubpath()
            cloth(wrap, colors: [0xad4c50, 0x50242e], depth: 0.49, in: c)
            c.saveGState()
            c.addPath(wrap); c.clip(); c.setAlpha(0.55); c.setBlendMode(.softLight)
            for offset in [0.0, 0.3, 0.6, 0.9] {
                drawPart(knit, at: CGPoint(x: offset + 0.10, y: 0.21), width: 0.31, height: 0.54, angle: .pi / 2, in: c)
            }
            c.restoreGState()
        case .autumn: break // Drawn in torso coordinates above.
        }
    }

    private func cloth(_ path: CGPath, colors: [UInt32], depth: CGFloat, in c: CGContext) {
        stroke(path, width: 0.055, color: rgb(0x171025, alpha: 0.48), in: c)
        c.saveGState()
        c.addPath(path); c.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { rgb($0) } as CFArray, locations: nil)!
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: depth), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    private func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in c: CGContext) {
        c.addPath(path); c.setStrokeColor(color); c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
    }

    private func drawPart(_ image: CGImage, at center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat, in c: CGContext) {
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: angle)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        c.restoreGState()
    }

    private func point(_ xy: [CGFloat]) -> CGPoint { CGPoint(x: xy[0], y: xy[1]) }
    private func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func artError(_ message: String) -> NSError {
        NSError(domain: "SusuSeasonDressing", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
