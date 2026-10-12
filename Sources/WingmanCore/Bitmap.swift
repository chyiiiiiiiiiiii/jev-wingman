import CoreGraphics

/// RGBA pixels of a capture, to sample the bubble colour around a line of text.
public struct Bitmap {
    let width: Int, height: Int
    let data: [UInt8]
    /// Median saturation over the whole capture: the chat's background, which in some themes is
    /// itself a dark blue that reads as saturated.
    private(set) var background: Double = 0

    public init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.data = data
        var samples: [Double] = []
        for gy in 0..<48 { for gx in 0..<48 { samples.append(saturation(x: gx * width / 48, y: gy * height / 48)) } }
        background = samples.isEmpty ? 0 : samples.sorted()[samples.count / 2]
    }

    /// How much more saturated than the background the pixels just outside the text box are: a coloured
    /// bubble scores high; a grey bubble, or text straight on the background, scores near 0.
    public func tint(around box: CGRect) -> Double {
        let ring = box.insetBy(dx: -4, dy: -4)
        var samples: [Double] = []
        for i in 0..<12 {
            let x = Int(ring.minX + ring.width * CGFloat(i) / 11)
            for y in [Int(ring.minY), Int(ring.maxY)] where x >= 0 && x < width && y >= 0 && y < height {
                samples.append(saturation(x: x, y: y))
            }
        }
        guard !samples.isEmpty else { return 0 }
        return max(0, samples.sorted()[samples.count / 2] - background)
    }

    /// Saturation of the text's own colour: the eighth of the box's pixels that differ most in brightness
    /// from the surroundings are the glyphs. A coloured name scores high, white or black text near 0.
    public func ink(of box: CGRect) -> Double {
        let ring = box.insetBy(dx: -4, dy: -4)
        var around: [Double] = []
        for i in 0..<12 {
            let x = Int(ring.minX + ring.width * CGFloat(i) / 11)
            for y in [Int(ring.minY), Int(ring.maxY)] where x >= 0 && x < width && y >= 0 && y < height {
                around.append(luminance(x: x, y: y))
            }
        }
        guard !around.isEmpty else { return 0 }
        let paper = around.sorted()[around.count / 2]
        let xs = max(0, Int(box.minX))..<min(width, Int(box.maxX)), ys = max(0, Int(box.minY))..<min(height, Int(box.maxY))
        guard !xs.isEmpty, !ys.isEmpty else { return 0 }
        // The brightness distance that the farthest eighth of the pixels reach, from a histogram.
        var counts = [Int](repeating: 0, count: 256)
        for y in ys { for x in xs { counts[min(255, Int(abs(luminance(x: x, y: y) - paper)))] += 1 } }
        var cut = 255, taken = counts[255]
        while cut > 0, taken < xs.count * ys.count / 8 { cut -= 1; taken += counts[cut] }
        var sum = [0.0, 0.0, 0.0], glyphs = 0.0
        for y in ys { for x in xs where Int(abs(luminance(x: x, y: y) - paper)) >= cut {
            let p = (y * width + x) * 4
            for c in 0..<3 { sum[c] += Double(data[p + c]) }
            glyphs += 1
        } }
        let rgb = sum.map { $0 / max(1, glyphs) }
        let high = rgb.max()!, low = rgb.min()!
        return high > 20 ? (high - low) / high : 0
    }

    private func luminance(x: Int, y: Int) -> Double {
        let p = (y * width + x) * 4
        return 0.3 * Double(data[p]) + 0.59 * Double(data[p + 1]) + 0.11 * Double(data[p + 2])
    }

    private func saturation(x: Int, y: Int) -> Double {
        let p = (y * width + x) * 4
        let rgb = [Double(data[p]), Double(data[p + 1]), Double(data[p + 2])]
        let high = rgb.max()!, low = rgb.min()!
        return high > 20 ? (high - low) / high : 0
    }
}
