import CoreGraphics

/// Joins successive frames of a scrolling area into one tall image.
///
/// Each frame is compared with the last frame that was kept to find how far the
/// content moved up, and only the newly revealed rows are added. Rows that stay put
/// between two frames at the top (sticky headers, toolbars) and at the bottom
/// (footers, status bars) are left out of the matching so they don't repeat down
/// the result; the footer of the final frame ends the image.
actor ScrollStitcher {
    enum Update: Sendable {
        /// The content hasn't moved, or there isn't enough detail to tell how far it moved.
        case unchanged
        case appended
        /// The new frame doesn't overlap the last kept one: scrolled too fast, or back up.
        case lostTrack
        case reachedLimit
    }

    /// Caps memory use and keeps the result inside what image viewers handle well.
    static let maxHeight = 30_000

    /// Mean grey-level difference (0–255) below which two rows count as the same.
    private static let matchTolerance = 5.0
    /// Columns in a frame's signature: each is the average of a vertical strip.
    private static let signatureColumns = 64

    private var last: (image: CGImage, signature: Signature)?
    /// The result so far, top to bottom; each slice owns its own pixels.
    private var slices: [CGImage] = []
    private(set) var height = 0
    private(set) var width = 0

    var pixelSize: CGSize { CGSize(width: width, height: height) }

    func add(_ frame: CGImage) -> Update {
        guard height < Self.maxHeight else { return .reachedLimit }
        guard let signature = Signature(frame, columns: Self.signatureColumns) else { return .unchanged }

        guard let last else {
            // First frame: keep all of it.
            guard let copy = frame.copyingRows(0, count: frame.height) else { return .unchanged }
            slices = [copy]
            width = frame.width
            height = frame.height
            self.last = (frame, signature)
            return .appended
        }

        guard last.image.width == frame.width, last.image.height == frame.height else { return .unchanged }
        let previous = last.signature
        let rows = signature.rows
        let bandLimit = rows * 2 / 5
        let header = previous.staticRows(comparedWith: signature, fromTop: true, limit: bandLimit, tolerance: Self.matchTolerance)
        let footer = previous.staticRows(comparedWith: signature, fromTop: false, limit: bandLimit, tolerance: Self.matchTolerance)
        let top = header
        let bottom = rows - footer
        let span = bottom - top
        let minOverlap = max(24, span / 8)
        guard span > minOverlap else { return .unchanged }

        // Nothing moved in the scrolling part.
        if previous.score(against: signature, offset: 0, top: top, bottom: bottom, step: 1) <= Self.matchTolerance {
            return .unchanged
        }

        guard let offset = bestOffset(previous, signature, top: top, bottom: bottom, minOverlap: minOverlap) else {
            return .lostTrack
        }
        // Flat areas (blank space, solid fills) match at any offset, so wait for detail.
        guard signature.detail(top: top, bottom: bottom - offset) >= 1 else { return .unchanged }

        // The kept image ends with the last frame's footer: swap it for the new rows plus the new footer.
        trimBottom(footer)
        let newRows = offset + footer
        guard let slice = frame.copyingRows(rows - newRows, count: newRows) else { return .unchanged }
        slices.append(slice)
        height += newRows
        self.last = (frame, signature)
        return height >= Self.maxHeight ? .reachedLimit : .appended
    }

    /// Finds how many rows the content moved up between `previous` and `next`.
    private func bestOffset(_ previous: Signature, _ next: Signature, top: Int, bottom: Int, minOverlap: Int) -> Int? {
        var best: (offset: Int, score: Double)?
        // Coarse pass on every 4th row, then confirm the winner on every row.
        for offset in 1...(bottom - top - minOverlap) {
            let score = previous.score(against: next, offset: offset, top: top, bottom: bottom, step: 4, giveUpAbove: best?.score)
            if score < (best?.score ?? .infinity) { best = (offset, score) }
        }
        guard let best, best.score <= Self.matchTolerance else { return nil }
        let confirmed = previous.score(against: next, offset: best.offset, top: top, bottom: bottom, step: 1)
        return confirmed <= Self.matchTolerance ? best.offset : nil
    }

    private func trimBottom(_ rows: Int) {
        var remaining = rows
        while remaining > 0, let slice = slices.last {
            slices.removeLast()
            if slice.height > remaining, let kept = slice.copyingRows(0, count: slice.height - remaining) {
                slices.append(kept)
                height -= remaining
                return
            }
            height -= slice.height
            remaining -= slice.height
        }
    }

    /// The whole result, or a copy scaled to `maxWidth` pixels wide for a live preview.
    func makeImage(maxWidth: Int? = nil) -> CGImage? {
        guard let first = slices.first, height > 0 else { return nil }
        let scale = maxWidth.map { min(1, CGFloat($0) / CGFloat(width)) } ?? 1
        let outWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let outHeight = max(1, Int((CGFloat(height) * scale).rounded()))
        guard let context = CGContext.rgba(width: outWidth, height: outHeight, colorSpace: first.colorSpace) else { return nil }
        context.interpolationQuality = scale < 1 ? .medium : .none
        // CoreGraphics puts the origin at the bottom left, so lay slices out from the top down.
        var y = CGFloat(height)
        for slice in slices {
            y -= CGFloat(slice.height)
            context.draw(slice, in: CGRect(x: 0, y: y * scale, width: CGFloat(width) * scale, height: CGFloat(slice.height) * scale))
        }
        return context.makeImage()
    }
}

