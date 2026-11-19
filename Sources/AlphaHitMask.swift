import AppKit

/// Fast, reusable alpha hit testing for bitmap-backed sprites.
enum AlphaHitMask {
    private struct Mask {
        weak var source: NSBitmapImageRep?
        let stride: Int
        let bytes: [UInt8]
    }
    private static let lock = NSLock()
    private static var masks: [ObjectIdentifier: Mask] = [:]
    private static let maxBytes = 12 * 1024 * 1024
    private static var totalBytes = 0

    static func hit(bitmap: NSBitmapImageRep, x: Int, y: Int, threshold: CGFloat = 0.1) -> Bool {
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return false }
        let key = ObjectIdentifier(bitmap)
        let mask: Mask
        lock.lock()
        if let cached = masks[key], cached.source === bitmap { mask = cached; lock.unlock() }
        else {
            if let expired = masks.removeValue(forKey: key) { totalBytes -= expired.bytes.count }
            let built = makeMask(bitmap)
            if built.bytes.count <= maxBytes {
                while totalBytes + built.bytes.count > maxBytes, let old = masks.first {
                    totalBytes -= old.value.bytes.count; masks.removeValue(forKey: old.key)
                }
                masks[key] = built; totalBytes += built.bytes.count
            }
            mask = built; lock.unlock()
        }
        return CGFloat(mask.bytes[y * mask.stride + x]) > threshold * 255
    }

    private static func makeMask(_ bitmap: NSBitmapImageRep) -> Mask {
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        let stride = (width + 15) & ~15
        var bytes = [UInt8](repeating: 0, count: stride * height)
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        if let image = bitmap.cgImage, let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: stride * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format),
           let pixels = context.data?.assumingMemoryBound(to: UInt8.self) {
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            for y in 0..<height {
                for x in 0..<width { bytes[y * stride + x] = pixels[y * context.bytesPerRow + x * 4 + 3] }
            }
        } else {
            for y in 0..<height {
                for x in 0..<width { bytes[y * stride + x] = UInt8(255 * (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)) }
            }
        }
        return Mask(source: bitmap, stride: stride, bytes: bytes)
    }
}
