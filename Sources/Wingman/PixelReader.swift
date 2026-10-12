import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import WingmanCore

/// Reads LINE and Telegram from a capture of their window: ScreenCaptureKit captures the window even
/// when covered, Vision reads the text, BubbleParser tells whose bubble each line is. OCR only runs
/// when the conversation area changed since the last read.
actor PixelReader {
    static let shared = PixelReader()

    private struct Cached {
        var fingerprint: Int
        var lines: [OCRLine]
    }
    private var cache: [pid_t: Cached] = [:]

    // MARK: - LINE: title and input box from accessibility, messages from pixels

    func readLine(pid: pid_t) async -> Reading? {
        guard let window = AXSnapshot.windows(pid: pid).first else { return nil }
        let snapshot = AXSnapshot(window: window, maxNodes: 2500)
        var input: UINode?
        func find(_ node: UINode) {
            if input == nil, node.role == "AXTextArea" { input = node }
            node.children.forEach(find)
        }
        find(snapshot.root)
        guard let input, let (image, windowFrame) = await Self.capture(pid: pid, matching: snapshot.root.frame) else { return nil }

        // The chat pane is the column above the input box, under the header with the chat name.
        let header: CGFloat = 64
        let pane = CGRect(x: input.frame.minX - windowFrame.minX - 8, y: header,
                          width: windowFrame.maxX - input.frame.minX + 8,
                          height: max(0, input.frame.minY - windowFrame.minY - header - 4))
        let lines = recognise(image, windowSize: windowFrame.size, region: pane, pid: pid)
        let title = snapshot.root.title == "LINE" || snapshot.root.title.isEmpty
            ? Self.header(in: lines, pane: pane) : snapshot.root.title
        let convo = Conversation(title: title, isThread: false, messages: BubbleParser.messages(from: lines, pane: pane),
                                 draft: input.value.trimmingCharacters(in: .whitespacesAndNewlines),
                                 composerHandle: input.handle, composerFrame: input.frame)
        return Reading(conversation: convo, composer: snapshot.elements[input.handle])
    }

    // MARK: - Telegram: everything from pixels

    /// Placeholder text of Telegram's empty input box, which marks where the chat pane starts.
    private static let placeholders = ["Write a message", "Message", "訊息", "輸入訊息", "撰寫訊息", "写消息"]

    func readTelegram(pid: pid_t) async -> Reading? {
        guard let (image, windowFrame) = await Self.capture(pid: pid) else { return nil }
        let size = windowFrame.size
        let lines = recognise(image, windowSize: size, region: CGRect(origin: .zero, size: size), pid: pid)

        let placeholder = lines.first { line in
            line.frame.minY > size.height * 0.75 && Self.placeholders.contains { line.text.hasPrefix($0) }
        }
        let paneX = placeholder.map { max(0, $0.frame.minX - 60) } ?? (size.width > 700 ? size.width * 0.34 : 0)
        let inputTop = placeholder.map { $0.frame.minY - 12 } ?? size.height - 56
        let header: CGFloat = 56
        let pane = CGRect(x: paneX, y: header, width: size.width - paneX, height: max(0, inputTop - header - 4))
        let composer = CGRect(x: windowFrame.minX + paneX, y: windowFrame.minY + inputTop,
                              width: size.width - paneX, height: size.height - inputTop)
        let convo = Conversation(title: Self.header(in: lines, pane: pane),
                                 isThread: false, messages: BubbleParser.messages(from: lines, pane: pane),
                                 draft: "", composerHandle: -1, composerFrame: composer)
        return Reading(conversation: convo, composer: nil)
    }

    // MARK: - Capture and OCR

    /// The app's window at `frame` (the one read over accessibility), or its largest when none is given,
    /// captured at full resolution, with its frame in screen points.
    static func capture(pid: pid_t, matching frame: CGRect? = nil) async -> (CGImage, CGRect)? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows
                .filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 200 })
                .min(by: { rank($0.frame, frame) < rank($1.frame, frame) })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return nil }
        return (image, window.frame)
    }

    /// Distance from the wanted frame, or the largest window first when no frame is given.
    private static func rank(_ candidate: CGRect, _ wanted: CGRect?) -> CGFloat {
        guard let wanted else { return -candidate.width * candidate.height }
        return abs(candidate.minX - wanted.minX) + abs(candidate.minY - wanted.minY)
            + abs(candidate.width - wanted.width) + abs(candidate.height - wanted.height)
    }

    /// OCR lines inside `region` (window points), reusing the last result while the region's pixels are unchanged.
    private func recognise(_ image: CGImage, windowSize: CGSize, region: CGRect, pid: pid_t) -> [OCRLine] {
        let scale = CGFloat(image.width) / windowSize.width
        let pixels = CGRect(x: region.minX * scale, y: region.minY * scale,
                            width: region.width * scale, height: region.height * scale).integral
        guard let crop = image.cropping(to: pixels) else { return [] }
        let print = Self.fingerprint(crop)
        if let cached = cache[pid], cached.fingerprint == print { return cached.lines }

        let started = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: crop).perform([request])
        let bitmap = Bitmap(crop)
        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let inCrop = CGRect(x: box.minX * CGFloat(crop.width), y: (1 - box.maxY) * CGFloat(crop.height),
                                width: box.width * CGFloat(crop.width), height: box.height * CGFloat(crop.height))
            return OCRLine(text: best.string, confidence: Double(best.confidence),
                           frame: CGRect(x: region.minX + inCrop.minX / scale, y: region.minY + inCrop.minY / scale,
                                         width: inCrop.width / scale, height: inCrop.height / scale),
                           tint: bitmap.tint(around: inCrop))
        }
        cache[pid] = Cached(fingerprint: print, lines: lines)
        Log.write("ocr pid=\(pid) lines=\(lines.count) \(Int(Date().timeIntervalSince(started) * 1000))ms")
        return lines
    }

    /// The chat name: the first line in the header band above the messages, left to right.
    private static func header(in lines: [OCRLine], pane: CGRect) -> String {
        lines.filter { $0.frame.maxY <= pane.minY + 4 && $0.frame.minX >= pane.minX - 8 }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }?.text ?? ""
    }

    /// A 32×32 grey thumbnail hashed: equal when nothing in the region changed.
    private static func fingerprint(_ image: CGImage) -> Int {
        var pixels = [UInt8](repeating: 0, count: 32 * 32)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                                          bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return pixels.hashValue
    }
}
