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

    private func saturation(x: Int, y: Int) -> Double {
        let p = (y * width + x) * 4
        let rgb = [Double(data[p]), Double(data[p + 1]), Double(data[p + 2])]
        let high = rgb.max()!, low = rgb.min()!
        return high > 20 ? (high - low) / high : 0
    }
}
