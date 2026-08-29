//
//  AsyncLoadRegistry.swift
//  mankai
//
//  Created by Travis XU on 6/8/2026.
//

import Foundation

/// Coalesces concurrent asynchronous operations for the same key.
final class AsyncLoadRegistry<Value>: @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let task: Task<Value, Error>
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(for key: String, operation: @escaping () async throws -> Value) async throws -> Value
    {
        let entry = lock.withLock {
            if let existing = entries[key] { return existing }

            let created = Entry(id: UUID(), task: Task { try await operation() })
            entries[key] = created
            return created
        }

        do {
            let result = try await entry.task.value
            removeEntry(for: key, id: entry.id)
            return result
        } catch {
            removeEntry(for: key, id: entry.id)
            throw error
        }
    }

    private func removeEntry(for key: String, id: UUID) {
        lock.withLock {
            guard entries[key]?.id == id else { return }
            entries.removeValue(forKey: key)
        }
    }
}
