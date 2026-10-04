import Foundation
import Synchronization

/// A float that can be poked from the audio thread and read from the UI thread.
public final class AtomicLevel: @unchecked Sendable {
    private let bits = Atomic<UInt32>(0)
    public init(_ value: Float = 0) { bits.store(value.bitPattern, ordering: .relaxed) }
    public func store(_ value: Float) { bits.store(value.bitPattern, ordering: .relaxed) }
    public func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }

    /// Keeps the larger of the current value and `value` (peak hold).
    public func storeMaximum(_ value: Float) {
        var current = load()
        while value > current {
            let (exchanged, original) = bits.compareExchange(expected: current.bitPattern,
                                                             desired: value.bitPattern,
                                                             ordering: .relaxed)
            if exchanged { return }
            current = Float(bitPattern: original)
        }
    }
}

/// Lock-free single-producer / single-consumer stereo ring buffer.
///
/// One thread (the capture callback) writes, one thread (the output render
/// callback) reads, and neither ever blocks. Frame storage is planar so the
/// consumer can hand pointers straight to the convolver.
public final class AudioRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    public let droppedFrames = AtomicLevel(0)
    public let missingFrames = AtomicLevel(0)

    public init(capacity: Int) {
        var size = 64
        while size < capacity { size <<= 1 }
        self.capacity = size
        self.mask = size - 1
        left = UnsafeMutablePointer<Float>.allocate(capacity: size)
        right = UnsafeMutablePointer<Float>.allocate(capacity: size)
        left.initialize(repeating: 0, count: size)
        right.initialize(repeating: 0, count: size)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// Frames currently available to read.
    public var fill: Int {
        writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .acquiring)
    }

    /// Producer side. Returns the number of frames actually stored.
    @discardableResult
    public func write(left sourceLeft: UnsafePointer<Float>,
                      right sourceRight: UnsafePointer<Float>,
                      count: Int) -> Int {
        guard count > 0 else { return 0 }
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let free = capacity - (write - read)
        let accepted = min(count, max(0, free))
        for frame in 0..<accepted {
            let index = (write + frame) & mask
            left[index] = sourceLeft[frame]
            right[index] = sourceRight[frame]
        }
        writeIndex.store(write + accepted, ordering: .releasing)
        if accepted < count {
            let total = droppedFrames.load() + Float(count - accepted)
            droppedFrames.store(total)
        }
        return accepted
    }

    /// Consumer side. Returns the number of frames actually read; the remainder
    /// of the destination is left untouched.
    @discardableResult
    public func read(into destinationLeft: UnsafeMutablePointer<Float>,
                     _ destinationRight: UnsafeMutablePointer<Float>,
                     count: Int) -> Int {
        guard count > 0 else { return 0 }
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        let available = write - read
        let taken = min(count, max(0, available))
        for frame in 0..<taken {
            let index = (read + frame) & mask
            destinationLeft[frame] = left[index]
            destinationRight[frame] = right[index]
        }
        readIndex.store(read + taken, ordering: .releasing)
        if taken < count {
            let total = missingFrames.load() + Float(count - taken)
            missingFrames.store(total)
        }
        return taken
    }

    public func clear() {
        let write = writeIndex.load(ordering: .relaxed)
        readIndex.store(write, ordering: .releasing)
    }

    /// Drops the oldest `count` frames, keeping latency bounded if the two
    /// devices drift apart.
    public func dropOldest(_ count: Int) {
        guard count > 0 else { return }
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        let available = max(0, write - read)
        readIndex.store(read + min(count, available), ordering: .releasing)
    }
}
