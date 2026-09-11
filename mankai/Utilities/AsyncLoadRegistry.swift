//
//  AsyncLoadRegistry.swift
//  mankai
//
//  Created by Travis XU on 6/8/2026.
//

import Foundation

/// Coalesces concurrent asynchronous operations for the same key.
final class AsyncLoadRegistry<Value: Sendable>: @unchecked Sendable {
    private final class Entry {
        let id: UUID
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<Value, Error>]

        init(id: UUID, waiterId: UUID, continuation: CheckedContinuation<Value, Error>) {
            self.id = id
            waiters = [waiterId: continuation]
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(for key: String, operation: @escaping @Sendable () async throws -> Value)
        async throws -> Value
    {
        try Task.checkCancellation()
        let waiterId = UUID()

        let value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let isCancelled = lock.withLock {
                    guard !Task.isCancelled else { return true }

                    if let entry = entries[key] {
                        entry.waiters[waiterId] = continuation
                    } else {
                        let entryId = UUID()
                        let entry = Entry(
                            id: entryId, waiterId: waiterId, continuation: continuation)
                        entries[key] = entry
                        entry.task = Task { [weak self] in
                            let result: Result<Value, Error>
                            do { result = .success(try await operation()) } catch {
                                result = .failure(error)
                            }

                            self?.complete(result, for: key, entryId: entryId)
                        }
                    }

                    return false
                }

                if isCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            cancelWaiter(id: waiterId, for: key)
        }

        try Task.checkCancellation()
        return value
    }

    private func complete(_ result: Result<Value, Error>, for key: String, entryId: UUID) {
        let continuations: [CheckedContinuation<Value, Error>] = lock.withLock {
            guard let entry = entries[key], entry.id == entryId else { return [] }
            entries.removeValue(forKey: key)
            return Array(entry.waiters.values)
        }

        for continuation in continuations { continuation.resume(with: result) }
    }

    private func cancelWaiter(id: UUID, for key: String) {
        let continuation: CheckedContinuation<Value, Error>? = lock.withLock {
            guard let entry = entries[key] else { return nil }
            return entry.waiters.removeValue(forKey: id)
        }

        continuation?.resume(throwing: CancellationError())
    }
}
