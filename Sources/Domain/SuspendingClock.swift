// Sources/Domain/SuspendingClock.swift
// Injected sleep so debounce and playback timeouts can advance in tests.
import Foundation

public protocol SuspendingClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct ContinuousSuspendingClock: SuspendingClock {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Test clock: `sleep` suspends until `advance(by:)` covers the remaining duration.
public final class ManualSuspendingClock: SuspendingClock, @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        var remaining: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var waiters: [Waiter] = []

    public init() {}

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    public func sleep(for duration: Duration) async throws {
        if duration <= .zero { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                waiters.append(Waiter(id: id, remaining: duration, continuation: continuation))
                lock.unlock()
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let continuation = self.removeWaiter(id: id)
            self.lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }

    public func waitUntilPending(atLeast count: Int = 1) async {
        for _ in 0..<80 {
            if pendingCount >= count { return }
            await Task.yield()
        }
    }

    public func advance(by step: Duration) async {
        let ready = collectReady(after: step)
        for continuation in ready {
            continuation.resume()
        }
        for _ in 0..<12 {
            await Task.yield()
        }
    }

    private func collectReady(after step: Duration) -> [CheckedContinuation<Void, Error>] {
        lock.lock()
        defer { lock.unlock() }
        var ready: [CheckedContinuation<Void, Error>] = []
        var stillWaiting: [Waiter] = []
        stillWaiting.reserveCapacity(waiters.count)
        for var waiter in waiters {
            waiter.remaining -= step
            if waiter.remaining <= .zero {
                ready.append(waiter.continuation)
            } else {
                stillWaiting.append(waiter)
            }
        }
        waiters = stillWaiting
        return ready
    }

    private func removeWaiter(id: UUID) -> CheckedContinuation<Void, Error>? {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
        return waiters.remove(at: index).continuation
    }
}