/// A small greyscale copy of a frame: full height, `columns` wide, row 0 at the top.
private struct Signature {
    let rows: Int
    let columns: Int
    let values: [UInt8]

    init?(_ image: CGImage, columns: Int) {
        rows = image.height
        self.columns = columns
        var values = [UInt8](repeating: 0, count: rows * columns)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: columns,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: columns,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.values = values
    }

    /// Sum of absolute differences between row `a` of this signature and row `b` of `other`.
    private func rowDifference(_ a: Int, _ other: Signature, _ b: Int) -> Int {
        values.withUnsafeBufferPointer { lhs in
            other.values.withUnsafeBufferPointer { rhs in
                var sum = 0
                let l = a * columns, r = b * columns
                for column in 0..<columns {
                    sum += abs(Int(lhs[l + column]) - Int(rhs[r + column]))
                }
                return sum
            }
        }
    }

    /// Rows at the top or bottom that are the same in both frames.
    func staticRows(comparedWith other: Signature, fromTop: Bool, limit: Int, tolerance: Double) -> Int {
        let maxDifference = Int(tolerance * Double(columns))
        var count = 0
        while count < limit {
            let row = fromTop ? count : rows - 1 - count
            if rowDifference(row, other, row) > maxDifference { break }
            count += 1
        }
        return count
    }

    /// Mean difference per sample when `next` is this frame moved up by `offset` rows,
    /// over the rows in `top..<bottom`. Stops early once it can't beat `giveUpAbove`.
    func score(against next: Signature, offset: Int, top: Int, bottom: Int, step: Int, giveUpAbove limit: Double? = nil) -> Double {
        let end = bottom - offset
        guard end > top else { return .infinity }
        let samples = ((end - top + step - 1) / step) * columns
        let budget = limit.flatMap { $0.isFinite ? Int($0 * Double(samples)) : nil } ?? .max
        var sum = 0
        var row = top
        while row < end {
            sum += rowDifference(row + offset, next, row)
            if sum > budget { return .infinity }
            row += step
        }
        return Double(sum) / Double(samples)
    }

    /// Mean difference between neighbouring rows: near zero for flat, featureless areas.
    func detail(top: Int, bottom: Int) -> Double {
        guard bottom - top > 1 else { return 0 }
        var sum = 0
        for row in top..<(bottom - 1) {
            sum += rowDifference(row, self, row + 1)
        }
        return Double(sum) / Double((bottom - top - 1) * columns)
    }
}

private extension CGImage {
    /// Copies `count` rows starting at `start` (from the top) into a new image that
    /// doesn't keep the rest of this one alive.
    func copyingRows(_ start: Int, count: Int) -> CGImage? {
        guard count > 0,
              let cropped = cropping(to: CGRect(x: 0, y: start, width: width, height: count)),
              let context = CGContext.rgba(width: width, height: count, colorSpace: colorSpace)
        else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: count))
        return context.makeImage()
    }
}

private extension CGContext {
    static func rgba(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
