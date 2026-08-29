//
//  NotificationService.swift
//  mankai
//
//  Created by Travis XU on 21/12/2025.
//

import Foundation
import SwiftUI

enum NotificationType {
    case error
    case warning
    case success
    case info
}

struct AppNotification: Identifiable, Equatable {
    let id = UUID()
    let type: NotificationType
    let message: String
    let duration: TimeInterval

    init(type: NotificationType, message: String, duration: TimeInterval = 5.0) {
        self.type = type
        self.message = message
        self.duration = duration
    }
}

final class NotificationService: ObservableObject {
    /// The shared singleton instance of NotificationService.
    static let shared = NotificationService()

    /// The list of active notifications.
    @Published var notifications: [AppNotification] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    /// Shows a notification with a custom type and message.
    /// - Parameters:
    ///   - type: The type of notification (error, warning, success, info).
    ///   - message: The message to display.
    ///   - duration: The duration in seconds before the notification auto-dismisses.
    func show(type: NotificationType, message: String, duration: TimeInterval = 5.0) {
        let notification = AppNotification(type: type, message: message, duration: duration)

        Task { @MainActor in
            notifications.append(notification)

            // Auto dismiss after duration
            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                dismiss(notification.id)
            }
            dismissTasks[notification.id] = task
        }
    }

    /// Shows an error notification.
    /// - Parameters:
    ///   - message: The error message.
    ///   - duration: The duration in seconds.
    func showError(_ message: String, duration: TimeInterval = 5.0) {
        show(type: .error, message: message, duration: duration)
    }

    /// Shows a warning notification.
    /// - Parameters:
    ///   - message: The warning message.
    ///   - duration: The duration in seconds.
    func showWarning(_ message: String, duration: TimeInterval = 5.0) {
        show(type: .warning, message: message, duration: duration)
    }

    /// Shows a success notification.
    /// - Parameters:
    ///   - message: The success message.
    ///   - duration: The duration in seconds.
    func showSuccess(_ message: String, duration: TimeInterval = 5.0) {
        show(type: .success, message: message, duration: duration)
    }

    /// Shows an informational notification.
    /// - Parameters:
    ///   - message: The info message.
    ///   - duration: The duration in seconds.
    func showInfo(_ message: String, duration: TimeInterval = 5.0) {
        show(type: .info, message: message, duration: duration)
    }

    /// Dismisses a notification by its ID.
    /// - Parameter id: The UUID of the notification to dismiss.
    @MainActor func dismiss(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
    }

    /// Dismisses all active notifications.
    @MainActor func dismissAll() {
        notifications.removeAll()
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
    }
}
