//
//  GlyphHistoryStore.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

/// Serializes glyph operation history and checkpointed replay renders.
actor GlyphHistoryStore {
    static let checkpointInterval = 200

    private(set) var operations: [GlyphOperation] = []
    private var checkpoints: [Int: CGImage] = [:]
    private var width: Int = 0
    private var height: Int = 0
    private var canvasBackground: RGBAColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)

    var operationCount: Int { operations.count }

    func copyOperations() -> [GlyphOperation] { operations }

    func canvasSize() -> (width: Int, height: Int) { (width, height) }

    /// Clears history and prepares for a canvas of the given size. Seeds checkpoint `0` (blank).
    func reset(width: Int, height: Int, canvasBackground: RGBAColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)) throws {
        self.width = width
        self.height = height
        self.canvasBackground = canvasBackground
        operations.removeAll(keepingCapacity: false)
        checkpoints.removeAll(keepingCapacity: false)
        checkpoints[0] = try GlyphRenderer.renderFull(
            operations: [],
            upTo: 0,
            width: width,
            height: height,
            canvasBackground: canvasBackground
        )
    }

    /// Replaces history in one step (e.g. restoring a saved document). Rebuilds sparse checkpoints at `checkpointInterval`.
    func importOperations(
        _ ops: [GlyphOperation],
        width: Int,
        height: Int,
        canvasBackground: RGBAColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)
    ) throws {
        self.width = width
        self.height = height
        self.canvasBackground = canvasBackground
        operations = ops
        checkpoints.removeAll(keepingCapacity: false)
        checkpoints[0] = try GlyphRenderer.renderFull(
            operations: [],
            upTo: 0,
            width: width,
            height: height,
            canvasBackground: canvasBackground
        )
        let n = ops.count
        var k = Self.checkpointInterval
        while k <= n {
            checkpoints[k] = try renderPrefix(k)
            k += Self.checkpointInterval
        }
    }

    func append(_ op: GlyphOperation) throws {
        guard width > 0, height > 0 else { return }
        operations.append(op)
        let c = operations.count
        if c % Self.checkpointInterval == 0 {
            checkpoints[c] = try renderPrefix(c)
        }
    }

    /// Keeps `operations[0..<k]`; drops the tail. Checkpoints with prefix length `> k` are removed.
    func truncate(keepingFirst k: Int) throws {
        let kk = max(0, min(k, operations.count))
        operations.removeSubrange(kk..<operations.endIndex)
        for key in checkpoints.keys where key > kk {
            checkpoints.removeValue(forKey: key)
        }
        if kk > 0, kk % Self.checkpointInterval == 0, checkpoints[kk] == nil {
            checkpoints[kk] = try renderPrefix(kk)
        }
    }

    func render(upTo index: Int) throws -> CGImage {
        guard width > 0, height > 0 else {
            throw ImageProcessingError.contextFailure
        }
        let idx = max(0, min(index, operations.count))
        let start = largestCheckpointKey(atMost: idx)
        let cp = checkpoints[start]
        return try GlyphRenderer.render(
            operations: operations,
            upTo: idx,
            width: width,
            height: height,
            startingCheckpointPrefixLength: start,
            checkpointImage: start == 0 ? nil : cp,
            canvasBackground: canvasBackground
        )
    }

    /// Full replay from scratch (tests / verification).
    func renderFullPrefix(upTo index: Int) throws -> CGImage {
        try GlyphRenderer.renderFull(
            operations: operations,
            upTo: index,
            width: width,
            height: height,
            canvasBackground: canvasBackground
        )
    }

    private func largestCheckpointKey(atMost index: Int) -> Int {
        var best = 0
        for k in checkpoints.keys where k <= index {
            if k > best { best = k }
        }
        return best
    }

    private func renderPrefix(_ prefixLength: Int) throws -> CGImage {
        let start = largestCheckpointKey(atMost: prefixLength)
        let cp = checkpoints[start]
        return try GlyphRenderer.render(
            operations: operations,
            upTo: prefixLength,
            width: width,
            height: height,
            startingCheckpointPrefixLength: start,
            checkpointImage: start == 0 ? nil : cp,
            canvasBackground: canvasBackground
        )
    }
}
